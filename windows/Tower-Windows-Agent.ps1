param(
    [ValidateSet('Run', 'Install', 'Remove')]
    [string]$Mode = 'Run',
    [string]$RequestPath = ''
)

$ErrorActionPreference = 'Stop'
$taskAgentName = 'Tower Background Agent'
$taskGuiName = 'Tower Control - User Logon'
$towerRoot = Join-Path $env:ProgramData 'Tower'
$configPath = Join-Path $towerRoot 'agent.json'
$statusPath = Join-Path $towerRoot 'agent-status.json'
$logPath = Join-Path $towerRoot 'agent.log'
$queuePath = Join-Path $towerRoot 'Queue'
$completedPath = Join-Path $towerRoot 'Completed'
$failedPath = Join-Path $towerRoot 'Failed'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Write-AgentLog([string]$Level, [string]$Message) {
    try {
        New-Item -ItemType Directory -Path $towerRoot -Force | Out-Null
        $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        Add-Content -Path $logPath -Encoding UTF8 -Value "$stamp [$Level] $Message"
    }
    catch {}
}

function Write-AgentStatus(
    [string]$State,
    [string]$Message,
    [bool]$Connected,
    [string]$LastConnectionUtc = '') {
    try {
        $payload = [ordered]@{
            state = $State
            message = $Message
            connected = $Connected
            processId = $PID
            updatedUtc = [DateTime]::UtcNow.ToString('o')
            lastConnectionUtc = $LastConnectionUtc
        }
        $temporary = "$statusPath.tmp"
        $payload | ConvertTo-Json -Depth 10 |
            Set-Content -Path $temporary -Encoding UTF8
        Move-Item -Path $temporary -Destination $statusPath -Force
    }
    catch {}
}

function Protect-AgentConfig([string]$Path) {
    $acl = New-Object Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    $inherit = [Security.AccessControl.InheritanceFlags]::None
    $propagate = [Security.AccessControl.PropagationFlags]::None
    $allow = [Security.AccessControl.AccessControlType]::Allow
    foreach ($sidText in @('S-1-5-18', 'S-1-5-32-544')) {
        $sid = New-Object Security.Principal.SecurityIdentifier($sidText)
        $rule = New-Object Security.AccessControl.FileSystemAccessRule(
            $sid,
            [Security.AccessControl.FileSystemRights]::FullControl,
            $inherit,
            $propagate,
            $allow
        )
        $acl.AddAccessRule($rule)
    }
    Set-Acl -Path $Path -AclObject $acl
}

function Install-TowerIntegration {
    if (-not (Test-IsAdministrator)) {
        throw 'Administrator rights are required to install startup integration.'
    }
    if ([string]::IsNullOrWhiteSpace($RequestPath) -or
        -not (Test-Path -LiteralPath $RequestPath)) {
        throw 'The Tower installation request is missing.'
    }

    $request = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace([string]$request.server) -or
        [string]::IsNullOrWhiteSpace([string]$request.token) -or
        [string]::IsNullOrWhiteSpace([string]$request.appDirectory) -or
        [string]::IsNullOrWhiteSpace([string]$request.userId)) {
        throw 'The Tower installation request is incomplete.'
    }

    $launcher = Join-Path ([string]$request.appDirectory) 'Start-Tower-Control.vbs'
    if (-not (Test-Path -LiteralPath $launcher)) {
        throw "Tower Control launcher not found: $launcher"
    }
    $installedAgent = Join-Path `
        ([string]$request.appDirectory) `
        'Tower-Windows-Agent.ps1'
    if (-not (Test-Path -LiteralPath $installedAgent)) {
        throw "Tower background agent not found: $installedAgent"
    }

    Stop-ScheduledTask -TaskName $taskAgentName -ErrorAction SilentlyContinue

    New-Item -ItemType Directory -Path $queuePath -Force | Out-Null
    New-Item -ItemType Directory -Path $completedPath -Force | Out-Null
    New-Item -ItemType Directory -Path $failedPath -Force | Out-Null
    [ordered]@{
        server = ([string]$request.server).TrimEnd('/')
        token = [string]$request.token
        pollSeconds = 5
        requestTimeoutSeconds = 10
    } | ConvertTo-Json -Depth 10 |
        Set-Content -Path $configPath -Encoding UTF8
    Protect-AgentConfig $configPath

    $powerShell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $agentArguments =
        '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass ' +
        "-File `"$installedAgent`" -Mode Run"
    $agentAction = New-ScheduledTaskAction `
        -Execute $powerShell `
        -Argument $agentArguments `
        -WorkingDirectory ([string]$request.appDirectory)
    $agentTrigger = New-ScheduledTaskTrigger -AtStartup
    $agentPrincipal = New-ScheduledTaskPrincipal `
        -UserId 'SYSTEM' `
        -LogonType ServiceAccount `
        -RunLevel Highest
    $agentSettings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RestartCount 999 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -MultipleInstances IgnoreNew
    Register-ScheduledTask `
        -TaskName $taskAgentName `
        -Action $agentAction `
        -Trigger $agentTrigger `
        -Principal $agentPrincipal `
        -Settings $agentSettings `
        -Description 'Starts the RF Tower background API and schedule agent at Windows startup.' `
        -Force | Out-Null

    $controlScript = Join-Path `
        ([string]$request.appDirectory) `
        'Tower-Control.ps1'
    if (-not (Test-Path -LiteralPath $controlScript)) {
        throw "Tower Control script not found: $controlScript"
    }
    $guiArguments =
        '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass ' +
        "-File `"$controlScript`""
    $guiAction = New-ScheduledTaskAction `
        -Execute $powerShell `
        -Argument $guiArguments `
        -WorkingDirectory ([string]$request.appDirectory)
    $guiTrigger = New-ScheduledTaskTrigger `
        -AtLogOn `
        -User ([string]$request.userId)
    $guiTrigger.Delay = 'PT15S'
    $guiPrincipal = New-ScheduledTaskPrincipal `
        -UserId ([string]$request.userId) `
        -LogonType Interactive `
        -RunLevel Highest
    $guiSettings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RestartCount 5 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -MultipleInstances IgnoreNew
    Register-ScheduledTask `
        -TaskName $taskGuiName `
        -Action $guiAction `
        -Trigger $guiTrigger `
        -Principal $guiPrincipal `
        -Settings $guiSettings `
        -Description 'Starts the visible RF Tower Control application after user logon.' `
        -Force | Out-Null

    Start-ScheduledTask -TaskName $taskAgentName
    Write-AgentLog 'INFO' 'Windows startup integration installed or repaired.'
}

