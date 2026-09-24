# Tower generated-IR remote buttons.
# Dot-sourced by Tower-Control-Tab.ps1 after shared HTTP helpers exist.

$script:remoteCommandDocument = $null
$script:remoteCommandRows = @()
$script:remoteCommandPopulating = $false
$script:remoteCommandVoiceLeaves = @()

$remoteRoot = New-Object System.Windows.Forms.TableLayoutPanel
$remoteRoot.Dock = 'Fill'
$remoteRoot.ColumnCount = 1
$remoteRoot.RowCount = 2
[void]$remoteRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
    [System.Windows.Forms.SizeType]::Absolute, 66
)))
[void]$remoteRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
    [System.Windows.Forms.SizeType]::Percent, 100
)))
$controlRemotePage.Controls.Add($remoteRoot)

$remoteHeader = New-Object System.Windows.Forms.Panel
$remoteHeader.Dock = 'Fill'
$remoteRoot.Controls.Add($remoteHeader, 0, 0)

$remoteTitle = New-Object System.Windows.Forms.Label
$remoteTitle.Text = 'Programmable SofaBaton Buttons'
$remoteTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
$remoteTitle.Location = New-Object System.Drawing.Point(2, 4)
$remoteTitle.AutoSize = $true
$remoteHeader.Controls.Add($remoteTitle)

$remoteStatus = New-Object System.Windows.Forms.Label
$remoteStatus.Text = 'Reload to read programmable IR buttons from Tower.'
$remoteStatus.Location = New-Object System.Drawing.Point(4, 34)
$remoteStatus.Size = New-Object System.Drawing.Size(650, 23)
$remoteStatus.ForeColor = [System.Drawing.Color]::DimGray
$remoteStatus.AutoEllipsis = $true
$remoteHeader.Controls.Add($remoteStatus)

$remoteSaveHeader = New-Object System.Windows.Forms.Button
$remoteSaveHeader.Text = 'Save to Tower'
$remoteSaveHeader.Size = New-Object System.Drawing.Size(112, 34)
$remoteSaveHeader.Anchor = 'Top,Right'
$remoteHeader.Controls.Add($remoteSaveHeader)

$remoteReload = New-Object System.Windows.Forms.Button
$remoteReload.Text = 'Reload'
$remoteReload.Size = New-Object System.Drawing.Size(82, 34)
$remoteReload.Anchor = 'Top,Right'
$remoteHeader.Controls.Add($remoteReload)

$remoteNewHeader = New-Object System.Windows.Forms.Button
$remoteNewHeader.Text = '+ New'
$remoteNewHeader.Size = New-Object System.Drawing.Size(78, 34)
$remoteNewHeader.Anchor = 'Top,Right'
$remoteHeader.Controls.Add($remoteNewHeader)

$remoteHeader.Add_Resize({
    $remoteSaveHeader.Left = [Math]::Max(280, $remoteHeader.ClientSize.Width - 116)
    $remoteSaveHeader.Top = 10
    $remoteReload.Left = [Math]::Max(190, $remoteSaveHeader.Left - 88)
    $remoteReload.Top = 10
    $remoteNewHeader.Left = [Math]::Max(104, $remoteReload.Left - 84)
    $remoteNewHeader.Top = 10
    $remoteStatus.Width = [Math]::Max(180, $remoteNewHeader.Left - 12)
})

$remoteSplit = New-Object System.Windows.Forms.SplitContainer
$remoteSplit.Dock = 'Fill'
$remoteSplit.FixedPanel = [System.Windows.Forms.FixedPanel]::Panel2
$remoteRoot.Controls.Add($remoteSplit, 0, 1)

# The sidebar/tab can have a temporary narrow size while being constructed.
# Position the divider only after layout, and preserve the editor width rather
# than a percentage of that temporary size. Only user moves update the setting.
if ($null -eq $config.PSObject.Properties['remoteButtonEditorWidth']) {
    $config | Add-Member -NotePropertyName remoteButtonEditorWidth -NotePropertyValue 640
}
$script:remoteSplitterApplying = $false

