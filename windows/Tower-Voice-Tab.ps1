# Tower Voice tab
# Dot-sourced by Tower-Control.ps1 after the shared HTTP/UI helpers exist.

$script:voiceConfig = $null
$script:voiceCatalog = $null
$script:voiceTreePopulating = $false
$script:voiceActionDrafts = @()
$script:voiceActionListPopulating = $false

$voiceTab = New-Object System.Windows.Forms.TabPage
$voiceTab.Text = 'Voice'
$voiceTab.Padding = New-Object System.Windows.Forms.Padding(10)
$script:voiceTab = $voiceTab
[void]$tabs.TabPages.Add($voiceTab)

$voiceRoot = New-Object System.Windows.Forms.TableLayoutPanel
$voiceRoot.Dock = 'Fill'
$voiceRoot.ColumnCount = 1
$voiceRoot.RowCount = 2
$voiceRoot.Margin = New-Object System.Windows.Forms.Padding(0)
[void]$voiceRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
    [System.Windows.Forms.SizeType]::Absolute,
    58
)))
[void]$voiceRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
    [System.Windows.Forms.SizeType]::Percent,
    100
)))
$voiceTab.Controls.Add($voiceRoot)

$voiceHeader = New-Object System.Windows.Forms.Panel
$voiceHeader.Dock = 'Fill'
$voiceRoot.Controls.Add($voiceHeader, 0, 0)

$voiceTitle = New-Object System.Windows.Forms.Label
$voiceTitle.Text = 'Voice Command Editor'
$voiceTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
$voiceTitle.Location = New-Object System.Drawing.Point(2, 4)
$voiceTitle.AutoSize = $true
$voiceHeader.Controls.Add($voiceTitle)

$voiceStatusLabel = New-Object System.Windows.Forms.Label
$voiceStatusLabel.Text = 'Open this tab to load the Tower voice configuration.'
$voiceStatusLabel.Location = New-Object System.Drawing.Point(4, 31)
$voiceStatusLabel.Size = New-Object System.Drawing.Size(620, 22)
$voiceStatusLabel.ForeColor = [System.Drawing.Color]::DimGray
$voiceStatusLabel.AutoEllipsis = $true
$voiceHeader.Controls.Add($voiceStatusLabel)

$voiceSaveButton = New-Object System.Windows.Forms.Button
$voiceSaveButton.Text = 'Save to Tower'
$voiceSaveButton.Size = New-Object System.Drawing.Size(112, 34)
$voiceSaveButton.Anchor = 'Top,Right'
$voiceHeader.Controls.Add($voiceSaveButton)

$voiceReloadButton = New-Object System.Windows.Forms.Button
$voiceReloadButton.Text = 'Reload'
$voiceReloadButton.Size = New-Object System.Drawing.Size(82, 34)
$voiceReloadButton.Anchor = 'Top,Right'
$voiceHeader.Controls.Add($voiceReloadButton)

$voiceHeader.Add_Resize({
    $voiceSaveButton.Left = [Math]::Max(200, $voiceHeader.ClientSize.Width - 116)
    $voiceSaveButton.Top = 9
    $voiceReloadButton.Left = [Math]::Max(110, $voiceSaveButton.Left - 88)
    $voiceReloadButton.Top = 9
    $voiceStatusLabel.Width = [Math]::Max(180, $voiceReloadButton.Left - 16)
})

$voiceSplit = New-Object System.Windows.Forms.SplitContainer
$voiceSplit.Dock = 'Fill'
$voiceSplit.Size = New-Object System.Drawing.Size(900, 600)
$voiceSplit.SplitterDistance = 310
$voiceSplit.Panel1MinSize = 100
$voiceSplit.Panel2MinSize = 100
$voiceRoot.Controls.Add($voiceSplit, 0, 1)

$voiceTreeGroup = New-Object System.Windows.Forms.GroupBox
$voiceTreeGroup.Text = 'Spoken command tree'
$voiceTreeGroup.Dock = 'Fill'
$voiceSplit.Panel1.Controls.Add($voiceTreeGroup)

$voiceTreeButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$voiceTreeButtons.Dock = [System.Windows.Forms.DockStyle]::Bottom
$voiceTreeButtons.Height = 43
$voiceTreeButtons.Padding = New-Object System.Windows.Forms.Padding(5, 5, 0, 0)
$voiceTreeGroup.Controls.Add($voiceTreeButtons)

$voiceAddButton = New-Object System.Windows.Forms.Button
$voiceAddButton.Text = '+ Add child'
$voiceAddButton.Size = New-Object System.Drawing.Size(100, 29)
[void]$voiceTreeButtons.Controls.Add($voiceAddButton)

$voiceDeleteButton = New-Object System.Windows.Forms.Button
$voiceDeleteButton.Text = 'Delete'
$voiceDeleteButton.Size = New-Object System.Drawing.Size(78, 29)
[void]$voiceTreeButtons.Controls.Add($voiceDeleteButton)

$voiceTree = New-Object System.Windows.Forms.TreeView
$voiceTree.Dock = 'Fill'
$voiceTree.HideSelection = $false
$voiceTree.FullRowSelect = $true
$voiceTreeGroup.Controls.Add($voiceTree)
$voiceTree.BringToFront()

$voiceEditorGroup = New-Object System.Windows.Forms.GroupBox
$voiceEditorGroup.Text = 'Selected level'
$voiceEditorGroup.Dock = 'Fill'
$voiceSplit.Panel2.Controls.Add($voiceEditorGroup)

