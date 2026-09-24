# Editable Home dashboard actions.
# Dot-sourced by Tower-Control.ps1 after the Tower API and shared UI helpers.

$script:homeActionTargets = @()
$script:homeActionPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$script:homeActionPanel.Location = New-Object System.Drawing.Point(14, 82)
$script:homeActionPanel.Height = 124
$script:homeActionPanel.Anchor = 'Top,Left,Right'
$script:homeActionPanel.AutoScroll = $true
$script:homeActionPanel.WrapContents = $true
$script:homeActionPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$script:homeActionPanel.Padding = New-Object System.Windows.Forms.Padding(4, 6, 4, 4)
$script:homeActionPanel.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
$homeTab.Controls.Add($script:homeActionPanel)

$homeEditButton = New-Object System.Windows.Forms.Button
$homeEditButton.Text = 'Edit Home'
$homeEditButton.Size = New-Object System.Drawing.Size(96, 32)
$homeEditButton.Anchor = 'Top,Right'
$homeEditButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$homeEditButton.BackColor = [System.Drawing.Color]::White
$homeEditButton.ForeColor = [System.Drawing.Color]::SteelBlue
Set-IrButtonVisualStyle $homeEditButton
$homeTab.Controls.Add($homeEditButton)

function Position-HomeActionLayout {
    $homeEditButton.Left = [Math]::Max(200, $homeTab.ClientSize.Width - 114)
    $homeEditButton.Top = 20
    $script:homeActionPanel.Width = [Math]::Max(100, $homeTab.ClientSize.Width - 28)

    $cardWidth = 190
    $rowHeight = 108
    $usableWidth = [Math]::Max($cardWidth, $script:homeActionPanel.ClientSize.Width - 24)
    $columns = [Math]::Max(1, [Math]::Floor($usableWidth / $cardWidth))
    $count = [Math]::Max(1, @($config.homeActions).Count)
    $rows = [Math]::Ceiling($count / $columns)
    $wantedHeight = [int]($rows * $rowHeight + 12)
    $maximumHeight = [Math]::Max(124, $homeTab.ClientSize.Height - 190)
    $script:homeActionPanel.Height = [Math]::Min($wantedHeight, $maximumHeight)

    $deviceTop = $script:homeActionPanel.Bottom + 16
    $homeDevicePanel.Top = $deviceTop
    $homeDevicePanel.Width = [Math]::Max(100, $homeTab.ClientSize.Width - 28)
    $homeDevicePanel.Height = [Math]::Max(100, $homeTab.ClientSize.Height - $deviceTop - 14)
}
$homeTab.Add_Resize({ Position-HomeActionLayout })
Position-HomeActionLayout

function Get-HomeTheme([string]$name) {
    switch ($name) {
        'Green' { return @([System.Drawing.Color]::FromArgb(229, 245, 232), [System.Drawing.Color]::FromArgb(28, 105, 55)) }
        'Red' { return @([System.Drawing.Color]::FromArgb(250, 231, 231), [System.Drawing.Color]::FromArgb(145, 35, 35)) }
        'Blue' { return @([System.Drawing.Color]::FromArgb(226, 238, 251), [System.Drawing.Color]::FromArgb(36, 83, 132)) }
        'Purple' { return @([System.Drawing.Color]::FromArgb(239, 233, 248), [System.Drawing.Color]::FromArgb(89, 61, 130)) }
        'Orange' { return @([System.Drawing.Color]::FromArgb(252, 241, 221), [System.Drawing.Color]::FromArgb(135, 82, 20)) }
        default { return @([System.Drawing.Color]::White, [System.Drawing.Color]::FromArgb(55, 55, 60)) }
    }
}

function Get-HomeActionSubtitle($item) {
    switch ([string]$item.kind) {
        'rf_preset' { return "RF Preset $([string]$item.target) $(([string]$item.action).ToUpperInvariant())" }
        'schedule' { return 'Tower schedule' }
        'remote_trigger' { return 'Programmable remote command' }
        'voice_path' { return 'Voice command set' }
        'ir_command' { return 'Learned IR command' }
        'script' { return 'Saved script' }
        default { return 'Tower action' }
    }
}

