param(
    [Parameter(Mandatory=$true)]
    [string]$SnapshotPath,

    [Parameter(Mandatory=$true)]
    [string]$StopPath,

    [Parameter(Mandatory=$true)]
    [string]$CommandPath,

    [int]$ParentProcessId = 0
)

$ErrorActionPreference = 'Stop'

# A non-zero Dell cooling floor can survive a helper restart. Keep a small
# marker beside the command file so a replacement helper restores Dell Auto
# before it resumes normal monitoring.
$coolingOwnershipPath = $CommandPath + '.owned'

function Write-AtomicJson {
    param(
        [Parameter(Mandatory=$true)]
        $Object
    )

    $directory =
        Split-Path `
            -Parent `
            $SnapshotPath

    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item `
            -ItemType Directory `
            -Path $directory `
            -Force |
            Out-Null
    }

    $temporaryPath =
        $SnapshotPath + '.tmp'

    $json =
        $Object |
            ConvertTo-Json `
                -Depth 16 `
                -Compress

    [System.IO.File]::WriteAllText(
        $temporaryPath,
        $json,
        [System.Text.UTF8Encoding]::new($false)
    )

    Move-Item `
        -LiteralPath $temporaryPath `
        -Destination $SnapshotPath `
        -Force
}

$dellSensorsScript = @'
$ErrorActionPreference = 'Stop'
Import-Module CimCmdlets -ErrorAction Stop

function Get-Number($value) {
    if ($null -eq $value) {
        return $null
    }

    try {
        return [double]$value
    }
    catch {
        return $null
    }
}

function Get-LowerThreshold($value) {
    $number = Get-Number $value

    if ($null -eq $number -or
        $number -lt -1000) {
        return $null
    }

    return $number
}

$sensors =
    @(
        Get-CimInstance `
            -Namespace 'root/DCIM/SYSMAN' `
            -ClassName DCIM_NumericSensor `
            -ErrorAction Stop |
        Where-Object {
            [int]$_.SensorType -in @(2, 5)
        } |
        ForEach-Object {
            $name = [string]$_.Caption

            if ([string]::IsNullOrWhiteSpace($name)) {
                $name = [string]$_.ElementName
            }

            [pscustomobject]@{
                SensorType =
                    [int]$_.SensorType
                Name =
                    $name
                DeviceID =
                    [string]$_.DeviceID
                Reading =
                    Get-Number $_.CurrentReading
                UpperWarning =
                    Get-Number `
                        $_.UpperThresholdNonCritical
                UpperCritical =
                    Get-Number `
                        $_.UpperThresholdCritical
                LowerWarning =
                    Get-LowerThreshold `
                        $_.LowerThresholdNonCritical
                LowerCritical =
                    Get-LowerThreshold `
                        $_.LowerThresholdCritical
                HealthState =
                    $_.HealthState
                CurrentState =
                    [string]$_.CurrentState
            }
        }
    )

if ($sensors.Count -eq 0) {
    throw 'Dell Command Monitor returned no temperature or fan sensors.'
}

[pscustomobject]@{
    Sensors = @($sensors)
}
'@

$dellBiosScript = @'
$ErrorActionPreference = 'Stop'
Import-Module CimCmdlets -ErrorAction Stop

$capabilities =
    @(
        Get-CimInstance `
            -Namespace 'root/DCIM/SYSMAN' `
            -ClassName DCIM_BIOSEnumeration `
            -ErrorAction Stop |
        Where-Object {
            [string]$_.AttributeName -match
                '^(Fan Speed Auto Level|HDD0 Fan Enable)'
        } |
        ForEach-Object {
            [pscustomobject]@{
                Source =
                    'DCIM_BIOSEnumeration'
                AttributeName =
                    [string]$_.AttributeName
                CurrentValue =
                    [string]$_.CurrentValue
                PossibleValues =
                    @($_.PossibleValues)
                PossibleValuesDescription =
                    @($_.PossibleValuesDescription)
                IsReadOnly =
                    [bool]$_.IsReadOnly
            }
        }
    )

[pscustomobject]@{
    Capabilities = @($capabilities)
}
'@

$coolingCommandScript = @'
param(
    [Parameter(Mandatory=$true)]
    [int]$RequestedValue
)

$ErrorActionPreference = 'Stop'
Import-Module CimCmdlets -ErrorAction Stop

$namespace = 'root/DCIM/SYSMAN'
$attributeName =
    'Fan Speed Auto Level on CPU Memory Zone'

