# Tower Control scheduler tab
# Dot-sourced by Tower-Control.ps1 after the shared HTTP/UI helpers exist.

$script:controlEditorLoaded = $false
$script:controlDocument = $null
$script:controlCatalog = $null
$script:controlVoiceConfig = $null
$script:controlVoiceLeaves = @()
$script:controlScheduleRows = @()
$script:controlPopulating = $false
$script:controlEventLogsLoaded = $false
$script:controlWindowsSyncNeeded = $false
$script:controlWindowsScheduleManager = Join-Path $PSScriptRoot 'Tower-Windows-Schedule-Manager.ps1'
$script:controlCurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name

$controlTab = New-Object System.Windows.Forms.TabPage
$controlTab.Text = 'Control'
$controlTab.Padding = New-Object System.Windows.Forms.Padding(10)
$script:controlTab = $controlTab
[void]$tabs.TabPages.Add($controlTab)

$controlRoot = New-Object System.Windows.Forms.TableLayoutPanel
$controlRoot.Dock = 'Fill'
$controlRoot.ColumnCount = 1
$controlRoot.RowCount = 2
$controlRoot.Margin = New-Object System.Windows.Forms.Padding(0)
[void]$controlRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
    [System.Windows.Forms.SizeType]::Absolute,
    64
)))
[void]$controlRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
    [System.Windows.Forms.SizeType]::Percent,
    100
)))
$controlTab.Controls.Add($controlRoot)

$controlHeader = New-Object System.Windows.Forms.Panel
$controlHeader.Dock = 'Fill'
$controlRoot.Controls.Add($controlHeader, 0, 0)

$controlTitle = New-Object System.Windows.Forms.Label
$controlTitle.Text = 'Control & Scheduler'
$controlTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
$controlTitle.Location = New-Object System.Drawing.Point(2, 4)
$controlTitle.AutoSize = $true
$controlHeader.Controls.Add($controlTitle)

$controlStatusLabel = New-Object System.Windows.Forms.Label
$controlStatusLabel.Text = 'Open this tab to load schedules stored on the Tower.'
$controlStatusLabel.Location = New-Object System.Drawing.Point(4, 32)
$controlStatusLabel.Size = New-Object System.Drawing.Size(600, 23)
$controlStatusLabel.ForeColor = [System.Drawing.Color]::DimGray
$controlStatusLabel.AutoEllipsis = $true
$controlHeader.Controls.Add($controlStatusLabel)

$controlSaveButton = New-Object System.Windows.Forms.Button
$controlSaveButton.Text = 'Save to Tower'
$controlSaveButton.Size = New-Object System.Drawing.Size(112, 34)
$controlSaveButton.Anchor = 'Top,Right'
$controlHeader.Controls.Add($controlSaveButton)

$controlReloadButton = New-Object System.Windows.Forms.Button
$controlReloadButton.Text = 'Reload'
$controlReloadButton.Size = New-Object System.Drawing.Size(82, 34)
$controlReloadButton.Anchor = 'Top,Right'
$controlHeader.Controls.Add($controlReloadButton)

$controlNewHeaderButton = New-Object System.Windows.Forms.Button
$controlNewHeaderButton.Text = '+ New'
$controlNewHeaderButton.Size = New-Object System.Drawing.Size(78, 34)
$controlNewHeaderButton.Anchor = 'Top,Right'
$controlHeader.Controls.Add($controlNewHeaderButton)

$controlHeader.Add_Resize({
    $controlSaveButton.Left = [Math]::Max(260, $controlHeader.ClientSize.Width - 116)
    $controlSaveButton.Top = 10
    $controlReloadButton.Left = [Math]::Max(172, $controlSaveButton.Left - 88)
    $controlReloadButton.Top = 10
    $controlNewHeaderButton.Left = [Math]::Max(88, $controlReloadButton.Left - 84)
    $controlNewHeaderButton.Top = 10
    $controlStatusLabel.Width = [Math]::Max(160, $controlNewHeaderButton.Left - 14)
})

$controlSplit = New-Object System.Windows.Forms.SplitContainer
$controlSplit.Dock = 'Fill'
$controlSplit.Size = New-Object System.Drawing.Size(900, 600)
$controlSplit.SplitterDistance = 350
$controlSplit.Panel1MinSize = 100
$controlSplit.Panel2MinSize = 100
$controlRoot.Controls.Add($controlSplit, 0, 1)

$controlListGroup = New-Object System.Windows.Forms.GroupBox
$controlListGroup.Text = 'Tower schedules'
$controlListGroup.Dock = 'Fill'
$controlSplit.Panel1.Controls.Add($controlListGroup)

$controlScheduleButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$controlScheduleButtons.Dock = [System.Windows.Forms.DockStyle]::Bottom
$controlScheduleButtons.Height = 43
$controlScheduleButtons.Padding = New-Object System.Windows.Forms.Padding(5, 5, 0, 0)
$controlListGroup.Controls.Add($controlScheduleButtons)

$controlAddButton = New-Object System.Windows.Forms.Button
$controlAddButton.Text = '+ New schedule'
$controlAddButton.Size = New-Object System.Drawing.Size(120, 29)
[void]$controlScheduleButtons.Controls.Add($controlAddButton)

$controlDeleteButton = New-Object System.Windows.Forms.Button
$controlDeleteButton.Text = 'Delete'
$controlDeleteButton.Size = New-Object System.Drawing.Size(78, 29)
[void]$controlScheduleButtons.Controls.Add($controlDeleteButton)

$controlScheduleList = New-Object System.Windows.Forms.ListBox
$controlScheduleList.Dock = 'Fill'
$controlScheduleList.IntegralHeight = $false
$controlScheduleList.HorizontalScrollbar = $true
$controlListGroup.Controls.Add($controlScheduleList)
$controlScheduleList.BringToFront()

$controlEditorGroup = New-Object System.Windows.Forms.GroupBox
$controlEditorGroup.Text = 'Schedule details'
$controlEditorGroup.Dock = 'Fill'
$controlSplit.Panel2.Controls.Add($controlEditorGroup)

$controlEditor = New-Object System.Windows.Forms.Panel
$controlEditor.Dock = 'Fill'
$controlEditor.AutoScroll = $true
$controlEditorGroup.Controls.Add($controlEditor)

function New-ControlEditorLabel([string]$text, [int]$top) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text
    $label.Location = New-Object System.Drawing.Point(14, $top)
    $label.Size = New-Object System.Drawing.Size(130, 25)
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $controlEditor.Controls.Add($label)
    return $label
}

$controlEnabledCheck = New-Object System.Windows.Forms.CheckBox
$controlEnabledCheck.Text = 'Enabled'
$controlEnabledCheck.Location = New-Object System.Drawing.Point(150, 17)
$controlEnabledCheck.AutoSize = $true
$controlEditor.Controls.Add($controlEnabledCheck)

$controlLocationBadge = New-Object System.Windows.Forms.Label
$controlLocationBadge.Text = 'Runs on Tower (independent from Windows)'
$controlLocationBadge.Location = New-Object System.Drawing.Point(250, 15)
$controlLocationBadge.Size = New-Object System.Drawing.Size(285, 25)
$controlLocationBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$controlLocationBadge.BackColor = [System.Drawing.Color]::FromArgb(220, 244, 228)
$controlLocationBadge.ForeColor = [System.Drawing.Color]::FromArgb(30, 105, 60)
$controlLocationBadge.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$controlEditor.Controls.Add($controlLocationBadge)

[void](New-ControlEditorLabel 'Schedule name' 56)
$controlNameText = New-Object System.Windows.Forms.TextBox
$controlNameText.Location = New-Object System.Drawing.Point(150, 56)
$controlNameText.Size = New-Object System.Drawing.Size(385, 25)
$controlEditor.Controls.Add($controlNameText)

[void](New-ControlEditorLabel 'Trigger' 96)
$controlTriggerCombo = New-Object System.Windows.Forms.ComboBox
$controlTriggerCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$controlTriggerCombo.Location = New-Object System.Drawing.Point(150, 96)
$controlTriggerCombo.Size = New-Object System.Drawing.Size(245, 25)
[void]$controlTriggerCombo.Items.AddRange(@(
    'On a schedule',
    'At log on',
    'At startup',
    'On idle',
    'On an event'
))
$controlEditor.Controls.Add($controlTriggerCombo)

$controlScheduleTypeLabel = New-ControlEditorLabel 'Schedule type' 136
$controlScheduleTypeCombo = New-Object System.Windows.Forms.ComboBox
$controlScheduleTypeCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$controlScheduleTypeCombo.Location = New-Object System.Drawing.Point(150, 136)
$controlScheduleTypeCombo.Size = New-Object System.Drawing.Size(190, 25)
[void]$controlScheduleTypeCombo.Items.AddRange(@('One time', 'Daily', 'Weekly'))
$controlEditor.Controls.Add($controlScheduleTypeCombo)