function Invoke-HomeAction($item) {
    try {
        $form.UseWaitCursor = $true
        Set-TowerStatus "Running $([string]$item.label)..."
        [System.Windows.Forms.Application]::DoEvents()
        switch ([string]$item.kind) {
            'rf_preset' {
                [void](Invoke-TowerPost '/api/v1/rf/preset' @{
                    preset = [int]$item.target
                    action = [string]$item.action
                })
            }
            'schedule' {
                [void](Invoke-TowerPost '/api/v1/schedules/run' @{ id = [string]$item.target })
            }
            'remote_trigger' {
                [void](Invoke-TowerPost '/api/v1/control/ir-triggers/run' @{ id = [string]$item.target })
            }
            'voice_path' {
                [void](Invoke-TowerPost '/api/v1/control/actions' @{
                    actions = @(@{ type='voice_path'; path=@($item.path) })
                })
            }
            'ir_command' {
                [void](Invoke-TowerPost '/api/v1/control/actions' @{
                    actions = @(@{
                        type='command'
                        device=[string]$item.target
                        command=[string]$item.command
                        transmitters=@($item.transmitters)
                    })
                })
            }
            'script' {
                [void](Invoke-TowerPost '/api/v1/control/actions' @{
                    actions = @(@{ type='script'; script=[string]$item.target })
                })
            }
            default { throw "Unsupported Home action: $([string]$item.kind)" }
        }
        Set-TowerStatus "$([string]$item.label) completed"
    }
    catch {
        Set-TowerStatus "$([string]$item.label) failed" $true
        [System.Windows.Forms.MessageBox]::Show(
            [string]$_.Exception.Message,
            'Home action failed', 'OK', 'Error') | Out-Null
    }
    finally { $form.UseWaitCursor = $false }
}

function Refresh-HomeActions {
    $script:homeActionPanel.SuspendLayout()
    try {
        $script:homeActionPanel.Controls.Clear()
        foreach ($item in @($config.homeActions)) {
            $card = New-Object System.Windows.Forms.Panel
            $card.Size = New-Object System.Drawing.Size(176, 94)
            $card.Margin = New-Object System.Windows.Forms.Padding(7)
            $card.BackColor = $script:homeActionPanel.BackColor

            $theme = Get-HomeTheme ([string]$item.color)
            $button = New-RfSmoothButton ([string]$item.label) 162 56 $theme[0] $theme[1] $theme[1]
            $button.Location = New-Object System.Drawing.Point(7, 4)
            $button.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
            $captured = $item
            $button.Add_MouseClick({ Invoke-HomeAction $captured }.GetNewClosure())
            $card.Controls.Add($button)

            $subtitle = New-Object System.Windows.Forms.Label
            $subtitle.Text = Get-HomeActionSubtitle $item
            $subtitle.Location = New-Object System.Drawing.Point(5, 64)
            $subtitle.Size = New-Object System.Drawing.Size(166, 22)
            $subtitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            $subtitle.ForeColor = [System.Drawing.Color]::DimGray
            $subtitle.Font = New-Object System.Drawing.Font('Segoe UI', 8)
            $subtitle.AutoEllipsis = $true
            $card.Controls.Add($subtitle)
            [void]$script:homeActionPanel.Controls.Add($card)
        }
    }
    finally {
        $script:homeActionPanel.ResumeLayout()
    }
}

function Add-HomeVoiceLeaves($children, [string[]]$prefix, [System.Collections.ArrayList]$output) {
    if ($null -eq $children) { return }
    foreach ($property in @($children.PSObject.Properties)) {
        $node = $property.Value
        $path = @($prefix) + @([string]$property.Name)
        if ($null -ne $node.PSObject.Properties['actions']) {
            [void]$output.Add([pscustomobject]@{
                Label = ($path -join ' > ')
                Value = ($path -join ' > ')
                Path = @($path)
            })
        }
        if ($null -ne $node.PSObject.Properties['children']) {
            Add-HomeVoiceLeaves $node.children $path $output
        }
    }
}

