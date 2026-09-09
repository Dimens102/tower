# Tower IR command layout editor
# Restored from release v0.11.02 and loaded by Tower-Control.ps1 after the
# shared IR controls and renderers have been created.

if ($null -eq $config.PSObject.Properties['irCommandLayouts']) {
    $config | Add-Member -NotePropertyName irCommandLayouts -NotePropertyValue @()
}

$script:irLayoutEditMode = $false
$script:irLayoutDeviceId = ''
$script:irLayoutWorking = @{}
$script:irLayoutDraggedEntry = $null
$script:irLayoutSelectedEntry = $null
$script:irLayoutGroupCounts = @{}
$script:irLayoutScopeKey = 'Default'
$script:irLayoutSanitizingName = $false

function ConvertTo-IrSafeButtonLabel([string]$label) {
    if ([string]::IsNullOrWhiteSpace($label)) { return '' }

    # Button labels are display metadata, not filenames. Keep them predictable
    # and prevent punctuation/path characters from becoming part of a label.
    $clean = [regex]::Replace($label, '[^\p{L}\p{Nd} ]', ' ')
    $clean = [regex]::Replace($clean, '\s+', ' ').Trim()
    if ($clean.Length -gt 40) {
        $clean = $clean.Substring(0, 40).Trim()
    }
    return $clean
}

function Get-IrDefaultLayoutLabel([string]$label) {
    if ($label -ieq 'CBL-SAT' -or $label -ieq 'CBL/SAT') {
        return 'CBL SAT'
    }
    return $label
}

function Get-IrCommandCategory([string]$name) {
    if ($name -match 'Power|Standby|Sleep') { return 'Power' }
    if ($name -match 'Volume|Mute|Sub|Center|Surround|Effect') { return 'Audio' }
    if ($name -match 'InternetRadio|Source|Input|HDMI|MediaPlayer|Blu-ray|Game|Aux|TV Audio|CD|Tuner|USB|Phone|Bluetooth|HEOS|CBL[\s/-]*SAT|Aspect Ratio|Auto-Adjust|Blank Screen|Video Mode|Freeze|VGA|S-Video|Video ') { return 'Sources / Display' }
    if ($name -match 'Arrow|\bOK\b|Menu|Guide|Gids|Back|Info|Option|Setup|TV Quick|Radio') { return 'Navigation' }
    if ($name -match 'Play|Pause|Stop|Forward|Rewind|Record|Fast') { return 'Media' }
    if ($name -match '^[0-9]$|Channel') { return 'Numbers / Channels' }
    if ($name -match 'Red|Green|Blue|Yellow|White|Lime|Purple|Brightness|Mode|Timer|Temp|Speed|RGB|Strobe|Fade|Smooth') { return 'Modes / Colors' }
    return 'Other'
}

function Position-IrLayoutHeaderControls {
    if ($null -eq $script:irLayoutHeadingPanel) { return }

    $right = $script:irLayoutHeadingPanel.ClientSize.Width - 8
    $script:irLayoutEditButton.Location =
        New-Object System.Drawing.Point(($right - 92), 6)
    $script:irLayoutSaveButton.Location =
        New-Object System.Drawing.Point(($right - 92), 6)
    $script:irLayoutCancelButton.Location =
        New-Object System.Drawing.Point(($right - 170), 6)

    # Leave a hard boundary between the title and the buttons. This avoids the
    # old Dock=Fill label ever intercepting their painting or mouse clicks.
    $irHeading.Width = [Math]::Max(80, $right - 180)
    $irHeading.Height = 44

    $irHeading.SendToBack()
    $script:irLayoutEditButton.BringToFront()
    $script:irLayoutSaveButton.BringToFront()
    $script:irLayoutCancelButton.BringToFront()
}

function Initialize-IrLayoutEditorUi {
    $irHeaderLayout.SuspendLayout()

    $irHeaderLayout.Controls.Remove($irHeading)
    $irHeaderLayout.RowCount = 8
    $irHeaderLayout.RowStyles.Clear()
    foreach ($height in @(44, 0, 0, 0, 25, 23, 40, 24)) {
        [void]$irHeaderLayout.RowStyles.Add((
            New-Object System.Windows.Forms.RowStyle(
                [System.Windows.Forms.SizeType]::Absolute,
                $height
            )
        ))
    }

    $script:irLayoutHeadingPanel = New-Object System.Windows.Forms.Panel
    $script:irLayoutHeadingPanel.Dock = 'Fill'
    $irHeaderLayout.Controls.Add($script:irLayoutHeadingPanel, 0, 0)
    $irHeading.Dock = [System.Windows.Forms.DockStyle]::None
    $irHeading.Location = New-Object System.Drawing.Point(0, 0)
    $script:irLayoutHeadingPanel.Controls.Add($irHeading)

    $script:irLayoutEditButton = New-RfSmoothButton `
        'Edit Layout' 92 29 `
        ([System.Drawing.Color]::FromArgb(232, 239, 249)) `
        ([System.Drawing.Color]::FromArgb(30, 65, 105)) `
        ([System.Drawing.Color]::FromArgb(120, 155, 195))
    $script:irLayoutSaveButton = New-RfSmoothButton `
        'Save Layout' 92 29 `
        ([System.Drawing.Color]::FromArgb(224, 244, 228)) `
        ([System.Drawing.Color]::FromArgb(30, 80, 40)) `
        ([System.Drawing.Color]::FromArgb(130, 175, 135))
    $script:irLayoutCancelButton = New-RfSmoothButton `
        'Cancel' 72 29 `
        ([System.Drawing.Color]::White) `
        ([System.Drawing.Color]::FromArgb(50, 50, 50)) `
        ([System.Drawing.Color]::FromArgb(155, 155, 155))

    $script:irLayoutSaveButton.Visible = $false
    $script:irLayoutCancelButton.Visible = $false
    $script:irLayoutHeadingPanel.Controls.Add($script:irLayoutEditButton)
    $script:irLayoutHeadingPanel.Controls.Add($script:irLayoutSaveButton)
    $script:irLayoutHeadingPanel.Controls.Add($script:irLayoutCancelButton)

    # Explicit z-order keeps the layout controls above the remote heading.
    $irHeading.SendToBack()
    $script:irLayoutEditButton.BringToFront()
    $script:irLayoutSaveButton.BringToFront()
    $script:irLayoutCancelButton.BringToFront()

    $script:irLayoutHeadingPanel.Add_Resize({
        Position-IrLayoutHeaderControls
    })
    Position-IrLayoutHeaderControls

    $script:irLayoutColorPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $script:irLayoutColorPanel.Dock = 'Fill'
    $script:irLayoutColorPanel.WrapContents = $false
    $script:irLayoutColorPanel.Padding = New-Object System.Windows.Forms.Padding(10, 2, 0, 0)
    $script:irLayoutColorPanel.Visible = $false
    $irHeaderLayout.Controls.Add($script:irLayoutColorPanel, 0, 1)

    $colorLabel = New-Object System.Windows.Forms.Label
    $colorLabel.Text = 'Button color:'
    $colorLabel.AutoSize = $true
    $colorLabel.Margin = New-Object System.Windows.Forms.Padding(0, 5, 8, 0)
    [void]$script:irLayoutColorPanel.Controls.Add($colorLabel)

    $colorChoices = @(
        @{ Key='Auto'; Name='Auto / original'; Color=[System.Drawing.Color]::White },
        @{ Key='Red'; Name='Red'; Color=[System.Drawing.Color]::FromArgb(246,226,226) },
        @{ Key='Blue'; Name='Blue'; Color=[System.Drawing.Color]::FromArgb(229,238,250) },
        @{ Key='Green'; Name='Green'; Color=[System.Drawing.Color]::FromArgb(230,244,232) },
        @{ Key='Purple'; Name='Purple'; Color=[System.Drawing.Color]::FromArgb(238,233,246) },
        @{ Key='Gold'; Name='Gold'; Color=[System.Drawing.Color]::FromArgb(251,241,224) },
        @{ Key='Gray'; Name='Gray'; Color=[System.Drawing.Color]::FromArgb(242,242,242) }
    )
    foreach ($choice in $colorChoices) {
        $swatch = New-Object System.Windows.Forms.Button
        $swatch.Size = New-Object System.Drawing.Size(28, 24)
        $swatch.Margin = New-Object System.Windows.Forms.Padding(2, 1, 2, 0)
        $swatch.FlatStyle = 'Flat'
        $swatch.FlatAppearance.BorderSize = 1
        $swatch.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(150,150,150)
        $swatch.BackColor = $choice.Color
        $swatch.Text = if ($choice.Key -eq 'Auto') { 'A' } else { '' }
        $swatch.Tag = [string]$choice.Key
        $toolTip.SetToolTip($swatch, [string]$choice.Name)
        $swatch.Add_Click({ param($sender,$eventArgs) Set-IrSelectedLayoutColor ([string]$sender.Tag) })
        [void]$script:irLayoutColorPanel.Controls.Add($swatch)
    }

    $script:irLayoutSizePanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $script:irLayoutSizePanel.Dock = 'Fill'
    $script:irLayoutSizePanel.WrapContents = $false
    $script:irLayoutSizePanel.Padding = New-Object System.Windows.Forms.Padding(10, 2, 0, 0)
    $script:irLayoutSizePanel.Visible = $false
    $irHeaderLayout.Controls.Add($script:irLayoutSizePanel, 0, 2)

    $sizeLabel = New-Object System.Windows.Forms.Label
    $sizeLabel.Text = 'Button size:'
    $sizeLabel.AutoSize = $true
    $sizeLabel.Margin = New-Object System.Windows.Forms.Padding(0, 5, 8, 0)
    [void]$script:irLayoutSizePanel.Controls.Add($sizeLabel)
    foreach ($choice in @(
        @{ Key='Default'; Label='Default' }, @{ Key='1x1'; Label='1x1' },
        @{ Key='2x1'; Label='2x1' }, @{ Key='1x2'; Label='1x2' },
        @{ Key='2x2'; Label='2x2' }
    )) {
        $width = if ($choice.Key -eq 'Default') { 64 } else { 48 }
        $button = New-RfSmoothButton `
            ([string]$choice.Label) $width 24 `
            ([System.Drawing.Color]::FromArgb(244,244,244)) `
            ([System.Drawing.Color]::FromArgb(45,45,45)) `
            ([System.Drawing.Color]::FromArgb(155,155,155))
        $button.Margin = New-Object System.Windows.Forms.Padding(2,1,2,0)
        $button.Tag = [string]$choice.Key
        $button.Add_Click({ param($sender,$eventArgs) Set-IrSelectedLayoutSize ([string]$sender.Tag) })
        [void]$script:irLayoutSizePanel.Controls.Add($button)
    }

    $script:irLayoutNamePanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $script:irLayoutNamePanel.Dock = 'Fill'
    $script:irLayoutNamePanel.WrapContents = $false
    $script:irLayoutNamePanel.Padding = New-Object System.Windows.Forms.Padding(10, 2, 0, 0)
    $script:irLayoutNamePanel.Visible = $false
    $irHeaderLayout.Controls.Add($script:irLayoutNamePanel, 0, 3)

    $nameLabel = New-Object System.Windows.Forms.Label
    $nameLabel.Text = 'Button name:'
    $nameLabel.AutoSize = $true
    $nameLabel.Margin = New-Object System.Windows.Forms.Padding(0, 5, 8, 0)
    [void]$script:irLayoutNamePanel.Controls.Add($nameLabel)

    $script:irLayoutNameTextBox = New-Object System.Windows.Forms.TextBox
    $script:irLayoutNameTextBox.Width = 220
    $script:irLayoutNameTextBox.MaxLength = 40
    $script:irLayoutNameTextBox.Enabled = $false
    $script:irLayoutNameTextBox.Add_KeyPress({
        param($sender,$eventArgs)
        if (-not [char]::IsControl($eventArgs.KeyChar) -and
            -not [char]::IsLetterOrDigit($eventArgs.KeyChar) -and
            -not [char]::IsWhiteSpace($eventArgs.KeyChar)) {
            $eventArgs.Handled = $true
        }
    })
    [void]$script:irLayoutNamePanel.Controls.Add($script:irLayoutNameTextBox)
    $script:irLayoutNameTextBox.Add_TextChanged({
        if ($script:irLayoutSanitizingName) { return }
        $clean = ConvertTo-IrSafeButtonLabel ([string]$script:irLayoutNameTextBox.Text)
        if ($clean -ne [string]$script:irLayoutNameTextBox.Text) {
            $script:irLayoutSanitizingName = $true
            $script:irLayoutNameTextBox.Text = $clean
            $script:irLayoutNameTextBox.SelectionStart = $clean.Length
            $script:irLayoutSanitizingName = $false
        }
    })

    $script:irLayoutRenameButton = New-RfSmoothButton `
        ([string][char]0x270E + ' Apply name') 104 24 `
        ([System.Drawing.Color]::FromArgb(232,239,249)) `
        ([System.Drawing.Color]::FromArgb(30,65,105)) `
        ([System.Drawing.Color]::FromArgb(120,155,195))
    $script:irLayoutRenameButton.Enabled = $false
    $script:irLayoutRenameButton.Margin = New-Object System.Windows.Forms.Padding(6,0,0,0)
    [void]$script:irLayoutNamePanel.Controls.Add($script:irLayoutRenameButton)

    $irHeaderLayout.SetRow($irDetailLabel, 4)
    $irHeaderLayout.SetRow($irTxLabel, 5)
    $irHeaderLayout.SetRow($irTransmitterPanel, 6)
    $irHeaderLayout.SetRow($irTxHintLabel, 7)
    $irHeaderLayout.ResumeLayout()

    $script:irLayoutEditButton.Add_Click({ Start-IrCommandLayoutEdit })
    $script:irLayoutSaveButton.Add_Click({ Save-IrCommandLayoutEdit })
    $script:irLayoutCancelButton.Add_Click({ Cancel-IrCommandLayoutEdit })
    $script:irLayoutRenameButton.Add_Click({ Rename-IrSelectedLayoutButton })
    $script:irLayoutNameTextBox.Add_KeyDown({
        param($sender,$eventArgs)
        if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            Rename-IrSelectedLayoutButton
            $eventArgs.SuppressKeyPress = $true
        }
    })
}