$controlDateLabel = New-ControlEditorLabel 'Date' 176
$controlDatePicker = New-Object System.Windows.Forms.DateTimePicker
$controlDatePicker.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$controlDatePicker.CustomFormat = 'dddd, dd MMMM yyyy'
$controlDatePicker.Location = New-Object System.Drawing.Point(150, 176)
$controlDatePicker.Size = New-Object System.Drawing.Size(245, 25)
$controlEditor.Controls.Add($controlDatePicker)

$controlTimeLabel = New-ControlEditorLabel 'Time' 216
$controlTimePicker = New-Object System.Windows.Forms.DateTimePicker
$controlTimePicker.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$controlTimePicker.CustomFormat = 'HH:mm'
$controlTimePicker.ShowUpDown = $true
$controlTimePicker.Location = New-Object System.Drawing.Point(150, 216)
$controlTimePicker.Size = New-Object System.Drawing.Size(100, 25)
$controlEditor.Controls.Add($controlTimePicker)

$controlTowerTimeHint = New-Object System.Windows.Forms.Label
$controlTowerTimeHint.Text = 'Uses the Tower local clock.'
$controlTowerTimeHint.Location = New-Object System.Drawing.Point(260, 219)
$controlTowerTimeHint.Size = New-Object System.Drawing.Size(250, 21)
$controlTowerTimeHint.ForeColor = [System.Drawing.Color]::DimGray
$controlEditor.Controls.Add($controlTowerTimeHint)

$controlDaysLabel = New-ControlEditorLabel 'Days' 256
$controlDaysPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$controlDaysPanel.Location = New-Object System.Drawing.Point(150, 252)
$controlDaysPanel.Size = New-Object System.Drawing.Size(450, 35)
$controlDaysPanel.WrapContents = $false
$controlEditor.Controls.Add($controlDaysPanel)

$script:controlDayChecks = @{}
$dayDefinitions = @(
    @{ Id = 1; Text = 'Mon' },
    @{ Id = 2; Text = 'Tue' },
    @{ Id = 3; Text = 'Wed' },
    @{ Id = 4; Text = 'Thu' },
    @{ Id = 5; Text = 'Fri' },
    @{ Id = 6; Text = 'Sat' },
    @{ Id = 0; Text = 'Sun' }
)
foreach ($dayDefinition in $dayDefinitions) {
    $dayCheck = New-Object System.Windows.Forms.CheckBox
    $dayCheck.Text = [string]$dayDefinition.Text
    $dayCheck.Tag = [int]$dayDefinition.Id
    $dayCheck.AutoSize = $true
    $dayCheck.Margin = New-Object System.Windows.Forms.Padding(2, 6, 6, 2)
    $script:controlDayChecks[[int]$dayDefinition.Id] = $dayCheck
    [void]$controlDaysPanel.Controls.Add($dayCheck)
}

$controlLogonAnyRadio = New-Object System.Windows.Forms.RadioButton
$controlLogonAnyRadio.Text = 'Any user'
$controlLogonAnyRadio.Location = New-Object System.Drawing.Point(150, 138)
$controlLogonAnyRadio.AutoSize = $true
$controlEditor.Controls.Add($controlLogonAnyRadio)

$controlLogonSpecificRadio = New-Object System.Windows.Forms.RadioButton
$controlLogonSpecificRadio.Text = 'Specific user'
$controlLogonSpecificRadio.Location = New-Object System.Drawing.Point(150, 176)
$controlLogonSpecificRadio.AutoSize = $true
$controlEditor.Controls.Add($controlLogonSpecificRadio)

$controlLogonUserText = New-Object System.Windows.Forms.TextBox
$controlLogonUserText.Location = New-Object System.Drawing.Point(270, 174)
$controlLogonUserText.Size = New-Object System.Drawing.Size(265, 25)
$controlEditor.Controls.Add($controlLogonUserText)

$controlWindowsTriggerHint = New-Object System.Windows.Forms.Label
$controlWindowsTriggerHint.Location = New-Object System.Drawing.Point(150, 139)
$controlWindowsTriggerHint.Size = New-Object System.Drawing.Size(410, 62)
$controlWindowsTriggerHint.ForeColor = [System.Drawing.Color]::DimGray
$controlEditor.Controls.Add($controlWindowsTriggerHint)

$controlEventLogLabel = New-ControlEditorLabel 'Log' 136
$controlEventLogCombo = New-Object System.Windows.Forms.ComboBox
$controlEventLogCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
$controlEventLogCombo.AutoCompleteMode = [System.Windows.Forms.AutoCompleteMode]::SuggestAppend
$controlEventLogCombo.AutoCompleteSource = [System.Windows.Forms.AutoCompleteSource]::ListItems
$controlEventLogCombo.Location = New-Object System.Drawing.Point(150, 136)
$controlEventLogCombo.Size = New-Object System.Drawing.Size(385, 25)
$controlEditor.Controls.Add($controlEventLogCombo)

$controlEventSourceLabel = New-ControlEditorLabel 'Source' 176
$controlEventSourceCombo = New-Object System.Windows.Forms.ComboBox
$controlEventSourceCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
$controlEventSourceCombo.AutoCompleteMode = [System.Windows.Forms.AutoCompleteMode]::SuggestAppend
$controlEventSourceCombo.AutoCompleteSource = [System.Windows.Forms.AutoCompleteSource]::ListItems
$controlEventSourceCombo.Location = New-Object System.Drawing.Point(150, 176)
$controlEventSourceCombo.Size = New-Object System.Drawing.Size(385, 25)
$controlEditor.Controls.Add($controlEventSourceCombo)

$controlEventIdLabel = New-ControlEditorLabel 'Event ID' 216
$controlEventIdText = New-Object System.Windows.Forms.TextBox
$controlEventIdText.Location = New-Object System.Drawing.Point(150, 216)
$controlEventIdText.Size = New-Object System.Drawing.Size(110, 25)
$controlEditor.Controls.Add($controlEventIdText)

$controlRuleLine = New-Object System.Windows.Forms.Label
$controlRuleLine.BorderStyle = [System.Windows.Forms.BorderStyle]::Fixed3D
$controlRuleLine.Location = New-Object System.Drawing.Point(14, 299)
$controlRuleLine.Size = New-Object System.Drawing.Size(585, 2)
$controlEditor.Controls.Add($controlRuleLine)

[void](New-ControlEditorLabel 'Command source' 318)
$controlSourceCombo = New-Object System.Windows.Forms.ComboBox
$controlSourceCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$controlSourceCombo.Location = New-Object System.Drawing.Point(150, 318)
$controlSourceCombo.Size = New-Object System.Drawing.Size(230, 25)
[void]$controlSourceCombo.Items.AddRange(@(
    'Voice command set',
    'RF preset',
    'RF device',
    'IR command'
))
$controlEditor.Controls.Add($controlSourceCombo)

$controlTargetLabel = New-ControlEditorLabel 'Command set' 358
$controlTargetCombo = New-Object System.Windows.Forms.ComboBox
$controlTargetCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$controlTargetCombo.Location = New-Object System.Drawing.Point(150, 358)
$controlTargetCombo.Size = New-Object System.Drawing.Size(385, 25)
$controlEditor.Controls.Add($controlTargetCombo)

$controlCommandLabel = New-ControlEditorLabel 'Command' 398
$controlCommandCombo = New-Object System.Windows.Forms.ComboBox
$controlCommandCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$controlCommandCombo.Location = New-Object System.Drawing.Point(150, 398)
$controlCommandCombo.Size = New-Object System.Drawing.Size(385, 25)
$controlEditor.Controls.Add($controlCommandCombo)

$controlOperationLabel = New-ControlEditorLabel 'Action' 438
$controlOperationCombo = New-Object System.Windows.Forms.ComboBox
$controlOperationCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$controlOperationCombo.Location = New-Object System.Drawing.Point(150, 438)
$controlOperationCombo.Size = New-Object System.Drawing.Size(110, 25)
[void]$controlOperationCombo.Items.AddRange(@('on', 'off'))
$controlEditor.Controls.Add($controlOperationCombo)

$controlTransmitterPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$controlTransmitterPanel.Location = New-Object System.Drawing.Point(150, 433)
$controlTransmitterPanel.Size = New-Object System.Drawing.Size(450, 38)
$controlTransmitterPanel.WrapContents = $false
$controlTransmitterPanel.Visible = $false
$controlEditor.Controls.Add($controlTransmitterPanel)