function Update-RemoteSplitterLayout {
    if ($script:remoteSplitterApplying -or $remoteSplit.IsDisposed) { return }
    $available = $remoteSplit.ClientSize.Width - $remoteSplit.SplitterWidth
    if ($available -lt 300) { return }

    $editorWidth = 640
    $storedWidth = 0
    if ([int]::TryParse([string]$config.remoteButtonEditorWidth, [ref]$storedWidth)) {
        $editorWidth = [Math]::Max(630, $storedWidth)
    }
    $minimumLeft = [Math]::Max(220, $remoteSplit.Panel1MinSize)
    $maximumLeft = $available - $remoteSplit.Panel2MinSize
    if ($maximumLeft -lt $minimumLeft) { return }
    $distance = [Math]::Max($minimumLeft, [Math]::Min($maximumLeft, $available - $editorWidth))
    $script:remoteSplitterApplying = $true
    try {
        if ($remoteSplit.SplitterDistance -ne $distance) {
            $remoteSplit.SplitterDistance = $distance
        }
    } finally {
        $script:remoteSplitterApplying = $false
    }
}

$remoteSplit.Add_SizeChanged({ Update-RemoteSplitterLayout })
$remoteSplit.Add_VisibleChanged({
    if ($remoteSplit.Visible) { Update-RemoteSplitterLayout }
})
# MouseUp persists the completed drag, avoiding programmatic SplitterMoved
# events during startup, monitor changes, and sidebar animation.
$remoteSplit.Add_MouseUp({
    if ($script:remoteSplitterApplying -or $_.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $width = $remoteSplit.ClientSize.Width - $remoteSplit.SplitterWidth - $remoteSplit.SplitterDistance
    $config.remoteButtonEditorWidth = [Math]::Max(630, $width)
    Update-RemoteSplitterLayout
    Save-TowerConfig
})

$remoteListGroup = New-Object System.Windows.Forms.GroupBox
$remoteListGroup.Text = 'Programmed remote buttons'
$remoteListGroup.Dock = 'Fill'
$remoteSplit.Panel1.Controls.Add($remoteListGroup)

$remoteListButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$remoteListButtons.Dock = 'Bottom'
$remoteListButtons.Height = 43
$remoteListButtons.Padding = New-Object System.Windows.Forms.Padding(5, 5, 0, 0)
$remoteListGroup.Controls.Add($remoteListButtons)

$remoteAdd = New-Object System.Windows.Forms.Button
$remoteAdd.Text = '+ New button'
$remoteAdd.Size = New-Object System.Drawing.Size(112, 29)
[void]$remoteListButtons.Controls.Add($remoteAdd)

$remoteDelete = New-Object System.Windows.Forms.Button
$remoteDelete.Text = 'Delete'
$remoteDelete.Size = New-Object System.Drawing.Size(78, 29)
[void]$remoteListButtons.Controls.Add($remoteDelete)

$remoteList = New-Object System.Windows.Forms.ListBox
$remoteList.Dock = 'Fill'
$remoteList.IntegralHeight = $false
$remoteList.HorizontalScrollbar = $true
$remoteListGroup.Controls.Add($remoteList)
$remoteList.BringToFront()

$remoteEditorGroup = New-Object System.Windows.Forms.GroupBox
$remoteEditorGroup.Text = 'Remote button details'
$remoteEditorGroup.Dock = 'Fill'
$remoteSplit.Panel2.Controls.Add($remoteEditorGroup)

$remoteEditor = New-Object System.Windows.Forms.Panel
$remoteEditor.Dock = 'Fill'
$remoteEditor.AutoScroll = $true
$remoteEditorGroup.Controls.Add($remoteEditor)

function New-RemoteLabel([string]$text, [int]$top) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text
    $label.Location = New-Object System.Drawing.Point(16, $top)
    $label.Size = New-Object System.Drawing.Size(145, 25)
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $remoteEditor.Controls.Add($label)
    return $label
}

$remoteEnabled = New-Object System.Windows.Forms.CheckBox
$remoteEnabled.Text = 'Enabled'
$remoteEnabled.Location = New-Object System.Drawing.Point(165, 18)
$remoteEnabled.AutoSize = $true
$remoteEditor.Controls.Add($remoteEnabled)