$voiceEditor = New-Object System.Windows.Forms.Panel
$voiceEditor.Dock = 'Fill'
$voiceEditor.AutoScroll = $true
$voiceEditorGroup.Controls.Add($voiceEditor)

function New-VoiceEditorLabel([string]$text, [int]$top) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text
    $label.Location = New-Object System.Drawing.Point(14, $top)
    $label.Size = New-Object System.Drawing.Size(135, 23)
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $voiceEditor.Controls.Add($label)
    return $label
}

[void](New-VoiceEditorLabel 'Wake phrase' 18)
$voiceWakeText = New-Object System.Windows.Forms.TextBox
$voiceWakeText.Location = New-Object System.Drawing.Point(155, 18)
$voiceWakeText.Size = New-Object System.Drawing.Size(300, 25)
$voiceEditor.Controls.Add($voiceWakeText)

$voiceWakeHint = New-Object System.Windows.Forms.Label
$voiceWakeHint.Text = 'The root phrase that activates the listener.'
$voiceWakeHint.Location = New-Object System.Drawing.Point(155, 46)
$voiceWakeHint.Size = New-Object System.Drawing.Size(390, 20)
$voiceWakeHint.ForeColor = [System.Drawing.Color]::DimGray
$voiceEditor.Controls.Add($voiceWakeHint)

[void](New-VoiceEditorLabel 'Phrase' 82)
$voicePhraseText = New-Object System.Windows.Forms.TextBox
$voicePhraseText.Location = New-Object System.Drawing.Point(155, 82)
$voicePhraseText.Size = New-Object System.Drawing.Size(300, 25)
$voiceEditor.Controls.Add($voicePhraseText)

[void](New-VoiceEditorLabel 'Spoken aliases' 118)
$voiceAliasesText = New-Object System.Windows.Forms.TextBox
$voiceAliasesText.Location = New-Object System.Drawing.Point(155, 118)
$voiceAliasesText.Size = New-Object System.Drawing.Size(390, 25)
$voiceEditor.Controls.Add($voiceAliasesText)

$voiceAliasHint = New-Object System.Windows.Forms.Label
$voiceAliasHint.Text = 'Separate alternatives with commas, for example: zoutlamp, salt lamp'
$voiceAliasHint.Location = New-Object System.Drawing.Point(155, 146)
$voiceAliasHint.Size = New-Object System.Drawing.Size(460, 20)
$voiceAliasHint.ForeColor = [System.Drawing.Color]::DimGray
$voiceEditor.Controls.Add($voiceAliasHint)

[void](New-VoiceEditorLabel 'Level type' 181)
$voiceTypeCombo = New-Object System.Windows.Forms.ComboBox
$voiceTypeCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$voiceTypeCombo.Location = New-Object System.Drawing.Point(155, 181)
$voiceTypeCombo.Size = New-Object System.Drawing.Size(220, 25)
[void]$voiceTypeCombo.Items.AddRange(@(
    'Branch (more words)',
    'RF preset',
    'RF device',
    'IR command'
))
$voiceEditor.Controls.Add($voiceTypeCombo)

$voiceTargetLabel = New-VoiceEditorLabel 'Target' 221
$voiceTargetCombo = New-Object System.Windows.Forms.ComboBox
$voiceTargetCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$voiceTargetCombo.Location = New-Object System.Drawing.Point(155, 221)
$voiceTargetCombo.Size = New-Object System.Drawing.Size(390, 25)
$voiceEditor.Controls.Add($voiceTargetCombo)

$voiceCommandLabel = New-VoiceEditorLabel 'Command' 261
$voiceCommandCombo = New-Object System.Windows.Forms.ComboBox
$voiceCommandCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$voiceCommandCombo.Location = New-Object System.Drawing.Point(155, 261)
$voiceCommandCombo.Size = New-Object System.Drawing.Size(390, 25)
$voiceEditor.Controls.Add($voiceCommandCombo)

$voiceActionLabel = New-VoiceEditorLabel 'Action' 301
$voiceActionCombo = New-Object System.Windows.Forms.ComboBox
$voiceActionCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$voiceActionCombo.Location = New-Object System.Drawing.Point(155, 301)
$voiceActionCombo.Size = New-Object System.Drawing.Size(130, 25)
[void]$voiceActionCombo.Items.AddRange(@('on', 'off'))
$voiceEditor.Controls.Add($voiceActionCombo)

$voiceTransmitterPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$voiceTransmitterPanel.Location = New-Object System.Drawing.Point(155, 296)
$voiceTransmitterPanel.Size = New-Object System.Drawing.Size(430, 36)
$voiceTransmitterPanel.WrapContents = $false
$voiceTransmitterPanel.Visible = $false
$voiceEditor.Controls.Add($voiceTransmitterPanel)

$script:voiceTransmitterChecks = @{}
foreach ($transmitterName in Get-AvailableIrTransmitters) {
    $transmitterCheck = New-Object System.Windows.Forms.CheckBox
    $transmitterCheck.Text = Get-ShortTransmitterLabel $transmitterName
    $transmitterCheck.Tag = $transmitterName
    $transmitterCheck.AutoSize = $true
    $transmitterCheck.Margin = New-Object System.Windows.Forms.Padding(3, 7, 8, 3)
    $script:voiceTransmitterChecks[$transmitterName] = $transmitterCheck
    [void]$voiceTransmitterPanel.Controls.Add($transmitterCheck)
}