$script:controlTransmitterChecks = @{}
foreach ($transmitterName in Get-AvailableIrTransmitters) {
    $transmitterCheck = New-Object System.Windows.Forms.CheckBox
    $transmitterCheck.Text = Get-ShortTransmitterLabel $transmitterName
    $transmitterCheck.Tag = $transmitterName
    $transmitterCheck.AutoSize = $true
    $transmitterCheck.Margin = New-Object System.Windows.Forms.Padding(3, 7, 8, 3)
    $script:controlTransmitterChecks[$transmitterName] = $transmitterCheck
    [void]$controlTransmitterPanel.Controls.Add($transmitterCheck)
}

$controlDelayLabel = New-ControlEditorLabel 'Delay before' 482
$controlDelaySeconds = New-Object System.Windows.Forms.NumericUpDown
$controlDelaySeconds.Location = New-Object System.Drawing.Point(150, 482)
$controlDelaySeconds.Size = New-Object System.Drawing.Size(75, 25)
$controlDelaySeconds.Minimum = 0
$controlDelaySeconds.Maximum = 300
$controlEditor.Controls.Add($controlDelaySeconds)

$controlDelayHint = New-Object System.Windows.Forms.Label
$controlDelayHint.Text = 'seconds (direct commands only)'
$controlDelayHint.Location = New-Object System.Drawing.Point(235, 485)
$controlDelayHint.Size = New-Object System.Drawing.Size(230, 21)
$controlDelayHint.ForeColor = [System.Drawing.Color]::DimGray
$controlEditor.Controls.Add($controlDelayHint)

$controlActionPreviewLabel = New-ControlEditorLabel 'Will execute' 524
$controlActionPreview = New-Object System.Windows.Forms.TextBox
$controlActionPreview.Location = New-Object System.Drawing.Point(150, 524)
$controlActionPreview.Size = New-Object System.Drawing.Size(445, 68)
$controlActionPreview.Multiline = $true
$controlActionPreview.ReadOnly = $true
$controlActionPreview.ScrollBars = 'Vertical'
$controlActionPreview.BackColor = [System.Drawing.SystemColors]::Window
$controlEditor.Controls.Add($controlActionPreview)

$controlApplyButton = New-Object System.Windows.Forms.Button
$controlApplyButton.Text = 'Apply schedule'
$controlApplyButton.Location = New-Object System.Drawing.Point(150, 614)
$controlApplyButton.Size = New-Object System.Drawing.Size(122, 32)
$controlEditor.Controls.Add($controlApplyButton)

$controlRunButton = New-Object System.Windows.Forms.Button
$controlRunButton.Text = 'Run now'
$controlRunButton.Location = New-Object System.Drawing.Point(282, 614)
$controlRunButton.Size = New-Object System.Drawing.Size(100, 32)
$controlEditor.Controls.Add($controlRunButton)

$controlEditorHint = New-Object System.Windows.Forms.Label
$controlEditorHint.Text = 'Apply updates the draft. Save to Tower makes it persistent. Voice sets stay linked and use their latest actions.'
$controlEditorHint.Location = New-Object System.Drawing.Point(150, 655)
$controlEditorHint.Size = New-Object System.Drawing.Size(450, 42)
$controlEditorHint.ForeColor = [System.Drawing.Color]::DimGray
$controlEditor.Controls.Add($controlEditorHint)

$controlNextLabel = New-ControlEditorLabel 'Next run' 700
$controlNextRun = New-Object System.Windows.Forms.Label
$controlNextRun.Location = New-Object System.Drawing.Point(150, 700)
$controlNextRun.Size = New-Object System.Drawing.Size(445, 25)
$controlNextRun.Text = 'No schedule selected'
$controlNextRun.ForeColor = [System.Drawing.Color]::DimGray
$controlEditor.Controls.Add($controlNextRun)

$controlLastLabel = New-ControlEditorLabel 'Last result' 736
$controlLastResult = New-Object System.Windows.Forms.Label
$controlLastResult.Location = New-Object System.Drawing.Point(150, 736)
$controlLastResult.Size = New-Object System.Drawing.Size(445, 48)
$controlLastResult.Text = 'Never run'
$controlLastResult.ForeColor = [System.Drawing.Color]::DimGray
$controlEditor.Controls.Add($controlLastResult)

function Set-ControlStatus([string]$message, [bool]$isError = $false) {
    $controlStatusLabel.Text = $message
    $controlStatusLabel.ForeColor = if ($isError) {
        [System.Drawing.Color]::Firebrick
    }
    else {
        [System.Drawing.Color]::ForestGreen
    }
}

function Invoke-ControlEditorEvent([scriptblock]$action, [string]$operation) {
    try {
        & $action
    }
    catch {
        $message = [string]$_.Exception.Message
        $details = $message
        if (-not [string]::IsNullOrWhiteSpace([string]$_.ScriptStackTrace)) {
            $details += "`r`n`r`n$([string]$_.ScriptStackTrace)"
        }
        Set-ControlStatus "Scheduler $operation failed: $message" $true
        [System.Windows.Forms.MessageBox]::Show(
            $details,
            "Scheduler $operation failed",
            'OK',
            'Error'
        ) | Out-Null
    }
}

function Copy-ControlObject($value) {
    if ($null -eq $value) { return $null }
    return ConvertFrom-Json -InputObject (
        ConvertTo-Json -InputObject $value -Depth 50 -Compress
    )
}

function Add-ControlVoiceLeaves($children, $parentPath) {
    if ($null -eq $children) { return }
    foreach ($property in @($children.PSObject.Properties)) {
        $path = @($parentPath) + @([string]$property.Name)
        if ($null -ne $property.Value.children) {
            Add-ControlVoiceLeaves $property.Value.children $path
        }
        elseif (@($property.Value.actions).Count -gt 0) {
            $script:controlVoiceLeaves += [pscustomobject]@{
                Path = @($path)
                Label = (@($path) -join ' -> ')
                Actions = @($property.Value.actions)
            }
        }
    }
}

function Refresh-ControlVoiceLeaves {
    $script:controlVoiceLeaves = @()
    if ($null -ne $script:controlVoiceConfig.command_tree) {
        Add-ControlVoiceLeaves $script:controlVoiceConfig.command_tree @()
    }
}

function Get-ControlActionDisplayName($action) {
    $delaySeconds = [Math]::Max(0, [int]$action.delay_before_seconds)
    $delayText = if ($delaySeconds -gt 0) { " after ${delaySeconds}s" } else { '' }
    switch ([string]$action.type) {
        'voice_path' {
            return "Voice: $(@($action.path) -join ' -> ')$delayText"
        }
        'rf_preset' {
            return "RF Preset $([int]$action.preset) -> $([string]$action.action)$delayText"
        }
        'rf_group' {
            $name = [string]$action.name
            if ([string]::IsNullOrWhiteSpace($name)) {
                $name = @($action.devices) -join ', '
            }
            return "RF $name -> $([string]$action.action)$delayText"
        }
        default {
            $outputs = @($action.transmitters)
            if ($outputs.Count -eq 0 -and
                -not [string]::IsNullOrWhiteSpace([string]$action.transmitter)) {
                $outputs = @([string]$action.transmitter)
            }
            $outputText = @($outputs | ForEach-Object {
                Get-ShortTransmitterLabel ([string]$_)
            }) -join ', '
            if ([string]::IsNullOrWhiteSpace($outputText)) { $outputText = 'default' }
            return "IR $([string]$action.device) -> $([string]$action.command) [$outputText]$delayText"
        }
    }
}

function Get-ControlTriggerText($schedule) {
    $trigger = $schedule.trigger
    switch ([string]$trigger.type) {
        'once' { return "Once $([string]$trigger.date) at $([string]$trigger.time)" }
        'weekly' {
            $dayNames = @('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat')
            $names = @(@($trigger.days) | ForEach-Object { $dayNames[[int]$_] })
            return "Weekly $($names -join ', ') at $([string]$trigger.time)"
        }
        'windows_logon' {
            if ([string]$trigger.userMode -eq 'specific') {
                return "Windows logon: $([string]$trigger.userId)"
            }
            return 'Windows logon: any user'
        }
        'windows_startup' { return 'Windows startup' }
        'windows_idle' { return 'Windows idle' }
        'windows_event' {
            return "Windows event: $([string]$trigger.log) / $([string]$trigger.source) / $([int]$trigger.eventId)"
        }
        default { return "Daily at $([string]$trigger.time)" }
    }
}

function Get-ControlSourceText($schedule) {
    if (-not [string]::IsNullOrWhiteSpace([string]$schedule.source.label)) {
        return [string]$schedule.source.label
    }
    $actions = @($schedule.actions)
    if ($actions.Count -eq 0) { return 'No command' }
    if ($actions.Count -eq 1) { return Get-ControlActionDisplayName $actions[0] }
    return "$($actions.Count) ordered actions"
}

