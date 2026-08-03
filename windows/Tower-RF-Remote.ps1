Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

$ErrorActionPreference = 'Stop'
$configDirectory = Join-Path $env:APPDATA 'Tower'
$configPath = Join-Path $configDirectory 'client.json'

function Get-TowerConfig {
    if (Test-Path $configPath) {
        return Get-Content $configPath -Raw | ConvertFrom-Json
    }

    $server = [Microsoft.VisualBasic.Interaction]::InputBox(
        'Enter the Tower address, for example http://192.168.2.20:8080',
        'Tower connection',
        'http://PI3A:8080')
    if ([string]::IsNullOrWhiteSpace($server)) { return $null }

    $token = [Microsoft.VisualBasic.Interaction]::InputBox(
        'Enter the same token used when starting Tower service.',
        'Tower authentication token',
        '')
    if ([string]::IsNullOrWhiteSpace($token)) { return $null }

    New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
    $config = [pscustomobject]@{
        server = $server.TrimEnd('/')
        token = $token
    }
    $config | ConvertTo-Json | Set-Content -Path $configPath -Encoding UTF8
    return $config
}

$config = Get-TowerConfig
if ($null -eq $config) { exit }

$headers = @{ Authorization = "Bearer $($config.token)" }
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Tower RF Remote'
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(540, 220)
$form.Size = New-Object System.Drawing.Size(700, 500)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'RF Power Controls'
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(18, 16)
$form.Controls.Add($title)

$status = New-Object System.Windows.Forms.Label
$status.Text = 'Connecting...'
$status.AutoSize = $true
$status.Location = New-Object System.Drawing.Point(20, 52)
$form.Controls.Add($status)

$panel = New-Object System.Windows.Forms.FlowLayoutPanel
$panel.Location = New-Object System.Drawing.Point(18, 82)
$panel.Anchor = 'Top,Bottom,Left,Right'
$panel.Size = New-Object System.Drawing.Size(648, 360)
$panel.AutoScroll = $true
$panel.FlowDirection = 'TopDown'
$panel.WrapContents = $false
$form.Controls.Add($panel)

function Send-RfAction([string]$deviceId, [string]$action, [string]$displayName) {
    try {
        $status.Text = "Sending $action to $displayName..."
        $form.Refresh()
        $body = @{ device = $deviceId; action = $action } | ConvertTo-Json -Compress
        Invoke-RestMethod -Method Post `
            -Uri "$($config.server)/api/v1/rf/send" `
            -Headers $headers `
            -ContentType 'application/json' `
            -Body $body | Out-Null
        $status.Text = "${displayName}: $action sent"
    }
    catch {
        $status.Text = 'Send failed'
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            'Tower RF error',
            'OK',
            'Error') | Out-Null
    }
}

try {
    $response = Invoke-RestMethod `
        -Uri "$($config.server)/api/v1/rf/devices" `
        -Headers $headers `
        -Method Get

    foreach ($device in $response.devices) {
        $row = New-Object System.Windows.Forms.Panel
        $row.Size = New-Object System.Drawing.Size(610, 54)
        $row.Margin = New-Object System.Windows.Forms.Padding(3, 3, 3, 6)

        $label = New-Object System.Windows.Forms.Label
        $label.Text = $device.name
        $label.AutoEllipsis = $true
        $label.Location = New-Object System.Drawing.Point(4, 15)
        $label.Size = New-Object System.Drawing.Size(330, 26)
        $row.Controls.Add($label)

        $onButton = New-Object System.Windows.Forms.Button
        $onButton.Text = 'On'
        $onButton.Location = New-Object System.Drawing.Point(350, 8)
        $onButton.Size = New-Object System.Drawing.Size(110, 38)
        $capturedId = [string]$device.id
        $capturedName = [string]$device.name
        $onButton.Add_Click({ Send-RfAction $capturedId 'on' $capturedName }.GetNewClosure())
        $row.Controls.Add($onButton)

        $offButton = New-Object System.Windows.Forms.Button
        $offButton.Text = 'Off'
        $offButton.Location = New-Object System.Drawing.Point(470, 8)
        $offButton.Size = New-Object System.Drawing.Size(110, 38)
        $offButton.Add_Click({ Send-RfAction $capturedId 'off' $capturedName }.GetNewClosure())
        $row.Controls.Add($offButton)

        $panel.Controls.Add($row)
    }

    $status.Text = "Connected to $($config.server) - $($response.devices.Count) RF devices"
}
catch {
    $status.Text = 'Connection failed'
    [System.Windows.Forms.MessageBox]::Show(
        "$($_.Exception.Message)`n`nConfiguration: $configPath",
        'Tower connection error',
        'OK',
        'Error') | Out-Null
}

[void]$form.ShowDialog()