$voiceDelayLabel = New-VoiceEditorLabel 'Delay before' 340
$voiceDelaySeconds = New-Object System.Windows.Forms.NumericUpDown
$voiceDelaySeconds.Location = New-Object System.Drawing.Point(155, 340)
$voiceDelaySeconds.Size = New-Object System.Drawing.Size(75, 25)
$voiceDelaySeconds.Minimum = 0
$voiceDelaySeconds.Maximum = 300
$voiceDelaySeconds.Value = 0
$voiceEditor.Controls.Add($voiceDelaySeconds)

$voiceDelayUnitLabel = New-Object System.Windows.Forms.Label
$voiceDelayUnitLabel.Text = 'seconds (0 = instant)'
$voiceDelayUnitLabel.Location = New-Object System.Drawing.Point(238, 343)
$voiceDelayUnitLabel.Size = New-Object System.Drawing.Size(170, 22)
$voiceDelayUnitLabel.ForeColor = [System.Drawing.Color]::DimGray
$voiceEditor.Controls.Add($voiceDelayUnitLabel)

$voiceApplyButton = New-Object System.Windows.Forms.Button
$voiceApplyButton.Text = 'Apply level'
$voiceApplyButton.Location = New-Object System.Drawing.Point(155, 382)
$voiceApplyButton.Size = New-Object System.Drawing.Size(110, 32)
$voiceEditor.Controls.Add($voiceApplyButton)

$voiceTestButton = New-Object System.Windows.Forms.Button
$voiceTestButton.Text = 'Test action'
$voiceTestButton.Location = New-Object System.Drawing.Point(275, 382)
$voiceTestButton.Size = New-Object System.Drawing.Size(110, 32)
$voiceEditor.Controls.Add($voiceTestButton)

$voiceEditorHint = New-Object System.Windows.Forms.Label
$voiceEditorHint.Text = 'Apply this level, then Save to Tower. Test action runs every action below in order.'
$voiceEditorHint.Location = New-Object System.Drawing.Point(155, 424)
$voiceEditorHint.Size = New-Object System.Drawing.Size(470, 42)
$voiceEditorHint.ForeColor = [System.Drawing.Color]::DimGray
$voiceEditor.Controls.Add($voiceEditorHint)

$voiceActionsLabel = New-VoiceEditorLabel 'Command actions' 480
$voiceActionsList = New-Object System.Windows.Forms.ListBox
$voiceActionsList.Location = New-Object System.Drawing.Point(155, 480)
$voiceActionsList.Size = New-Object System.Drawing.Size(430, 121)
$voiceEditor.Controls.Add($voiceActionsList)

$voiceActionButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$voiceActionButtons.Location = New-Object System.Drawing.Point(155, 609)
$voiceActionButtons.Size = New-Object System.Drawing.Size(430, 40)
$voiceActionButtons.WrapContents = $false
$voiceEditor.Controls.Add($voiceActionButtons)

$voiceAddActionButton = New-Object System.Windows.Forms.Button
$voiceAddActionButton.Text = '+ Add action'
$voiceAddActionButton.Size = New-Object System.Drawing.Size(105, 29)
[void]$voiceActionButtons.Controls.Add($voiceAddActionButton)

$voiceUpdateActionButton = New-Object System.Windows.Forms.Button
$voiceUpdateActionButton.Text = 'Update action'
$voiceUpdateActionButton.Size = New-Object System.Drawing.Size(110, 29)
[void]$voiceActionButtons.Controls.Add($voiceUpdateActionButton)

$voiceRemoveActionButton = New-Object System.Windows.Forms.Button
$voiceRemoveActionButton.Text = 'Remove action'
$voiceRemoveActionButton.Size = New-Object System.Drawing.Size(110, 29)
[void]$voiceActionButtons.Controls.Add($voiceRemoveActionButton)

function Set-VoiceStatus([string]$message, [bool]$isError = $false) {
    $voiceStatusLabel.Text = $message
    $voiceStatusLabel.ForeColor = if ($isError) {
        [System.Drawing.Color]::Firebrick
    }
    else {
        [System.Drawing.Color]::ForestGreen
    }
}

function ConvertTo-VoicePropertyObject($dictionary) {
    # Windows PowerShell 5.1 cannot reliably cast a runtime OrderedDictionary
    # to [pscustomobject], and enumerating it through Add-Member can produce an
    # empty property name. A JSON round trip creates the same property object
    # format returned by the Tower API without either PowerShell 5.1 bug.
    $json = ConvertTo-Json -InputObject $dictionary -Depth 50 -Compress
    $result = ConvertFrom-Json -InputObject $json
    return $result
}

function Invoke-VoiceEditorEvent([scriptblock]$action, [string]$operation) {
    try {
        & $action
    }
    catch {
        $message = [string]$_.Exception.Message
        $details = $message
        if (-not [string]::IsNullOrWhiteSpace([string]$_.ScriptStackTrace)) {
            $details += "`r`n`r`n$([string]$_.ScriptStackTrace)"
        }
        Set-VoiceStatus "Voice $operation failed: $message" $true
        [System.Windows.Forms.MessageBox]::Show(
            $details,
            "Voice $operation failed",
            'OK',
            'Error'
        ) | Out-Null
    }
}

function Get-VoicePathFromTreeNode($treeNode) {
    if ($null -eq $treeNode -or $null -eq $treeNode.Tag) { return @() }
    return @($treeNode.Tag.Path)
}

function Add-VoiceTreeChildren($uiParent, $children, $parentPath) {
    if ($null -eq $children) { return }
    foreach ($property in @($children.PSObject.Properties)) {
        $path = @($parentPath) + @([string]$property.Name)
        $node = New-Object System.Windows.Forms.TreeNode
        $node.Text = [string]$property.Name
        $node.Tag = [pscustomobject]@{
            Path = @($path)
            NodeData = $property.Value
            Siblings = $children
        }
        [void]$uiParent.Nodes.Add($node)
        if ($null -ne $property.Value.children) {
            Add-VoiceTreeChildren $node $property.Value.children $path
        }
    }
}