function Get-ControlScheduleDisplayText($schedule) {
    $state = if ([bool]$schedule.enabled) { '[ON] ' } else { '[OFF] ' }
    return "$state$([string]$schedule.name)  |  $(Get-ControlTriggerText $schedule)  |  $(Get-ControlSourceText $schedule)"
}

function Get-ControlNextRunText($schedule) {
    if (-not [bool]$schedule.enabled) { return 'Disabled' }
    if ([string]$schedule.trigger.type -like 'windows_*') {
        return 'Waiting for Windows trigger'
    }
    try {
        $now = [datetime]::Now
        $timeText = [string]$schedule.trigger.time
        $clock = [datetime]::ParseExact(
            $timeText,
            'HH:mm',
            [System.Globalization.CultureInfo]::InvariantCulture
        )
        $type = [string]$schedule.trigger.type
        if ($type -eq 'once') {
            $candidate = [datetime]::ParseExact(
                "$([string]$schedule.trigger.date) $timeText",
                'yyyy-MM-dd HH:mm',
                [System.Globalization.CultureInfo]::InvariantCulture
            )
            if ($candidate -lt $now) { return 'Past due' }
            return $candidate.ToString('ddd dd MMM yyyy HH:mm')
        }
        if ($type -eq 'daily') {
            $candidate = $now.Date.AddHours($clock.Hour).AddMinutes($clock.Minute)
            if ($candidate -le $now) { $candidate = $candidate.AddDays(1) }
            return $candidate.ToString('ddd dd MMM yyyy HH:mm')
        }
        if ($type -eq 'weekly') {
            $days = @($schedule.trigger.days | ForEach-Object { [int]$_ })
            for ($offset = 0; $offset -le 7; $offset++) {
                $candidate = $now.Date.AddDays($offset).AddHours($clock.Hour).AddMinutes($clock.Minute)
                if ($candidate -gt $now -and $days -contains [int]$candidate.DayOfWeek) {
                    return $candidate.ToString('ddd dd MMM yyyy HH:mm')
                }
            }
        }
    }
    catch {}
    return 'Invalid timing'
}

function Find-ControlScheduleIndexById([string]$id) {
    $items = @($script:controlDocument.schedules)
    for ($index = 0; $index -lt $items.Count; $index++) {
        if ([string]$items[$index].id -eq $id) { return $index }
    }
    return -1
}

function Refresh-ControlScheduleList([string]$selectedId = '') {
    if ([string]::IsNullOrWhiteSpace($selectedId) -and
        $controlScheduleList.SelectedIndex -ge 0 -and
        $controlScheduleList.SelectedIndex -lt $script:controlScheduleRows.Count) {
        $selectedId = [string]$script:controlScheduleRows[$controlScheduleList.SelectedIndex].id
    }

    $script:controlPopulating = $true
    try {
        $controlScheduleList.Items.Clear()
        $script:controlScheduleRows = @($script:controlDocument.schedules)
        $selectedIndex = -1
        for ($index = 0; $index -lt $script:controlScheduleRows.Count; $index++) {
            $schedule = $script:controlScheduleRows[$index]
            [void]$controlScheduleList.Items.Add((Get-ControlScheduleDisplayText $schedule))
            if ([string]$schedule.id -eq $selectedId) { $selectedIndex = $index }
        }
        if ($selectedIndex -lt 0 -and $controlScheduleList.Items.Count -gt 0) {
            $selectedIndex = 0
        }
        if ($selectedIndex -ge 0) {
            $controlScheduleList.SelectedIndex = $selectedIndex
        }
    }
    finally {
        $script:controlPopulating = $false
    }

    if ($controlScheduleList.SelectedIndex -ge 0) {
        Show-ControlSchedule $script:controlScheduleRows[$controlScheduleList.SelectedIndex]
    }
    else {
        Clear-ControlScheduleEditor
    }
}

function Set-ControlComboIndexById($combo, $items, [string]$id) {
    $combo.SelectedIndex = -1
    for ($index = 0; $index -lt @($items).Count; $index++) {
        if ([string]$items[$index].id -eq $id) {
            $combo.SelectedIndex = $index
            return
        }
    }
}

function Refresh-ControlCommandChoices([string]$selectedCommand = '') {
    $controlCommandCombo.Items.Clear()
    $deviceIndex = $controlTargetCombo.SelectedIndex
    if ($deviceIndex -lt 0 -or $deviceIndex -ge @($script:controlCatalog.irDevices).Count) {
        return
    }
    $commands = @($script:controlCatalog.irDevices[$deviceIndex].commands)
    foreach ($command in $commands) {
        [void]$controlCommandCombo.Items.Add(
            "$([string]$command.name)  [$([string]$command.id)]"
        )
    }
    Set-ControlComboIndexById $controlCommandCombo $commands $selectedCommand
    if ($controlCommandCombo.SelectedIndex -lt 0 -and $controlCommandCombo.Items.Count -gt 0) {
        $controlCommandCombo.SelectedIndex = 0
    }
}

function Initialize-ControlEventLogs([string]$selectedLog = '') {
    if (-not $script:controlEventLogsLoaded) {
        $currentText = [string]$controlEventLogCombo.Text
        $controlEventLogCombo.Items.Clear()
        $logs = @(
            Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty LogName |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                Sort-Object -Unique
        )
        foreach ($logName in $logs) { [void]$controlEventLogCombo.Items.Add([string]$logName) }
        $script:controlEventLogsLoaded = $true
        if ([string]::IsNullOrWhiteSpace($selectedLog)) { $selectedLog = $currentText }
    }
    if ([string]::IsNullOrWhiteSpace($selectedLog)) { $selectedLog = 'System' }
    $controlEventLogCombo.Text = $selectedLog
}

function Refresh-ControlEventSources([string]$selectedSource = '') {
    $currentText = [string]$controlEventSourceCombo.Text
    $controlEventSourceCombo.Items.Clear()
    $logName = ([string]$controlEventLogCombo.Text).Trim()
    if (-not [string]::IsNullOrWhiteSpace($logName)) {
        try {
            $logInfo = Get-WinEvent -ListLog $logName -ErrorAction Stop
            foreach ($provider in @($logInfo.ProviderNames | Sort-Object -Unique)) {
                [void]$controlEventSourceCombo.Items.Add([string]$provider)
            }
        }
        catch {}
    }
    if ([string]::IsNullOrWhiteSpace($selectedSource)) { $selectedSource = $currentText }
    $controlEventSourceCombo.Text = $selectedSource
}

function Update-ControlTriggerFields {
    $selection = [string]$controlTriggerCombo.SelectedItem
    $isSchedule = $selection -eq 'On a schedule'
    $isOnce = $isSchedule -and [string]$controlScheduleTypeCombo.SelectedItem -eq 'One time'
    $isWeekly = $isSchedule -and [string]$controlScheduleTypeCombo.SelectedItem -eq 'Weekly'
    $isLogon = $selection -eq 'At log on'
    $isStartup = $selection -eq 'At startup'
    $isIdle = $selection -eq 'On idle'
    $isEvent = $selection -eq 'On an event'

    $controlScheduleTypeLabel.Visible = $isSchedule
    $controlScheduleTypeCombo.Visible = $isSchedule
    $controlDateLabel.Visible = $isOnce
    $controlDatePicker.Visible = $isOnce
    $controlTimeLabel.Visible = $isSchedule
    $controlTimePicker.Visible = $isSchedule
    $controlTowerTimeHint.Visible = $isSchedule
    $controlDaysLabel.Visible = $isWeekly
    $controlDaysPanel.Visible = $isWeekly
    $controlLogonAnyRadio.Visible = $isLogon
    $controlLogonSpecificRadio.Visible = $isLogon
    $controlLogonUserText.Visible = $isLogon
    $controlLogonUserText.Enabled = $isLogon -and $controlLogonSpecificRadio.Checked
    $controlWindowsTriggerHint.Visible = $isStartup -or $isIdle
    $controlEventLogLabel.Visible = $isEvent
    $controlEventLogCombo.Visible = $isEvent
    $controlEventSourceLabel.Visible = $isEvent
    $controlEventSourceCombo.Visible = $isEvent
    $controlEventIdLabel.Visible = $isEvent
    $controlEventIdText.Visible = $isEvent

    if ($isStartup) {
        $controlWindowsTriggerHint.Text =
            'No additional settings required. The command is queued during Windows startup and runs when the Tower agent connects.'
    }
    elseif ($isIdle) {
        $controlWindowsTriggerHint.Text =
            'Uses Windows idle detection (10 minutes idle, with a one-hour wait window).'
    }
    if ($isEvent -and -not $script:controlPopulating) {
        Initialize-ControlEventLogs ([string]$controlEventLogCombo.Text)
        Refresh-ControlEventSources ([string]$controlEventSourceCombo.Text)
    }

    if ($isSchedule) {
        $controlLocationBadge.Text = 'Runs on Tower (independent from Windows)'
        $controlLocationBadge.BackColor = [System.Drawing.Color]::FromArgb(220, 244, 228)
        $controlLocationBadge.ForeColor = [System.Drawing.Color]::FromArgb(30, 105, 60)
    }
    else {
        $controlLocationBadge.Text = 'Runs through Windows Task Scheduler'
        $controlLocationBadge.BackColor = [System.Drawing.Color]::FromArgb(224, 238, 252)
        $controlLocationBadge.ForeColor = [System.Drawing.Color]::FromArgb(32, 82, 135)
    }
}