if ($RequestedValue -lt 0 -or
    $RequestedValue -gt 100) {
    throw 'Cooling level must be between 0 and 100.'
}

$attribute =
    Get-CimInstance `
        -Namespace $namespace `
        -ClassName DCIM_BIOSEnumeration `
        -ErrorAction Stop |
    Where-Object {
        [string]$_.AttributeName -eq
            $attributeName
    } |
    Select-Object -First 1

if ($null -eq $attribute) {
    throw 'CPU / Memory cooling level is not exposed.'
}

if ([bool]$attribute.IsReadOnly) {
    throw 'CPU / Memory cooling level is read-only.'
}

$service =
    Get-CimInstance `
        -Namespace $namespace `
        -ClassName DCIM_BIOSService `
        -ErrorAction Stop |
    Select-Object -First 1

if ($null -eq $service) {
    throw 'DCIM_BIOSService is unavailable.'
}

$result =
    $service |
    Invoke-CimMethod `
        -MethodName SetBIOSAttributes `
        -Arguments @{
            AttributeName =
                @($attributeName)
            AttributeValue =
                @([string]$RequestedValue)
        } `
        -ErrorAction Stop

if ([int]$result.ReturnValue -ne 0) {
    throw (
        'SetBIOSAttributes failed. ReturnValue=' +
        [string]$result.ReturnValue
    )
}

$readback =
    Get-CimInstance `
        -Namespace $namespace `
        -ClassName DCIM_BIOSEnumeration `
        -ErrorAction Stop |
    Where-Object {
        [string]$_.AttributeName -eq
            $attributeName
    } |
    Select-Object -First 1

if ($null -eq $readback) {
    throw 'Cooling write succeeded but readback failed.'
}

$current =
    [int]$readback.CurrentValue[0]

if ($current -ne $RequestedValue) {
    throw (
        'Cooling readback mismatch. Requested=' +
        [string]$RequestedValue +
        ', Current=' +
        [string]$current
    )
}

[pscustomobject]@{
    AttributeName = $attributeName
    RequestedValue = $RequestedValue
    CurrentValue = $current
    ReturnValue = [int]$result.ReturnValue
    SetResult = @($result.SetResult)
}
'@

$nvidiaScript = @'
$ErrorActionPreference = 'Stop'

$command =
    Get-Command `
        nvidia-smi.exe `
        -ErrorAction SilentlyContinue |
    Select-Object -First 1

$exe =
    if ($null -ne $command) {
        [string]$command.Source
    }
    else {
        $null
    }