function New-IrCommandButton(
    $device,
    $command,
    [string]$category,
    [string]$labelOverride = '') {

    $button = New-Object System.Windows.Forms.Button
    $displayText = if (-not [string]::IsNullOrWhiteSpace($labelOverride)) {
        $labelOverride
    }
    elseif ([string]::IsNullOrWhiteSpace([string]$command.name)) {
        [string]$command.id
    }
    else {
        [string]$command.name
    }

    $displayText = Get-IrDefaultLayoutLabel $displayText
    $button.Text = $displayText
    $button.Size = New-Object System.Drawing.Size(150, 44)
    $button.Margin = New-Object System.Windows.Forms.Padding(6)
    Set-IrButtonVisualStyle $button

    switch ($category) {
        'Power'       { $baseColor = [System.Drawing.Color]::FromArgb(246,226,226); $pressedColor = [System.Drawing.Color]::FromArgb(223,188,188) }
        'Navigation'  { $baseColor = [System.Drawing.Color]::FromArgb(229,238,250); $pressedColor = [System.Drawing.Color]::FromArgb(184,208,239) }
        'Audio'       { $baseColor = [System.Drawing.Color]::FromArgb(230,244,232); $pressedColor = [System.Drawing.Color]::FromArgb(188,224,194) }
        'Volume'      { $baseColor = [System.Drawing.Color]::FromArgb(230,244,232); $pressedColor = [System.Drawing.Color]::FromArgb(188,224,194) }
        'Media'       { $baseColor = [System.Drawing.Color]::FromArgb(238,233,246); $pressedColor = [System.Drawing.Color]::FromArgb(212,198,231) }
        'Input'       { $baseColor = [System.Drawing.Color]::FromArgb(251,241,224); $pressedColor = [System.Drawing.Color]::FromArgb(240,216,176) }
        'Controls'    { $baseColor = [System.Drawing.Color]::FromArgb(229,238,250); $pressedColor = [System.Drawing.Color]::FromArgb(184,208,239) }
        'Colors'      { $baseColor = [System.Drawing.Color]::FromArgb(235,241,250); $pressedColor = [System.Drawing.Color]::FromArgb(198,215,239) }
        'Modes'       { $baseColor = [System.Drawing.Color]::FromArgb(241,236,248); $pressedColor = [System.Drawing.Color]::FromArgb(223,208,242) }
        'Temperature' { $baseColor = [System.Drawing.Color]::FromArgb(230,244,232); $pressedColor = [System.Drawing.Color]::FromArgb(188,224,194) }
        'Timer'       { $baseColor = [System.Drawing.Color]::FromArgb(251,241,224); $pressedColor = [System.Drawing.Color]::FromArgb(240,216,176) }
        'Test'        { $baseColor = [System.Drawing.Color]::FromArgb(242,242,242); $pressedColor = [System.Drawing.Color]::FromArgb(219,219,219) }
        default       { $baseColor = Get-IrButtonBaseColor $category; $pressedColor = Get-IrButtonPressedColor $category }
    }

    $button.BackColor = $baseColor
    $button.Tag = [pscustomobject]@{
        BaseColor = $baseColor
        PressedColor = $pressedColor
        DefaultBaseColor = $baseColor
        DefaultPressedColor = $pressedColor
    }

    $button.Add_MouseDown({
        if ($this.Tag -and $this.Tag.PressedColor) {
            $this.BackColor = $this.Tag.PressedColor
        }
    })
    $button.Add_MouseUp({
        if ($this.Tag -and $this.Tag.BaseColor) {
            $this.BackColor = $this.Tag.BaseColor
        }
    })
    $button.Add_MouseLeave({
        if ($this.Tag -and $this.Tag.BaseColor) {
            $this.BackColor = $this.Tag.BaseColor
        }
    })

    $capturedDeviceId = [string]$device.id
    $capturedCommandId = [string]$command.id
    $capturedDeviceName = [string]$device.name
    $button.Add_Click({
        if ($script:irLayoutEditMode) { return }
        $currentLabel = $displayText
        if ($null -ne $this.Tag -and
            $null -ne $this.Tag.PSObject.Properties['LayoutEntry'] -and
            $null -ne $this.Tag.LayoutEntry -and
            -not [string]::IsNullOrWhiteSpace(
                [string]$this.Tag.LayoutEntry.Label
            )) {
            $currentLabel = [string]$this.Tag.LayoutEntry.Label
        }
        Send-IrCommand `
            $capturedDeviceId `
            $capturedCommandId `
            "$capturedDeviceName - $currentLabel"
    }.GetNewClosure())

    if (-not [string]::IsNullOrWhiteSpace([string]$command.description)) {
        $toolTip.SetToolTip($button, [string]$command.description)
    }

    return $button
}

function Get-IrLayoutGroupKey([string]$title) {
    $key = if ([string]::IsNullOrWhiteSpace($title)) {
        'Commands'
    }
    else {
        $title
    }

    if (-not $script:irLayoutGroupCounts.ContainsKey($key)) {
        $script:irLayoutGroupCounts[$key] = 0
    }

    $script:irLayoutGroupCounts[$key] =
        [int]$script:irLayoutGroupCounts[$key] + 1

    $count = [int]$script:irLayoutGroupCounts[$key]
    $instanceKey = if ($count -le 1) {
        $key
    }
    else {
        "$key#$count"
    }

    return ([string]$script:irLayoutScopeKey + '::' + $instanceKey)
}

function Get-IrLayoutEntryKey(
    [string]$groupKey,
    [string]$commandId) {

    return ($groupKey + '|' + $commandId)
}

function Get-IrSavedLayoutEntry(
    [string]$deviceId,
    [string]$groupKey,
    [string]$commandId) {

    foreach ($item in @($config.irCommandLayouts)) {
        if ([string]$item.deviceId -eq $deviceId -and
            [string]$item.groupKey -eq $groupKey -and
            [string]$item.commandId -eq $commandId) {
            return $item
        }
    }

    return $null
}

function Get-IrSavedLayoutEntryForCommand(
    [string]$deviceId,
    [string]$commandId) {

    $scopePrefix = [string]$script:irLayoutScopeKey + '::'

    foreach ($item in @($config.irCommandLayouts)) {
        if ([string]$item.deviceId -eq $deviceId -and
            [string]$item.commandId -eq $commandId -and
            ([string]$item.groupKey).StartsWith($scopePrefix)) {
            return $item
        }
    }

    return $null
}

function Get-IrLayoutColorPair([string]$colorKey) {
    switch ($colorKey) {
        'Red' {
            return [pscustomobject]@{
                Base = [System.Drawing.Color]::FromArgb(246, 226, 226)
                Pressed = [System.Drawing.Color]::FromArgb(223, 188, 188)
            }
        }
        'Blue' {
            return [pscustomobject]@{
                Base = [System.Drawing.Color]::FromArgb(229, 238, 250)
                Pressed = [System.Drawing.Color]::FromArgb(184, 208, 239)
            }
        }
        'Green' {
            return [pscustomobject]@{
                Base = [System.Drawing.Color]::FromArgb(230, 244, 232)
                Pressed = [System.Drawing.Color]::FromArgb(188, 224, 194)
            }
        }
        'Purple' {
            return [pscustomobject]@{
                Base = [System.Drawing.Color]::FromArgb(238, 233, 246)
                Pressed = [System.Drawing.Color]::FromArgb(212, 198, 231)
            }
        }
        'Gold' {
            return [pscustomobject]@{
                Base = [System.Drawing.Color]::FromArgb(251, 241, 224)
                Pressed = [System.Drawing.Color]::FromArgb(240, 216, 176)
            }
        }
        'Gray' {
            return [pscustomobject]@{
                Base = [System.Drawing.Color]::FromArgb(242, 242, 242)
                Pressed = [System.Drawing.Color]::FromArgb(219, 219, 219)
            }
        }
        default {
            return $null
        }
    }
}

function Apply-IrEntryColor($entry, [string]$colorKey) {
    if ($null -eq $entry -or $null -eq $entry.Button -or
        $null -eq $entry.Button.Tag) {
        return
    }

    $button = $entry.Button
    $pair = Get-IrLayoutColorPair $colorKey

    if ($null -eq $pair) {
        $button.Tag.BaseColor = $button.Tag.DefaultBaseColor
        $button.Tag.PressedColor = $button.Tag.DefaultPressedColor
        $entry.ColorKey = 'Auto'
    }
    else {
        $button.Tag.BaseColor = $pair.Base
        $button.Tag.PressedColor = $pair.Pressed
        $entry.ColorKey = $colorKey
    }

    $button.BackColor = $button.Tag.BaseColor
}

function Get-IrManagedGroupByKey([string]$groupKey) {
    foreach ($group in @($irCommandPanel.Controls)) {
        if ($group -is [System.Windows.Forms.GroupBox] -and
            $null -ne $group.Tag -and
            [string]$group.Tag.LayoutKind -eq 'ManagedGrid' -and
            [string]$group.Tag.GroupKey -eq $groupKey) {
            return $group
        }
    }

    return $null
}

function Apply-IrSavedGroupAssignmentsAndStyles {
    if ($null -eq $script:currentIrDevice) { return }

    $deviceId = [string]$script:currentIrDevice.id
    $groups = @(
        $irCommandPanel.Controls |
            Where-Object {
                $_ -is [System.Windows.Forms.GroupBox] -and
                $null -ne $_.Tag -and
                [string]$_.Tag.LayoutKind -eq 'ManagedGrid'
            }
    )

    # Start from the renderer defaults, then apply saved group, size, color and
    # display-name overrides. CommandId is never changed by the layout editor.
    foreach ($sourceGroup in $groups) {
        foreach ($entry in @($sourceGroup.Tag.Entries)) {
            $saved = Get-IrSavedLayoutEntryForCommand `
                $deviceId `
                ([string]$entry.CommandId)

            $label = Get-IrDefaultLayoutLabel ([string]$entry.DefaultLabel)
            if ($null -ne $saved -and
                $null -ne $saved.PSObject.Properties['label'] -and
                -not [string]::IsNullOrWhiteSpace([string]$saved.label)) {
                $savedLabel = ConvertTo-IrSafeButtonLabel ([string]$saved.label)
                if (-not [string]::IsNullOrWhiteSpace($savedLabel)) {
                    $label = $savedLabel
                }
            }
            $entry.Label = $label
            $entry.Button.Text = $label

            if ($null -eq $saved) {
                $entry.RowSpan = [int]$entry.DefaultRowSpan
                $entry.ColumnSpan = [int]$entry.DefaultColumnSpan
                Apply-IrEntryColor $entry 'Auto'
                continue
            }

            $targetKey = [string]$saved.groupKey
            if (-not [string]::IsNullOrWhiteSpace($targetKey) -and
                $targetKey -ne [string]$sourceGroup.Tag.GroupKey) {
                $targetGroup = Get-IrManagedGroupByKey $targetKey
                if ($null -ne $targetGroup) {
                    [void]$sourceGroup.Tag.Entries.Remove($entry)
                    [void]$targetGroup.Tag.Entries.Add($entry)
                    $entry.GroupKey = [string]$targetGroup.Tag.GroupKey
                }
            }

            $entry.RowSpan = if (
                $null -ne $saved.PSObject.Properties['rowSpan'] -and
                [int]$saved.rowSpan -gt 0
            ) {
                [int]$saved.rowSpan
            }
            else {
                [int]$entry.DefaultRowSpan
            }
            $entry.ColumnSpan = if (
                $null -ne $saved.PSObject.Properties['columnSpan'] -and
                [int]$saved.columnSpan -gt 0
            ) {
                [int]$saved.columnSpan
            }
            else {
                [int]$entry.DefaultColumnSpan
            }

            $colorKey = 'Auto'
            if ($null -ne $saved.PSObject.Properties['colorKey'] -and
                -not [string]::IsNullOrWhiteSpace([string]$saved.colorKey)) {
                $colorKey = [string]$saved.colorKey
            }
            Apply-IrEntryColor $entry $colorKey
        }
    }
}

function Test-IrGroupHasSavedLayout(
    [string]$deviceId,
    [string]$groupKey) {

    foreach ($item in @($config.irCommandLayouts)) {
        if ([string]$item.deviceId -eq $deviceId -and
            [string]$item.groupKey -eq $groupKey) {
            return $true
        }
    }

    return $false
}

function Get-IrLayoutAvailableWidth {
    # Keep command GroupBox borders on the same horizontal anchors as the IR
    # header controls. The FlowLayoutPanel contributes 7 px padding plus the
    # GroupBox contributes a 4 px margin, so each group begins 11 px from the
    # left. Reserve the same 11 px on the right: this keeps both outer margins
    # exactly equal and aligns the group border with the right edge of the
    # Edit/Save Layout toolbar.
    return [Math]::Max(
        360,
        [int]$irCommandPanel.ClientSize.Width - 22
    )
}

function Get-IrLayoutAvailableColumns($tag) {
    if ($null -eq $tag) { return 1 }

    $availableWidth = Get-IrLayoutAvailableWidth
    $innerWidth = [Math]::Max(162, $availableWidth - 22)
    $cellWidth = [Math]::Max(1, [int]$tag.CellWidth)

    return [Math]::Max(
        1,
        [int][Math]::Floor($innerWidth / [double]$cellWidth)
    )
}

function Test-IrLayoutRegionFree(
    $occupancy,
    [int]$row,
    [int]$column,
    [int]$rowSpan,
    [int]$columnSpan,
    [int]$columnLimit) {

    if ($row -lt 0 -or $column -lt 0) { return $false }
    if (($column + $columnSpan) -gt $columnLimit) { return $false }

    for ($r = $row; $r -lt ($row + $rowSpan); $r++) {
        for ($c = $column; $c -lt ($column + $columnSpan); $c++) {
            if ($occupancy.ContainsKey("$r,$c")) {
                return $false
            }
        }
    }

    return $true
}

function Add-IrLayoutRegion(
    $occupancy,
    [int]$row,
    [int]$column,
    [int]$rowSpan,
    [int]$columnSpan,
    $value) {

    for ($r = $row; $r -lt ($row + $rowSpan); $r++) {
        for ($c = $column; $c -lt ($column + $columnSpan); $c++) {
            $occupancy["$r,$c"] = $value
        }
    }
}

function Get-IrFirstFreeLayoutPosition(
    $occupancy,
    [int]$rowSpan,
    [int]$columnSpan,
    [int]$columnLimit) {

    for ($row = 0; $row -lt 1000; $row++) {
        for ($column = 0; $column -lt $columnLimit; $column++) {
            if (Test-IrLayoutRegionFree `
                    $occupancy `
                    $row `
                    $column `
                    $rowSpan `
                    $columnSpan `
                    $columnLimit) {
                return [pscustomobject]@{
                    Row = $row
                    Column = $column
                }
            }
        }
    }

    return [pscustomobject]@{
        Row = 0
        Column = 0
    }
}

function Set-IrLayoutGridDimensions(
    $grid,
    [int]$columns,
    [int]$rows,
    [int]$cellWidth,
    [int]$cellHeight) {

    $columns = [Math]::Max(1, $columns)
    $rows = [Math]::Max(1, $rows)

    $grid.ColumnStyles.Clear()
    $grid.RowStyles.Clear()
    $grid.ColumnCount = $columns
    $grid.RowCount = $rows

    for ($c = 0; $c -lt $columns; $c++) {
        $style = New-Object System.Windows.Forms.ColumnStyle
        $style.SizeType = [System.Windows.Forms.SizeType]::Absolute
        $style.Width = $cellWidth
        [void]$grid.ColumnStyles.Add($style)
    }

    for ($r = 0; $r -lt $rows; $r++) {
        $style = New-Object System.Windows.Forms.RowStyle
        $style.SizeType = [System.Windows.Forms.SizeType]::Absolute
        $style.Height = $cellHeight
        [void]$grid.RowStyles.Add($style)
    }
}

function Get-IrEntryConfiguredPosition($groupTag, $entry) {
    $deviceId = [string]$groupTag.DeviceId
    $groupKey = [string]$groupTag.GroupKey
    $commandId = [string]$entry.CommandId

    if ($script:irLayoutEditMode -and
        [string]$script:irLayoutDeviceId -eq $deviceId -and
        $script:irLayoutWorking.ContainsKey($commandId)) {
        $working = $script:irLayoutWorking[$commandId]
        if ([string]$working.GroupKey -eq $groupKey) {
            return [pscustomobject]@{
                Row = [int]$working.Row
                Column = [int]$working.Column
            }
        }
    }

    $saved = Get-IrSavedLayoutEntry $deviceId $groupKey $commandId
    if ($null -ne $saved) {
        return [pscustomobject]@{
            Row = [int]$saved.row
            Column = [int]$saved.column
        }
    }

    return $null
}

function Apply-IrManagedGroupLayout($group) {
    if ($null -eq $group -or $null -eq $group.Tag) { return }

    $tag = $group.Tag
    if ([string]$tag.LayoutKind -ne 'ManagedGrid') { return }

    $grid = $tag.Layout
    $entries = @($tag.Entries)

    $deviceId = [string]$tag.DeviceId
    $groupKey = [string]$tag.GroupKey
    $availableColumns = Get-IrLayoutAvailableColumns $tag
    $availableWidth = Get-IrLayoutAvailableWidth
    $hasSaved = Test-IrGroupHasSavedLayout $deviceId $groupKey
    $isEditing =
        $script:irLayoutEditMode -and
        [string]$script:irLayoutDeviceId -eq $deviceId

    if ($entries.Count -eq 0) {
        if (-not $isEditing) {
            $group.Visible = $false
            return
        }

        $group.Visible = $true
        $group.Width = $availableWidth
        $grid.SuspendLayout()
        $grid.Controls.Clear()
        Set-IrLayoutGridDimensions `
            $grid `
            $availableColumns `
            2 `
            ([int]$tag.CellWidth) `
            ([int]$tag.CellHeight)
        $grid.CellBorderStyle =
            [System.Windows.Forms.TableLayoutPanelCellBorderStyle]::None
        $grid.Width = [Math]::Max(
            [int]$tag.CellWidth,
            ($availableColumns * [int]$tag.CellWidth)
        )
        # Keep a fixed-width command grid visually centred inside the wider
        # group. This is especially noticeable for one-row remotes/categories.
        $grid.Left = [Math]::Max(
            8,
            [int][Math]::Floor(
                ($group.ClientSize.Width - $grid.Width) / 2.0
            )
        )
        $grid.Height = 2 * [int]$tag.CellHeight
        $group.Height = $grid.Height + 36
        $grid.ResumeLayout()
        $grid.Invalidate()
        return
    }

    $group.Visible = $true

    $useManagedWidth =
        [string]$tag.LayoutMode -eq 'Flow' -or
        $hasSaved -or
        $isEditing

    if (-not $useManagedWidth) {
        $columns = [Math]::Max(1, [int]$tag.BaseColumns)
        $rows = [Math]::Max(1, [int]$tag.BaseRows)

        $grid.SuspendLayout()
        $grid.Controls.Clear()
        Set-IrLayoutGridDimensions `
            $grid `
            $columns `
            $rows `
            ([int]$tag.CellWidth) `
            ([int]$tag.CellHeight)

        foreach ($entry in $entries) {
            $entry.LogicalRow = [int]$entry.DefaultRow
            $entry.LogicalColumn = [int]$entry.DefaultColumn
            $entry.DisplayRow = [int]$entry.DefaultRow
            $entry.DisplayColumn = [int]$entry.DefaultColumn

            $grid.Controls.Add(
                $entry.Button,
                [int]$entry.DefaultColumn,
                [int]$entry.DefaultRow
            )
            # TableLayoutPanel stores span values on the control itself. Always
            # write both values, including 1, so a previously enlarged button can
            # shrink back to 1x1/2x1/1x2 without retaining an old span.
            $grid.SetRowSpan(
                $entry.Button,
                [Math]::Max(1, [int]$entry.RowSpan)
            )
            $grid.SetColumnSpan(
                $entry.Button,
                [Math]::Max(1, [int]$entry.ColumnSpan)
            )

            $entry.Button.Cursor = [System.Windows.Forms.Cursors]::Default
        }

        $grid.CellBorderStyle =
            [System.Windows.Forms.TableLayoutPanelCellBorderStyle]::None
        $grid.Size = New-Object System.Drawing.Size(
            ($columns * [int]$tag.CellWidth),
            ($rows * [int]$tag.CellHeight)
        )
        $group.Size = New-Object System.Drawing.Size(
            ($grid.Width + 18),
            ($grid.Height + 36)
        )
        $grid.ResumeLayout()
        return
    }

    $group.Width = $availableWidth
    # Keep every command column exactly CellWidth wide. TableLayoutPanel will
    # otherwise assign any leftover client width to its last column even when
    # the ColumnStyles are Absolute, making the right-most buttons wider.
    $grid.Width = [Math]::Max(
        [int]$tag.CellWidth,
        ($availableColumns * [int]$tag.CellWidth)
    )
    # Fixed-size columns can leave spare pixels in the group when another full
    # column will not fit. Split that spare width evenly on both sides instead
    # of leaving the command rows visually anchored to the left.
    $grid.Left = [Math]::Max(
        8,
        [int][Math]::Floor(
            ($group.ClientSize.Width - $grid.Width) / 2.0
        )
    )

    # Build logical positions first. Saved/edit coordinates win. Commands that
    # do not yet have a saved slot use their renderer default when possible,
    # otherwise the next free logical cell.
    $logicalOccupancy = @{}
    $positioned = New-Object System.Collections.ArrayList
    $unpositioned = New-Object System.Collections.ArrayList

    foreach ($entry in $entries) {
        $position = Get-IrEntryConfiguredPosition $tag $entry
        if ($null -ne $position) {
            $entry.LogicalRow = [int]$position.Row
            $entry.LogicalColumn = [int]$position.Column
            [void]$positioned.Add($entry)
        }
        else {
            [void]$unpositioned.Add($entry)
        }
    }

    $logicalColumnLimit = [Math]::Max(
        $availableColumns,
        [Math]::Max(1, [int]$tag.BaseColumns)
    )

    foreach ($entry in $positioned) {
        $logicalColumnLimit = [Math]::Max(
            $logicalColumnLimit,
            ([int]$entry.LogicalColumn + [int]$entry.ColumnSpan)
        )
    }

    foreach ($entry in @($positioned | Sort-Object LogicalRow, LogicalColumn, DefaultIndex)) {
        if (Test-IrLayoutRegionFree `
                $logicalOccupancy `
                ([int]$entry.LogicalRow) `
                ([int]$entry.LogicalColumn) `
                ([int]$entry.RowSpan) `
                ([int]$entry.ColumnSpan) `
                $logicalColumnLimit) {
            Add-IrLayoutRegion `
                $logicalOccupancy `
                ([int]$entry.LogicalRow) `
                ([int]$entry.LogicalColumn) `
                ([int]$entry.RowSpan) `
                ([int]$entry.ColumnSpan) `
                $entry
        }
        else {
            [void]$unpositioned.Add($entry)
        }
    }

    $defaultIndex = 0
    foreach ($entry in @($unpositioned | Sort-Object DefaultIndex)) {
        $preferred = $null

        if ([string]$tag.LayoutMode -eq 'Fixed') {
            if (Test-IrLayoutRegionFree `
                    $logicalOccupancy `
                    ([int]$entry.DefaultRow) `
                    ([int]$entry.DefaultColumn) `
                    ([int]$entry.RowSpan) `
                    ([int]$entry.ColumnSpan) `
                    $logicalColumnLimit) {
                $preferred = [pscustomobject]@{
                    Row = [int]$entry.DefaultRow
                    Column = [int]$entry.DefaultColumn
                }
            }
        }
        elseif (-not $hasSaved -and -not $isEditing) {
            $candidateRow =
                [int][Math]::Floor($defaultIndex / [double]$availableColumns)
            $candidateColumn = $defaultIndex % $availableColumns
            if (Test-IrLayoutRegionFree `
                    $logicalOccupancy `
                    $candidateRow `
                    $candidateColumn `
                    ([int]$entry.RowSpan) `
                    ([int]$entry.ColumnSpan) `
                    $logicalColumnLimit) {
                $preferred = [pscustomobject]@{
                    Row = $candidateRow
                    Column = $candidateColumn
                }
            }
            $defaultIndex++
        }

        if ($null -eq $preferred) {
            $preferred = Get-IrFirstFreeLayoutPosition `
                $logicalOccupancy `
                ([int]$entry.RowSpan) `
                ([int]$entry.ColumnSpan) `
                $logicalColumnLimit
        }

        $entry.LogicalRow = [int]$preferred.Row
        $entry.LogicalColumn = [int]$preferred.Column
        Add-IrLayoutRegion `
            $logicalOccupancy `
            ([int]$entry.LogicalRow) `
            ([int]$entry.LogicalColumn) `
            ([int]$entry.RowSpan) `
            ([int]$entry.ColumnSpan) `
            $entry
    }

    # If the sidebar becomes too narrow for the saved columns, compact only the
    # display. Logical positions remain untouched and return when width allows.
    $displayFits = $true
    $displayOccupancy = @{}
    foreach ($entry in @($entries | Sort-Object LogicalRow, LogicalColumn, DefaultIndex)) {
        if (-not (Test-IrLayoutRegionFree `
                $displayOccupancy `
                ([int]$entry.LogicalRow) `
                ([int]$entry.LogicalColumn) `
                ([int]$entry.RowSpan) `
                ([int]$entry.ColumnSpan) `
                $availableColumns)) {
            $displayFits = $false
            break
        }

        Add-IrLayoutRegion `
            $displayOccupancy `
            ([int]$entry.LogicalRow) `
            ([int]$entry.LogicalColumn) `
            ([int]$entry.RowSpan) `
            ([int]$entry.ColumnSpan) `
            $entry
    }

    if ($displayFits) {
        foreach ($entry in $entries) {
            $entry.DisplayRow = [int]$entry.LogicalRow
            $entry.DisplayColumn = [int]$entry.LogicalColumn
        }
    }
    else {
        $displayOccupancy = @{}
        foreach ($entry in @($entries | Sort-Object LogicalRow, LogicalColumn, DefaultIndex)) {
            $position = Get-IrFirstFreeLayoutPosition `
                $displayOccupancy `
                ([int]$entry.RowSpan) `
                ([int]$entry.ColumnSpan) `
                $availableColumns

            $entry.DisplayRow = [int]$position.Row
            $entry.DisplayColumn = [int]$position.Column
            Add-IrLayoutRegion `
                $displayOccupancy `
                ([int]$entry.DisplayRow) `
                ([int]$entry.DisplayColumn) `
                ([int]$entry.RowSpan) `
                ([int]$entry.ColumnSpan) `
                $entry
        }
    }

    $maxRow = 0
    foreach ($entry in $entries) {
        $maxRow = [Math]::Max(
            $maxRow,
            ([int]$entry.DisplayRow + [int]$entry.RowSpan)
        )
    }
    $rowCount = [Math]::Max(1, $maxRow)
    if ($isEditing) {
        # One empty row is deliberately kept visible so a button can be dragged
        # down into a new row without first changing anything else.
        $rowCount++
    }

    $grid.SuspendLayout()
    $grid.Controls.Clear()
    Set-IrLayoutGridDimensions `
        $grid `
        $availableColumns `
        $rowCount `
        ([int]$tag.CellWidth) `
        ([int]$tag.CellHeight)

    foreach ($entry in $entries) {
        $grid.Controls.Add(
            $entry.Button,
            [int]$entry.DisplayColumn,
            [int]$entry.DisplayRow
        )
        # Explicitly reset spans to 1 as well as applying larger values. WinForms
        # otherwise retains the previous TableLayoutPanel span on this control.
        $grid.SetRowSpan(
            $entry.Button,
            [Math]::Max(1, [int]$entry.RowSpan)
        )
        $grid.SetColumnSpan(
            $entry.Button,
            [Math]::Max(1, [int]$entry.ColumnSpan)
        )

        $entry.Button.Cursor = if ($isEditing) {
            [System.Windows.Forms.Cursors]::SizeAll
        }
        else {
            [System.Windows.Forms.Cursors]::Default
        }
    }

    # Edit-mode guides are painted manually so only the internal row/column
    # separators are visible. The GroupBox remains the only outer border.
    $grid.CellBorderStyle =
        [System.Windows.Forms.TableLayoutPanelCellBorderStyle]::None

    $grid.Height = $rowCount * [int]$tag.CellHeight
    $group.Height = $grid.Height + 36
    $grid.ResumeLayout()
    $grid.Invalidate()
}

function Test-IrWorkingGroupLayoutValid($group) {
    if ($null -eq $group -or $null -eq $group.Tag) { return $false }

    $tag = $group.Tag
    $columns = Get-IrLayoutAvailableColumns $tag
    $occupancy = @{}

    foreach ($entry in @($tag.Entries)) {
        $commandId = [string]$entry.CommandId

        if (-not $script:irLayoutWorking.ContainsKey($commandId)) {
            return $false
        }

        $position = $script:irLayoutWorking[$commandId]
        if ([string]$position.GroupKey -ne [string]$tag.GroupKey) {
            return $false
        }

        $rowSpan = if ($null -ne $position.PSObject.Properties['RowSpan']) {
            [Math]::Max(1, [int]$position.RowSpan)
        }
        else {
            [Math]::Max(1, [int]$entry.RowSpan)
        }
        $columnSpan = if ($null -ne $position.PSObject.Properties['ColumnSpan']) {
            [Math]::Max(1, [int]$position.ColumnSpan)
        }
        else {
            [Math]::Max(1, [int]$entry.ColumnSpan)
        }

        if (-not (Test-IrLayoutRegionFree `
                $occupancy `
                ([int]$position.Row) `
                ([int]$position.Column) `
                $rowSpan `
                $columnSpan `
                $columns)) {
            return $false
        }

        Add-IrLayoutRegion `
            $occupancy `
            ([int]$position.Row) `
            ([int]$position.Column) `
            $rowSpan `
            $columnSpan `
            $entry
    }

    return $true
}

function Register-IrLayoutGridHandlers($group, $grid) {
    $grid.AllowDrop = $true
    $grid.Tag = $group

    $grid.Add_Paint({
        param($sender, $eventArgs)

        $targetGroup = $sender.Tag
        if (-not $script:irLayoutEditMode -or
            $null -eq $targetGroup -or
            $null -eq $targetGroup.Tag -or
            [string]$script:irLayoutDeviceId -ne
                [string]$targetGroup.Tag.DeviceId) {
            return
        }

        $tag = $targetGroup.Tag
        $pen = New-Object System.Drawing.Pen(
            [System.Drawing.Color]::FromArgb(185, 185, 185)
        )

        try {
            $cellWidth = [Math]::Max(1, [int]$tag.CellWidth)
            $cellHeight = [Math]::Max(1, [int]$tag.CellHeight)

            for ($x = $cellWidth; $x -lt $sender.ClientSize.Width; $x += $cellWidth) {
                $eventArgs.Graphics.DrawLine(
                    $pen,
                    $x,
                    0,
                    $x,
                    $sender.ClientSize.Height
                )
            }

            for ($y = $cellHeight; $y -lt $sender.ClientSize.Height; $y += $cellHeight) {
                $eventArgs.Graphics.DrawLine(
                    $pen,
                    0,
                    $y,
                    $sender.ClientSize.Width,
                    $y
                )
            }
        }
        finally {
            $pen.Dispose()
        }
    })

    $grid.Add_DragEnter({
        param($sender, $eventArgs)

        if ($script:irLayoutEditMode -and
            $null -ne $script:irLayoutDraggedEntry) {
            $eventArgs.Effect =
                [System.Windows.Forms.DragDropEffects]::Move
        }
        else {
            $eventArgs.Effect =
                [System.Windows.Forms.DragDropEffects]::None
        }
    })

    $grid.Add_DragOver({
        param($sender, $eventArgs)

        $targetGroup = $sender.Tag
        $entry = $script:irLayoutDraggedEntry

        if (-not $script:irLayoutEditMode -or
            $null -eq $targetGroup -or
            $null -eq $entry -or
            [string]$targetGroup.Tag.DeviceId -ne
                [string]$script:irLayoutDeviceId) {
            $eventArgs.Effect =
                [System.Windows.Forms.DragDropEffects]::None
            return
        }

        $eventArgs.Effect =
            [System.Windows.Forms.DragDropEffects]::Move
    })

    $grid.Add_DragDrop({
        param($sender, $eventArgs)

        $targetGroup = $sender.Tag
        $entry = $script:irLayoutDraggedEntry
        $script:irLayoutDraggedEntry = $null

        if (-not $script:irLayoutEditMode -or
            $null -eq $targetGroup -or
            $null -eq $entry -or
            [string]$targetGroup.Tag.DeviceId -ne
                [string]$script:irLayoutDeviceId) {
            return
        }

        $tag = $targetGroup.Tag
        $point = $sender.PointToClient(
            (New-Object System.Drawing.Point(
                [int]$eventArgs.X,
                [int]$eventArgs.Y
            ))
        )

        $column = [int][Math]::Floor(
            $point.X / [double][Math]::Max(1, [int]$tag.CellWidth)
        )
        $row = [int][Math]::Floor(
            $point.Y / [double][Math]::Max(1, [int]$tag.CellHeight)
        )
        $columns = Get-IrLayoutAvailableColumns $tag

        if ($row -lt 0 -or
            $column -lt 0 -or
            ($column + [int]$entry.ColumnSpan) -gt $columns) {
            return
        }

        $commandId = [string]$entry.CommandId
        if (-not $script:irLayoutWorking.ContainsKey($commandId)) {
            return
        }

        $sourceOld = $script:irLayoutWorking[$commandId]
        $sourceGroup =
            Get-IrManagedGroupByKey ([string]$sourceOld.GroupKey)

        if ($null -eq $sourceGroup) {
            return
        }

        $sameGroup =
            [string]$sourceGroup.Tag.GroupKey -eq
            [string]$targetGroup.Tag.GroupKey

        $occupant = $null
        foreach ($candidate in @($targetGroup.Tag.Entries)) {
            if ([string]$candidate.CommandId -eq $commandId) {
                continue
            }

            $candidateId = [string]$candidate.CommandId
            if (-not $script:irLayoutWorking.ContainsKey($candidateId)) {
                continue
            }

            $candidatePosition =
                $script:irLayoutWorking[$candidateId]

            $candidateRowSpan = if (
                $null -ne $candidatePosition.PSObject.Properties['RowSpan']
            ) {
                [Math]::Max(1, [int]$candidatePosition.RowSpan)
            }
            else {
                [Math]::Max(1, [int]$candidate.RowSpan)
            }
            $candidateColumnSpan = if (
                $null -ne $candidatePosition.PSObject.Properties['ColumnSpan']
            ) {
                [Math]::Max(1, [int]$candidatePosition.ColumnSpan)
            }
            else {
                [Math]::Max(1, [int]$candidate.ColumnSpan)
            }

            if ($row -ge [int]$candidatePosition.Row -and
                $row -lt ([int]$candidatePosition.Row + $candidateRowSpan) -and
                $column -ge [int]$candidatePosition.Column -and
                $column -lt ([int]$candidatePosition.Column + $candidateColumnSpan)) {
                $occupant = $candidate
                break
            }
        }

        $occupantOld = $null
        if ($null -ne $occupant) {
            $occupantOld =
                $script:irLayoutWorking[[string]$occupant.CommandId]
        }

        # Move the source entry into the target group when crossing a GroupBox.
        # An occupied target swaps back into the source group/slot, which keeps
        # the drag behavior useful without silently deleting a command.
        if (-not $sameGroup) {
            [void]$sourceGroup.Tag.Entries.Remove($entry)
            [void]$targetGroup.Tag.Entries.Add($entry)
            $entry.GroupKey = [string]$targetGroup.Tag.GroupKey

            if ($null -ne $occupant) {
                [void]$targetGroup.Tag.Entries.Remove($occupant)
                [void]$sourceGroup.Tag.Entries.Add($occupant)
                $occupant.GroupKey =
                    [string]$sourceGroup.Tag.GroupKey
            }
        }

        $script:irLayoutWorking[$commandId] = [pscustomobject]@{
            GroupKey = [string]$targetGroup.Tag.GroupKey
            Row = $row
            Column = $column
            ColorKey = [string]$sourceOld.ColorKey
            Label = [string]$sourceOld.Label
            RowSpan = [Math]::Max(1, [int]$sourceOld.RowSpan)
            ColumnSpan = [Math]::Max(1, [int]$sourceOld.ColumnSpan)
        }

        if ($null -ne $occupant) {
            $script:irLayoutWorking[[string]$occupant.CommandId] =
                [pscustomobject]@{
                    GroupKey = if ($sameGroup) {
                        [string]$targetGroup.Tag.GroupKey
                    }
                    else {
                        [string]$sourceGroup.Tag.GroupKey
                    }
                    Row = [int]$sourceOld.Row
                    Column = [int]$sourceOld.Column
                    ColorKey = [string]$occupantOld.ColorKey
                    Label = [string]$occupantOld.Label
                    RowSpan = [Math]::Max(1, [int]$occupantOld.RowSpan)
                    ColumnSpan = [Math]::Max(1, [int]$occupantOld.ColumnSpan)
                }
        }

        $valid =
            (Test-IrWorkingGroupLayoutValid $targetGroup) -and
            (Test-IrWorkingGroupLayoutValid $sourceGroup)

        if (-not $valid) {
            $script:irLayoutWorking[$commandId] = $sourceOld
            if ($null -ne $occupant) {
                $script:irLayoutWorking[[string]$occupant.CommandId] =
                    $occupantOld
            }

            if (-not $sameGroup) {
                [void]$targetGroup.Tag.Entries.Remove($entry)
                [void]$sourceGroup.Tag.Entries.Add($entry)
                $entry.GroupKey = [string]$sourceGroup.Tag.GroupKey

                if ($null -ne $occupant) {
                    [void]$sourceGroup.Tag.Entries.Remove($occupant)
                    [void]$targetGroup.Tag.Entries.Add($occupant)
                    $occupant.GroupKey =
                        [string]$targetGroup.Tag.GroupKey
                }
            }

            Set-TowerStatus 'That grid position cannot fit this button.'
            Apply-IrManagedGroupLayout $sourceGroup
            if (-not $sameGroup) {
                Apply-IrManagedGroupLayout $targetGroup
            }
            return
        }

        Apply-IrManagedGroupLayout $sourceGroup
        if (-not $sameGroup) {
            Apply-IrManagedGroupLayout $targetGroup
        }

        Update-IrLayoutSelectionVisuals
        Set-TowerStatus 'Layout changed - click Save Layout to keep it.'
    })
}

function Update-IrLayoutSelectionVisuals {
    $selectedEntry = $null

    foreach ($group in @($irCommandPanel.Controls)) {
        if ($group -isnot [System.Windows.Forms.GroupBox] -or
            $null -eq $group.Tag -or
            [string]$group.Tag.LayoutKind -ne 'ManagedGrid') {
            continue
        }

        foreach ($entry in @($group.Tag.Entries)) {
            if ($null -eq $entry.Button) { continue }

            $selected =
                $script:irLayoutEditMode -and
                $null -ne $script:irLayoutSelectedEntry -and
                [string]$entry.CommandId -eq
                    [string]$script:irLayoutSelectedEntry.CommandId

            $entry.Button.FlatAppearance.BorderSize =
                if ($selected) { 2 } else { 1 }
            $entry.Button.FlatAppearance.BorderColor =
                if ($selected) {
                    [System.Drawing.Color]::FromArgb(70, 90, 115)
                }
                else {
                    [System.Drawing.Color]::FromArgb(150, 150, 150)
                }

            $label = if ([string]::IsNullOrWhiteSpace([string]$entry.Label)) {
                Get-IrDefaultLayoutLabel ([string]$entry.DefaultLabel)
            }
            else {
                [string]$entry.Label
            }
            $entry.Button.Text = if ($script:irLayoutEditMode) {
                ([string][char]0x270E + ' ' + $label)
            }
            else {
                $label
            }

            if ($selected) { $selectedEntry = $entry }
        }
    }

    $hasSelection = $script:irLayoutEditMode -and $null -ne $selectedEntry
    $script:irLayoutNameTextBox.Enabled = $hasSelection
    $script:irLayoutRenameButton.Enabled = $hasSelection
    if ($hasSelection) {
        $script:irLayoutNameTextBox.Text = [string]$selectedEntry.Label
        $script:irLayoutNameTextBox.SelectAll()
    }
    else {
        $script:irLayoutNameTextBox.Text = ''
    }
}

function Rename-IrSelectedLayoutButton {
    if (-not $script:irLayoutEditMode -or
        $null -eq $script:irLayoutSelectedEntry) {
        Set-TowerStatus 'Select a command button first, then enter its new name.'
        return
    }

    $entry = $script:irLayoutSelectedEntry
    $commandId = [string]$entry.CommandId
    if (-not $script:irLayoutWorking.ContainsKey($commandId)) { return }

    $requested = [string]$script:irLayoutNameTextBox.Text
    $label = ConvertTo-IrSafeButtonLabel $requested
    if ([string]::IsNullOrWhiteSpace($label)) {
        Set-TowerStatus 'Button names must contain at least one letter or number.'
        $script:irLayoutNameTextBox.Focus()
        return
    }

    $current = $script:irLayoutWorking[$commandId]
    $script:irLayoutWorking[$commandId] = [pscustomobject]@{
        GroupKey = [string]$current.GroupKey
        Row = [int]$current.Row
        Column = [int]$current.Column
        ColorKey = [string]$current.ColorKey
        Label = $label
        RowSpan = [Math]::Max(1, [int]$current.RowSpan)
        ColumnSpan = [Math]::Max(1, [int]$current.ColumnSpan)
    }
    $entry.Label = $label
    Update-IrLayoutSelectionVisuals
    Set-TowerStatus "Button renamed to '$label' - click Save Layout to keep it."
}

function Select-IrLayoutEntry($entry) {
    if (-not $script:irLayoutEditMode -or $null -eq $entry) {
        return
    }

    $script:irLayoutSelectedEntry = $entry
    Update-IrLayoutSelectionVisuals
}

function Set-IrSelectedLayoutColor([string]$colorKey) {
    if (-not $script:irLayoutEditMode -or
        $null -eq $script:irLayoutSelectedEntry) {
        Set-TowerStatus 'Select a command button first, then choose its color.'
        return
    }

    $entry = $script:irLayoutSelectedEntry
    $commandId = [string]$entry.CommandId

    if (-not $script:irLayoutWorking.ContainsKey($commandId)) {
        return
    }

    $current = $script:irLayoutWorking[$commandId]
    $script:irLayoutWorking[$commandId] = [pscustomobject]@{
        GroupKey = [string]$current.GroupKey
        Row = [int]$current.Row
        Column = [int]$current.Column
        ColorKey = if ($colorKey -in @(
            'Red', 'Blue', 'Green', 'Purple', 'Gold', 'Gray'
        )) {
            $colorKey
        }
        else {
            'Auto'
        }
        Label = [string]$current.Label
        RowSpan = [Math]::Max(1, [int]$current.RowSpan)
        ColumnSpan = [Math]::Max(1, [int]$current.ColumnSpan)
    }

    Apply-IrEntryColor `
        $entry `
        ([string]$script:irLayoutWorking[$commandId].ColorKey)
    Update-IrLayoutSelectionVisuals
    Set-TowerStatus 'Button color changed - click Save Layout to keep it.'
}

function Set-IrSelectedLayoutSize([string]$sizeKey) {
    if (-not $script:irLayoutEditMode -or
        $null -eq $script:irLayoutSelectedEntry) {
        Set-TowerStatus 'Select a command button first, then choose its size.'
        return
    }

    $entry = $script:irLayoutSelectedEntry
    $commandId = [string]$entry.CommandId
    if (-not $script:irLayoutWorking.ContainsKey($commandId)) { return }

    $current = $script:irLayoutWorking[$commandId]
    $group = Get-IrManagedGroupByKey ([string]$current.GroupKey)
    if ($null -eq $group) { return }

    $rowSpan = 1
    $columnSpan = 1
    switch ($sizeKey) {
        'Default' {
            $rowSpan = [Math]::Max(1, [int]$entry.DefaultRowSpan)
            $columnSpan = [Math]::Max(1, [int]$entry.DefaultColumnSpan)
        }
        '2x1' { $rowSpan = 1; $columnSpan = 2 }
        '1x2' { $rowSpan = 2; $columnSpan = 1 }
        '2x2' { $rowSpan = 2; $columnSpan = 2 }
        default { $rowSpan = 1; $columnSpan = 1 }
    }

    $columns = Get-IrLayoutAvailableColumns $group.Tag
    $occupancy = @{}
    foreach ($candidate in @($group.Tag.Entries)) {
        $candidateId = [string]$candidate.CommandId
        if ($candidateId -eq $commandId -or
            -not $script:irLayoutWorking.ContainsKey($candidateId)) {
            continue
        }

        $candidatePosition = $script:irLayoutWorking[$candidateId]
        $candidateRowSpan = if (
            $null -ne $candidatePosition.PSObject.Properties['RowSpan']
        ) {
            [Math]::Max(1, [int]$candidatePosition.RowSpan)
        }
        else {
            [Math]::Max(1, [int]$candidate.RowSpan)
        }
        $candidateColumnSpan = if (
            $null -ne $candidatePosition.PSObject.Properties['ColumnSpan']
        ) {
            [Math]::Max(1, [int]$candidatePosition.ColumnSpan)
        }
        else {
            [Math]::Max(1, [int]$candidate.ColumnSpan)
        }

        Add-IrLayoutRegion `
            $occupancy `
            ([int]$candidatePosition.Row) `
            ([int]$candidatePosition.Column) `
            $candidateRowSpan `
            $candidateColumnSpan `
            $candidate
    }

    if (-not (Test-IrLayoutRegionFree `
            $occupancy `
            ([int]$current.Row) `
            ([int]$current.Column) `
            $rowSpan `
            $columnSpan `
            $columns)) {
        Set-TowerStatus (
            "Size $sizeKey does not fit here - move the button to a free area first."
        )
        return
    }

    $script:irLayoutWorking[$commandId] = [pscustomobject]@{
        GroupKey = [string]$current.GroupKey
        Row = [int]$current.Row
        Column = [int]$current.Column
        ColorKey = [string]$current.ColorKey
        Label = [string]$current.Label
        RowSpan = $rowSpan
        ColumnSpan = $columnSpan
    }
    $entry.RowSpan = $rowSpan
    $entry.ColumnSpan = $columnSpan

    Apply-IrManagedGroupLayout $group
    Update-IrLayoutSelectionVisuals
    Set-TowerStatus "Button size changed to $sizeKey - click Save Layout to keep it."
}

function Register-IrLayoutButtonHandler($button, $entry) {
    if ($null -eq $button -or $null -eq $entry) { return }

    if ($null -ne $button.Tag) {
        $button.Tag | Add-Member `
            -NotePropertyName LayoutEntry `
            -NotePropertyValue $entry `
            -Force
    }

    $button.Add_MouseDown({
        param($sender, $eventArgs)

        if (-not $script:irLayoutEditMode -or
            $eventArgs.Button -ne
                [System.Windows.Forms.MouseButtons]::Left -or
            $null -eq $sender.Tag -or
            $null -eq $sender.Tag.LayoutEntry) {
            return
        }

        Select-IrLayoutEntry $sender.Tag.LayoutEntry
        $script:irLayoutDraggedEntry = $sender.Tag.LayoutEntry
        [void]$sender.DoDragDrop(
            [string]$sender.Tag.LayoutEntry.CommandId,
            [System.Windows.Forms.DragDropEffects]::Move
        )
    })
}

function Update-IrLayoutToolbarState {
    $hasDevice = $null -ne $script:currentIrDevice
    $irLayoutEditButton.Enabled = $hasDevice -and -not $script:irLayoutEditMode
    $irLayoutEditButton.Visible = -not $script:irLayoutEditMode
    $irLayoutSaveButton.Visible = $script:irLayoutEditMode
    $irLayoutCancelButton.Visible = $script:irLayoutEditMode
    $irLayoutColorPanel.Visible = $script:irLayoutEditMode
    $irLayoutSizePanel.Visible = $script:irLayoutEditMode
    $irLayoutNamePanel.Visible = $script:irLayoutEditMode

    if ($script:irLayoutEditMode) {
        $irHeaderLayout.RowStyles[1].Height = 40
        $irHeaderLayout.RowStyles[2].Height = 40
        $irHeaderLayout.RowStyles[3].Height = 40
        $irRightLayout.RowStyles[0].Height = 276
    }
    else {
        $irHeaderLayout.RowStyles[1].Height = 0
        $irHeaderLayout.RowStyles[2].Height = 0
        $irHeaderLayout.RowStyles[3].Height = 0
        $irRightLayout.RowStyles[0].Height = 156
        $script:irLayoutNameTextBox.Enabled = $false
        $script:irLayoutRenameButton.Enabled = $false
        $script:irLayoutNameTextBox.Text = ''
    }

    Position-IrLayoutHeaderControls
}

function Start-IrCommandLayoutEdit {
    if ($null -eq $script:currentIrDevice -or
        $script:irLayoutEditMode) {
        return
    }

    $script:irLayoutDeviceId =
        [string]$script:currentIrDevice.id
    $script:irLayoutWorking = @{}
    $script:irLayoutSelectedEntry = $null

    # Capture exactly what is currently visible as the starting logical layout,
    # including manual group membership and any saved color override.
    foreach ($group in @($irCommandPanel.Controls)) {
        if ($group -isnot [System.Windows.Forms.GroupBox] -or
            $null -eq $group.Tag -or
            [string]$group.Tag.LayoutKind -ne 'ManagedGrid') {
            continue
        }

        Apply-IrManagedGroupLayout $group
        foreach ($entry in @($group.Tag.Entries)) {
            $saved = Get-IrSavedLayoutEntryForCommand `
                ([string]$script:irLayoutDeviceId) `
                ([string]$entry.CommandId)

            $colorKey = if ($null -ne $saved -and
                $null -ne $saved.PSObject.Properties['colorKey'] -and
                -not [string]::IsNullOrWhiteSpace([string]$saved.colorKey)) {
                [string]$saved.colorKey
            }
            else {
                'Auto'
            }

            $script:irLayoutWorking[[string]$entry.CommandId] =
                [pscustomobject]@{
                    GroupKey = [string]$group.Tag.GroupKey
                    Row = [int]$entry.DisplayRow
                    Column = [int]$entry.DisplayColumn
                    ColorKey = $colorKey
                    Label = [string]$entry.Label
                    RowSpan = [Math]::Max(1, [int]$entry.RowSpan)
                    ColumnSpan = [Math]::Max(1, [int]$entry.ColumnSpan)
                }
        }
    }

    $script:irLayoutEditMode = $true
    $irDeviceList.Enabled = $false
    $irDeviceToolbar.Enabled = $false
    Update-IrLayoutToolbarState
    Refresh-IrCommandGroupWidths
    Update-IrLayoutSelectionVisuals
    Set-TowerStatus (
        'Edit Layout: drag buttons between groups, or select one to change its name, color or size.'
    )
}

function Save-IrCommandLayoutEdit {
    if (-not $script:irLayoutEditMode -or
        [string]::IsNullOrWhiteSpace($script:irLayoutDeviceId)) {
        return
    }

    $deviceId = [string]$script:irLayoutDeviceId
    $scopePrefix = [string]$script:irLayoutScopeKey + '::'
    $kept = @(
        @($config.irCommandLayouts) |
            Where-Object {
                [string]$_.deviceId -ne $deviceId -or
                -not ([string]$_.groupKey).StartsWith($scopePrefix)
            }
    )
    $saved = New-Object System.Collections.ArrayList

    foreach ($group in @($irCommandPanel.Controls)) {
        if ($group -isnot [System.Windows.Forms.GroupBox] -or
            $null -eq $group.Tag -or
            [string]$group.Tag.LayoutKind -ne 'ManagedGrid') {
            continue
        }

        foreach ($entry in @($group.Tag.Entries)) {
            $commandId = [string]$entry.CommandId
            if (-not $script:irLayoutWorking.ContainsKey($commandId)) {
                continue
            }

            $position = $script:irLayoutWorking[$commandId]
            [void]$saved.Add([pscustomobject]@{
                deviceId = $deviceId
                groupKey = [string]$position.GroupKey
                commandId = $commandId
                row = [int]$position.Row
                column = [int]$position.Column
                colorKey = [string]$position.ColorKey
                label = ConvertTo-IrSafeButtonLabel ([string]$position.Label)
                rowSpan = [Math]::Max(1, [int]$position.RowSpan)
                columnSpan = [Math]::Max(1, [int]$position.ColumnSpan)
            })
        }
    }

    $config.irCommandLayouts = @($kept) + @($saved)
    Save-TowerConfig

    $script:irLayoutEditMode = $false
    $script:irLayoutDeviceId = ''
    $script:irLayoutWorking = @{}
    $script:irLayoutDraggedEntry = $null
    $script:irLayoutSelectedEntry = $null
    $irDeviceList.Enabled = $true
    $irDeviceToolbar.Enabled = $true
    Update-IrLayoutToolbarState

    Show-IrDevice $script:currentIrDevice
    Set-TowerStatus 'IR command layout saved.'
}

function Cancel-IrCommandLayoutEdit {
    if (-not $script:irLayoutEditMode) { return }

    $script:irLayoutEditMode = $false
    $script:irLayoutDeviceId = ''
    $script:irLayoutWorking = @{}
    $script:irLayoutDraggedEntry = $null
    $script:irLayoutSelectedEntry = $null
    $irDeviceList.Enabled = $true
    $irDeviceToolbar.Enabled = $true
    Update-IrLayoutToolbarState

    Show-IrDevice $script:currentIrDevice
    Set-TowerStatus 'IR command layout changes cancelled.'
}


function New-IrGridGroup(
    [string]$title,
    [int]$columns,
    [int]$rows,
    [int]$buttonWidth = 150,
    [int]$buttonHeight = 46) {

    $cellWidth = $buttonWidth + 12
    $cellHeight = $buttonHeight + 12
    $columns = [Math]::Max(1, $columns)
    $rows = [Math]::Max(1, $rows)
    $gridWidth = $columns * $cellWidth
    $gridHeight = $rows * $cellHeight

    $group = New-Object System.Windows.Forms.GroupBox
    $group.Text = $title
    $group.AutoSize = $false
    $group.Padding = New-Object System.Windows.Forms.Padding(8, 22, 8, 8)
    $group.Margin = New-Object System.Windows.Forms.Padding(4, 4, 4, 10)
    $group.Size = New-Object System.Drawing.Size(
        ($gridWidth + 18),
        ($gridHeight + 36)
    )

    $grid = New-Object System.Windows.Forms.TableLayoutPanel
    $grid.AutoSize = $false
    $grid.GrowStyle =
        [System.Windows.Forms.TableLayoutPanelGrowStyle]::FixedSize
    $grid.Location = New-Object System.Drawing.Point(8, 22)
    $grid.Size = New-Object System.Drawing.Size($gridWidth, $gridHeight)
    $grid.Margin = New-Object System.Windows.Forms.Padding(0)
    $grid.Padding = New-Object System.Windows.Forms.Padding(0)

    Set-IrLayoutGridDimensions `
        $grid `
        $columns `
        $rows `
        $cellWidth `
        $cellHeight

    $entries = New-Object System.Collections.ArrayList
    $group.Tag = [pscustomobject]@{
        LayoutKind = 'ManagedGrid'
        LayoutMode = 'Fixed'
        Layout = $grid
        Entries = $entries
        DeviceId = ''
        GroupKey = Get-IrLayoutGroupKey $title
        BaseColumns = $columns
        BaseRows = $rows
        CellWidth = $cellWidth
        CellHeight = $cellHeight
        ButtonWidth = $buttonWidth
        ButtonHeight = $buttonHeight
    }

    $group.Controls.Add($grid)
    Register-IrLayoutGridHandlers $group $grid

    return [pscustomobject]@{
        Group = $group
        Grid = $grid
        ButtonWidth = $buttonWidth
        ButtonHeight = $buttonHeight
    }
}

function Add-IrGridButton(
    $bundle,
    $device,
    $command,
    [string]$category,
    [int]$row,
    [int]$column,
    [string]$labelOverride = '',
    [int]$rowSpan = 1,
    [int]$columnSpan = 1) {

    if ($null -eq $command) { return }

    $button = New-IrCommandButton $device $command $category $labelOverride
    $defaultLabel = Get-IrDefaultLayoutLabel ([string]$button.Text)
    $button.Dock = [System.Windows.Forms.DockStyle]::Fill

    $groupTag = $bundle.Group.Tag
    if ([string]::IsNullOrWhiteSpace([string]$groupTag.DeviceId)) {
        $groupTag.DeviceId = [string]$device.id
    }

    $entry = [pscustomobject]@{
        Button = $button
        CommandId = [string]$command.id
        DefaultLabel = $defaultLabel
        Label = $defaultLabel
        GroupKey = [string]$groupTag.GroupKey
        DefaultRow = $row
        DefaultColumn = $column
        DefaultIndex = [int]$groupTag.Entries.Count
        DefaultRowSpan = [Math]::Max(1, $rowSpan)
        DefaultColumnSpan = [Math]::Max(1, $columnSpan)
        RowSpan = [Math]::Max(1, $rowSpan)
        ColumnSpan = [Math]::Max(1, $columnSpan)
        LogicalRow = $row
        LogicalColumn = $column
        DisplayRow = $row
        DisplayColumn = $column
        ColorKey = 'Auto'
    }

    [void]$groupTag.Entries.Add($entry)
    Register-IrLayoutButtonHandler $button $entry

    $bundle.Grid.Controls.Add($button, $column, $row)
    if ($rowSpan -gt 1) {
        $bundle.Grid.SetRowSpan($button, $rowSpan)
    }
    if ($columnSpan -gt 1) {
        $bundle.Grid.SetColumnSpan($button, $columnSpan)
    }
}

function Resize-IrCommandGroup($group) {
    Apply-IrManagedGroupLayout $group
}

function Update-IrCommandPanelScrollExtent {
    if ($null -eq $irCommandPanel -or $irCommandPanel.IsDisposed) {
        return
    }

    $contentHeight = [int]$irCommandPanel.Padding.Vertical
    foreach ($control in @($irCommandPanel.Controls)) {
        if (-not $control.Visible) { continue }
        $contentHeight +=
            [int]$control.Height +
            [int]$control.Margin.Vertical
    }

    # FlowLayoutPanel occasionally keeps its pre-edit scroll range when every
    # group gains the additional empty drop row. Supplying the real total
    # content height makes the final group reachable on the first edit pass.
    $irCommandPanel.AutoScrollMinSize =
        New-Object System.Drawing.Size(
            0,
            [Math]::Max(0, $contentHeight)
        )
    $irCommandPanel.PerformLayout()
}

function Refresh-IrCommandGroupWidths {
    if ($null -eq $irCommandPanel -or $irCommandPanel.IsDisposed) {
        return
    }

    $savedScrollX = -[int]$irCommandPanel.AutoScrollPosition.X
    $savedScrollY = -[int]$irCommandPanel.AutoScrollPosition.Y

    $irCommandPanel.SuspendLayout()
    try {
        foreach ($group in @($irCommandPanel.Controls)) {
            if ($group -is [System.Windows.Forms.GroupBox] -and
                $null -ne $group.Tag) {
                Resize-IrCommandGroup $group
            }
        }
    }
    finally {
        $irCommandPanel.ResumeLayout($true)
    }

    Update-IrCommandPanelScrollExtent
    $irCommandPanel.AutoScrollPosition =
        New-Object System.Drawing.Point($savedScrollX, $savedScrollY)

    # Header growth and FlowLayoutPanel measurement finish on separate Windows
    # layout messages. Recalculate once more after both have settled.
    try {
        [void]$irCommandPanel.BeginInvoke([System.Action]{
            Update-IrCommandPanelScrollExtent
        })
    }
    catch {
        # The form can be closing while a final resize event is delivered.
    }
}

function Add-IrFlowGroup($device, [string]$title, $commands) {
    $commandList = @($commands)
    if ($commandList.Count -eq 0) { return }

    $bundle = New-IrGridGroup `
        $title `
        1 `
        ([Math]::Max(1, $commandList.Count))
    $bundle.Group.Tag.LayoutMode = 'Flow'
    $bundle.Group.Tag.DeviceId = [string]$device.id

    for ($i = 0; $i -lt $commandList.Count; $i++) {
        Add-IrGridButton `
            $bundle `
            $device `
            $commandList[$i] `
            $title `
            $i `
            0
    }

    [void]$irCommandPanel.Controls.Add($bundle.Group)
    Resize-IrCommandGroup $bundle.Group
}

function Add-DenonModeSelector {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Size = New-Object System.Drawing.Size(310, 48)
    $panel.Margin = New-Object System.Windows.Forms.Padding(4, 0, 4, 8)

    $mainButton = New-Object System.Windows.Forms.Button
    $mainButton.Text = 'MAIN'
    $mainButton.Size = New-Object System.Drawing.Size(130, 36)
    $mainButton.Location = New-Object System.Drawing.Point(0, 4)
    $mainButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat

    $zoneButton = New-Object System.Windows.Forms.Button
    $zoneButton.Text = 'ZONE 2'
    $zoneButton.Size = New-Object System.Drawing.Size(130, 36)
    $zoneButton.Location = New-Object System.Drawing.Point(142, 4)
    $zoneButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat

    if ($script:denonZoneMode -eq 'Zone2') {
        $zoneButton.BackColor = [System.Drawing.Color]::SteelBlue
        $zoneButton.ForeColor = [System.Drawing.Color]::White
    }
    else {
        $mainButton.BackColor = [System.Drawing.Color]::SteelBlue
        $mainButton.ForeColor = [System.Drawing.Color]::White
    }

    $mainButton.Add_Click({
        if ($script:irLayoutEditMode) {
            Set-TowerStatus 'Save or cancel Edit Layout before changing zone.'
            return
        }
        $script:denonZoneMode = 'Main'
        Show-IrDevice $script:currentIrDevice
    })

    $zoneButton.Add_Click({
        if ($script:irLayoutEditMode) {
            Set-TowerStatus 'Save or cancel Edit Layout before changing zone.'
            return
        }
        $script:denonZoneMode = 'Zone2'
        Show-IrDevice $script:currentIrDevice
    })

    $panel.Controls.Add($mainButton)
    $panel.Controls.Add($zoneButton)
    [void]$irCommandPanel.Controls.Add($panel)
}

function Add-DenonFlowGroup(
    $device,
    [string]$title,
    $commands) {

    $commandList = @($commands)
    if ($commandList.Count -eq 0) { return }

    $bundle = New-IrGridGroup `
        $title `
        1 `
        ([Math]::Max(1, $commandList.Count))
    $bundle.Group.Tag.LayoutMode = 'Flow'
    $bundle.Group.Tag.DeviceId = [string]$device.id

    for ($i = 0; $i -lt $commandList.Count; $i++) {
        $command = $commandList[$i]
        $label = Get-DenonButtonLabel $command
        Add-IrGridButton `
            $bundle `
            $device `
            $command `
            $title `
            $i `
            0 `
            $label
    }

    [void]$irCommandPanel.Controls.Add($bundle.Group)
    Resize-IrCommandGroup $bundle.Group
}

function Show-IrDevice($device) {
    if ($script:irLayoutEditMode) {
        $incomingId = if ($null -eq $device) {
            ''
        }
        else {
            [string]$device.id
        }

        if ($incomingId -ne [string]$script:irLayoutDeviceId) {
            Set-TowerStatus 'Save or cancel Edit Layout before changing remote.'
            return
        }
    }

    $renderTimer = [System.Diagnostics.Stopwatch]::StartNew()

    $script:currentIrDevice = $device
    $script:irLayoutGroupCounts = @{}
    $script:irLayoutScopeKey = if ($null -ne $device -and
        [string]$device.name -eq 'AVR X2800H') {
        'Denon-' + [string]$script:denonZoneMode
    }
    else {
        'Default'
    }
    Update-IrLayoutToolbarState
    $irCommandPanel.SuspendLayout()
    $irCommandPanel.Controls.Clear()
    $irCommandPanel.AutoScrollMinSize = [System.Drawing.Size]::Empty

    # Mark the previous rendering invalid until this build finishes.
    $script:renderedIrDeviceId = ''
    $script:renderedIrDeviceSignature = ''

    if ($null -eq $device) {
        $irHeading.Text = 'Select an IR device'
        $irDetailLabel.Text = ''
        Update-RemotePreview $null
        $irCommandPanel.ResumeLayout()

        $script:renderedIrDeviceId = ''
        $script:renderedIrDeviceSignature = ''
        $renderTimer.Stop()
        return
    }

    $irHeading.Text = [string]$device.name
    $detailParts = @()
    if (-not [string]::IsNullOrWhiteSpace([string]$device.manufacturer)) { $detailParts += [string]$device.manufacturer }
    if (-not [string]::IsNullOrWhiteSpace([string]$device.location)) { $detailParts += [string]$device.location }
    if (-not [string]::IsNullOrWhiteSpace([string]$device.transmitter)) { $detailParts += ('Profile default: ' + (Get-ShortTransmitterLabel ([string]$device.transmitter))) }
    $irDetailLabel.Text = ($detailParts -join '   |   ')

    Update-RemotePreview $device

    $commands = @($device.commands | Where-Object { $_.transport -eq 'IR' -and $_.enabled })
    if ($commands.Count -eq 0) {
        $emptyLabel = New-Object System.Windows.Forms.Label
        $emptyLabel.Text = 'No IR commands are enabled for this device.'
        $emptyLabel.AutoSize = $true
        $emptyLabel.Margin = New-Object System.Windows.Forms.Padding(10)
        $irCommandPanel.Controls.Add($emptyLabel)
        $irCommandPanel.ResumeLayout()

        $script:renderedIrDeviceId = [string]$device.id
        $script:renderedIrDeviceSignature =
            Get-IrDeviceRenderSignature $device
        $renderTimer.Stop()
        Write-TowerLog 'INFO' (
            "Rendered IR pane for '$([string]$device.name)' in " +
            "$($renderTimer.ElapsedMilliseconds) ms"
        )
        return
    }

    $deviceName = [string]$device.name

    if ($deviceName -eq 'AVR X2800H') {
        Render-DenonRemote $device $commands
    }
    elseif ($deviceName -match 'KPN') {
        Render-KpnRemote $device $commands
    }
    elseif ($deviceName -ieq 'LED Light Bar') {
        Render-LedLightBarRemote $device $commands
    }
    elseif ($deviceName -ieq 'PAC 7.2') {
        Render-PacRemote $device $commands
    }
    elseif ($deviceName -match 'Z5500') {
        Render-Z5500Remote $device $commands
    }
    else {
        Render-IrGenericGroups $device $commands
    }

    Apply-IrSavedGroupAssignmentsAndStyles
    Refresh-IrCommandGroupWidths
    $irCommandPanel.ResumeLayout()

    $script:renderedIrDeviceId = [string]$device.id
    $script:renderedIrDeviceSignature =
        Get-IrDeviceRenderSignature $device

    $renderTimer.Stop()
    Write-TowerLog 'INFO' (
        "Rendered IR pane for '$([string]$device.name)' in " +
        "$($renderTimer.ElapsedMilliseconds) ms"
    )
}

Initialize-IrLayoutEditorUi
Update-IrLayoutToolbarState