function Update-ControlActionPreview {
    if ($script:controlPopulating) { return }
    try {
        $actions = @()
        if ([string]$controlSourceCombo.SelectedItem -eq 'Voice command set' -and
            $controlTargetCombo.SelectedIndex -ge 0) {
            $actions = @($script:controlVoiceLeaves[$controlTargetCombo.SelectedIndex].Actions)
        }
        else {
            $actions = @(Get-ControlActionsFromFields)
        }
        $lines = @()
        for ($index = 0; $index -lt $actions.Count; $index++) {
            $lines += "$($index + 1). $(Get-ControlActionDisplayName $actions[$index])"
        }
        $controlActionPreview.Text = $lines -join "`r`n"
    }
    catch {
        $controlActionPreview.Text = [string]$_.Exception.Message
    }
}

function Update-ControlActionFields(
    [string]$targetId = '',
    [string]$commandId = '',
    [string]$operation = '',
    $transmitters = @()
) {
    $type = [string]$controlSourceCombo.SelectedItem
    $controlTargetCombo.Items.Clear()

    $isVoice = $type -eq 'Voice command set'
    $isPreset = $type -eq 'RF preset'
    $isRfDevice = $type -eq 'RF device'
    $isIr = $type -eq 'IR command'

    $controlCommandLabel.Visible = $isIr
    $controlCommandCombo.Visible = $isIr
    $controlOperationLabel.Text = 'Action'
    $controlOperationLabel.Visible = $isPreset -or $isRfDevice
    $controlOperationCombo.Visible = $isPreset -or $isRfDevice
    $controlTransmitterPanel.Visible = $isIr
    $controlDelayLabel.Visible = -not $isVoice
    $controlDelaySeconds.Visible = -not $isVoice
    $controlDelayHint.Visible = -not $isVoice

    if ($isVoice) {
        $controlTargetLabel.Text = 'Command set'
        foreach ($leaf in @($script:controlVoiceLeaves)) {
            [void]$controlTargetCombo.Items.Add([string]$leaf.Label)
        }
        for ($index = 0; $index -lt $script:controlVoiceLeaves.Count; $index++) {
            if ((@($script:controlVoiceLeaves[$index].Path) -join "`n") -eq $targetId) {
                $controlTargetCombo.SelectedIndex = $index
                break
            }
        }
    }
    elseif ($isPreset) {
        $controlTargetLabel.Text = 'Preset'
        $items = @($script:controlCatalog.presets)
        foreach ($item in $items) {
            [void]$controlTargetCombo.Items.Add(
                "$([string]$item.name)  ($([int]$item.deviceCount) devices)"
            )
        }
        Set-ControlComboIndexById $controlTargetCombo $items $targetId
    }
    elseif ($isRfDevice) {
        $controlTargetLabel.Text = 'RF device'
        $items = @($script:controlCatalog.rfDevices)
        foreach ($item in $items) {
            [void]$controlTargetCombo.Items.Add(
                "$([string]$item.name)  [$([string]$item.id)]"
            )
        }
        Set-ControlComboIndexById $controlTargetCombo $items $targetId
    }
    elseif ($isIr) {
        $controlTargetLabel.Text = 'IR remote/device'
        $controlOperationLabel.Text = 'IR outputs'
        $controlOperationLabel.Visible = $true
        $items = @($script:controlCatalog.irDevices)
        foreach ($item in $items) {
            [void]$controlTargetCombo.Items.Add(
                "$([string]$item.name)  [$([string]$item.id)]"
            )
        }
        Set-ControlComboIndexById $controlTargetCombo $items $targetId
        Refresh-ControlCommandChoices $commandId

        $selectedTransmitters = @($transmitters | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_)
        })
        if ($selectedTransmitters.Count -eq 0) {
            $selectedTransmitters = @($script:selectedIrTransmitters)
        }
        foreach ($name in $script:controlTransmitterChecks.Keys) {
            $script:controlTransmitterChecks[$name].Checked =
                $selectedTransmitters -contains $name
        }
    }

    if ($controlTargetCombo.SelectedIndex -lt 0 -and $controlTargetCombo.Items.Count -gt 0) {
        $controlTargetCombo.SelectedIndex = 0
    }
    if ($operation -in @('on', 'off')) {
        $controlOperationCombo.SelectedItem = $operation
    }
    elseif ($controlOperationCombo.Items.Count -gt 0) {
        $controlOperationCombo.SelectedIndex = 0
    }
    Update-ControlActionPreview
}

function Get-ControlActionsFromFields {
    $type = [string]$controlSourceCombo.SelectedItem
    $delaySeconds = [int]$controlDelaySeconds.Value

    if ($type -eq 'Voice command set') {
        if ($controlTargetCombo.SelectedIndex -lt 0) { throw 'Select a Voice command set.' }
        $leaf = $script:controlVoiceLeaves[$controlTargetCombo.SelectedIndex]
        return @([pscustomobject][ordered]@{
            type = 'voice_path'
            path = @($leaf.Path)
            delay_before_seconds = 0
        })
    }
    if ($type -eq 'RF preset') {
        if ($controlTargetCombo.SelectedIndex -lt 0) { throw 'Select an RF preset.' }
        $preset = @($script:controlCatalog.presets)[$controlTargetCombo.SelectedIndex]
        return @([pscustomobject][ordered]@{
            type = 'rf_preset'
            preset = [int]$preset.id
            action = [string]$controlOperationCombo.SelectedItem
            delay_before_seconds = $delaySeconds
        })
    }
    if ($type -eq 'RF device') {
        if ($controlTargetCombo.SelectedIndex -lt 0) { throw 'Select an RF device.' }
        $device = @($script:controlCatalog.rfDevices)[$controlTargetCombo.SelectedIndex]
        return @([pscustomobject][ordered]@{
            type = 'rf_group'
            name = [string]$device.name
            devices = @([string]$device.id)
            action = [string]$controlOperationCombo.SelectedItem
            delay_before_seconds = $delaySeconds
        })
    }
    if ($type -eq 'IR command') {
        if ($controlTargetCombo.SelectedIndex -lt 0 -or
            $controlCommandCombo.SelectedIndex -lt 0) {
            throw 'Select an IR device and command.'
        }
        $device = @($script:controlCatalog.irDevices)[$controlTargetCombo.SelectedIndex]
        $command = @($device.commands)[$controlCommandCombo.SelectedIndex]
        $selectedTransmitters = @(
            $script:controlTransmitterChecks.Keys |
                Where-Object { $script:controlTransmitterChecks[$_].Checked } |
                Sort-Object
        )
        if ($selectedTransmitters.Count -eq 0) { throw 'Select at least one IR output.' }
        return @([pscustomobject][ordered]@{
            type = 'command'
            device = [string]$device.id
            command = [string]$command.id
            transmitters = @($selectedTransmitters)
            delay_before_seconds = $delaySeconds
        })
    }
    throw 'Select a command source.'
}

function Get-ControlSourceFromFields {
    $type = [string]$controlSourceCombo.SelectedItem
    if ($controlTargetCombo.SelectedIndex -lt 0) { throw 'Select a command target.' }
    switch ($type) {
        'Voice command set' {
            $leaf = $script:controlVoiceLeaves[$controlTargetCombo.SelectedIndex]
            return [pscustomobject][ordered]@{
                type = 'voice'
                path = @($leaf.Path)
                label = "Voice: $([string]$leaf.Label)"
            }
        }
        'RF preset' {
            $preset = @($script:controlCatalog.presets)[$controlTargetCombo.SelectedIndex]
            return [pscustomobject][ordered]@{
                type = 'rf_preset'
                id = [int]$preset.id
                operation = [string]$controlOperationCombo.SelectedItem
                label = "RF: $([string]$preset.name) -> $([string]$controlOperationCombo.SelectedItem)"
            }
        }
        'RF device' {
            $device = @($script:controlCatalog.rfDevices)[$controlTargetCombo.SelectedIndex]
            return [pscustomobject][ordered]@{
                type = 'rf_device'
                id = [string]$device.id
                operation = [string]$controlOperationCombo.SelectedItem
                label = "RF: $([string]$device.name) -> $([string]$controlOperationCombo.SelectedItem)"
            }
        }
        'IR command' {
            $device = @($script:controlCatalog.irDevices)[$controlTargetCombo.SelectedIndex]
            $command = @($device.commands)[$controlCommandCombo.SelectedIndex]
            return [pscustomobject][ordered]@{
                type = 'ir'
                id = [string]$device.id
                command = [string]$command.id
                label = "IR: $([string]$device.name) -> $([string]$command.name)"
            }
        }
    }
    throw 'Select a command source.'
}

