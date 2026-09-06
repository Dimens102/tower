param(
    [ValidateSet('Install', 'Remove')]
    [string]$Mode = 'Install'
)

$ErrorActionPreference = 'Stop'
$installDirectory = $PSScriptRoot
$towerData = Join-Path $env:ProgramData 'Tower'
$msiLog = Join-Path $towerData 'msi-install.log'

function Write-MsiLog([string]$Message) {
    New-Item -ItemType Directory -Path $towerData -Force | Out-Null
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    Add-Content -LiteralPath $msiLog -Encoding UTF8 -Value "$stamp $Message"
}

function Get-InteractiveTowerProfile {
    $computer = Get-CimInstance Win32_ComputerSystem
    $userId = [string]$computer.UserName
    if ([string]::IsNullOrWhiteSpace($userId)) {
        return $null
    }

    $userName = ($userId -split '\\')[-1]
    $profile = Get-CimInstance Win32_UserProfile |
        Where-Object {
            $_.Loaded -and $_.LocalPath -and
            (Split-Path $_.LocalPath -Leaf) -ieq $userName
        } |
        Select-Object -First 1
    if ($null -eq $profile) {
        return $null
    }
    [pscustomobject]@{
        UserId = $userId
        ClientConfigPath = Join-Path $profile.LocalPath 'AppData\Roaming\Tower\client.json'
    }
}

try {
    if ($Mode -eq 'Remove') {
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
            Where-Object {
                $_.ProcessId -ne $PID -and
                [string]$_.CommandLine -like "*$installDirectory*Tower-Control.ps1*"
            } |
            ForEach-Object {
                Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            }
        $agent = Join-Path $installDirectory 'Tower-Windows-Agent.ps1'
        $scheduleManager = Join-Path $installDirectory 'Tower-Windows-Schedule-Manager.ps1'
        if (Test-Path -LiteralPath $scheduleManager) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass `
                -File $scheduleManager -Mode RemoveAll
            if ($LASTEXITCODE -ne 0) {
                throw "Tower Windows-schedule cleanup failed with code $LASTEXITCODE."
            }
        }
        if (Test-Path -LiteralPath $agent) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass `
                -File $agent -Mode Remove
        }
        Write-MsiLog 'Tower Control MSI uninstall cleanup completed.'
        exit 0
    }

    $interactiveProfile = Get-InteractiveTowerProfile
    if ($null -eq $interactiveProfile) {
        Write-MsiLog 'Tower Control installed without startup integration: no logged-in user profile was found.'
        exit 0
    }
    $clientConfigPath = $interactiveProfile.ClientConfigPath
    if (-not (Test-Path -LiteralPath $clientConfigPath)) {
        Write-MsiLog (
            'Tower Control installed without startup integration: ' +
            "client configuration not found at $clientConfigPath"
        )
        exit 0
    }

    $clientConfig = Get-Content -LiteralPath $clientConfigPath -Raw |
        ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace([string]$clientConfig.server) -or
        [string]::IsNullOrWhiteSpace([string]$clientConfig.token)) {
        Write-MsiLog (
            'Tower Control installed without startup integration: ' +
            'client configuration has no server or token.'
        )
        exit 0
    }

    $requestPath = Join-Path $env:TEMP (
        'tower-msi-install-{0}.json' -f [Guid]::NewGuid().ToString('N')
    )
    [ordered]@{
        server = ([string]$clientConfig.server).TrimEnd('/')
        token = [string]$clientConfig.token
        appDirectory = $installDirectory
        userId = $interactiveProfile.UserId
    } | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $requestPath -Encoding UTF8

    $agent = Join-Path $installDirectory 'Tower-Windows-Agent.ps1'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File $agent -Mode Install -RequestPath $requestPath
    if ($LASTEXITCODE -ne 0) {
        throw "Tower background-agent setup failed with code $LASTEXITCODE."
    }

    Start-ScheduledTask -TaskName 'Tower Control - User Logon'
    Write-MsiLog 'Tower Control MSI installation and startup integration completed.'
    exit 0
}
catch {
    Write-MsiLog "Tower Control MSI configuration failed: $($_.Exception.Message)"
    throw
}
finally {
    if ($requestPath) {
        Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue
    }
}