function Select-VoiceTreePath($path) {
    $wanted = @($path) -join "`n"
    $pending = New-Object System.Collections.Queue
    foreach ($rootNode in $voiceTree.Nodes) { $pending.Enqueue($rootNode) }
    while ($pending.Count -gt 0) {
        $candidate = $pending.Dequeue()
        if ((@(Get-VoicePathFromTreeNode $candidate) -join "`n") -eq $wanted) {
            $voiceTree.SelectedNode = $candidate
            $candidate.EnsureVisible()
            return
        }
        foreach ($child in $candidate.Nodes) { $pending.Enqueue($child) }
    }
}

function Refresh-VoiceTree($selectedPath = $null) {
    $script:voiceTreePopulating = $true
    try {
        if ($null -eq $selectedPath -and $null -ne $voiceTree.SelectedNode) {
            $selectedPath = @(Get-VoicePathFromTreeNode $voiceTree.SelectedNode)
        }
        $voiceTree.BeginUpdate()
        $voiceTree.Nodes.Clear()
        $root = New-Object System.Windows.Forms.TreeNode
        $root.Text = if ([string]::IsNullOrWhiteSpace([string]$script:voiceConfig.wake_phrase)) {
            'Tower'
        } else {
            [string]$script:voiceConfig.wake_phrase
        }
        $root.NodeFont = New-Object System.Drawing.Font(
            $voiceTree.Font,
            [System.Drawing.FontStyle]::Bold
        )
        $root.Tag = [pscustomobject]@{
            Path = @()
            NodeData = $null
            Siblings = $null
        }
        [void]$voiceTree.Nodes.Add($root)
        Add-VoiceTreeChildren $root $script:voiceConfig.command_tree @()
        $root.Expand()
        $voiceTree.EndUpdate()
        if ($null -ne $selectedPath) {
            Select-VoiceTreePath $selectedPath
        }
        if ($null -eq $voiceTree.SelectedNode) {
            $voiceTree.SelectedNode = $root
        }
    }
    finally {
        $script:voiceTreePopulating = $false
    }
    Show-VoiceTreeSelection
}

function Set-VoiceComboIndexById($combo, $items, [string]$id) {
    $combo.SelectedIndex = -1
    for ($index = 0; $index -lt @($items).Count; $index++) {
        if ([string]$items[$index].id -eq $id) {
            $combo.SelectedIndex = $index
            return
        }
    }
}

function Refresh-VoiceCommandChoices([string]$selectedCommand = '') {
    $voiceCommandCombo.Items.Clear()
    $deviceIndex = $voiceTargetCombo.SelectedIndex
    if ($deviceIndex -lt 0 -or $deviceIndex -ge @($script:voiceCatalog.irDevices).Count) {
        return
    }
    $commands = @($script:voiceCatalog.irDevices[$deviceIndex].commands)
    foreach ($command in $commands) {
        [void]$voiceCommandCombo.Items.Add(
            "$([string]$command.name)  [$([string]$command.id)]"
        )
    }
    Set-VoiceComboIndexById $voiceCommandCombo $commands $selectedCommand
    if ($voiceCommandCombo.SelectedIndex -lt 0 -and $voiceCommandCombo.Items.Count -gt 0) {
        $voiceCommandCombo.SelectedIndex = 0
    }
}

function Get-VoiceActionDisplayName($action) {
    $delaySeconds = [Math]::Max(0, [int]$action.delay_before_seconds)
    $delayText = if ($delaySeconds -gt 0) { " [wait ${delaySeconds}s]" } else { '' }
    switch ([string]$action.type) {
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

function Refresh-VoiceActionList([int]$selectedIndex = 0) {
    $script:voiceActionListPopulating = $true
    try {
        $voiceActionsList.Items.Clear()
        foreach ($action in @($script:voiceActionDrafts)) {
            [void]$voiceActionsList.Items.Add((Get-VoiceActionDisplayName $action))
        }
        if ($voiceActionsList.Items.Count -gt 0) {
            $voiceActionsList.SelectedIndex = [Math]::Min(
                [Math]::Max(0, $selectedIndex),
                $voiceActionsList.Items.Count - 1
            )
        }
    }
    finally {
        $script:voiceActionListPopulating = $false
    }
    $voiceUpdateActionButton.Enabled = $voiceActionsList.SelectedIndex -ge 0
    $voiceRemoveActionButton.Enabled = $voiceActionsList.Items.Count -gt 1
}

function Show-VoiceActionFields($action) {
    if ($null -eq $action) { return }
    $targetId = ''
    $commandId = ''
    $operation = ''
    $transmitters = @()
    $delaySeconds = [Math]::Max(0, [int]$action.delay_before_seconds)
    switch ([string]$action.type) {
        'rf_preset' {
            $voiceTypeCombo.SelectedItem = 'RF preset'
            $targetId = [string]$action.preset
            $operation = [string]$action.action
        }
        'rf_group' {
            $voiceTypeCombo.SelectedItem = 'RF device'
            $targetId = [string](@($action.devices)[0])
            $operation = [string]$action.action
        }
        default {
            $voiceTypeCombo.SelectedItem = 'IR command'
            $targetId = [string]$action.device
            $commandId = [string]$action.command
            if ($null -ne $action.transmitters) {
                $transmitters = @($action.transmitters)
            }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$action.transmitter)) {
                $transmitters = @([string]$action.transmitter)
            }
        }
    }
    $voiceDelaySeconds.Value = [Math]::Min(
        [decimal]$voiceDelaySeconds.Maximum,
        [decimal]$delaySeconds
    )
    Update-VoiceActionFields $targetId $commandId $operation $transmitters
}