if ([string]::IsNullOrWhiteSpace($exe)) {
    $fallbacks = @(
        "$env:SystemRoot\System32\nvidia-smi.exe",
        "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe"
    )

    foreach ($path in $fallbacks) {
        if (Test-Path -LiteralPath $path) {
            $exe = $path
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($exe)) {
    throw 'nvidia-smi.exe not found.'
}

$output =
    @(
        & $exe `
            '--query-gpu=index,name,temperature.gpu,fan.speed,utilization.gpu,power.draw,memory.used,memory.total,pstate' `
            '--format=csv,noheader,nounits' `
            2>&1
    )

if ($LASTEXITCODE -ne 0) {
    throw (
        'nvidia-smi failed: ' +
        ($output -join ' ')
    )
}

$line =
    [string](
        $output |
            Select-Object -First 1
    )

$gpu =
    $line |
        ConvertFrom-Csv `
            -Header @(
                'Index',
                'Name',
                'Temperature',
                'FanPercent',
                'Utilization',
                'Power',
                'MemoryUsed',
                'MemoryTotal',
                'PState'
            )

function Parse-Number($value) {
    $text = [string]$value

    if ($text -match
        '[-+]?[0-9]+(?:\.[0-9]+)?') {
        return [double]$matches[0]
    }

    return $null
}

[pscustomobject]@{
    Gpu =
        [pscustomobject]@{
            Index =
                [int](Parse-Number $gpu.Index)
            Name =
                ([string]$gpu.Name).Trim()
            Temperature =
                Parse-Number $gpu.Temperature
            FanPercent =
                Parse-Number $gpu.FanPercent
            Utilization =
                Parse-Number $gpu.Utilization
            Power =
                Parse-Number $gpu.Power
            MemoryUsed =
                Parse-Number $gpu.MemoryUsed
            MemoryTotal =
                Parse-Number $gpu.MemoryTotal
            PState =
                ([string]$gpu.PState).Trim()
        }
}
'@

$storageScript = @'
$ErrorActionPreference = 'Stop'
Import-Module Storage -ErrorAction Stop

$rows = @()

foreach ($disk in @(
    Get-PhysicalDisk -ErrorAction Stop
)) {
    $reliability = $null

    try {
        $reliability =
            $disk |
                Get-StorageReliabilityCounter `
                    -ErrorAction Stop
    }
    catch {}

    $rows +=
        [pscustomobject]@{
            FriendlyName =
                [string]$disk.FriendlyName
            DeviceId =
                [string]$disk.DeviceId
            SerialNumber =
                [string]$disk.SerialNumber
            MediaType =
                [string]$disk.MediaType
            BusType =
                [string]$disk.BusType
            Health =
                [string]$disk.HealthStatus
            OperationalStatus =
                @($disk.OperationalStatus) -join ', '
            Temperature =
                if ($null -ne $reliability) {
                    $reliability.Temperature
                }
                else {
                    $null
                }
            TemperatureMax =
                if ($null -ne $reliability) {
                    $reliability.TemperatureMax
                }
                else {
                    $null
                }
            Wear =
                if ($null -ne $reliability) {
                    $reliability.Wear
                }
                else {
                    $null
                }
            PowerOnHours =
                if ($null -ne $reliability) {
                    $reliability.PowerOnHours
                }
                else {
                    $null
                }
            ReadErrors =
                if ($null -ne $reliability) {
                    $reliability.ReadErrorsTotal
                }
                else {
                    $null
                }
            WriteErrors =
                if ($null -ne $reliability) {
                    $reliability.WriteErrorsTotal
                }
                else {
                    $null
                }
        }
}

[pscustomobject]@{
    Storage = @($rows)
}
'@

$percScript = @'
$ErrorActionPreference = 'Stop'

$exe =
    "$env:ProgramFiles\Dell\Command Monitor\perccli64.exe"

if (-not (Test-Path -LiteralPath $exe)) {
    throw "perccli64.exe not found: $exe"
}

function Get-LineValue {
    param(
        [string[]]$Lines,
        [string]$Pattern
    )

    foreach ($line in $Lines) {
        if ([string]$line -match $Pattern) {
            return ([string]$matches[1]).Trim()
        }
    }

    return $null
}

function Get-NumberFromText($value) {
    if ($null -eq $value) {
        return $null
    }

    if ([string]$value -match
        '[-+]?[0-9]+(?:\.[0-9]+)?') {
        return [double]$matches[0]
    }

    return $null
}

$controllerLines =
    @(
        & $exe /c0 show all 2>&1 |
            ForEach-Object {
                [string]$_
            }
    )

if ($LASTEXITCODE -ne 0) {
    throw (
        'perccli64 /c0 show all failed: ' +
        ($controllerLines -join ' ')
    )
}

$model =
    Get-LineValue `
        $controllerLines `
        '^Model\s*=\s*(.+)$'

$status =
    Get-LineValue `
        $controllerLines `
        '^Controller Status\s*=\s*(.+)$'

$rocTemperature =
    Get-NumberFromText (
        Get-LineValue `
            $controllerLines `
            '^ROC temperature\(Degree Celsius\)\s*=\s*(.+)$'
    )

$controllerTemperature =
    Get-NumberFromText (
        Get-LineValue `
            $controllerLines `
            '^Ctrl temperature\(Degree Celsius\)\s*=\s*(.+)$'
    )

$drives = @()

foreach ($slot in @(4, 5, 6, 7)) {
    $driveLines =
        @(
            & $exe "/c0/s$slot" show all 2>&1 |
                ForEach-Object {
                    [string]$_
                }
        )

    if ($LASTEXITCODE -ne 0) {
        $drives +=
            [pscustomobject]@{
                Slot = $slot
                Model = "Slot $slot"
                Temperature = $null
                Health = 'Unavailable'
                MediaErrors = $null
                OtherErrors = $null
                PredictiveFailures = $null
                SmartAlert = ''
            }

        continue
    }

    $driveModel =
        Get-LineValue `
            $driveLines `
            '^Model Number\s*=\s*(.+)$'

    if ([string]::IsNullOrWhiteSpace($driveModel)) {
        $driveModel = "PERC drive slot $slot"
    }

    $temperatureText =
        Get-LineValue `
            $driveLines `
            '^Drive Temperature\s*=\s*(.+)$'

    $driveTemperature =
        if ([string]$temperatureText -match
            '([0-9]+(?:\.[0-9]+)?)\s*C') {
            [double]$matches[1]
        }
        else {
            $null
        }

    $mediaErrors =
        Get-NumberFromText (
            Get-LineValue `
                $driveLines `
                '^Media Error Count\s*=\s*(.+)$'
        )

    $otherErrors =
        Get-NumberFromText (
            Get-LineValue `
                $driveLines `
                '^Other Error Count\s*=\s*(.+)$'
        )

    $predictiveFailures =
        Get-NumberFromText (
            Get-LineValue `
                $driveLines `
                '^Predictive Failure Count\s*=\s*(.+)$'
        )

    $smartAlert =
        Get-LineValue `
            $driveLines `
            '^S\.M\.A\.R\.T alert flagged by drive\s*=\s*(.+)$'

    $state = $null
    $statePattern =
        '^\s*:\s*' +
        [regex]::Escape([string]$slot) +
        '\s+\d+\s+(\S+)'

    foreach ($line in $driveLines) {
        if ([string]$line -match $statePattern) {
            $state = [string]$matches[1]
            break
        }
    }

    $health =
        switch ($state) {
            'Onln' {
                'Online'
            }
            'Optl' {
                'Optimal'
            }
            default {
                if ([string]::IsNullOrWhiteSpace($state)) {
                    'Online'
                }
                else {
                    [string]$state
                }
            }
        }

    $drives +=
        [pscustomobject]@{
            Slot = $slot
            Model = $driveModel
            Temperature = $driveTemperature
            Health = $health
            MediaErrors = $mediaErrors
            OtherErrors = $otherErrors
            PredictiveFailures = $predictiveFailures
            SmartAlert = $smartAlert
        }
}

[pscustomobject]@{
    Perc =
        [pscustomobject]@{
            Model =
                if ([string]::IsNullOrWhiteSpace($model)) {
                    'PERC H330'
                }
                else {
                    $model
                }
            ControllerStatus =
                $status
            RocTemperature =
                $rocTemperature
            ControllerTemperature =
                $controllerTemperature
            Drives =
                @($drives)
        }
}
'@

$coolingControl =
    [pscustomobject]@{
        State = 'Idle'
        CommandId = ''
        RequestedValue = $null
        CurrentValue = $null
        Error = ''
        Updated = ''
    }

$coolingPowerShell = $null
$coolingAsync = $null
$coolingStarted = $null
$towerOwnsCooling =
    (Test-Path -LiteralPath $coolingOwnershipPath)

$runspacePool =
    [runspacefactory]::CreateRunspacePool(
        1,
        6
    )

$runspacePool.Open()

$now = [datetime]::Now

$collectors =
    @(
        [pscustomobject]@{
            Name = 'DellSensors'
            # A healthy Precision 7820 enumeration takes about eight seconds.
            # Leave the provider idle between samples instead of querying it
            # almost continuously.
            IntervalSeconds = 15
            TimeoutSeconds = 30
            NextRun = $now
            Script = $dellSensorsScript
            PowerShell = $null
            Async = $null
            Started = $null
            Data = $null
            State = 'Loading'
            Error = ''
            Updated = ''
        },
        [pscustomobject]@{
            Name = 'NVIDIA'
            IntervalSeconds = 2
            NextRun = $now
            Script = $nvidiaScript
            PowerShell = $null
            Async = $null
            Started = $null
            Data = $null
            State = 'Loading'
            Error = ''
            Updated = ''
        },
        [pscustomobject]@{
            Name = 'Storage'
            IntervalSeconds = 8
            NextRun = $now.AddMilliseconds(300)
            Script = $storageScript
            PowerShell = $null
            Async = $null
            Started = $null
            Data = $null
            State = 'Loading'
            Error = ''
            Updated = ''
        },
        [pscustomobject]@{
            Name = 'PERC'
            IntervalSeconds = 12
            NextRun = $now.AddMilliseconds(700)
            Script = $percScript
            PowerShell = $null
            Async = $null
            Started = $null
            Data = $null
            State = 'Loading'
            Error = ''
            Updated = ''
        },
        [pscustomobject]@{
            Name = 'DellBIOS'
            # Cooling capability is effectively static. Refresh it only as a
            # low-frequency health check; a completed cooling write schedules
            # an immediate readback separately.
            IntervalSeconds = 600
            TimeoutSeconds = 45
            NextRun = $now.AddSeconds(5)
            Script = $dellBiosScript
            PowerShell = $null
            Async = $null
            Started = $null
            Data = $null
            State = 'Loading'
            Error = ''
            Updated = ''
        }
    )

function Get-Collector {
    param(
        [string]$Name
    )

    return (
        $collectors |
            Where-Object {
                [string]$_.Name -eq $Name
            } |
            Select-Object -First 1
    )
}

function Test-DellProviderBusy {
    if ($null -ne $coolingPowerShell) {
        return $true
    }

    foreach ($name in @('DellSensors', 'DellBIOS')) {
        $collector = Get-Collector $name

        if ($null -ne $collector -and
            $null -ne $collector.PowerShell) {
            return $true
        }
    }

    return $false
}

function Get-CollectorPayload {
    param(
        [string]$Name,
        [string]$Property
    )

    $collector =
        Get-Collector $Name

    if ($null -eq $collector -or
        $null -eq $collector.Data) {
        return $null
    }

    return $collector.Data.$Property
}

function Write-CurrentSnapshot {
    $dellSensors =
        Get-CollectorPayload `
            'DellSensors' `
            'Sensors'

    $capabilities =
        Get-CollectorPayload `
            'DellBIOS' `
            'Capabilities'

    $biosCollector =
        Get-Collector 'DellBIOS'

    $gpu =
        Get-CollectorPayload `
            'NVIDIA' `
            'Gpu'

    $storage =
        Get-CollectorPayload `
            'Storage' `
            'Storage'

    $perc =
        Get-CollectorPayload `
            'PERC' `
            'Perc'

    $mainCoolingCapability =
        @(
            @($capabilities) |
                Where-Object {
                    [string]$_.AttributeName -eq
                        'Fan Speed Auto Level on CPU Memory Zone'
                }
        ) |
            Select-Object -First 1

    $coolingAvailable =
        ($null -ne $mainCoolingCapability)

    $coolingReadOnly =
        if ($null -eq $mainCoolingCapability) {
            $true
        }
        else {
            [bool]$mainCoolingCapability.IsReadOnly
        }

    $reportedCoolingValue =
        if ($null -ne $coolingControl.CurrentValue) {
            $coolingControl.CurrentValue
        }
        elseif ($null -ne $mainCoolingCapability) {
            [string]$mainCoolingCapability.CurrentValue
        }
        else {
            $null
        }

    $statuses =
        @(
            $collectors |
                ForEach-Object {
                    [pscustomobject]@{
                        Name =
                            [string]$_.Name
                        State =
                            [string]$_.State
                        Error =
                            [string]$_.Error
                        Updated =
                            [string]$_.Updated
                    }
                }
        )

    Write-AtomicJson (
        [pscustomobject]@{
            ok = $true
            timestamp =
                [datetime]::Now.ToString('o')
            error = ''
            sensors =
                if ($null -eq $dellSensors) {
                    @()
                }
                else {
                    @($dellSensors)
                }
            capabilities =
                if ($null -eq $capabilities) {
                    @()
                }
                else {
                    @($capabilities)
                }
            gpu = $gpu
            storage =
                if ($null -eq $storage) {
                    @()
                }
                else {
                    @($storage)
                }
            perc = $perc
            coolingControl =
                [pscustomobject]@{
                    Available = $coolingAvailable
                    IsReadOnly = $coolingReadOnly
                    DiscoveryState =
                        if ($null -eq $biosCollector) {
                            'Loading'
                        }
                        else {
                            [string]$biosCollector.State
                        }
                    DiscoveryError =
                        if ($null -eq $biosCollector) {
                            ''
                        }
                        else {
                            [string]$biosCollector.Error
                        }
                    AttributeName =
                        'Fan Speed Auto Level on CPU Memory Zone'
                    State =
                        [string]$coolingControl.State
                    CommandId =
                        [string]$coolingControl.CommandId
                    RequestedValue =
                        $coolingControl.RequestedValue
                    CurrentValue =
                        $reportedCoolingValue
                    Error =
                        [string]$coolingControl.Error
                    Updated =
                        [string]$coolingControl.Updated
                }
            sourceStatus =
                @($statuses)
        }
    )
}

function Start-Collector {
    param(
        $Collector
    )

    if ($null -ne $Collector.PowerShell) {
        return $false
    }

    # Dell Command | Monitor can deadlock when its sensor and BIOS providers
    # are queried concurrently. GPU, storage and PERC remain independent, but
    # every DCM operation is deliberately serialized.
    if ([string]$Collector.Name -in @('DellSensors', 'DellBIOS') -and
        (Test-DellProviderBusy)) {
        return $false
    }

    $powerShell =
        [powershell]::Create()

    $powerShell.RunspacePool =
        $runspacePool

    [void]$powerShell.AddScript(
        [string]$Collector.Script
    )

    try {
        $Collector.PowerShell =
            $powerShell

        $Collector.Async =
            $powerShell.BeginInvoke()

        $Collector.Started =
            [datetime]::Now

        $Collector.State =
            'Running'

        $Collector.Error = ''
    }
    catch {
        try {
            $powerShell.Dispose()
        }
        catch {}

        $Collector.PowerShell = $null
        $Collector.Async = $null
        $Collector.State = 'Error'
        $Collector.Error =
            [string]$_.Exception.Message

        $Collector.NextRun =
            [datetime]::Now.AddSeconds(
                [int]$Collector.IntervalSeconds
            )

        $Collector.Started = $null

        return $true
    }

    return $true
}

function Complete-Collector {
    param(
        $Collector
    )

    if ($null -eq $Collector -or
        $null -eq $Collector.PowerShell -or
        $null -eq $Collector.Async -or
        -not $Collector.Async.IsCompleted) {
        return $false
    }

    try {
        $result =
            @(
                $Collector.PowerShell.EndInvoke(
                    $Collector.Async
                )
            )

        if ($result.Count -eq 0) {
            throw 'Collector returned no result.'
        }

        $Collector.Data =
            $result |
                Select-Object -Last 1

        $Collector.State = 'OK'
        $Collector.Error = ''
        $Collector.Updated =
            [datetime]::Now.ToString('o')
    }
    catch {
        $Collector.State = 'Error'
        $Collector.Error =
            [string]$_.Exception.Message
    }
    finally {
        try {
            $Collector.PowerShell.Dispose()
        }
        catch {}

        $Collector.PowerShell = $null
        $Collector.Async = $null
        $Collector.Started = $null

        $nextDelaySeconds =
            [int]$Collector.IntervalSeconds

        if ([string]$Collector.Name -eq 'DellSensors' -and
            [string]$Collector.State -eq 'Error') {
            $nextDelaySeconds = 60
        }

        $Collector.NextRun =
            [datetime]::Now.AddSeconds(
                $nextDelaySeconds
            )
    }

    return $true
}

function Report-CollectorTimeout {
    param(
        $Collector
    )

    if ($null -eq $Collector.PowerShell -or
        $null -eq $Collector.Async -or
        $null -eq $Collector.Started -or
        $Collector.Async.IsCompleted -or
        [string]$Collector.State -eq 'Timeout') {
        return
    }

    $elapsed =
        ([datetime]::Now - [datetime]$Collector.Started).TotalSeconds

    if ($elapsed -lt [double]$Collector.TimeoutSeconds) {
        return
    }

    $Collector.State = 'Timeout'
    $Collector.Error =
        [string]$Collector.Name +
        ' exceeded its ' +
        [string]$Collector.TimeoutSeconds +
        ' second limit. Tower will not submit another Dell query until this call finishes.'
    $Collector.Updated =
        [datetime]::Now.ToString('o')

    Write-CurrentSnapshot

    # Killing and immediately restarting the helper does not cancel work that
    # is already executing inside WMI Provider Host. It can instead stack more
    # requests onto a wedged Dell provider. Keep this helper alive, publish one
    # timeout state, and wait for the existing call to finish. Other hardware
    # collectors remain independent and the UI stays responsive.
}

function Stop-HelperOnCoolingTimeout {
    if ($null -eq $coolingPowerShell -or
        $null -eq $coolingAsync -or
        $null -eq $coolingStarted -or
        $coolingAsync.IsCompleted) {
        return
    }

    $elapsed =
        ([datetime]::Now - [datetime]$coolingStarted).TotalSeconds

    if ($elapsed -lt 60) {
        return
    }

    $coolingControl.State = 'Error'
    $coolingControl.Error =
        'Dell cooling write exceeded 60 seconds. The helper will restart and restore Dell Auto.'
    $coolingControl.Updated =
        [datetime]::Now.ToString('o')

    Write-CurrentSnapshot
    Start-Sleep -Milliseconds 1200
    [Environment]::Exit(125)
}

function Test-ParentProcessAlive {
    if ($ParentProcessId -le 0) {
        return $true
    }

    try {
        $process =
            Get-Process `
                -Id $ParentProcessId `
                -ErrorAction Stop

        return ($null -ne $process)
    }
    catch {
        return $false
    }
}

function Start-CoolingCommandIfPending {
    if ($null -ne $coolingPowerShell) {
        return $false
    }

    if (-not (Test-Path -LiteralPath $CommandPath)) {
        return $false
    }

    # Cooling commands have priority, but they must wait for an already-running
    # Dell sensor or BIOS read so only one DCM operation exists at a time.
    if (Test-DellProviderBusy) {
        return $false
    }

    try {
        $raw =
            Get-Content `
                -LiteralPath $CommandPath `
                -Raw `
                -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $false
        }

        $command =
            $raw |
                ConvertFrom-Json `
                    -ErrorAction Stop

        Remove-Item `
            -LiteralPath $CommandPath `
            -Force `
            -ErrorAction SilentlyContinue

        if ([string]$command.action -ne
            'set-main-cooling') {
            throw (
                'Unsupported cooling action: ' +
                [string]$command.action
            )
        }

        $requestedValue =
            [int]$command.value

        if ($requestedValue -lt 0 -or
            $requestedValue -gt 100) {
            throw 'Cooling level must be between 0 and 100.'
        }

        $commandId =
            [string]$command.id

        if ([string]::IsNullOrWhiteSpace($commandId)) {
            throw 'Cooling command does not contain an ID.'
        }

        $coolingControl.State = 'Applying'
        $coolingControl.CommandId = $commandId
        $coolingControl.RequestedValue = $requestedValue
        $coolingControl.Error = ''
        $coolingControl.Updated =
            [datetime]::Now.ToString('o')

        # As soon as Tower attempts a non-zero level, assume ownership for
        # fail-safe purposes. If the UI disappears before completion, the
        # helper will still return the level to Dell Auto (0) on exit.
        if ($requestedValue -gt 0) {
            $script:towerOwnsCooling = $true

            [System.IO.File]::WriteAllText(
                $coolingOwnershipPath,
                'Tower may own a non-zero Dell cooling floor.',
                [System.Text.UTF8Encoding]::new($false)
            )
        }

        $powerShell =
            [powershell]::Create()

        $powerShell.RunspacePool =
            $runspacePool

        [void]$powerShell.AddScript(
            $coolingCommandScript
        )

        [void]$powerShell.AddArgument(
            $requestedValue
        )

        $script:coolingPowerShell =
            $powerShell

        $script:coolingAsync =
            $powerShell.BeginInvoke()

        $script:coolingStarted =
            [datetime]::Now

        return $true
    }
    catch {
        Remove-Item `
            -LiteralPath $CommandPath `
            -Force `
            -ErrorAction SilentlyContinue

        $coolingControl.State = 'Error'
        $coolingControl.Error =
            [string]$_.Exception.Message
        $coolingControl.Updated =
            [datetime]::Now.ToString('o')

        return $true
    }
}

function Complete-CoolingCommand {
    if ($null -eq $coolingPowerShell -or
        $null -eq $coolingAsync -or
        -not $coolingAsync.IsCompleted) {
        return $false
    }

    $requestedValue =
        $coolingControl.RequestedValue

    try {
        $result =
            @(
                $coolingPowerShell.EndInvoke(
                    $coolingAsync
                )
            ) |
                Select-Object -Last 1

        if ($null -eq $result) {
            throw 'Cooling command returned no result.'
        }

        $coolingControl.CurrentValue =
            [int]$result.CurrentValue

        $coolingControl.State = 'Applied'
        $coolingControl.Error = ''
        $coolingControl.Updated =
            [datetime]::Now.ToString('o')

        if ([int]$coolingControl.CurrentValue -eq 0) {
            $script:towerOwnsCooling = $false

            Remove-Item `
                -LiteralPath $coolingOwnershipPath `
                -Force `
                -ErrorAction SilentlyContinue
        }

        $biosCollector =
            Get-Collector 'DellBIOS'

        if ($null -ne $biosCollector) {
            $biosCollector.NextRun =
                [datetime]::Now
        }
    }
    catch {
        $coolingControl.State = 'Error'
        $coolingControl.Error =
            [string]$_.Exception.Message
        $coolingControl.Updated =
            [datetime]::Now.ToString('o')

        # If a write to 0 failed while Tower may own a non-zero floor, keep
        # ownership true so the final fail-safe attempts 0 again on exit.
        if ($null -ne $requestedValue -and
            [int]$requestedValue -gt 0) {
            $script:towerOwnsCooling = $true
        }
    }
    finally {
        try {
            $coolingPowerShell.Dispose()
        }
        catch {}

        $script:coolingPowerShell = $null
        $script:coolingAsync = $null
        $script:coolingStarted = $null
    }

    return $true
}

function Restore-TowerCoolingToDellAuto {
    if (-not [bool]$script:towerOwnsCooling) {
        return
    }

    try {
        $namespace = 'root/DCIM/SYSMAN'
        $attributeName =
            'Fan Speed Auto Level on CPU Memory Zone'

        $service =
            Get-CimInstance `
                -Namespace $namespace `
                -ClassName DCIM_BIOSService `
                -ErrorAction Stop |
            Select-Object -First 1

        if ($null -eq $service) {
            return
        }

        $result =
            $service |
            Invoke-CimMethod `
                -MethodName SetBIOSAttributes `
                -Arguments @{
                    AttributeName =
                        @($attributeName)
                    AttributeValue =
                        @('0')
                } `
                -ErrorAction Stop

        if ([int]$result.ReturnValue -eq 0) {
            $script:towerOwnsCooling = $false

            Remove-Item `
                -LiteralPath $coolingOwnershipPath `
                -Force `
                -ErrorAction SilentlyContinue
        }
    }
    catch {
        # The fallback itself must never prevent helper shutdown.
    }
}

if ([bool]$towerOwnsCooling -and
    -not (Test-Path -LiteralPath $CommandPath)) {
    $recoveryCommand =
        [pscustomobject]@{
            id =
                'recovery-' +
                [guid]::NewGuid().ToString('N')
            action = 'set-main-cooling'
            value = 0
            created = [datetime]::Now.ToString('o')
        } |
            ConvertTo-Json -Compress

    [System.IO.File]::WriteAllText(
        $CommandPath,
        $recoveryCommand,
        [System.Text.UTF8Encoding]::new($false)
    )
}

Write-CurrentSnapshot

try {
    while (-not (Test-Path -LiteralPath $StopPath) -and
        (Test-ParentProcessAlive)) {
        $changed = $false
        $now = [datetime]::Now

        if (Start-CoolingCommandIfPending) {
            $changed = $true
            Write-CurrentSnapshot
        }

        if (Complete-CoolingCommand) {
            $changed = $true
            Write-CurrentSnapshot
        }

        foreach ($collector in $collectors) {
            if ($null -eq $collector.PowerShell -and
                $now -ge $collector.NextRun) {
                if (Start-Collector $collector) {
                    $changed = $true
                }
            }
        }

        foreach ($collector in $collectors) {
            if (Complete-Collector $collector) {
                $changed = $true

                # Publish immediately after EACH individual source completes.
                Write-CurrentSnapshot
            }
        }

        Stop-HelperOnCoolingTimeout

        foreach ($name in @('DellSensors', 'DellBIOS')) {
            Report-CollectorTimeout (
                Get-Collector $name
            )
        }

        if ($changed) {
            Write-CurrentSnapshot
        }

        Start-Sleep -Milliseconds 200
    }
}
finally {
    if ($null -ne $coolingPowerShell) {
        try {
            $coolingPowerShell.Stop()
        }
        catch {}

        try {
            $coolingPowerShell.Dispose()
        }
        catch {}

        $script:coolingPowerShell = $null
        $script:coolingAsync = $null
        $script:coolingStarted = $null
    }

    foreach ($collector in $collectors) {
        if ($null -eq $collector.PowerShell) {
            continue
        }

        try {
            $collector.PowerShell.Stop()
        }
        catch {}

        try {
            $collector.PowerShell.Dispose()
        }
        catch {}
    }

    # All Dell reads are stopped before the fail-safe BIOS write so shutdown
    # preserves the same one-operation-at-a-time rule as normal runtime.
    Restore-TowerCoolingToDellAuto

    try {
        $runspacePool.Close()
    }
    catch {}

    try {
        $runspacePool.Dispose()
    }
    catch {}

    Remove-Item `
        -LiteralPath $CommandPath `
        -Force `
        -ErrorAction SilentlyContinue

    Remove-Item `
        -LiteralPath ($CommandPath + '.tmp') `
        -Force `
        -ErrorAction SilentlyContinue

    Remove-Item `
        -LiteralPath $StopPath `
        -Force `
        -ErrorAction SilentlyContinue

    Remove-Item `
        -LiteralPath $SnapshotPath `
        -Force `
        -ErrorAction SilentlyContinue
}
