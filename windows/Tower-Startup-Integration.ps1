# Windows Task Scheduler integration for Tower Control.
# Dot-sourced after the Settings tab has been created.

$script:towerAgentTaskName = 'Tower Background Agent'
$script:towerGuiTaskName = 'Tower Control - User Logon'
$script:towerAgentStatusPath = Join-Path $env:ProgramData 'Tower\agent-status.json'
$script:towerAgentInstaller = Join-Path $scriptDirectory 'Tower-Windows-Agent.ps1'

$startupGroup = New-Object System.Windows.Forms.GroupBox
$startupGroup.Text = 'Windows startup integration'
$startupGroup.Location = New-Object System.Drawing.Point(20, 565)
$startupGroup.Size = New-Object System.Drawing.Size(780, 225)
$settingsTab.Controls.Add($startupGroup)

$startupDescription = New-Object System.Windows.Forms.Label
$startupDescription.Text =
    'Uses Windows Task Scheduler. The background agent starts with Windows and talks to the Tower independently. ' +
    'The visible application starts 15 seconds after user logon.'
$startupDescription.Location = New-Object System.Drawing.Point(16, 28)
$startupDescription.Size = New-Object System.Drawing.Size(740, 44)
$startupDescription.ForeColor = [System.Drawing.Color]::DimGray
$startupGroup.Controls.Add($startupDescription)

$startupStatus = New-Object System.Windows.Forms.Label
$startupStatus.Text = 'Checking Windows Task Scheduler...'
$startupStatus.Location = New-Object System.Drawing.Point(16, 82)
$startupStatus.Size = New-Object System.Drawing.Size(740, 42)
$startupGroup.Controls.Add($startupStatus)

$startupInstallButton = New-Object System.Windows.Forms.Button
$startupInstallButton.Text = 'Install / Repair'
$startupInstallButton.Location = New-Object System.Drawing.Point(16, 137)
$startupInstallButton.Size = New-Object System.Drawing.Size(125, 34)
$startupGroup.Controls.Add($startupInstallButton)

$startupRemoveButton = New-Object System.Windows.Forms.Button
$startupRemoveButton.Text = 'Remove'
$startupRemoveButton.Location = New-Object System.Drawing.Point(151, 137)
$startupRemoveButton.Size = New-Object System.Drawing.Size(100, 34)
$startupGroup.Controls.Add($startupRemoveButton)

$startupRefreshButton = New-Object System.Windows.Forms.Button
$startupRefreshButton.Text = 'Refresh status'
$startupRefreshButton.Location = New-Object System.Drawing.Point(261, 137)
$startupRefreshButton.Size = New-Object System.Drawing.Size(120, 34)
$startupGroup.Controls.Add($startupRefreshButton)

$startupNote = New-Object System.Windows.Forms.Label
$startupNote.Text = 'Installation requires one Windows administrator/UAC confirmation.'
$startupNote.Location = New-Object System.Drawing.Point(16, 183)
$startupNote.Size = New-Object System.Drawing.Size(740, 25)
$startupNote.ForeColor = [System.Drawing.Color]::DimGray
$startupGroup.Controls.Add($startupNote)

function Get-TowerScheduledTask([string]$Name) {
    try {
        return Get-ScheduledTask -TaskName $Name -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Refresh-TowerStartupStatus {
    $agentTask = Get-TowerScheduledTask $script:towerAgentTaskName
    $guiTask = Get-TowerScheduledTask $script:towerGuiTaskName
    $installed = $null -ne $agentTask -and $null -ne $guiTask
    $agentState = if ($null -ne $agentTask) { [string]$agentTask.State } else { 'Not installed' }
    $guiState = if ($null -ne $guiTask) { [string]$guiTask.State } else { 'Not installed' }
    $connection = 'No agent heartbeat yet'
    try {
        if (Test-Path -LiteralPath $script:towerAgentStatusPath) {
            $status = Get-Content -LiteralPath $script:towerAgentStatusPath -Raw |
                ConvertFrom-Json
            $connection = [string]$status.message
        }
    }
    catch {
        $connection = 'Agent heartbeat could not be read'
    }
    $startupStatus.Text =
        "Background agent: $agentState | Tower Control: $guiState`r`n" +
        "Agent connection: $connection"
    $startupStatus.ForeColor = if ($installed) {
        [System.Drawing.Color]::ForestGreen
    } else {
        [System.Drawing.Color]::DarkOrange
    }
    $startupRemoveButton.Enabled = $installed
}

function Invoke-TowerStartupManager([ValidateSet('Install', 'Remove')] [string]$Mode) {
    if (-not (Test-Path -LiteralPath $script:towerAgentInstaller)) {
        throw "Startup agent file missing: $script:towerAgentInstaller"
    }
    if ($Mode -eq 'Install') {
        $expectedDirectory = Join-Path $env:ProgramFiles 'Tower Control'
        if (-not ([IO.Path]::GetFullPath($scriptDirectory).TrimEnd('\')).Equals(
                ([IO.Path]::GetFullPath($expectedDirectory).TrimEnd('\')),
                [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Run Install-Tower-Control.cmd first. Startup integration must point to the stable Program Files installation.'
        }
    }

    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $script:towerAgentInstaller),
        '-Mode', $Mode
    )
    $requestPath = ''
    if ($Mode -eq 'Install') {
        $requestPath = Join-Path $configDirectory (
            'startup-install-{0}.json' -f [Guid]::NewGuid().ToString('N')
        )
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        [ordered]@{
            server = [string]$config.server
            token = [string]$config.token
            appDirectory = [string]$scriptDirectory
            userId = [string]$identity
        } | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $requestPath -Encoding UTF8
        $arguments += @('-RequestPath', ('"{0}"' -f $requestPath))
    }

    try {
        $process = Start-Process `
            -FilePath 'powershell.exe' `
            -ArgumentList ($arguments -join ' ') `
            -Verb RunAs `
            -Wait `
            -PassThru
        if ($process.ExitCode -ne 0) {
            throw "Windows startup manager exited with code $($process.ExitCode)."
        }
    }
    finally {
        if (-not [string]::IsNullOrWhiteSpace($requestPath)) {
            Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep -Milliseconds 400
    Refresh-TowerStartupStatus
}

$startupInstallButton.Add_Click({
    try {
        Invoke-TowerStartupManager 'Install'
        [System.Windows.Forms.MessageBox]::Show(
            'The Tower background agent and user-logon startup task are installed.',
            'Tower startup integration', 'OK', 'Information'
        ) | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            'Tower startup installation failed', 'OK', 'Error'
        ) | Out-Null
    }
})

$startupRemoveButton.Add_Click({
    $answer = [System.Windows.Forms.MessageBox]::Show(
        'Remove both Tower scheduled startup tasks?',
        'Remove Tower startup integration', 'YesNo', 'Warning'
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    try {
        Invoke-TowerStartupManager 'Remove'
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            'Tower startup removal failed', 'OK', 'Error'
        ) | Out-Null
    }
})

$startupRefreshButton.Add_Click({ Refresh-TowerStartupStatus })
$settingsTab.AutoScroll = $true
Refresh-TowerStartupStatus
