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
$script:rfDevices = @()
$script:irDevices = @()

function Invoke-TowerGet([string]$path) {
    return Invoke-RestMethod -Method Get `
        -Uri "$($config.server)$path" `
        -Headers $headers `
        -TimeoutSec 5
}

function Invoke-TowerPost([string]$path, [hashtable]$content) {
    $body = $content | ConvertTo-Json -Compress
    return Invoke-RestMethod -Method Post `
        -Uri "$($config.server)$path" `
        -Headers $headers `
        -ContentType 'application/json' `
        -Body $body `
        -TimeoutSec 20
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Tower Control'
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(850, 580)
$form.Size = New-Object System.Drawing.Size(1100, 760)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 76
$header.BackColor = [System.Drawing.Color]::FromArgb(35, 42, 52)
$form.Controls.Add($header)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Tower Control'
$title.ForeColor = [System.Drawing.Color]::White
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 18)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(18, 9)
$header.Controls.Add($title)

$status = New-Object System.Windows.Forms.Label
$status.Text = 'Connecting...'
$status.ForeColor = [System.Drawing.Color]::Gainsboro
$status.AutoEllipsis = $true
$status.Location = New-Object System.Drawing.Point(21, 46)
$status.Size = New-Object System.Drawing.Size(820, 24)
$status.Anchor = 'Top,Left,Right'
$header.Controls.Add($status)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = 'Refresh All'
$refreshButton.Size = New-Object System.Drawing.Size(120, 38)
$refreshButton.Location = New-Object System.Drawing.Point(940, 18)
$refreshButton.Anchor = 'Top,Right'
$refreshButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$refreshButton.UseVisualStyleBackColor = $false
$refreshButton.BackColor = [System.Drawing.Color]::FromArgb(60, 72, 88)
$refreshButton.ForeColor = [System.Drawing.Color]::White
$refreshButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(150, 160, 172)
$refreshButton.FlatAppearance.BorderSize = 1
$header.Controls.Add($refreshButton)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$tabs.Padding = New-Object System.Drawing.Point(16, 7)
$form.Controls.Add($tabs)
$tabs.BringToFront()

$sensorsTab = New-Object System.Windows.Forms.TabPage
$sensorsTab.Text = 'Sensors'
$sensorsTab.Padding = New-Object System.Windows.Forms.Padding(12)
$tabs.TabPages.Add($sensorsTab)

$sensorPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$sensorPanel.Dock = 'Fill'
$sensorPanel.AutoScroll = $true
$sensorPanel.WrapContents = $true
$sensorPanel.FlowDirection = 'LeftToRight'
$sensorsTab.Controls.Add($sensorPanel)

$rfTab = New-Object System.Windows.Forms.TabPage
$rfTab.Text = 'RF Power'
$rfTab.Padding = New-Object System.Windows.Forms.Padding(12)
$tabs.TabPages.Add($rfTab)

$rfTop = New-Object System.Windows.Forms.Panel
$rfTop.Dock = 'Top'
$rfTop.Height = 64
$rfTab.Controls.Add($rfTop)

$allOnButton = New-Object System.Windows.Forms.Button
$allOnButton.Text = 'ALL ON'
$allOnButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
$allOnButton.BackColor = [System.Drawing.Color]::FromArgb(210, 242, 218)
$allOnButton.Size = New-Object System.Drawing.Size(160, 46)
$allOnButton.Location = New-Object System.Drawing.Point(0, 4)
$rfTop.Controls.Add($allOnButton)

$allOffButton = New-Object System.Windows.Forms.Button
$allOffButton.Text = 'ALL OFF'
$allOffButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
$allOffButton.BackColor = [System.Drawing.Color]::FromArgb(250, 218, 218)
$allOffButton.Size = New-Object System.Drawing.Size(160, 46)
$allOffButton.Location = New-Object System.Drawing.Point(174, 4)
$rfTop.Controls.Add($allOffButton)

$rfPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$rfPanel.Dock = 'Fill'
$rfPanel.AutoScroll = $true
$rfPanel.FlowDirection = 'TopDown'
$rfPanel.WrapContents = $false
$rfTab.Controls.Add($rfPanel)
$rfPanel.BringToFront()

