param(
    [ValidateSet('Sync', 'RemoveAll')]
    [string]$Mode = 'Sync',
    [string]$RequestPath = ''
)

$ErrorActionPreference = 'Stop'
$taskFolderPath = '\RF Tower\Schedules'
$towerRoot = Join-Path $env:ProgramData 'Tower'
$logPath = Join-Path $towerRoot 'windows-scheduler.log'

function Test-TowerAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Write-TowerSchedulerLog([string]$Level, [string]$Message) {
    try {
        New-Item -ItemType Directory -Path $towerRoot -Force | Out-Null
        $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$stamp [$Level] $Message"
    }
    catch {}
}

function Get-TowerTaskFolder($service, [bool]$Create) {
    try {
        return $service.GetFolder($taskFolderPath)
    }
    catch {
        if (-not $Create) { return $null }
    }

    $root = $service.GetFolder('\')
    try {
        $towerFolder = $service.GetFolder('\RF Tower')
    }
    catch {
        $towerFolder = $root.CreateFolder('RF Tower', $null)
    }
    try {
        return $service.GetFolder($taskFolderPath)
    }
    catch {
        return $towerFolder.CreateFolder('Schedules', $null)
    }
}

function Remove-TowerTaskFolderIfEmpty($service) {
    try {
        $folder = $service.GetFolder($taskFolderPath)
        if ($folder.GetTasks(1).Count -eq 0 -and
            $folder.GetFolders(0).Count -eq 0) {
            $towerFolder = $service.GetFolder('\RF Tower')
            $towerFolder.DeleteFolder('Schedules', 0)
        }
    }
    catch {}
}

function New-TowerEventSubscription([string]$Log, [string]$Source, [int]$EventId) {
    if ([string]::IsNullOrWhiteSpace($Log) -or
        [string]::IsNullOrWhiteSpace($Source)) {
        throw 'Event schedules require a Windows log and source.'
    }
    if ($EventId -lt 0) { throw 'Event ID cannot be negative.' }
    $escapedLog = [Security.SecurityElement]::Escape($Log)
    $escapedSource = [Security.SecurityElement]::Escape($Source)
    return (
        '<QueryList><Query Id="0" Path="{0}"><Select Path="{0}">' +
        '*[System[Provider[@Name="{1}"] and (EventID={2})]]' +
        '</Select></Query></QueryList>'
    ) -f $escapedLog, $escapedSource, $EventId
}

function Register-TowerWindowsSchedule($service, $folder, $schedule, [string]$AppDirectory) {
    $scheduleId = [string]$schedule.id
    if ($scheduleId -notmatch '^[A-Fa-f0-9]{32}$') {
        throw "Invalid schedule ID: $scheduleId"
    }
    $commandScript = Join-Path $AppDirectory 'Tower-Agent-Command.ps1'
    if (-not (Test-Path -LiteralPath $commandScript)) {
        throw "Tower agent command helper is missing: $commandScript"
    }

    $definition = $service.NewTask(0)
    $definition.RegistrationInfo.Description =
        "RF Tower schedule: $([string]$schedule.name) [$scheduleId]"
    $definition.Principal.UserId = 'SYSTEM'
    $definition.Principal.LogonType = 5
    $definition.Principal.RunLevel = 1
    $definition.Settings.Enabled = [bool]$schedule.enabled
    $definition.Settings.StartWhenAvailable = $true
    $definition.Settings.DisallowStartIfOnBatteries = $false
    $definition.Settings.StopIfGoingOnBatteries = $false
    $definition.Settings.ExecutionTimeLimit = 'PT5M'
    $definition.Settings.MultipleInstances = 2

    $triggerType = [string]$schedule.trigger.type
    switch ($triggerType) {
        'windows_logon' {
            $trigger = $definition.Triggers.Create(9)
            if ([string]$schedule.trigger.userMode -eq 'specific') {
                $userId = ([string]$schedule.trigger.userId).Trim()
                if ([string]::IsNullOrWhiteSpace($userId)) {
                    throw "Schedule '$([string]$schedule.name)' requires a user."
                }
                $trigger.UserId = $userId
            }
        }
        'windows_startup' {
            $trigger = $definition.Triggers.Create(8)
        }
        'windows_idle' {
            $trigger = $definition.Triggers.Create(6)
            $definition.Settings.IdleSettings.IdleDuration = 'PT10M'
            $definition.Settings.IdleSettings.WaitTimeout = 'PT1H'
            $definition.Settings.IdleSettings.StopOnIdleEnd = $false
            $definition.Settings.IdleSettings.RestartOnIdle = $false
        }
        'windows_event' {
            $trigger = $definition.Triggers.Create(0)
            $trigger.Subscription = New-TowerEventSubscription `
                ([string]$schedule.trigger.log) `
                ([string]$schedule.trigger.source) `
                ([int]$schedule.trigger.eventId)
        }
        default {
            throw "Unsupported Windows trigger type: $triggerType"
        }
    }
    $trigger.Enabled = [bool]$schedule.enabled

    $powerShell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $action = $definition.Actions.Create(0)
    $action.Path = $powerShell
    $action.WorkingDirectory = $AppDirectory
    $action.Arguments =
        '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass ' +
        "-File `"$commandScript`" -ScheduleId `"$scheduleId`""

    # TASK_CREATE_OR_UPDATE=6, TASK_LOGON_SERVICE_ACCOUNT=5.
    [void]$folder.RegisterTaskDefinition(
        $scheduleId,
        $definition,
        6,
        'SYSTEM',
        $null,
        5,
        $null
    )
}

if (-not (Test-TowerAdministrator)) {
    throw 'Administrator rights are required to manage Tower Windows schedules.'
}

$service = New-Object -ComObject 'Schedule.Service'
$service.Connect()

try {
    if ($Mode -eq 'RemoveAll') {
        $folder = Get-TowerTaskFolder $service $false
        if ($null -ne $folder) {
            foreach ($task in @($folder.GetTasks(1))) {
                $folder.DeleteTask([string]$task.Name, 0)
            }
        }
        Remove-TowerTaskFolderIfEmpty $service
        Write-TowerSchedulerLog 'INFO' 'Removed all Tower Windows schedules.'
        exit 0
    }

    if ([string]::IsNullOrWhiteSpace($RequestPath) -or
        -not (Test-Path -LiteralPath $RequestPath)) {
        throw 'The Windows schedule synchronization request is missing.'
    }
    $request = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json
    $appDirectory = [string]$request.appDirectory
    if ([string]::IsNullOrWhiteSpace($appDirectory) -or
        -not (Test-Path -LiteralPath $appDirectory)) {
        throw 'The installed Tower Control directory is invalid.'
    }

    $desired = @($request.schedules)
    $folder = Get-TowerTaskFolder $service ($desired.Count -gt 0)
    if ($null -ne $folder) {
        $desiredIds = @($desired | ForEach-Object { [string]$_.id })
        foreach ($existing in @($folder.GetTasks(1))) {
            if ($desiredIds -notcontains [string]$existing.Name) {
                $folder.DeleteTask([string]$existing.Name, 0)
            }
        }
        foreach ($schedule in $desired) {
            Register-TowerWindowsSchedule $service $folder $schedule $appDirectory
        }
    }
    Remove-TowerTaskFolderIfEmpty $service
    Write-TowerSchedulerLog 'INFO' "Synchronized $($desired.Count) Tower Windows schedule(s)."
    exit 0
}
catch {
    Write-TowerSchedulerLog 'ERROR' $_.Exception.Message
    Write-Error $_
    exit 1
}
finally {
    if (-not [string]::IsNullOrWhiteSpace($RequestPath)) {
        Remove-Item -LiteralPath $RequestPath -Force -ErrorAction SilentlyContinue
    }
}