function Get-VoiceActionFromFields {
    $type = [string]$voiceTypeCombo.SelectedItem
    $delaySeconds = [int]$voiceDelaySeconds.Value
    if ($type -eq 'RF preset') {
        if ($voiceTargetCombo.SelectedIndex -lt 0) { throw 'Select a preset.' }
        $preset = @($script:voiceCatalog.presets)[$voiceTargetCombo.SelectedIndex]
        return [pscustomobject][ordered]@{
            type = 'rf_preset'
            preset = [int]$preset.id
            action = [string]$voiceActionCombo.SelectedItem
            delay_before_seconds = $delaySeconds
        }
    }
    if ($type -eq 'RF device') {
        if ($voiceTargetCombo.SelectedIndex -lt 0) { throw 'Select an RF device.' }
        $device = @($script:voiceCatalog.rfDevices)[$voiceTargetCombo.SelectedIndex]
        return [pscustomobject][ordered]@{
            type = 'rf_group'
            name = [string]$device.name
            action = [string]$voiceActionCombo.SelectedItem
            devices = @([string]$device.id)
            delay_before_seconds = $delaySeconds
        }
    }
    if ($type -eq 'IR command') {
        if ($voiceTargetCombo.SelectedIndex -lt 0 -or
            $voiceCommandCombo.SelectedIndex -lt 0) {
            throw 'Select an IR device and command.'
        }
        $device = @($script:voiceCatalog.irDevices)[$voiceTargetCombo.SelectedIndex]
        $command = @($device.commands)[$voiceCommandCombo.SelectedIndex]
        $selectedTransmitters = @(
            $script:voiceTransmitterChecks.Keys |
                Where-Object { $script:voiceTransmitterChecks[$_].Checked } |
                Sort-Object
        )
        if ($selectedTransmitters.Count -eq 0) {
            throw 'Select at least one IR output.'
        }
        return [pscustomobject][ordered]@{
            type = 'command'
            device = [string]$device.id
            command = [string]$command.id
            transmitters = @($selectedTransmitters)
            delay_before_seconds = $delaySeconds
        }
    }
    throw 'Select an action type.'
}

function Set-VoiceSelectedActionDraft {
    $action = Get-VoiceActionFromFields
    $index = $voiceActionsList.SelectedIndex
    if ($index -lt 0 -or $script:voiceActionDrafts.Count -eq 0) {
        $script:voiceActionDrafts = @($action)
        Refresh-VoiceActionList 0
        return
    }
    $script:voiceActionDrafts[$index] = $action
    Refresh-VoiceActionList $index
}

function Add-VoiceActionDraft {
    $action = Get-VoiceActionFromFields
    $script:voiceActionDrafts = @($script:voiceActionDrafts) + @($action)
    Refresh-VoiceActionList ($script:voiceActionDrafts.Count - 1)
}

function Remove-VoiceActionDraft {
    $removeIndex = $voiceActionsList.SelectedIndex
    if ($removeIndex -lt 0 -or $script:voiceActionDrafts.Count -le 1) { return }
    $remaining = @()
    for ($index = 0; $index -lt $script:voiceActionDrafts.Count; $index++) {
        if ($index -ne $removeIndex) {
            $remaining += $script:voiceActionDrafts[$index]
        }
    }
    $script:voiceActionDrafts = @($remaining)
    Refresh-VoiceActionList ([Math]::Min($removeIndex, $remaining.Count - 1))
    Show-VoiceActionFields $script:voiceActionDrafts[$voiceActionsList.SelectedIndex]
}