function Get-HomeEditorCatalog {
    $result = @{
        schedule=@(); remote_trigger=@(); voice_path=@(); ir_command=@(); script=@()
    }
    $scheduleResponse = Invoke-TowerGet '/api/v1/schedules'
    $scheduleDocument = $scheduleResponse.schedules
    $scheduleRows = if ($null -ne $scheduleDocument.PSObject.Properties['schedules']) {
        @($scheduleDocument.schedules)
    }
    else {
        @($scheduleDocument)
    }
    foreach ($schedule in $scheduleRows) {
        $result.schedule += [pscustomobject]@{ Label=[string]$schedule.name; Value=[string]$schedule.id }
    }
    foreach ($trigger in @((Invoke-TowerGet '/api/v1/control/ir-triggers').document.triggers)) {
        $result.remote_trigger += [pscustomobject]@{ Label=[string]$trigger.name; Value=[string]$trigger.id }
    }
    foreach ($saved in @((Invoke-TowerGet '/api/v1/control/scripts').scripts)) {
        $prefix = switch ([string]$saved.kind) {
            'wol' {'[WOL]'}
            'powershell' {'[WIN]'}
            default {'[PI]'}
        }
        $result.script += [pscustomobject]@{ Label="$prefix $([string]$saved.name)"; Value=[string]$saved.id }
    }
    $voice = Invoke-TowerGet '/api/v1/voice/config'
    $leaves = New-Object System.Collections.ArrayList
    Add-HomeVoiceLeaves $voice.config.command_tree @() $leaves
    $result.voice_path = @($leaves)

    $catalog = (Invoke-TowerGet '/api/v1/voice/catalog').catalog
    foreach ($device in @($catalog.irDevices)) {
        foreach ($command in @($device.commands)) {
            $result.ir_command += [pscustomobject]@{
                Label = "$([string]$device.name) > $([string]$command.name)"
                Value = "$([string]$device.id)|$([string]$command.id)"
                Device = [string]$device.id
                Command = [string]$command.id
            }
        }
    }
    return $result
}