[void](New-RemoteLabel 'Button name' 58)
$remoteName = New-Object System.Windows.Forms.TextBox
$remoteName.Location = New-Object System.Drawing.Point(165, 58)
$remoteName.Size = New-Object System.Drawing.Size(385, 25)
$remoteEditor.Controls.Add($remoteName)

[void](New-RemoteLabel 'Generated IR code' 98)
$remoteCode = New-Object System.Windows.Forms.TextBox
$remoteCode.Location = New-Object System.Drawing.Point(165, 98)
$remoteCode.Size = New-Object System.Drawing.Size(220, 25)
$remoteCode.ReadOnly = $true
$remoteCode.BackColor = [System.Drawing.SystemColors]::Window
$remoteEditor.Controls.Add($remoteCode)

$remoteCodeHint = New-Object System.Windows.Forms.Label
$remoteCodeHint.Text = 'Tower assigns a unique 38 kHz NEC code when saved.'
$remoteCodeHint.Location = New-Object System.Drawing.Point(165, 126)
$remoteCodeHint.Size = New-Object System.Drawing.Size(420, 23)
$remoteCodeHint.ForeColor = [System.Drawing.Color]::DimGray
$remoteEditor.Controls.Add($remoteCodeHint)

$remoteRule = New-Object System.Windows.Forms.Label
$remoteRule.BorderStyle = [System.Windows.Forms.BorderStyle]::Fixed3D
$remoteRule.Location = New-Object System.Drawing.Point(16, 160)
$remoteRule.Size = New-Object System.Drawing.Size(580, 2)
$remoteEditor.Controls.Add($remoteRule)

[void](New-RemoteLabel 'Run this' 180)
$remoteSource = New-Object System.Windows.Forms.ComboBox
$remoteSource.DropDownStyle = 'DropDownList'
$remoteSource.Location = New-Object System.Drawing.Point(165, 180)
$remoteSource.Size = New-Object System.Drawing.Size(220, 25)
[void]$remoteSource.Items.AddRange(@(
    'RF preset',
    'RF device',
    'IR command',
    'Voice command set',
    'Saved script'
))
$remoteEditor.Controls.Add($remoteSource)

$remoteTargetLabel = New-RemoteLabel 'Target' 220
$remoteTarget = New-Object System.Windows.Forms.ComboBox
$remoteTarget.DropDownStyle = 'DropDownList'
$remoteTarget.Location = New-Object System.Drawing.Point(165, 220)
$remoteTarget.Size = New-Object System.Drawing.Size(385, 25)
$remoteEditor.Controls.Add($remoteTarget)

$remoteOperationLabel = New-RemoteLabel 'Action' 260
$remoteOperation = New-Object System.Windows.Forms.ComboBox
$remoteOperation.DropDownStyle = 'DropDownList'
$remoteOperation.Location = New-Object System.Drawing.Point(165, 260)
$remoteOperation.Size = New-Object System.Drawing.Size(150, 25)
$remoteEditor.Controls.Add($remoteOperation)

$remoteTeachLabel = New-RemoteLabel 'Teach from output' 310
$remoteTeachOutput = New-Object System.Windows.Forms.ComboBox
$remoteTeachOutput.DropDownStyle = 'DropDownList'
$remoteTeachOutput.Location = New-Object System.Drawing.Point(165, 310)
$remoteTeachOutput.Size = New-Object System.Drawing.Size(220, 25)
foreach ($transmitter in Get-AvailableIrTransmitters) {
    [void]$remoteTeachOutput.Items.Add([string]$transmitter)
}
if ($remoteTeachOutput.Items.Count -gt 0) { $remoteTeachOutput.SelectedIndex = 0 }
$remoteEditor.Controls.Add($remoteTeachOutput)

$remoteTeachHint = New-Object System.Windows.Forms.Label
$remoteTeachHint.Text = 'Put SofaBaton in learn mode, aim it at this Tower IR output, then press Teach. Tower transmits for about 8 seconds.'
$remoteTeachHint.Location = New-Object System.Drawing.Point(165, 340)
$remoteTeachHint.Size = New-Object System.Drawing.Size(430, 44)
$remoteTeachHint.ForeColor = [System.Drawing.Color]::DimGray
$remoteEditor.Controls.Add($remoteTeachHint)