function Update-VoiceActionFields(
    [string]$targetId = '',
    [string]$commandId = '',
    [string]$operation = '',
    $transmitters = @()
) {
    if ($script:voiceTreePopulating) { return }
    $type = [string]$voiceTypeCombo.SelectedItem
    $voiceTargetCombo.Items.Clear()

    $isBranch = $type -eq 'Branch (more words)'
    $isPreset = $type -eq 'RF preset'
    $isRfDevice = $type -eq 'RF device'
    $isIr = $type -eq 'IR command'

    $voiceTargetLabel.Visible = -not $isBranch
    $voiceTargetCombo.Visible = -not $isBranch
    $voiceCommandLabel.Visible = $isIr
    $voiceCommandCombo.Visible = $isIr
    $voiceActionLabel.Text = 'Action'
    $voiceActionLabel.Visible = $isPreset -or $isRfDevice
    $voiceActionCombo.Visible = $isPreset -or $isRfDevice
    $voiceTransmitterPanel.Visible = $isIr
    $voiceDelayLabel.Visible = -not $isBranch
    $voiceDelaySeconds.Visible = -not $isBranch
    $voiceDelayUnitLabel.Visible = -not $isBranch
    $voiceTestButton.Enabled = -not $isBranch
    $voiceActionsList.Enabled = -not $isBranch
    $voiceAddActionButton.Enabled = -not $isBranch
    $voiceUpdateActionButton.Enabled =
        -not $isBranch -and $voiceActionsList.SelectedIndex -ge 0
    $voiceRemoveActionButton.Enabled =
        -not $isBranch -and $voiceActionsList.Items.Count -gt 1

    if ($isPreset) {
        $voiceTargetLabel.Text = 'Preset'
        $items = @($script:voiceCatalog.presets)
        foreach ($item in $items) {
            [void]$voiceTargetCombo.Items.Add(
                "$([string]$item.name)  ($([int]$item.deviceCount) devices)"
            )
        }
        Set-VoiceComboIndexById $voiceTargetCombo $items $targetId
    }
    elseif ($isRfDevice) {
        $voiceTargetLabel.Text = 'RF device'
        $items = @($script:voiceCatalog.rfDevices)
        foreach ($item in $items) {
            [void]$voiceTargetCombo.Items.Add(
                "$([string]$item.name)  [$([string]$item.id)]"
            )
        }
        Set-VoiceComboIndexById $voiceTargetCombo $items $targetId
    }
    elseif ($isIr) {
        $voiceTargetLabel.Text = 'IR remote/device'
        $voiceActionLabel.Text = 'IR outputs'
        $voiceActionLabel.Visible = $true
        $items = @($script:voiceCatalog.irDevices)
        foreach ($item in $items) {
            [void]$voiceTargetCombo.Items.Add(
                "$([string]$item.name)  [$([string]$item.id)]"
            )
        }
        Set-VoiceComboIndexById $voiceTargetCombo $items $targetId
        Refresh-VoiceCommandChoices $commandId

        $selectedTransmitters = @($transmitters | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_)
        })
        if ($selectedTransmitters.Count -eq 0) {
            $selectedTransmitters = @($script:selectedIrTransmitters)
        }
        foreach ($name in $script:voiceTransmitterChecks.Keys) {
            $script:voiceTransmitterChecks[$name].Checked =
                $selectedTransmitters -contains $name
        }
    }

    if (-not $isBranch -and $voiceTargetCombo.SelectedIndex -lt 0 -and
        $voiceTargetCombo.Items.Count -gt 0) {
        $voiceTargetCombo.SelectedIndex = 0
    }
    if ($operation -in @('on', 'off')) {
        $voiceActionCombo.SelectedItem = $operation
    }
    elseif ($voiceActionCombo.Items.Count -gt 0) {
        $voiceActionCombo.SelectedIndex = 0
    }
}

function Show-VoiceTreeSelection {
    if ($script:voiceTreePopulating -or $null -eq $voiceTree.SelectedNode) { return }
    $path = @(Get-VoicePathFromTreeNode $voiceTree.SelectedNode)
    $isRoot = $path.Count -eq 0
    $voicePhraseText.Enabled = -not $isRoot
    $voiceAliasesText.Enabled = -not $isRoot
    $voiceTypeCombo.Enabled = -not $isRoot
    $voiceApplyButton.Enabled = -not $isRoot
    $voiceDeleteButton.Enabled = -not $isRoot
    $voiceTestButton.Enabled = -not $isRoot

    if ($isRoot) {
        $script:voiceActionDrafts = @()
        Refresh-VoiceActionList
        $voicePhraseText.Text = ''
        $voiceAliasesText.Text = ''
        $voiceTypeCombo.SelectedIndex = 0
        Update-VoiceActionFields
        return
    }

    $node = $voiceTree.SelectedNode.Tag.NodeData
    if ($null -eq $node) { return }
    $voicePhraseText.Text = [string]$voiceTree.SelectedNode.Text
    $voiceAliasesText.Text = @($node.aliases) -join ', '

    if ($null -ne $node.children) {
        $script:voiceActionDrafts = @()
        Refresh-VoiceActionList
        $voiceTypeCombo.SelectedItem = 'Branch (more words)'
        Update-VoiceActionFields
    }
    else {
        $script:voiceActionDrafts = @($node.actions)
        Refresh-VoiceActionList 0
        if ($script:voiceActionDrafts.Count -gt 0) {
            Show-VoiceActionFields $script:voiceActionDrafts[0]
        }
    }
}