$irTab = New-Object System.Windows.Forms.TabPage
$irTab.Text = 'IR Remotes'
$irTab.Padding = New-Object System.Windows.Forms.Padding(8)
$tabs.TabPages.Add($irTab)

$irSplit = New-Object System.Windows.Forms.SplitContainer
$irSplit.Dock = 'Fill'
$irSplit.SplitterDistance = 275
$irSplit.FixedPanel = 'Panel1'
$irTab.Controls.Add($irSplit)

$irDeviceList = New-Object System.Windows.Forms.ListBox
$irDeviceList.Dock = 'Fill'
$irDeviceList.IntegralHeight = $false
$irSplit.Panel1.Controls.Add($irDeviceList)

$irHeading = New-Object System.Windows.Forms.Label
$irHeading.Dock = 'Top'
$irHeading.Height = 64
$irHeading.Padding = New-Object System.Windows.Forms.Padding(10, 7, 4, 4)
$irHeading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 14)
$irHeading.Text = 'Select an IR device'
$irSplit.Panel2.Controls.Add($irHeading)

$irCommandPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$irCommandPanel.Dock = 'Fill'
$irCommandPanel.AutoScroll = $true
$irCommandPanel.WrapContents = $true
$irCommandPanel.FlowDirection = 'LeftToRight'
$irCommandPanel.Padding = New-Object System.Windows.Forms.Padding(7)
$irSplit.Panel2.Controls.Add($irCommandPanel)
$irCommandPanel.BringToFront()

$toolTip = New-Object System.Windows.Forms.ToolTip

function Set-TowerStatus([string]$text, [bool]$isError = $false) {
    $status.Text = $text
    $status.ForeColor = if ($isError) {
        [System.Drawing.Color]::FromArgb(255, 170, 170)
    } else {
        [System.Drawing.Color]::Gainsboro
    }
}

function Format-SensorValue($measurement) {
    $value = [double]$measurement.value
    $culture = [System.Globalization.CultureInfo]::CurrentCulture

    if ($measurement.unit -eq 'C') {
        return "$($value.ToString('0.0', $culture)) $([char]0x00B0)C"
    }
    if ($measurement.unit -eq '%') {
        return "$($value.ToString('0.0', $culture)) %"
    }
    if ($measurement.unit -eq 'hPa') {
        return "$($value.ToString('0.0', $culture)) hPa"
    }
    if ($measurement.unit -eq 'ohm') {
        if ([Math]::Abs($value) -ge 1000) {
            return "$(($value / 1000).ToString('0.0', $culture)) k$([char]0x03A9)"
        }
        return "$($value.ToString('0', $culture)) $([char]0x03A9)"
    }

    return "$($value.ToString('0.0', $culture)) $($measurement.unit)".Trim()
}

function Format-SensorAge([long]$ageSeconds) {
    if ($ageSeconds -lt 0 -or $ageSeconds -lt 5) { return 'Updated just now' }
    if ($ageSeconds -lt 60) { return "Updated $ageSeconds seconds ago" }

    $minutes = [Math]::Floor($ageSeconds / 60)
    if ($minutes -eq 1) { return 'Updated 1 minute ago' }
    return "Updated $minutes minutes ago"
}