$remoteApply = New-Object System.Windows.Forms.Button
$remoteApply.Text = 'Apply button'
$remoteApply.Location = New-Object System.Drawing.Point(165, 397)
$remoteApply.Size = New-Object System.Drawing.Size(112, 32)
$remoteEditor.Controls.Add($remoteApply)

$remoteTeach = New-Object System.Windows.Forms.Button
$remoteTeach.Text = 'Teach SofaBaton'
$remoteTeach.Location = New-Object System.Drawing.Point(287, 397)
$remoteTeach.Size = New-Object System.Drawing.Size(132, 32)
$remoteEditor.Controls.Add($remoteTeach)

$remoteRun = New-Object System.Windows.Forms.Button
$remoteRun.Text = 'Run action now'
$remoteRun.Location = New-Object System.Drawing.Point(429, 397)
$remoteRun.Size = New-Object System.Drawing.Size(122, 32)
$remoteEditor.Controls.Add($remoteRun)

$remoteExplanation = New-Object System.Windows.Forms.Label
$remoteExplanation.Text = (
    "How it works:`r`n" +
    "1. Create and Save the button so Tower assigns its unique code.`r`n" +
    "2. Start learning on SofaBaton and press Teach SofaBaton here.`r`n" +
    "3. Press the learned SofaBaton button; Tower receives it and runs the action.`r`n`r`n" +
    "RF presets and devices now use explicit ON or OFF actions. SMART was removed because estimated device state is passive and is never allowed to choose an operational command. " +
    "Release the remote button for 10 seconds before using it again."
)
$remoteExplanation.Location = New-Object System.Drawing.Point(165, 450)
$remoteExplanation.Size = New-Object System.Drawing.Size(430, 180)
$remoteExplanation.ForeColor = [System.Drawing.Color]::DimGray
$remoteEditor.Controls.Add($remoteExplanation)

function Set-RemoteStatus([string]$message, [bool]$error = $false) {
    $remoteStatus.Text = $message
    $remoteStatus.ForeColor = if ($error) {
        [System.Drawing.Color]::Firebrick
    } else {
        [System.Drawing.Color]::ForestGreen
    }
}

function Add-RemoteVoiceLeaves($children, $parentPath) {
    if ($null -eq $children) { return }
    foreach ($property in @($children.PSObject.Properties)) {
        $path = @($parentPath) + @([string]$property.Name)
        if ($null -ne $property.Value.children) {
            Add-RemoteVoiceLeaves $property.Value.children $path
        } elseif (@($property.Value.actions).Count -gt 0) {
            $script:remoteCommandVoiceLeaves += [pscustomobject]@{
                Path = @($path)
                Label = @($path) -join ' -> '
            }
        }
    }
}

function Get-RemoteSelectedTrigger {
    if ($remoteList.SelectedIndex -lt 0 -or
        $remoteList.SelectedIndex -ge $script:remoteCommandRows.Count) {
        return $null
    }
    return $script:remoteCommandRows[$remoteList.SelectedIndex]
}

function Set-RemoteTargetById($items, [string]$id) {
    for ($index = 0; $index -lt @($items).Count; $index++) {
        if ([string]$items[$index].id -eq $id) {
            $remoteTarget.SelectedIndex = $index
            return
        }
    }
    if ($remoteTarget.Items.Count -gt 0) { $remoteTarget.SelectedIndex = 0 }
}

function Update-RemoteCommandChoices([string]$commandId = '') {
    $remoteOperation.Items.Clear()
    if ([string]$remoteSource.SelectedItem -ne 'IR command' -or
        $remoteTarget.SelectedIndex -lt 0) { return }
    $device = @($script:controlCatalog.irDevices)[$remoteTarget.SelectedIndex]
    foreach ($command in @($device.commands)) {
        [void]$remoteOperation.Items.Add(
            "$([string]$command.name)  [$([string]$command.id)]"
        )
    }
    for ($index = 0; $index -lt @($device.commands).Count; $index++) {
        if ([string]$device.commands[$index].id -eq $commandId) {
            $remoteOperation.SelectedIndex = $index
            return
        }
    }
    if ($remoteOperation.Items.Count -gt 0) { $remoteOperation.SelectedIndex = 0 }
}