function Get-VoiceAliases {
    return @(
        ([string]$voiceAliasesText.Text -split ',') |
            ForEach-Object { $_.Trim().ToLowerInvariant() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )
}

function Apply-VoiceNodeEditor([bool]$showErrors = $true) {
    $selected = $voiceTree.SelectedNode
    if ($null -eq $selected -or $null -eq $selected.Parent) { return $true }

    try {
        $oldPhrase = [string]$selected.Text
        $newPhrase = ([string]$voicePhraseText.Text).Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($newPhrase)) {
            throw 'Phrase cannot be empty.'
        }

        $parentPath = @(Get-VoicePathFromTreeNode $selected.Parent)
        $siblings = $selected.Tag.Siblings
        $existingNode = $selected.Tag.NodeData
        if ($null -eq $siblings -or $null -eq $existingNode) {
            throw "Cannot locate voice level '$oldPhrase'. Press Reload and try again."
        }
        $duplicate = @(
            $siblings.PSObject.Properties |
                Where-Object { [string]$_.Name -eq $newPhrase }
        ) | Select-Object -First 1
        if ($newPhrase -ne $oldPhrase -and $null -ne $duplicate) {
            throw "Another level already uses '$newPhrase'."
        }

        $nodeData = [ordered]@{}
        $aliases = @(Get-VoiceAliases)
        if ($aliases.Count -gt 0) { $nodeData.aliases = $aliases }

        $type = [string]$voiceTypeCombo.SelectedItem
        if ($type -eq 'Branch (more words)') {
            $nodeData.children = if ($null -ne $existingNode.children) {
                $existingNode.children
            } else {
                [pscustomobject][ordered]@{}
            }
        }
        else {
            Set-VoiceSelectedActionDraft
            if ($script:voiceActionDrafts.Count -eq 0) {
                throw 'Add at least one command action.'
            }
            $nodeData.actions = @($script:voiceActionDrafts)
        }

        $replacement = ConvertTo-VoicePropertyObject $nodeData
        if ($newPhrase -eq $oldPhrase) {
            $existingProperty = @(
                $siblings.PSObject.Properties |
                    Where-Object { [string]$_.Name -eq $oldPhrase }
            ) | Select-Object -First 1
            if ($null -eq $existingProperty) {
                throw "Voice level '$oldPhrase' no longer exists. Press Reload and try again."
            }
            $existingProperty.Value = $replacement
        }
        else {
            $siblings.PSObject.Properties.Remove($oldPhrase)
            $siblings | Add-Member `
                -MemberType NoteProperty `
                -Name $newPhrase `
                -Value $replacement
        }
        $newPath = @($parentPath) + @($newPhrase)
        Refresh-VoiceTree $newPath
        return $true
    }
    catch {
        if ($showErrors) {
            $details = [string]$_.Exception.Message
            if (-not [string]::IsNullOrWhiteSpace([string]$_.ScriptStackTrace)) {
                $details += "`r`n`r`n$([string]$_.ScriptStackTrace)"
            }
            [System.Windows.Forms.MessageBox]::Show(
                $details,
                'Voice level',
                'OK',
                'Warning'
            ) | Out-Null
        }
        return $false
    }
}

function Add-VoiceChild {
    $selectedTreeNode = $voiceTree.SelectedNode
    if ($null -eq $selectedTreeNode) { return }
    $selectedPath = @(Get-VoicePathFromTreeNode $selectedTreeNode)
    if ($null -ne $selectedTreeNode.Parent) {
        $selectedNodeData = $selectedTreeNode.Tag.NodeData
        if ($null -eq $selectedNodeData.children) {
            [System.Windows.Forms.MessageBox]::Show(
                'Change this level to Branch, press Apply level, then add its child.',
                'Voice command tree',
                'OK',
                'Information'
            ) | Out-Null
            return
        }
    }

    Add-Type -AssemblyName Microsoft.VisualBasic
    $phrase = [Microsoft.VisualBasic.Interaction]::InputBox(
        'Spoken phrase for the new level:',
        'Add voice level',
        'new command'
    ).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($phrase)) { return }

    $children = if ($null -eq $selectedTreeNode.Parent) {
        $script:voiceConfig.command_tree
    }
    else {
        $selectedNodeData.children
    }
    $duplicate = @(
        $children.PSObject.Properties |
            Where-Object { [string]$_.Name -eq $phrase }
    ) | Select-Object -First 1
    if ($null -ne $duplicate) {
        [System.Windows.Forms.MessageBox]::Show(
            "'$phrase' already exists at this level.",
            'Voice command tree',
            'OK',
            'Warning'
        ) | Out-Null
        return
    }

    $newNode = [pscustomobject][ordered]@{
        actions = @([pscustomobject][ordered]@{
            type = 'rf_preset'
            preset = 1
            action = 'on'
        })
    }
    $children | Add-Member `
        -MemberType NoteProperty `
        -Name $phrase `
        -Value $newNode
    Refresh-VoiceTree (@($selectedPath) + @($phrase))
}

function Remove-VoiceLevel {
    $selectedNode = $voiceTree.SelectedNode
    if ($null -eq $selectedNode -or $null -eq $selectedNode.Parent) { return }
    $phrase = [string]$selectedNode.Text
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Delete '$phrase' and everything below it?",
        'Delete voice level',
        'YesNo',
        'Warning'
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $parentTreeNode = $selectedNode.Parent
    $parentPath = @(Get-VoicePathFromTreeNode $parentTreeNode)
    $children = $selectedNode.Tag.Siblings
    if ($null -eq $children) {
        throw "Cannot find the parent of voice level '$phrase'. Press Reload and try again."
    }

    # The selected TreeNode supplies both the spoken phrase and its parent, so
    # deletion does not depend on array indexing or object reconstruction.
    $children.PSObject.Properties.Remove($phrase)
    Refresh-VoiceTree $parentPath
}

function Merge-LegacyVoiceCommands {
    if ($null -eq $script:voiceConfig.commands) { return }
    $tree = $script:voiceConfig.command_tree
    foreach ($property in @($script:voiceConfig.commands.PSObject.Properties)) {
        if (@($property.Value).Count -gt 0 -and
            $null -eq $tree.PSObject.Properties[[string]$property.Name]) {
            $legacyNode = [pscustomobject][ordered]@{
                actions = @($property.Value)
            }
            $tree | Add-Member `
                -MemberType NoteProperty `
                -Name ([string]$property.Name) `
                -Value $legacyNode
        }
    }
    $script:voiceConfig.commands = [pscustomobject][ordered]@{}
}

function Refresh-VoiceStatus {
    if (-not $script:voiceEditorLoaded) { return }
    try {
        $response = Invoke-TowerGet '/api/v1/voice/status'
        $state = [string]$response.status.state
        $message = [string]$response.status.message
        Set-VoiceStatus "Voice: $state - $message" ($state -in @('failed', 'error', 'unavailable'))
    }
    catch {
        Set-VoiceStatus "Voice status unavailable: $($_.Exception.Message)" $true
    }
}

function Refresh-VoiceEditor {
    try {
        $voiceTab.UseWaitCursor = $true
        Set-VoiceStatus 'Loading voice configuration from Tower...'
        $configResponse = Invoke-TowerGet '/api/v1/voice/config'
        $catalogResponse = Invoke-TowerGet '/api/v1/voice/catalog'
        $script:voiceConfig = $configResponse.config
        $script:voiceCatalog = $catalogResponse.catalog
        Merge-LegacyVoiceCommands
        $voiceWakeText.Text = [string]$script:voiceConfig.wake_phrase
        $script:voiceEditorLoaded = $true
        Refresh-VoiceTree
        Refresh-VoiceStatus
    }
    catch {
        $script:voiceEditorLoaded = $false
        Set-VoiceStatus "Voice editor load failed: $($_.Exception.Message)" $true
    }
    finally {
        $voiceTab.UseWaitCursor = $false
    }
}

function Save-VoiceEditor {
    if (-not $script:voiceEditorLoaded) { return }
    if (-not (Apply-VoiceNodeEditor $true)) { return }
    $wakePhrase = ([string]$voiceWakeText.Text).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($wakePhrase)) {
        [System.Windows.Forms.MessageBox]::Show(
            'Wake phrase cannot be empty.',
            'Voice configuration',
            'OK',
            'Warning'
        ) | Out-Null
        return
    }
    $script:voiceConfig.wake_phrase = $wakePhrase

    try {
        $voiceTab.UseWaitCursor = $true
        $response = Invoke-TowerPost '/api/v1/voice/config' @{
            config = $script:voiceConfig
        }
        Set-VoiceStatus ([string]$response.message)
        Refresh-VoiceTree
    }
    catch {
        $details = Get-TowerHttpErrorDetails $_ 'POST' '/api/v1/voice/config' @{}
        Set-VoiceStatus "Voice save failed: $($details.Message)" $true
        [System.Windows.Forms.MessageBox]::Show(
            $details.Text,
            'Voice configuration save failed',
            'OK',
            'Error'
        ) | Out-Null
    }
    finally {
        $voiceTab.UseWaitCursor = $false
    }
}

function Test-VoiceAction {
    if (-not (Apply-VoiceNodeEditor $true)) { return }
    $path = @(Get-VoicePathFromTreeNode $voiceTree.SelectedNode)
    $node = $voiceTree.SelectedNode.Tag.NodeData
    if ($null -eq $node -or $null -ne $node.children) {
        [System.Windows.Forms.MessageBox]::Show(
            'Select a leaf action to test.',
            'Voice test',
            'OK',
            'Information'
        ) | Out-Null
        return
    }

    try {
        $actionCount = 0
        foreach ($action in @($node.actions)) {
            $delaySeconds = [Math]::Max(0, [int]$action.delay_before_seconds)
            if ($delaySeconds -gt 0) {
                Set-VoiceStatus "Waiting $delaySeconds seconds before action $($actionCount + 1)..."
                [System.Windows.Forms.Application]::DoEvents()
                Start-Sleep -Seconds $delaySeconds
            }
            switch ([string]$action.type) {
                'rf_preset' {
                    $response = Invoke-TowerPost '/api/v1/rf/preset' @{
                        preset = [int]$action.preset
                        action = [string]$action.action
                    }
                }
                'rf_group' {
                    $response = Invoke-TowerPost '/api/v1/rf/group' @{
                        action = [string]$action.action
                        devices = @($action.devices)
                    }
                }
                default {
                    $request = @{
                        device = [string]$action.device
                        command = [string]$action.command
                    }
                    if (@($action.transmitters).Count -gt 0) {
                        $request.transmitters = @($action.transmitters)
                    }
                    elseif (-not [string]::IsNullOrWhiteSpace([string]$action.transmitter)) {
                        $request.transmitter = [string]$action.transmitter
                    }
                    $response = Invoke-TowerPost '/api/v1/execute' $request
                }
            }
            $actionCount++
        }
        Set-VoiceStatus "Test succeeded ($actionCount actions): $(@($path) -join ' -> ')"
    }
    catch {
        Set-VoiceStatus "Voice action test failed: $($_.Exception.Message)" $true
    }
}

$voiceTree.Add_AfterSelect({ Show-VoiceTreeSelection })
$voiceActionsList.Add_SelectedIndexChanged({
    if (-not $script:voiceActionListPopulating -and
        $voiceActionsList.SelectedIndex -ge 0) {
        Show-VoiceActionFields `
            $script:voiceActionDrafts[$voiceActionsList.SelectedIndex]
    }
})
$voiceTypeCombo.Add_SelectedIndexChanged({
    if (-not $script:voiceTreePopulating) { Update-VoiceActionFields }
})
$voiceTargetCombo.Add_SelectedIndexChanged({
    if (-not $script:voiceTreePopulating -and
        [string]$voiceTypeCombo.SelectedItem -eq 'IR command') {
        Refresh-VoiceCommandChoices
    }
})
$voiceApplyButton.Add_Click({ [void](Apply-VoiceNodeEditor $true) })
$voiceAddActionButton.Add_Click({
    Invoke-VoiceEditorEvent { Add-VoiceActionDraft } 'add action'
})
$voiceUpdateActionButton.Add_Click({
    Invoke-VoiceEditorEvent { Set-VoiceSelectedActionDraft } 'update action'
})
$voiceRemoveActionButton.Add_Click({
    Invoke-VoiceEditorEvent { Remove-VoiceActionDraft } 'remove action'
})
$voiceAddButton.Add_Click({
    Invoke-VoiceEditorEvent { Add-VoiceChild } 'add'
})
$voiceDeleteButton.Add_Click({
    Invoke-VoiceEditorEvent { Remove-VoiceLevel } 'delete'
})
$voiceTestButton.Add_Click({ Test-VoiceAction })
$voiceSaveButton.Add_Click({ Save-VoiceEditor })
$voiceReloadButton.Add_Click({ Refresh-VoiceEditor })

$voiceHeader.PerformLayout()