function Refresh-Sensors {
    try {
        $response = Invoke-TowerGet '/api/v1/sensors'
        $sensorPanel.SuspendLayout()
        $sensorPanel.Controls.Clear()

        foreach ($sensor in @($response.sensors)) {
            $card = New-Object System.Windows.Forms.GroupBox
            $card.Text = [string]$sensor.name
            $card.Size = New-Object System.Drawing.Size(315, 210)
            $card.Margin = New-Object System.Windows.Forms.Padding(8)
            $card.Padding = New-Object System.Windows.Forms.Padding(12)

            if (-not [bool]$sensor.available) {
                $unavailable = New-Object System.Windows.Forms.Label
                $unavailable.Text = 'No reading available'
                $unavailable.ForeColor = [System.Drawing.Color]::DarkRed
                $unavailable.AutoSize = $true
                $unavailable.Location = New-Object System.Drawing.Point(15, 34)
                $card.Controls.Add($unavailable)
            } else {
                $y = 31
                foreach ($measurement in @($sensor.measurements)) {
                    $nameLabel = New-Object System.Windows.Forms.Label
                    $nameLabel.Text = [string]$measurement.name
                    $nameLabel.Location = New-Object System.Drawing.Point(15, $y)
                    $nameLabel.Size = New-Object System.Drawing.Size(135, 25)
                    $card.Controls.Add($nameLabel)

                    $valueLabel = New-Object System.Windows.Forms.Label
                    $valueLabel.Text = Format-SensorValue $measurement
                    $valueLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
                    $valueLabel.TextAlign = 'MiddleRight'
                    $valueLabel.Location = New-Object System.Drawing.Point(148, ($y - 2))
                    $valueLabel.Size = New-Object System.Drawing.Size(145, 27)
                    $card.Controls.Add($valueLabel)
                    $y += 32
                }

                $ageLabel = New-Object System.Windows.Forms.Label
                $ageLabel.Text = Format-SensorAge ([long]$sensor.ageSeconds)
                $ageLabel.ForeColor = [System.Drawing.Color]::DimGray
                $ageLabel.Location = New-Object System.Drawing.Point(15, 178)
                $ageLabel.Size = New-Object System.Drawing.Size(275, 23)
                $card.Controls.Add($ageLabel)
            }
            $sensorPanel.Controls.Add($card)
        }
        $sensorPanel.ResumeLayout()
    }
    catch {
        Set-TowerStatus 'Sensor refresh failed' $true
    }
}

function Send-RfAction([string]$deviceId, [string]$action, [string]$displayName) {
    try {
        Set-TowerStatus "Sending $action to $displayName..."
        $form.Refresh()
        Invoke-TowerPost '/api/v1/rf/send' @{ device = $deviceId; action = $action } | Out-Null
        Set-TowerStatus "${displayName}: $action sent"
    }
    catch {
        Set-TowerStatus "${displayName}: $action failed" $true
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message, 'Tower RF error', 'OK', 'Error') | Out-Null
    }
}

function Send-AllRfAction([string]$action) {
    try {
        Set-TowerStatus "Sending $action to every RF power device..."
        $form.Refresh()
        $response = Invoke-TowerPost '/api/v1/rf/all' @{ action = $action }
        $count = @($response.results).Count
        Set-TowerStatus "All RF devices: $action sent to $count devices"
    }
    catch {
        Set-TowerStatus "RF All $action failed" $true
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message, 'Tower RF All error', 'OK', 'Error') | Out-Null
    }
}

function Load-RfDevices {
    $response = Invoke-TowerGet '/api/v1/rf/devices'
    $script:rfDevices = @($response.devices)
    $rfPanel.SuspendLayout()
    $rfPanel.Controls.Clear()

    foreach ($device in $script:rfDevices) {
        $row = New-Object System.Windows.Forms.Panel
        $row.Size = New-Object System.Drawing.Size(780, 58)
        $row.Margin = New-Object System.Windows.Forms.Padding(3, 3, 3, 7)

        $label = New-Object System.Windows.Forms.Label
        $label.Text = [string]$device.name
        $label.AutoEllipsis = $true
        $label.Location = New-Object System.Drawing.Point(5, 16)
        $label.Size = New-Object System.Drawing.Size(430, 27)
        $row.Controls.Add($label)

        $onButton = New-Object System.Windows.Forms.Button
        $onButton.Text = 'On'
        $onButton.Location = New-Object System.Drawing.Point(450, 7)
        $onButton.Size = New-Object System.Drawing.Size(140, 42)
        $capturedId = [string]$device.id
        $capturedName = [string]$device.name
        $onButton.Add_Click({ Send-RfAction $capturedId 'on' $capturedName }.GetNewClosure())
        $row.Controls.Add($onButton)

        $offButton = New-Object System.Windows.Forms.Button
        $offButton.Text = 'Off'
        $offButton.Location = New-Object System.Drawing.Point(605, 7)
        $offButton.Size = New-Object System.Drawing.Size(140, 42)
        $offButton.Add_Click({ Send-RfAction $capturedId 'off' $capturedName }.GetNewClosure())
        $row.Controls.Add($offButton)
        $rfPanel.Controls.Add($row)
    }
    $rfPanel.ResumeLayout()
}