function Show-HomeEditor {
    $catalog = Get-HomeEditorCatalog
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Edit Home dashboard'
    $dialog.StartPosition = 'CenterParent'
    $dialog.Size = New-Object System.Drawing.Size(780, 570)
    $dialog.MinimumSize = New-Object System.Drawing.Size(720, 520)
    $dialog.Font = $form.Font

    $list = New-Object System.Windows.Forms.ListBox
    $list.Location = New-Object System.Drawing.Point(14, 14)
    $list.Size = New-Object System.Drawing.Size(270, 465)
    $list.Anchor = 'Top,Bottom,Left'
    $dialog.Controls.Add($list)

    $labels = @('Button name','Action type','Target','RF action','Button color')
    $tops = @(20,70,120,170,220)
    for ($i=0; $i -lt $labels.Count; $i++) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $labels[$i]
        $label.Location = New-Object System.Drawing.Point(310, $tops[$i])
        $label.Size = New-Object System.Drawing.Size(105, 25)
        $dialog.Controls.Add($label)
    }
    $name = New-Object System.Windows.Forms.TextBox
    $name.Location = New-Object System.Drawing.Point(420, 20)
    $name.Size = New-Object System.Drawing.Size(320, 25)
    $name.Anchor = 'Top,Left,Right'
    $dialog.Controls.Add($name)

    $type = New-Object System.Windows.Forms.ComboBox
    $type.DropDownStyle = 'DropDownList'
    $type.Location = New-Object System.Drawing.Point(420, 70)
    $type.Size = New-Object System.Drawing.Size(320, 25)
    [void]$type.Items.AddRange(@('RF preset','Tower schedule','Programmable remote button','Voice command set','IR remote command','Saved script'))
    $dialog.Controls.Add($type)

    $target = New-Object System.Windows.Forms.ComboBox
    $target.DropDownStyle = 'DropDownList'
    $target.Location = New-Object System.Drawing.Point(420, 120)
    $target.Size = New-Object System.Drawing.Size(320, 25)
    $target.Anchor = 'Top,Left,Right'
    $dialog.Controls.Add($target)

    $rfAction = New-Object System.Windows.Forms.ComboBox
    $rfAction.DropDownStyle = 'DropDownList'
    $rfAction.Location = New-Object System.Drawing.Point(420, 170)
    $rfAction.Size = New-Object System.Drawing.Size(150, 25)
    [void]$rfAction.Items.AddRange(@('ON','OFF'))
    $dialog.Controls.Add($rfAction)

    $color = New-Object System.Windows.Forms.ComboBox
    $color.DropDownStyle = 'DropDownList'
    $color.Location = New-Object System.Drawing.Point(420, 220)
    $color.Size = New-Object System.Drawing.Size(150, 25)
    [void]$color.Items.AddRange(@('White','Blue','Green','Red','Orange','Purple'))
    $dialog.Controls.Add($color)

    $status = New-Object System.Windows.Forms.Label
    $status.Text = 'Changes are stored in this Windows user profile.'
    $status.Location = New-Object System.Drawing.Point(310, 275)
    $status.Size = New-Object System.Drawing.Size(430, 45)
    $status.ForeColor = [System.Drawing.Color]::DimGray
    $dialog.Controls.Add($status)

    $newButton = New-Object System.Windows.Forms.Button
    $newButton.Text = '+ New'; $newButton.Location = New-Object System.Drawing.Point(14, 490); $newButton.Size = New-Object System.Drawing.Size(80, 32); $newButton.Anchor='Bottom,Left'
    $cloneButton = New-Object System.Windows.Forms.Button
    $cloneButton.Text = 'Clone'; $cloneButton.Location = New-Object System.Drawing.Point(100, 490); $cloneButton.Size = New-Object System.Drawing.Size(70, 32); $cloneButton.Anchor='Bottom,Left'
    $upButton = New-Object System.Windows.Forms.Button
    $upButton.Text = '< Earlier'; $upButton.Location = New-Object System.Drawing.Point(176, 490); $upButton.Size = New-Object System.Drawing.Size(78, 32); $upButton.Anchor='Bottom,Left'
    $downButton = New-Object System.Windows.Forms.Button
    $downButton.Text = 'Later >'; $downButton.Location = New-Object System.Drawing.Point(260, 490); $downButton.Size = New-Object System.Drawing.Size(70, 32); $downButton.Anchor='Bottom,Left'
    $deleteButton = New-Object System.Windows.Forms.Button
    $deleteButton.Text = 'Delete'; $deleteButton.Location = New-Object System.Drawing.Point(336, 490); $deleteButton.Size = New-Object System.Drawing.Size(65, 32); $deleteButton.Anchor='Bottom,Left'
    foreach ($button in @($newButton,$cloneButton,$upButton,$downButton,$deleteButton)) { $dialog.Controls.Add($button) }

    $apply = New-Object System.Windows.Forms.Button
    $apply.Text='Apply button'; $apply.Location=New-Object System.Drawing.Point(420,340); $apply.Size=New-Object System.Drawing.Size(130,34); $dialog.Controls.Add($apply)
    $shortcut = New-Object System.Windows.Forms.Button
    $shortcut.Text='Desktop shortcut'; $shortcut.Location=New-Object System.Drawing.Point(560,340); $shortcut.Size=New-Object System.Drawing.Size(140,34); $dialog.Controls.Add($shortcut)
    $close = New-Object System.Windows.Forms.Button
    $close.Text='Done'; $close.Location=New-Object System.Drawing.Point(650,490); $close.Size=New-Object System.Drawing.Size(90,32); $close.Anchor='Bottom,Right'; $dialog.Controls.Add($close)

    function Refresh-HomeEditorList([string]$selectId='') {
        $list.Items.Clear()
        $selected = -1
        for ($i=0; $i -lt @($config.homeActions).Count; $i++) {
            $entry = @($config.homeActions)[$i]
            [void]$list.Items.Add([string]$entry.label)
            if ([string]$entry.id -eq $selectId) { $selected = $i }
        }
        if ($selected -ge 0) { $list.SelectedIndex=$selected }
        elseif ($list.Items.Count) { $list.SelectedIndex=0 }
    }
    function Home-TypeKey([string]$display) {
        switch ($display) {
            'RF preset' {'rf_preset'} 'Tower schedule' {'schedule'}
            'Programmable remote button' {'remote_trigger'} 'Voice command set' {'voice_path'}
            'IR remote command' {'ir_command'} 'Saved script' {'script'}
        }
    }
    function Home-TypeDisplay([string]$key) {
        switch ($key) {
            'rf_preset' {'RF preset'} 'schedule' {'Tower schedule'}
            'remote_trigger' {'Programmable remote button'} 'voice_path' {'Voice command set'}
            'ir_command' {'IR remote command'} 'script' {'Saved script'} default {'RF preset'}
        }
    }
    function Populate-HomeTargets([string]$selectValue='') {
        $key = Home-TypeKey ([string]$type.SelectedItem)
        $script:homeActionTargets = @()
        $target.Items.Clear()
        if ($key -eq 'rf_preset') {
            $script:homeActionTargets = @(1..3 | ForEach-Object { [pscustomobject]@{Label="Preset $_";Value=[string]$_} })
        } else { $script:homeActionTargets = @($catalog[$key]) }
        for ($i=0;$i -lt $script:homeActionTargets.Count;$i++) {
            [void]$target.Items.Add([string]$script:homeActionTargets[$i].Label)
            if ([string]$script:homeActionTargets[$i].Value -eq $selectValue) { $target.SelectedIndex=$i }
        }
        if ($target.SelectedIndex -lt 0 -and $target.Items.Count) { $target.SelectedIndex=0 }
        $rfAction.Enabled = $key -eq 'rf_preset'
    }
    function Show-HomeEditorSelection {
        if ($list.SelectedIndex -lt 0) { return }
        $entry=@($config.homeActions)[$list.SelectedIndex]
        $name.Text=[string]$entry.label
        $type.SelectedItem=Home-TypeDisplay ([string]$entry.kind)
        Populate-HomeTargets ([string]$entry.target + $(if ([string]$entry.kind -eq 'ir_command'){"|$([string]$entry.command)"}else{''}))
        $rfAction.SelectedItem=$(if ([string]$entry.action -eq 'off'){'OFF'}else{'ON'})
        $color.SelectedItem=$(if ([string]::IsNullOrWhiteSpace([string]$entry.color)){'White'}else{[string]$entry.color})
    }
    $type.Add_SelectedIndexChanged({ Populate-HomeTargets })
    $list.Add_SelectedIndexChanged({ Show-HomeEditorSelection })
    $newButton.Add_Click({
        $entry=[pscustomobject]@{id=[Guid]::NewGuid().ToString('N');label='New Home button';kind='rf_preset';target='1';action='on';color='Blue'}
        $config.homeActions=@($config.homeActions)+@($entry); Save-TowerConfig; Refresh-HomeEditorList ([string]$entry.id)
    })
    $cloneButton.Add_Click({
        if ($list.SelectedIndex -lt 0) { return }
        $source = @($config.homeActions)[$list.SelectedIndex]
        $clone = $source | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $clone.id = [Guid]::NewGuid().ToString('N')
        $baseName = ([string]$source.label).Trim()
        if ([string]::IsNullOrWhiteSpace($baseName)) { $baseName = 'Home button' }
        $number = 2
        do {
            $candidate = "$baseName ($number)"
            $exists = @($config.homeActions | Where-Object {
                [string]$_.label -ieq $candidate
            }).Count -gt 0
            $number++
        } while ($exists)
        $clone.label = $candidate
        $config.homeActions = @($config.homeActions) + @($clone)
        Save-TowerConfig
        Refresh-HomeEditorList ([string]$clone.id)
        Refresh-HomeActions
        Position-HomeActionLayout
        $status.Text = "Button cloned as '$candidate'."
    })
    $deleteButton.Add_Click({
        if ($list.SelectedIndex -lt 0) { return }
        $selectedEntry = @($config.homeActions)[$list.SelectedIndex]
        $id = [string]$selectedEntry.id
        $config.homeActions = @($config.homeActions | Where-Object { [string]$_.id -ne $id })
        Save-TowerConfig; Refresh-HomeEditorList; Refresh-HomeActions; Position-HomeActionLayout
    })
    $upButton.Add_Click({
        $i = $list.SelectedIndex
        if ($i -le 0) { return }
        $a = @($config.homeActions); $tmp = $a[$i-1]; $a[$i-1] = $a[$i]; $a[$i] = $tmp
        $config.homeActions = $a; Save-TowerConfig
        Refresh-HomeEditorList ([string]$a[$i-1].id); Refresh-HomeActions; Position-HomeActionLayout
    })
    $downButton.Add_Click({
        $i = $list.SelectedIndex; $a = @($config.homeActions)
        if ($i -lt 0 -or $i -ge $a.Count - 1) { return }
        $tmp = $a[$i+1]; $a[$i+1] = $a[$i]; $a[$i] = $tmp
        $config.homeActions = $a; Save-TowerConfig
        Refresh-HomeEditorList ([string]$a[$i+1].id); Refresh-HomeActions; Position-HomeActionLayout
    })
    $apply.Add_Click({
        if ($list.SelectedIndex -lt 0 -or $target.SelectedIndex -lt 0) { return }
        $entry=@($config.homeActions)[$list.SelectedIndex];$choice=$script:homeActionTargets[$target.SelectedIndex];$entry.label=([string]$name.Text).Trim();if(!$entry.label){$entry.label=[string]$choice.Label}
        $entry.kind=Home-TypeKey ([string]$type.SelectedItem);$entry.color=[string]$color.SelectedItem
        if ([string]$entry.kind -eq 'ir_command') {$entry.target=[string]$choice.Device;$entry|Add-Member -Force NoteProperty command ([string]$choice.Command);$entry|Add-Member -Force NoteProperty transmitters @($script:selectedIrTransmitters)}
        elseif ([string]$entry.kind -eq 'voice_path') {$entry.target=[string]$choice.Value;$entry|Add-Member -Force NoteProperty path @($choice.Path)}
        else{$entry.target=[string]$choice.Value}
        if ([string]$entry.kind -eq 'rf_preset') {$entry.action=([string]$rfAction.SelectedItem).ToLowerInvariant()}
        Save-TowerConfig;Refresh-HomeEditorList ([string]$entry.id);Refresh-HomeActions;Position-HomeActionLayout;$status.Text='Button saved. Home flows left to right and wraps into rows.'
    })
    $shortcut.Add_Click({
        if ($list.SelectedIndex -lt 0) { return }; $entry=@($config.homeActions)[$list.SelectedIndex]
        $shell=New-Object -ComObject WScript.Shell;$path=Join-Path ([Environment]::GetFolderPath('Desktop')) (([string]$entry.label -replace '[\\/:*?"<>|]','_')+'.lnk')
        $link=$shell.CreateShortcut($path);$link.TargetPath="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe";$link.Arguments="-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSScriptRoot\Tower-Home-Action.ps1`" -ActionId `"$([string]$entry.id)`"";$link.WorkingDirectory=$PSScriptRoot
        $icon=Join-Path $PSScriptRoot 'assets\tower-icon-tray.ico';if(Test-Path $icon){$link.IconLocation=$icon};$link.Save();$status.Text="Desktop shortcut created: $path"
    })
    $close.Add_Click({$dialog.Close()})
    $type.SelectedIndex=0;$rfAction.SelectedIndex=0;$color.SelectedItem='Blue';Refresh-HomeEditorList
    [void]$dialog.ShowDialog($form);$dialog.Dispose()
}

$homeEditButton.Add_Click({
    try { $form.UseWaitCursor=$true; Show-HomeEditor }
    catch {[System.Windows.Forms.MessageBox]::Show([string]$_.Exception.Message,'Home editor failed','OK','Error')|Out-Null}
    finally {$form.UseWaitCursor=$false}
})

Refresh-HomeActions
Position-HomeActionLayout