function Update-RemoteActionFields(
    [string]$targetId = '',
    [string]$operation = '',
    [string]$commandId = ''
) {
    $type = [string]$remoteSource.SelectedItem
    $remoteTarget.Items.Clear()
    $remoteOperation.Items.Clear()
    $remoteOperationLabel.Text = 'Action'
    $remoteTeachLabel.Text = if ($type -eq 'IR command') {
        'Teach / action output'
    } else {
        'Teach from output'
    }

    if ($type -eq 'RF preset') {
        $items = @($script:controlCatalog.presets)
        foreach ($item in $items) {
            [void]$remoteTarget.Items.Add(
                "$([string]$item.name)  ($([int]$item.deviceCount) devices)"
            )
        }
        [void]$remoteOperation.Items.AddRange(@('ON', 'OFF'))
        Set-RemoteTargetById $items $targetId
    } elseif ($type -eq 'RF device') {
        $items = @($script:controlCatalog.rfDevices)
        foreach ($item in $items) {
            [void]$remoteTarget.Items.Add(
                "$([string]$item.name)  [$([string]$item.id)]"
            )
        }
        [void]$remoteOperation.Items.AddRange(@('ON', 'OFF'))
        Set-RemoteTargetById $items $targetId
    } elseif ($type -eq 'IR command') {
        $items = @($script:controlCatalog.irDevices)
        foreach ($item in $items) {
            [void]$remoteTarget.Items.Add(
                "$([string]$item.name)  [$([string]$item.id)]"
            )
        }
        Set-RemoteTargetById $items $targetId
        Update-RemoteCommandChoices $commandId
    } elseif ($type -eq 'Saved script') {
        $script:remoteScriptRows=@((Invoke-TowerGet '/api/v1/control/scripts').scripts)
        foreach($item in $script:remoteScriptRows){
            $prefix=switch([string]$item.kind){'wol'{'[WOL]'}'powershell'{'[WIN]'}default{'[PI]'}}
            [void]$remoteTarget.Items.Add("$prefix $([string]$item.name)")
        }
        Set-RemoteTargetById $script:remoteScriptRows $targetId
        $remoteOperation.Visible=$false;$remoteOperationLabel.Visible=$false
    } elseif ($type -eq 'Voice command set') {
        foreach ($leaf in @($script:remoteCommandVoiceLeaves)) {
            [void]$remoteTarget.Items.Add([string]$leaf.Label)
        }
        for ($index = 0; $index -lt $script:remoteCommandVoiceLeaves.Count; $index++) {
            if ((@($script:remoteCommandVoiceLeaves[$index].Path) -join "`n") -eq $targetId) {
                $remoteTarget.SelectedIndex = $index
                break
            }
        }
        $remoteOperation.Visible = $false
        $remoteOperationLabel.Visible = $false
    }

    if ($type -notin @('Voice command set','Saved script')) {
        $remoteOperation.Visible = $true
        $remoteOperationLabel.Visible = $true
    }
    if ($remoteTarget.SelectedIndex -lt 0 -and $remoteTarget.Items.Count -gt 0) {
        $remoteTarget.SelectedIndex = 0
    }
    if ($type -ne 'IR command' -and $operation) {
        if ($operation -eq 'toggle') {
            $remoteOperation.Items.Insert(0, 'SMART disabled - choose ON or OFF')
            $remoteOperation.SelectedIndex = 0
            Set-RemoteStatus 'This older button used SMART. Select explicit ON or OFF and save it.' $true
        }
        else {
            $remoteOperation.SelectedItem = $operation.ToUpperInvariant()
        }
    }
    if ($type -ne 'IR command' -and
        $remoteOperation.SelectedIndex -lt 0 -and
        $remoteOperation.Items.Count -gt 0) {
        $remoteOperation.SelectedIndex = 0
    }
}