function Clear-ControlScheduleEditor {
    $script:controlPopulating = $true
    try {
        $controlEditor.Enabled = $true
        $controlEditorGroup.Text = 'Schedule details - press + New schedule to begin'
        $controlEnabledCheck.Checked = $true
        $controlNameText.Text = ''
        $controlTriggerCombo.SelectedItem = 'On a schedule'
        $controlScheduleTypeCombo.SelectedItem = 'Daily'
        $controlDatePicker.Value = [datetime]::Today.AddDays(1)
        $controlTimePicker.Value = [datetime]::Now.AddMinutes(5)
        foreach ($check in $script:controlDayChecks.Values) { $check.Checked = $false }
        $controlLogonAnyRadio.Checked = $true
        $controlLogonSpecificRadio.Checked = $false
        $controlLogonUserText.Text = $script:controlCurrentUser
        $controlEventLogCombo.Text = 'System'
        $controlEventSourceCombo.Text = ''
        $controlEventIdText.Text = ''
        $controlSourceCombo.SelectedItem = 'Voice command set'
        $controlDelaySeconds.Value = 0
        $controlNextRun.Text = 'No schedule selected'
        $controlLastResult.Text = 'Never run'
        $controlDeleteButton.Enabled = $false
        $controlRunButton.Enabled = $false
        $controlApplyButton.Enabled = $false
    }
    finally {
        $script:controlPopulating = $false
    }
    Update-ControlTriggerFields
    Update-ControlActionFields
    $controlActionPreview.Text = 'Press + New schedule to create a Tower or Windows-triggered command.'
    $controlEditor.Enabled = $false
}

function Show-ControlSchedule($schedule) {
    if ($null -eq $schedule) { Clear-ControlScheduleEditor; return }
    $script:controlPopulating = $true
    try {
        $controlEditor.Enabled = $true
        $controlEditorGroup.Text = 'Schedule details'
        $controlEnabledCheck.Checked = [bool]$schedule.enabled
        $controlNameText.Text = [string]$schedule.name
        switch ([string]$schedule.trigger.type) {
            'once' {
                $controlTriggerCombo.SelectedItem = 'On a schedule'
                $controlScheduleTypeCombo.SelectedItem = 'One time'
            }
            'weekly' {
                $controlTriggerCombo.SelectedItem = 'On a schedule'
                $controlScheduleTypeCombo.SelectedItem = 'Weekly'
            }
            'daily' {
                $controlTriggerCombo.SelectedItem = 'On a schedule'
                $controlScheduleTypeCombo.SelectedItem = 'Daily'
            }
            'windows_logon' {
                $controlTriggerCombo.SelectedItem = 'At log on'
                $controlLogonAnyRadio.Checked = [string]$schedule.trigger.userMode -ne 'specific'
                $controlLogonSpecificRadio.Checked = [string]$schedule.trigger.userMode -eq 'specific'
                $controlLogonUserText.Text = if ([string]::IsNullOrWhiteSpace([string]$schedule.trigger.userId)) {
                    $script:controlCurrentUser
                } else { [string]$schedule.trigger.userId }
            }
            'windows_startup' { $controlTriggerCombo.SelectedItem = 'At startup' }
            'windows_idle' { $controlTriggerCombo.SelectedItem = 'On idle' }
            'windows_event' {
                $controlTriggerCombo.SelectedItem = 'On an event'
                $controlEventLogCombo.Text = [string]$schedule.trigger.log
                $controlEventSourceCombo.Text = [string]$schedule.trigger.source
                $controlEventIdText.Text = [string]$schedule.trigger.eventId
            }
            default {
                $controlTriggerCombo.SelectedItem = 'On a schedule'
                $controlScheduleTypeCombo.SelectedItem = 'Daily'
            }
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$schedule.trigger.date)) {
            $parsedDate = [datetime]::Today
            if ([datetime]::TryParseExact(
                [string]$schedule.trigger.date,
                'yyyy-MM-dd',
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::None,
                [ref]$parsedDate)) {
                $controlDatePicker.Value = $parsedDate
            }
        }
        $parsedTime = [datetime]::Today
        if ([datetime]::TryParseExact(
            [string]$schedule.trigger.time,
            'HH:mm',
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None,
            [ref]$parsedTime)) {
            $controlTimePicker.Value = $parsedTime
        }
        foreach ($day in $script:controlDayChecks.Keys) {
            $script:controlDayChecks[$day].Checked = @($schedule.trigger.days) -contains [int]$day
        }

        $source = $schedule.source
        $firstAction = @($schedule.actions) | Select-Object -First 1
        $targetId = ''
        $commandId = ''
        $operation = ''
        $transmitters = @()
        $sourceType = [string]$source.type
        if ([string]::IsNullOrWhiteSpace($sourceType)) {
            switch ([string]$firstAction.type) {
                'voice_path' { $sourceType = 'voice' }
                'rf_preset' { $sourceType = 'rf_preset' }
                'rf_group' { $sourceType = 'rf_device' }
                default { $sourceType = 'ir' }
            }
        }
        switch ($sourceType) {
            'voice' {
                $controlSourceCombo.SelectedItem = 'Voice command set'
                $targetId = if (@($source.path).Count -gt 0) {
                    @($source.path) -join "`n"
                } else {
                    @($firstAction.path) -join "`n"
                }
            }
            'rf_preset' {
                $controlSourceCombo.SelectedItem = 'RF preset'
                $targetId = if ($null -ne $source.id) { [string]$source.id } else { [string]$firstAction.preset }
                $operation = [string]$firstAction.action
            }
            'rf_device' {
                $controlSourceCombo.SelectedItem = 'RF device'
                $targetId = if (-not [string]::IsNullOrWhiteSpace([string]$source.id)) {
                    [string]$source.id
                } else {
                    [string](@($firstAction.devices)[0])
                }
                $operation = [string]$firstAction.action
            }
            default {
                $controlSourceCombo.SelectedItem = 'IR command'
                $targetId = [string]$firstAction.device
                $commandId = [string]$firstAction.command
                $transmitters = @($firstAction.transmitters)
            }
        }
        $delay = [Math]::Max(0, [int]$firstAction.delay_before_seconds)
        $controlDelaySeconds.Value = [Math]::Min([decimal]$controlDelaySeconds.Maximum, [decimal]$delay)
        $controlNextRun.Text = Get-ControlNextRunText $schedule
        $controlNextRun.ForeColor = if ([bool]$schedule.enabled) {
            [System.Drawing.Color]::FromArgb(35, 95, 145)
        } else {
            [System.Drawing.Color]::DimGray
        }
        $lastRun = [string]$schedule.lastRun
        $lastResultText = [string]$schedule.lastResult
        if ([string]::IsNullOrWhiteSpace($lastRun)) {
            $controlLastResult.Text = 'Never run'
            $controlLastResult.ForeColor = [System.Drawing.Color]::DimGray
        }
        else {
            $controlLastResult.Text = "$lastRun - $lastResultText"
            $controlLastResult.ForeColor = if ($lastResultText -eq 'success') {
                [System.Drawing.Color]::ForestGreen
            } else {
                [System.Drawing.Color]::Firebrick
            }
        }
        $controlDeleteButton.Enabled = $true
        $controlRunButton.Enabled = $true
        $controlApplyButton.Enabled = $true
    }
    finally {
        $script:controlPopulating = $false
    }
    Update-ControlTriggerFields
    Update-ControlActionFields $targetId $commandId $operation $transmitters
    Update-ControlActionPreview
}