function Remove-TowerIntegration {
    if (-not (Test-IsAdministrator)) {
        throw 'Administrator rights are required to remove startup integration.'
    }
    foreach ($name in @($taskAgentName, $taskGuiName)) {
        Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $name -Confirm:$false `
            -ErrorAction SilentlyContinue
    }
    Get-Process powershell -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $_.Path -and $_.Id -ne $PID -and
                (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine `
                    -like '*Tower-Windows-Agent.ps1*Mode Run*'
            }
            catch { $false }
        } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $statusPath -Force -ErrorAction SilentlyContinue
    Write-AgentLog 'INFO' 'Windows startup integration removed.'
}

function Invoke-AgentRequest($Config, [string]$Method, [string]$Path, $Body = $null) {
    if ($Path -notmatch '^/api/v1/[A-Za-z0-9_./-]+$') {
        throw "Blocked invalid Tower API path: $Path"
    }
    if ($Method -notin @('GET', 'POST')) {
        throw "Blocked unsupported HTTP method: $Method"
    }
    $parameters = @{
        Method = $Method
        Uri = "$($Config.server)$Path"
        Headers = @{ Authorization = "Bearer $($Config.token)" }
        DisableKeepAlive = $true
        TimeoutSec = [int]$Config.requestTimeoutSeconds
    }
    if ($Method -eq 'POST') {
        $parameters.ContentType = 'application/json'
        $parameters.Body = if ($null -eq $Body) {
            '{}'
        } else {
            ConvertTo-Json -InputObject $Body -Depth 50 -Compress
        }
    }
    return Invoke-RestMethod @parameters
}

function Move-AgentJob([string]$Source, [string]$DestinationDirectory) {
    $name = [IO.Path]::GetFileName($Source)
    $destination = Join-Path $DestinationDirectory $name
    Move-Item -LiteralPath $Source -Destination $destination -Force
}

function Run-TowerAgent {
    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "Tower agent configuration not found: $configPath"
    }
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    # Local Tower traffic must not wait for Windows proxy auto-discovery.
    [Net.WebRequest]::DefaultWebProxy = New-Object Net.WebProxy
    $lastConnectionUtc = ''
    Write-AgentLog 'INFO' "Agent started as $([Security.Principal.WindowsIdentity]::GetCurrent().Name)."
    Write-AgentStatus 'starting' 'Waiting for Tower connectivity' $false

    while ($true) {
        $connected = $false
        $message = 'Tower unavailable'
        try {
            $null = Invoke-AgentRequest $config 'GET' '/api/v1/status'
            $connected = $true
            $message = 'Connected to Tower'
            $lastConnectionUtc = [DateTime]::UtcNow.ToString('o')
        }
        catch {
            $message = "Tower connection failed: $($_.Exception.Message)"
        }

        if ($connected) {
            foreach ($file in @(Get-ChildItem -LiteralPath $queuePath -Filter '*.json' |
                    Sort-Object CreationTimeUtc)) {
                try {
                    $job = Get-Content -LiteralPath $file.FullName -Raw |
                        ConvertFrom-Json
                    $method = ([string]$job.method).ToUpperInvariant()
                    $null = Invoke-AgentRequest `
                        $config `
                        $method `
                        ([string]$job.path) `
                        $job.body
                    Move-AgentJob $file.FullName $completedPath
                    Write-AgentLog 'INFO' "Completed queued job $($file.Name)."
                }
                catch {
                    Write-AgentLog 'ERROR' "Queued job $($file.Name) failed: $($_.Exception.Message)"
                    Move-AgentJob $file.FullName $failedPath
                }
            }
        }

        Write-AgentStatus `
            $(if ($connected) { 'ready' } else { 'waiting' }) `
            $message `
            $connected `
            $lastConnectionUtc
        Start-Sleep -Seconds ([Math]::Max(2, [int]$config.pollSeconds))
    }
}

try {
    switch ($Mode) {
        'Install' { Install-TowerIntegration }
        'Remove' { Remove-TowerIntegration }
        default { Run-TowerAgent }
    }
    exit 0
}
catch {
    Write-AgentLog 'ERROR' "$Mode failed: $($_.Exception.Message)"
    if ($Mode -eq 'Run') {
        Write-AgentStatus 'failed' $_.Exception.Message $false
    }
    Write-Error $_
    exit 1
}
finally {
    if ($Mode -eq 'Install' -and
        -not [string]::IsNullOrWhiteSpace($RequestPath)) {
        Remove-Item -LiteralPath $RequestPath -Force -ErrorAction SilentlyContinue
    }
}