function Send-IrCommand([string]$deviceId, [string]$commandId, [string]$displayName) {
    try {
        Set-TowerStatus "Sending $displayName..."
        $form.Refresh()
        $response = Invoke-TowerPost '/api/v1/execute' @{ device = $deviceId; command = $commandId }
        Set-TowerStatus "${displayName}: $($response.message)"
    }
    catch {
        Set-TowerStatus "$displayName failed" $true
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message, 'Tower IR error', 'OK', 'Error') | Out-Null
    }
}

function Show-IrDevice($device) {
    $irCommandPanel.SuspendLayout()
    $irCommandPanel.Controls.Clear()

    if ($null -eq $device) {
        $irHeading.Text = 'Select an IR device'
        $irCommandPanel.ResumeLayout()
        return
    }

    $detailParts = @()
    if (-not [string]::IsNullOrWhiteSpace([string]$device.manufacturer)) { $detailParts += [string]$device.manufacturer }
    if (-not [string]::IsNullOrWhiteSpace([string]$device.location)) { $detailParts += [string]$device.location }
    $detail = if ($detailParts.Count -gt 0) { '  -  ' + ($detailParts -join ' / ') } else { '' }
    $irHeading.Text = "$($device.name)$detail"

    foreach ($command in @($device.commands | Where-Object { $_.transport -eq 'IR' -and $_.enabled })) {
        $button = New-Object System.Windows.Forms.Button
        $button.Text = if ([string]::IsNullOrWhiteSpace([string]$command.name)) { [string]$command.id } else { [string]$command.name }
        $button.Size = New-Object System.Drawing.Size(175, 52)
        $button.Margin = New-Object System.Windows.Forms.Padding(7)
        $capturedDeviceId = [string]$device.id
        $capturedCommandId = [string]$command.id
        $capturedDisplayName = "$($device.name) - $($button.Text)"
        $button.Add_Click({ Send-IrCommand $capturedDeviceId $capturedCommandId $capturedDisplayName }.GetNewClosure())
        if (-not [string]::IsNullOrWhiteSpace([string]$command.description)) {
            $toolTip.SetToolTip($button, [string]$command.description)
        }
        $irCommandPanel.Controls.Add($button)
    }
    $irCommandPanel.ResumeLayout()
}

function Load-IrDevices {
    $response = Invoke-TowerGet '/api/v1/devices'
    $script:irDevices = @($response.devices | Where-Object {
        @($_.commands | Where-Object { $_.transport -eq 'IR' -and $_.enabled }).Count -gt 0
    })

    $irDeviceList.Items.Clear()
    foreach ($device in $script:irDevices) {
        [void]$irDeviceList.Items.Add($device)
    }
    $irDeviceList.DisplayMember = 'name'
    if ($irDeviceList.Items.Count -gt 0) {
        $irDeviceList.SelectedIndex = 0
    } else {
        Show-IrDevice $null
    }
}

function Refresh-All {
    try {
        Load-RfDevices
        Load-IrDevices
        Refresh-Sensors
        Set-TowerStatus "Connected to $($config.server) - $($script:rfDevices.Count) RF devices, $($script:irDevices.Count) IR devices"
    }
    catch {
        Set-TowerStatus 'Connection failed' $true
        [System.Windows.Forms.MessageBox]::Show(
            "$($_.Exception.Message)`n`nConfiguration: $configPath",
            'Tower connection error', 'OK', 'Error') | Out-Null
    }
}

$allOnButton.Add_Click({ Send-AllRfAction 'on' })
$allOffButton.Add_Click({ Send-AllRfAction 'off' })
$refreshButton.Add_Click({ Refresh-All })
$irDeviceList.Add_SelectedIndexChanged({ Show-IrDevice $irDeviceList.SelectedItem })

$sensorTimer = New-Object System.Windows.Forms.Timer
$sensorTimer.Interval = 10000
$sensorTimer.Add_Tick({ Refresh-Sensors })

$form.Add_Shown({
    Refresh-All
    $sensorTimer.Start()
})
$form.Add_FormClosed({ $sensorTimer.Stop() })

[void]$form.ShowDialog()