function Get-RemoteActionFromFields {
    $type = [string]$remoteSource.SelectedItem
    if ($remoteTarget.SelectedIndex -lt 0) { throw 'Select a target.' }
    if($type -eq 'Saved script'){return [pscustomobject]@{type='script';script=[string]$script:remoteScriptRows[$remoteTarget.SelectedIndex].id}}
    if ($type -eq 'RF preset') {
        if ([string]$remoteOperation.SelectedItem -like 'SMART*') {
            throw 'SMART is disabled. Choose explicit ON or OFF.'
        }
        $preset = @($script:controlCatalog.presets)[$remoteTarget.SelectedIndex]
        return [pscustomobject][ordered]@{
            type = 'rf_preset'
            preset = [int]$preset.id
            action = ([string]$remoteOperation.SelectedItem).ToLowerInvariant()
        }
    }
    if ($type -eq 'RF device') {
        if ([string]$remoteOperation.SelectedItem -like 'SMART*') {
            throw 'SMART is disabled. Choose explicit ON or OFF.'
        }
        $device = @($script:controlCatalog.rfDevices)[$remoteTarget.SelectedIndex]
        return [pscustomobject][ordered]@{
            type = 'rf_group'
            name = [string]$device.name
            devices = @([string]$device.id)
            action = ([string]$remoteOperation.SelectedItem).ToLowerInvariant()
        }
    }
    if ($type -eq 'IR command') {
        if ($remoteOperation.SelectedIndex -lt 0) { throw 'Select an IR command.' }
        $device = @($script:controlCatalog.irDevices)[$remoteTarget.SelectedIndex]
        $command = @($device.commands)[$remoteOperation.SelectedIndex]
        return [pscustomobject][ordered]@{
            type = 'command'
            device = [string]$device.id
            command = [string]$command.id
            transmitters = @([string]$remoteTeachOutput.SelectedItem)
        }
    }
    if ($type -eq 'Voice command set') {
        $leaf = $script:remoteCommandVoiceLeaves[$remoteTarget.SelectedIndex]
        return [pscustomobject][ordered]@{
            type = 'voice_path'
            path = @($leaf.Path)
        }
    }
    throw 'Select what this remote button should run.'
}

function Get-RemoteActionSummary($trigger) {
    $action = @($trigger.actions)[0]
    switch ([string]$action.type) {
        'rf_preset' { return "Preset $([int]$action.preset) -> $([string]$action.action)" }
        'rf_group' { return "RF $([string]$action.name) -> $([string]$action.action)" }
        'script' {return "Script: $([string]$action.script)"}
        'voice_path' { return "Voice: $(@($action.path) -join ' -> ')" }
        default { return "IR $([string]$action.device) -> $([string]$action.command)" }
    }
}

function Refresh-RemoteList([string]$selectId = '') {
    $script:remoteCommandRows = @($script:remoteCommandDocument.triggers)
    $remoteList.Items.Clear()
    $selected = -1
    for ($index = 0; $index -lt $script:remoteCommandRows.Count; $index++) {
        $trigger = $script:remoteCommandRows[$index]
        $state = if ([bool]$trigger.enabled) { '[ON]' } else { '[OFF]' }
        [void]$remoteList.Items.Add(
            "$state $([string]$trigger.name)  |  $(Get-RemoteActionSummary $trigger)"
        )
        if ([string]$trigger.id -eq $selectId) { $selected = $index }
    }
    if ($selected -ge 0) {
        $remoteList.SelectedIndex = $selected
    } elseif ($remoteList.Items.Count -gt 0) {
        $remoteList.SelectedIndex = 0
    } else {
        $remoteEditorGroup.Text = 'Remote button details - press + New button'
    }
}

function Show-RemoteTrigger($trigger) {
    if ($null -eq $trigger) { return }
    $script:remoteCommandPopulating = $true
    try {
        $remoteEnabled.Checked = [bool]$trigger.enabled
        $remoteName.Text = [string]$trigger.name
        $remoteCode.Text = if ([int]$trigger.command -gt 0) {
            'NEC 0x{0:X2} / 0x{1:X2}' -f [int]$trigger.address, [int]$trigger.command
        } else {
            'Assigned when saved'
        }
        $action = @($trigger.actions)[0]
        switch ([string]$action.type) {
            'script' {$remoteSource.SelectedItem='Saved script';Update-RemoteActionFields ([string]$action.script)}

            'rf_preset' {
                $remoteSource.SelectedItem = 'RF preset'
                Update-RemoteActionFields ([string]$action.preset) ([string]$action.action)
            }
            'rf_group' {
                $remoteSource.SelectedItem = 'RF device'
                Update-RemoteActionFields ([string]@($action.devices)[0]) ([string]$action.action)
            }
            'voice_path' {
                $remoteSource.SelectedItem = 'Voice command set'
                Update-RemoteActionFields (@($action.path) -join "`n")
            }
            default {
                $remoteSource.SelectedItem = 'IR command'
                Update-RemoteActionFields ([string]$action.device) '' ([string]$action.command)
                if (@($action.transmitters).Count -gt 0) {
                    $remoteTeachOutput.SelectedItem = [string]@($action.transmitters)[0]
                }
            }
        }
        $remoteEditorGroup.Text = "Remote button details - $([string]$trigger.name)"
    } finally {
        $script:remoteCommandPopulating = $false
    }
}