function Add-ControlSchedule {
    if (-not $script:controlEditorLoaded) { return }
    $now = [datetime]::Now
    if ($script:piClockHasSync) {
        try {
            $piClock = [datetime]::ParseExact(
                (Get-PiClockDisplayText),
                'HH:mm:ss',
                [System.Globalization.CultureInfo]::InvariantCulture
            )
            $now = $now.Date.AddHours($piClock.Hour).AddMinutes($piClock.Minute).AddSeconds($piClock.Second)
        }
        catch {}
    }
    $now = $now.AddMinutes(5)
    $newSchedule = [pscustomobject][ordered]@{
        id = ([guid]::NewGuid()).ToString('N')
        name = 'New schedule'
        enabled = $true
        trigger = [pscustomobject][ordered]@{
            type = 'daily'
            time = $now.ToString('HH:mm')
        }
        source = [pscustomobject][ordered]@{
            type = 'voice'
            path = if ($script:controlVoiceLeaves.Count -gt 0) {
                @($script:controlVoiceLeaves[0].Path)
            } else { @() }
            label = if ($script:controlVoiceLeaves.Count -gt 0) {
                "Voice: $([string]$script:controlVoiceLeaves[0].Label)"
            } else { 'Voice command set' }
        }
        actions = if ($script:controlVoiceLeaves.Count -gt 0) {
            @([pscustomobject][ordered]@{
                type = 'voice_path'
                path = @($script:controlVoiceLeaves[0].Path)
                delay_before_seconds = 0
            })
        } else { @() }
    }
    $script:controlDocument.schedules = @($script:controlDocument.schedules) + @($newSchedule)
    Refresh-ControlScheduleList ([string]$newSchedule.id)
    $controlNameText.SelectAll()
    $controlNameText.Focus()
    Set-ControlStatus 'New draft created. Choose its timing and command, then Save to Tower.'
}

function Get-ControlSelectedSchedule {
    $index = $controlScheduleList.SelectedIndex
    if ($index -lt 0 -or $index -ge $script:controlScheduleRows.Count) { return $null }
    $id = [string]$script:controlScheduleRows[$index].id
    $documentIndex = Find-ControlScheduleIndexById $id
    if ($documentIndex -lt 0) { return $null }
    return $script:controlDocument.schedules[$documentIndex]
}

function Apply-ControlSchedule([bool]$showErrors = $true) {
    try {
        $schedule = Get-ControlSelectedSchedule
        if ($null -eq $schedule) { throw 'Select or create a schedule first.' }
        $name = ([string]$controlNameText.Text).Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { throw 'Schedule name cannot be empty.' }

        $oldWasWindows = [string]$schedule.trigger.type -like 'windows_*'
        $triggerSelection = [string]$controlTriggerCombo.SelectedItem
        if ($triggerSelection -eq 'On a schedule') {
            $triggerType = switch ([string]$controlScheduleTypeCombo.SelectedItem) {
                'One time' { 'once' }
                'Weekly' { 'weekly' }
                default { 'daily' }
            }
            $trigger = [ordered]@{
                type = $triggerType
                time = $controlTimePicker.Value.ToString('HH:mm')
            }
            if ($triggerType -eq 'once') {
                $trigger.date = $controlDatePicker.Value.ToString('yyyy-MM-dd')
            }
            elseif ($triggerType -eq 'weekly') {
                $days = @(
                    $script:controlDayChecks.Keys |
                        Where-Object { $script:controlDayChecks[$_].Checked } |
                        ForEach-Object { [int]$_ } |
                        Sort-Object
                )
                if ($days.Count -eq 0) { throw 'Select at least one weekday.' }
                $trigger.days = @($days)
            }
        }
        elseif ($triggerSelection -eq 'At log on') {
            $userMode = if ($controlLogonSpecificRadio.Checked) { 'specific' } else { 'any' }
            $userId = ([string]$controlLogonUserText.Text).Trim()
            if ($userMode -eq 'specific' -and [string]::IsNullOrWhiteSpace($userId)) {
                throw 'Enter the Windows account for the logon trigger.'
            }
            $trigger = [ordered]@{
                type = 'windows_logon'
                userMode = $userMode
                userId = if ($userMode -eq 'specific') { $userId } else { '' }
            }
        }
        elseif ($triggerSelection -eq 'At startup') {
            $trigger = [ordered]@{ type = 'windows_startup' }
        }
        elseif ($triggerSelection -eq 'On idle') {
            $trigger = [ordered]@{ type = 'windows_idle' }
        }
        elseif ($triggerSelection -eq 'On an event') {
            $logName = ([string]$controlEventLogCombo.Text).Trim()
            $sourceName = ([string]$controlEventSourceCombo.Text).Trim()
            $eventId = 0
            if ([string]::IsNullOrWhiteSpace($logName) -or
                [string]::IsNullOrWhiteSpace($sourceName)) {
                throw 'Select a Windows event log and source.'
            }
            if (-not [int]::TryParse(([string]$controlEventIdText.Text).Trim(), [ref]$eventId) -or
                $eventId -lt 0) {
                throw 'Event ID must be a non-negative whole number.'
            }
            $trigger = [ordered]@{
                type = 'windows_event'
                log = $logName
                source = $sourceName
                eventId = $eventId
            }
        }
        else {
            throw 'Select a trigger.'
        }

        $replacement = [ordered]@{
            id = [string]$schedule.id
            name = $name
            enabled = [bool]$controlEnabledCheck.Checked
            trigger = Copy-ControlObject $trigger
            source = Get-ControlSourceFromFields
            actions = @(Get-ControlActionsFromFields)
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$schedule.lastRun)) {
            $replacement.lastRun = [string]$schedule.lastRun
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$schedule.lastResult)) {
            $replacement.lastResult = [string]$schedule.lastResult
        }
        $replacementObject = Copy-ControlObject $replacement
        $documentIndex = Find-ControlScheduleIndexById ([string]$schedule.id)
        $script:controlDocument.schedules[$documentIndex] = $replacementObject
        if ($oldWasWindows -or [string]$trigger.type -like 'windows_*') {
            $script:controlWindowsSyncNeeded = $true
        }
        Refresh-ControlScheduleList ([string]$schedule.id)
        Set-ControlStatus "Draft updated: $name"
        return $true
    }
    catch {
        if ($showErrors) {
            [System.Windows.Forms.MessageBox]::Show(
                [string]$_.Exception.Message,
                'Schedule details',
                'OK',
                'Warning'
            ) | Out-Null
        }
        return $false
    }
}

function Get-ControlInstalledWindowsTaskIds {
    try {
        return @(
            Get-ScheduledTask `
                -TaskPath '\RF Tower\Schedules\' `
                -ErrorAction SilentlyContinue |
                ForEach-Object { [string]$_.TaskName }
        )
    }
    catch { return @() }
}

function Sync-ControlWindowsSchedules {
    $desiredIds = @(
        @($script:controlDocument.schedules) |
            Where-Object { [string]$_.trigger.type -like 'windows_*' } |
            ForEach-Object { [string]$_.id } |
            Sort-Object
    )
    $installedIds = @(Get-ControlInstalledWindowsTaskIds | Sort-Object)
    $taskSetMatches = $false
    if ($desiredIds.Count -eq $installedIds.Count) {
        $taskSetMatches =
            $desiredIds.Count -eq 0 -or
            (@(Compare-Object $desiredIds $installedIds).Count -eq 0)
    }
    $shouldSync = $script:controlWindowsSyncNeeded -or -not $taskSetMatches
    if (-not $shouldSync) { return }
    if ($desiredIds.Count -gt 0 -and
        $null -eq (Get-ScheduledTask -TaskName 'Tower Background Agent' -ErrorAction SilentlyContinue)) {
        throw 'Install or repair Windows startup integration in Settings first. Windows-triggered commands require the Tower Background Agent.'
    }
    if (-not (Test-Path -LiteralPath $script:controlWindowsScheduleManager)) {
        throw "Windows schedule manager is missing: $script:controlWindowsScheduleManager"
    }

    $expectedDirectory = Join-Path $env:ProgramFiles 'Tower Control'
    if (-not ([IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')).Equals(
            ([IO.Path]::GetFullPath($expectedDirectory).TrimEnd('\')),
            [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Run Install-Tower-Control.cmd before saving Windows triggers. Their tasks must point to the stable Program Files installation.'
    }

    $windowsSchedules = @(
        @($script:controlDocument.schedules) |
            Where-Object { [string]$_.trigger.type -like 'windows_*' }
    )
    New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
    $requestPath = Join-Path $configDirectory (
        'windows-schedules-{0}.json' -f ([guid]::NewGuid()).ToString('N')
    )
    [ordered]@{
        appDirectory = [string]$PSScriptRoot
        schedules = @($windowsSchedules)
    } | ConvertTo-Json -Depth 50 |
        Set-Content -LiteralPath $requestPath -Encoding UTF8

    $arguments = @(
        '-NoProfile',
        '-WindowStyle', 'Hidden',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $script:controlWindowsScheduleManager),
        '-Mode', 'Sync',
        '-RequestPath', ('"{0}"' -f $requestPath)
    )
    try {
        $process = Start-Process `
            -FilePath 'powershell.exe' `
            -ArgumentList ($arguments -join ' ') `
            -Verb RunAs `
            -Wait `
            -PassThru
        if ($process.ExitCode -ne 0) {
            throw "Windows Task Scheduler synchronization exited with code $($process.ExitCode)."
        }
        $script:controlWindowsSyncNeeded = $false
    }
    finally {
        Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue
    }
}

function Save-ControlDocument([bool]$applySelection = $true) {
    if (-not $script:controlEditorLoaded) { return $false }
    if ($applySelection -and $controlScheduleList.SelectedIndex -ge 0 -and
        -not (Apply-ControlSchedule $true)) { return $false }
    try {
        $controlTab.UseWaitCursor = $true
        $response = Invoke-TowerPost '/api/v1/schedules' @{
            schedules = @($script:controlDocument.schedules)
        }
        $script:controlDocument = $response.schedules
        Refresh-ControlScheduleList
        try {
            Sync-ControlWindowsSchedules
        }
        catch {
            Set-ControlStatus "Saved on Tower, but Windows task setup failed: $($_.Exception.Message)" $true
            [System.Windows.Forms.MessageBox]::Show(
                [string]$_.Exception.Message,
                'Windows Task Scheduler setup failed',
                'OK',
                'Error'
            ) | Out-Null
            return $false
        }
        Set-ControlStatus "$(@($script:controlDocument.schedules).Count) schedule(s) saved and synchronized."
        return $true
    }
    catch {
        $details = Get-TowerHttpErrorDetails $_ 'POST' '/api/v1/schedules' @{}
        Set-ControlStatus "Schedule save failed: $($details.Message)" $true
        [System.Windows.Forms.MessageBox]::Show(
            $details.Text,
            'Schedule save failed',
            'OK',
            'Error'
        ) | Out-Null
        return $false
    }
    finally {
        $controlTab.UseWaitCursor = $false
    }
}

function Remove-ControlSchedule {
    $schedule = Get-ControlSelectedSchedule
    if ($null -eq $schedule) { return }
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Delete schedule '$([string]$schedule.name)' from the Tower?",
        'Delete schedule',
        'YesNo',
        'Warning'
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    try {
        $controlTab.UseWaitCursor = $true
        $removedWindowsSchedule = [string]$schedule.trigger.type -like 'windows_*'
        [void](Invoke-TowerPost '/api/v1/schedules/delete' @{
            id = [string]$schedule.id
        })
        Refresh-ControlEditor
        if ($removedWindowsSchedule) {
            $script:controlWindowsSyncNeeded = $true
            Sync-ControlWindowsSchedules
        }
        Set-ControlStatus "Schedule deleted: $([string]$schedule.name)"
    }
    finally {
        $controlTab.UseWaitCursor = $false
    }
}

function Run-ControlScheduleNow {
    $schedule = Get-ControlSelectedSchedule
    if ($null -eq $schedule) { return }
    if (-not (Save-ControlDocument $true)) { return }
    $schedule = Get-ControlSelectedSchedule
    try {
        $controlTab.UseWaitCursor = $true
        Set-ControlStatus "Running $([string]$schedule.name)..."
        [System.Windows.Forms.Application]::DoEvents()
        $response = Invoke-TowerPost '/api/v1/schedules/run' @{
            id = [string]$schedule.id
        }
        if ($null -ne $response.schedule) {
            $documentIndex = Find-ControlScheduleIndexById ([string]$schedule.id)
            if ($documentIndex -ge 0) {
                $script:controlDocument.schedules[$documentIndex] = $response.schedule
            }
        }
        Refresh-ControlScheduleList ([string]$schedule.id)
        Set-ControlStatus "Schedule completed: $([string]$schedule.name)"
    }
    catch {
        $details = Get-TowerHttpErrorDetails $_ 'POST' '/api/v1/schedules/run' @{}
        Set-ControlStatus "Schedule failed: $($details.Message)" $true
        [System.Windows.Forms.MessageBox]::Show(
            $details.Text,
            'Schedule run failed',
            'OK',
            'Error'
        ) | Out-Null
        Refresh-ControlEditor
    }
    finally {
        $controlTab.UseWaitCursor = $false
    }
}

function Refresh-ControlEditor {
    try {
        $controlTab.UseWaitCursor = $true
        Set-ControlStatus 'Loading scheduler, command catalog, and Voice sets from Tower...'
        $scheduleResponse = Invoke-TowerGet '/api/v1/schedules'
        $catalogResponse = Invoke-TowerGet '/api/v1/voice/catalog'
        $voiceResponse = Invoke-TowerGet '/api/v1/voice/config'
        $script:controlDocument = $scheduleResponse.schedules
        $script:controlCatalog = $catalogResponse.catalog
        $script:controlVoiceConfig = $voiceResponse.config
        if ($null -eq $script:controlDocument.schedules) {
            $script:controlDocument = [pscustomobject]@{
                version = 1
                schedules = @()
            }
        }
        Refresh-ControlVoiceLeaves
        $script:controlEditorLoaded = $true
        Refresh-ControlScheduleList
        Set-ControlStatus (
            "$(@($script:controlDocument.schedules).Count) Tower schedule(s) loaded; " +
            "$($script:controlVoiceLeaves.Count) Voice command set(s) available."
        )
    }
    catch {
        $script:controlEditorLoaded = $false
        Set-ControlStatus "Scheduler load failed: $($_.Exception.Message)" $true
    }
    finally {
        $controlTab.UseWaitCursor = $false
    }
}

$controlScheduleList.Add_SelectedIndexChanged({
    if (-not $script:controlPopulating -and
        $controlScheduleList.SelectedIndex -ge 0 -and
        $controlScheduleList.SelectedIndex -lt $script:controlScheduleRows.Count) {
        Show-ControlSchedule $script:controlScheduleRows[$controlScheduleList.SelectedIndex]
    }
})
$controlTriggerCombo.Add_SelectedIndexChanged({
    if (-not $script:controlPopulating) { Update-ControlTriggerFields }
})
$controlScheduleTypeCombo.Add_SelectedIndexChanged({
    if (-not $script:controlPopulating) { Update-ControlTriggerFields }
})
$controlLogonAnyRadio.Add_CheckedChanged({
    if (-not $script:controlPopulating) { Update-ControlTriggerFields }
})
$controlLogonSpecificRadio.Add_CheckedChanged({
    if (-not $script:controlPopulating) { Update-ControlTriggerFields }
})
$controlEventLogCombo.Add_SelectedIndexChanged({
    if (-not $script:controlPopulating -and
        [string]$controlTriggerCombo.SelectedItem -eq 'On an event') {
        $controlEventSourceCombo.Text = ''
        Refresh-ControlEventSources
    }
})
$controlEventLogCombo.Add_DropDown({
    if (-not $script:controlEventLogsLoaded) {
        Initialize-ControlEventLogs ([string]$controlEventLogCombo.Text)
    }
})
$controlSourceCombo.Add_SelectedIndexChanged({
    if (-not $script:controlPopulating) { Update-ControlActionFields }
})
$controlTargetCombo.Add_SelectedIndexChanged({
    if (-not $script:controlPopulating) {
        if ([string]$controlSourceCombo.SelectedItem -eq 'IR command') {
            Refresh-ControlCommandChoices
        }
        Update-ControlActionPreview
    }
})
$controlCommandCombo.Add_SelectedIndexChanged({
    if (-not $script:controlPopulating) { Update-ControlActionPreview }
})
$controlOperationCombo.Add_SelectedIndexChanged({
    if (-not $script:controlPopulating) { Update-ControlActionPreview }
})
$controlDelaySeconds.Add_ValueChanged({
    if (-not $script:controlPopulating) { Update-ControlActionPreview }
})
foreach ($check in $script:controlTransmitterChecks.Values) {
    $check.Add_CheckedChanged({
        if (-not $script:controlPopulating) { Update-ControlActionPreview }
    })
}
$controlAddButton.Add_Click({
    Invoke-ControlEditorEvent { Add-ControlSchedule } 'new schedule'
})
$controlNewHeaderButton.Add_Click({
    Invoke-ControlEditorEvent { Add-ControlSchedule } 'new schedule'
})
$controlDeleteButton.Add_Click({
    Invoke-ControlEditorEvent { Remove-ControlSchedule } 'delete'
})
$controlApplyButton.Add_Click({
    Invoke-ControlEditorEvent { [void](Apply-ControlSchedule $true) } 'apply'
})
$controlSaveButton.Add_Click({
    Invoke-ControlEditorEvent { [void](Save-ControlDocument $true) } 'save'
})
$controlRunButton.Add_Click({
    Invoke-ControlEditorEvent { Run-ControlScheduleNow } 'run now'
})
$controlReloadButton.Add_Click({
    Invoke-ControlEditorEvent { Refresh-ControlEditor } 'reload'
})

Clear-ControlScheduleEditor