function Apply-RemoteTrigger {
    $trigger = Get-RemoteSelectedTrigger
    if ($null -eq $trigger) { throw 'Create or select a remote button first.' }
    if ([string]::IsNullOrWhiteSpace($remoteName.Text)) {
        throw 'Enter a button name.'
    }
    $trigger.name = $remoteName.Text.Trim()
    $trigger.enabled = $remoteEnabled.Checked
    $trigger.actions = @((Get-RemoteActionFromFields))
    Refresh-RemoteList ([string]$trigger.id)
    Set-RemoteStatus 'Button draft updated. Press Save to Tower to make it persistent.'
}

function Save-RemoteDocument {
    Apply-RemoteTrigger
    $selectedId = [string](Get-RemoteSelectedTrigger).id
    $response = Invoke-TowerPost '/api/v1/control/ir-triggers' @{
        triggers = @($script:remoteCommandDocument.triggers)
    }
    $script:remoteCommandDocument = $response.document
    Refresh-RemoteList $selectedId
    if(Get-Command Set-TowerDirty -ErrorAction SilentlyContinue){Set-TowerDirty $remoteSaveHeader $false}
    Set-RemoteStatus "$(@($script:remoteCommandDocument.triggers).Count) remote button(s) saved on Tower."
}

function Reload-RemoteCommands {
    $controlRemotePage.UseWaitCursor = $true
    try {
        $response = Invoke-TowerGet '/api/v1/control/ir-triggers'
        $catalogResponse = Invoke-TowerGet '/api/v1/voice/catalog'
        $voiceResponse = Invoke-TowerGet '/api/v1/voice/config'
        $script:remoteCommandDocument = $response.document
        $script:controlCatalog = $catalogResponse.catalog
        $script:remoteCommandVoiceLeaves = @()
        Add-RemoteVoiceLeaves $voiceResponse.config.command_tree @()
        Refresh-RemoteList
        $receiver = $response.document.receiver
        $receiverText = if ([bool]$receiver.available) {
            "$([string]$receiver.status) on $([string]$receiver.device)"
        } else {
            [string]$receiver.status
        }
        Set-RemoteStatus (
            "$(@($script:remoteCommandDocument.triggers).Count) remote button(s) loaded; $receiverText"
        ) (-not [bool]$receiver.available)
    } catch {
        Set-RemoteStatus "Remote buttons could not be loaded: $($_.Exception.Message)" $true
    } finally {
        $controlRemotePage.UseWaitCursor = $false
    }
}

function Add-RemoteTrigger {
    if ($null -eq $script:remoteCommandDocument) {
        Reload-RemoteCommands
    }
    $id = 'remote-' + [Guid]::NewGuid().ToString('N')
    $newTrigger = [pscustomobject][ordered]@{
        id = $id
        name = 'New SofaBaton button'
        enabled = $true
        protocol = 'NEC'
        address = 84
        command = 0
        actions = @([pscustomobject][ordered]@{
            type = 'rf_preset'
            preset = 1
            action = 'on'
        })
    }
    $script:remoteCommandDocument.triggers = @(
        @($script:remoteCommandDocument.triggers) + @($newTrigger)
    )
    Refresh-RemoteList $id
    $remoteName.SelectAll()
    $remoteName.Focus()
    Set-RemoteStatus 'New button draft created. Give it a name and choose its action.'
}

function Delete-RemoteTrigger {
    $trigger = Get-RemoteSelectedTrigger
    if ($null -eq $trigger) { return }
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Delete remote button '$([string]$trigger.name)'?",
        'Delete remote button',
        'YesNo',
        'Warning'
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    if ([int]$trigger.command -gt 0) {
        [void](Invoke-TowerPost '/api/v1/control/ir-triggers/delete' @{
            id = [string]$trigger.id
        })
        Reload-RemoteCommands
    } else {
        $script:remoteCommandDocument.triggers = @(
            @($script:remoteCommandDocument.triggers) |
                Where-Object { [string]$_.id -ne [string]$trigger.id }
        )
        Refresh-RemoteList
    }
    Set-RemoteStatus 'Remote button deleted.'
}

function Teach-RemoteTrigger {
    Save-RemoteDocument
    $trigger = Get-RemoteSelectedTrigger
    Set-RemoteStatus 'Transmitting for about 8 seconds - keep SofaBaton in learn mode...'
    [System.Windows.Forms.Application]::DoEvents()
    $response = Invoke-TowerPost '/api/v1/control/ir-triggers/teach' @{
        id = [string]$trigger.id
        transmitter = [string]$remoteTeachOutput.SelectedItem
    }
    Set-RemoteStatus ([string]$response.message)
}

function Run-RemoteTriggerNow {
    Save-RemoteDocument
    $trigger = Get-RemoteSelectedTrigger
    Set-RemoteStatus "Running '$([string]$trigger.name)'..."
    [System.Windows.Forms.Application]::DoEvents()
    $response = Invoke-TowerPost '/api/v1/control/ir-triggers/run' @{
        id = [string]$trigger.id
    }
    Set-RemoteStatus ([string]$response.message)
}

function Invoke-RemoteEditor([scriptblock]$action, [string]$operation) {
    try {
        $controlRemotePage.UseWaitCursor = $true
        & $action
    } catch {
        Set-RemoteStatus "$operation failed: $($_.Exception.Message)" $true
        [System.Windows.Forms.MessageBox]::Show(
            [string]$_.Exception.Message,
            "$operation failed",
            'OK',
            'Error'
        ) | Out-Null
    } finally {
        $controlRemotePage.UseWaitCursor = $false
    }
}

$remoteList.Add_SelectedIndexChanged({
    if (-not $script:remoteCommandPopulating) {
        Show-RemoteTrigger (Get-RemoteSelectedTrigger)
    }
})
$remoteSource.Add_SelectedIndexChanged({
    if (-not $script:remoteCommandPopulating) { Update-RemoteActionFields }
})
$remoteTarget.Add_SelectedIndexChanged({
    if (-not $script:remoteCommandPopulating -and
        [string]$remoteSource.SelectedItem -eq 'IR command') {
        Update-RemoteCommandChoices
    }
})
$remoteAdd.Add_Click({ Invoke-RemoteEditor { Add-RemoteTrigger } 'New remote button' })
$remoteNewHeader.Add_Click({ Invoke-RemoteEditor { Add-RemoteTrigger } 'New remote button' })
$remoteDelete.Add_Click({ Invoke-RemoteEditor { Delete-RemoteTrigger } 'Delete remote button' })
$remoteApply.Add_Click({ Invoke-RemoteEditor { Apply-RemoteTrigger } 'Apply remote button' })
$remoteSaveHeader.Add_Click({ Invoke-RemoteEditor { Save-RemoteDocument } 'Save remote buttons' })
$remoteTeach.Add_Click({ Invoke-RemoteEditor { Teach-RemoteTrigger } 'Teach SofaBaton' })
$remoteRun.Add_Click({ Invoke-RemoteEditor { Run-RemoteTriggerNow } 'Run remote action' })
$remoteReload.Add_Click({ Invoke-RemoteEditor { Reload-RemoteCommands } 'Reload remote buttons' })
$controlRemotePage.Add_Enter({
    Update-RemoteSplitterLayout
    if ($null -eq $script:remoteCommandDocument) { Reload-RemoteCommands }
})
$controlModeTabs.Add_SelectedIndexChanged({
    if ($controlModeTabs.SelectedTab -eq $controlRemotePage -and
        $null -eq $script:remoteCommandDocument) {
        Reload-RemoteCommands
    }
})

$script:remoteCommandPopulating = $true
$remoteEnabled.Checked = $true
$remoteSource.SelectedIndex = 0
$script:remoteCommandPopulating = $false
