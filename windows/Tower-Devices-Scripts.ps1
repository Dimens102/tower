# Shared estimated power states and scripts stored on Tower.
$script:dsPopulating = $false
$script:dsScriptId = ''
function New-DsButton($parent, [string]$text) {
    $b=New-Object System.Windows.Forms.Button
    $b.Text=$text; $b.AutoSize=$true; $b.Height=32; $b.Margin=New-Object System.Windows.Forms.Padding(4)
    [void]$parent.Controls.Add($b); return $b
}
function New-DsRow($parent,[string]$label,$control) {
    $row=$parent.RowCount; $parent.RowCount++
    [void]$parent.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
    $l=New-Object System.Windows.Forms.Label; $l.Text=$label; $l.AutoSize=$true; $l.Margin=New-Object System.Windows.Forms.Padding(6,9,12,9)
    $parent.Controls.Add($l,0,$row);$control.Dock='Fill';$control.Margin=New-Object System.Windows.Forms.Padding(4,5,8,5)
    $parent.Controls.Add($control,1,$row)
}
function Invoke-DsTask([scriptblock]$task) {
    try { & $task } catch { [void][System.Windows.Forms.MessageBox]::Show([string]$_.Exception.Message,'Tower','OK','Error') }
}
$dsTab=New-Object System.Windows.Forms.TabPage; $dsTab.Text='Devices'; [void]$tabs.TabPages.Add($dsTab)
$dsRoot=New-Object System.Windows.Forms.TableLayoutPanel; $dsRoot.Dock='Fill';$dsRoot.ColumnCount=1;$dsRoot.RowCount=4
foreach($height in @(44,42)){[void]$dsRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',$height)))}
[void]$dsRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',100)))
[void]$dsRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',330)))
$dsTab.Controls.Add($dsRoot)
$dsHint=New-Object System.Windows.Forms.Label; $dsHint.Dock='Fill';$dsHint.Text='Estimated states from Tower commands. Mark On/Off corrects the record without sending a signal.';$dsHint.Padding=New-Object System.Windows.Forms.Padding(8);$dsRoot.Controls.Add($dsHint,0,0)
$dsTools=New-Object System.Windows.Forms.FlowLayoutPanel;$dsTools.Dock='Fill';$dsRoot.Controls.Add($dsTools,0,1)
$dsRefresh=New-DsButton $dsTools 'Refresh'
$dsMarkOn=New-DsButton $dsTools 'Mark On';$dsMarkOff=New-DsButton $dsTools 'Mark Off';$dsMarkUnknown=New-DsButton $dsTools 'Mark Unknown'
$dsSendOn=New-DsButton $dsTools 'Turn On';$dsSendOff=New-DsButton $dsTools 'Turn Off'
$dsList=New-Object System.Windows.Forms.ListView;$dsList.Dock='Fill';$dsList.View='Details';$dsList.FullRowSelect=$true;$dsList.MultiSelect=$false;$dsList.HideSelection=$false
$dsList.Scrollable=$true
foreach($col in @(@('Device',230),@('State',95),@('Updated',150),@('Source',280))){[void]$dsList.Columns.Add([string]$col[0],[int]$col[1])}
$dsRoot.Controls.Add($dsList,0,2)
$dsProfile=New-Object System.Windows.Forms.GroupBox;$dsProfile.Text='IR power behavior';$dsProfile.Dock='Fill';$dsRoot.Controls.Add($dsProfile,0,3)
$dsFields=New-Object System.Windows.Forms.TableLayoutPanel;$dsFields.Dock='Fill';$dsFields.ColumnCount=2;$dsFields.RowCount=0;$dsFields.AutoScroll=$true
[void]$dsFields.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute',180)));[void]$dsFields.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent',100)));$dsProfile.Controls.Add($dsFields)
$dsOnCommand=New-Object System.Windows.Forms.ComboBox;$dsOnCommand.DropDownStyle='DropDownList';New-DsRow $dsFields 'ON command' $dsOnCommand
$dsOffCommand=New-Object System.Windows.Forms.ComboBox;$dsOffCommand.DropDownStyle='DropDownList';New-DsRow $dsFields 'OFF command' $dsOffCommand
$dsOffDetails=New-Object System.Windows.Forms.FlowLayoutPanel;$dsOffDetails.AutoSize=$true
$dsCount=New-Object System.Windows.Forms.NumericUpDown;$dsCount.Minimum=1;$dsCount.Maximum=10;$dsCount.Width=60;$dsOffDetails.Controls.Add($dsCount)
$dsDelayText=New-Object System.Windows.Forms.Label;$dsDelayText.Text='presses; seconds between:';$dsDelayText.AutoSize=$true;$dsDelayText.Margin=New-Object System.Windows.Forms.Padding(8,6,8,0);$dsOffDetails.Controls.Add($dsDelayText)
$dsDelay=New-Object System.Windows.Forms.NumericUpDown;$dsDelay.Minimum=0;$dsDelay.Maximum=30;$dsDelay.Width=60;$dsOffDetails.Controls.Add($dsDelay);New-DsRow $dsFields 'OFF sequence' $dsOffDetails
$dsOutputs=New-Object System.Windows.Forms.TextBox;New-DsRow $dsFields 'IR outputs (001, 002...)' $dsOutputs
$dsDiscrete=New-Object System.Windows.Forms.CheckBox;$dsDiscrete.Text='Separate ON and OFF signals (safe even when state is unknown)';$dsDiscrete.AutoSize=$true;New-DsRow $dsFields 'Power signal type' $dsDiscrete
$dsSave=New-Object System.Windows.Forms.Button;$dsSave.Text='Save to Tower';$dsSave.Size=New-Object System.Drawing.Size(160,36)
# A fixed-height row prevents the last AutoSize row stretching the button.
$dsSaveRow=$dsFields.RowCount;$dsFields.RowCount++
[void]$dsFields.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',48)))
$dsSave.Anchor=[System.Windows.Forms.AnchorStyles]::None
$dsFields.Controls.Add($dsSave,0,$dsSaveRow);$dsFields.SetColumnSpan($dsSave,2)
$dsFields.RowCount++
[void]$dsFields.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',100)))
# Keep the editor visible as fonts/DPI change; only the list gives up height.
$dsProfile.Add_Layout({
    $wanted=20
    for($r=0;$r -lt $dsSaveRow;$r++) {
        $rowHeight=0
        for($c=0;$c -lt 2;$c++) {
            $control=$dsFields.GetControlFromPosition($c,$r)
            if($null -ne $control) {
                $preferred=$control.GetPreferredSize((New-Object System.Drawing.Size([Math]::Max(1,$control.Width),0)))
                $rowHeight=[Math]::Max($rowHeight,$preferred.Height+$control.Margin.Vertical)
            }
        }
        $wanted+=$rowHeight
    }
    $wanted+=$dsFields.RowStyles[$dsSaveRow].Height+12
    $wanted=[Math]::Max(330,$wanted)
    if([Math]::Abs($dsRoot.RowStyles[3].Height-$wanted) -gt 1){$dsRoot.RowStyles[3].Height=$wanted}
})
function Get-DsSelected {if($dsList.SelectedItems.Count -eq 0){throw 'Select a device first.'};return $dsList.SelectedItems[0].Tag}
function Refresh-DsDevices {
    $selected=if($dsList.SelectedItems.Count){[string]$dsList.SelectedItems[0].Tag.id}else{''}
    $response=Invoke-TowerGet '/api/v1/control/device-states'
    $dsList.BeginUpdate();$dsList.Items.Clear()
    foreach($d in @($response.document.devices)) {
        $row=New-Object System.Windows.Forms.ListViewItem([string]$d.name);$row.Tag=$d
        [void]$row.SubItems.Add([string]$d.state)
        $date=if([long]$d.updated -gt 0){[DateTimeOffset]::FromUnixTimeSeconds([long]$d.updated).LocalDateTime.ToString('dd-MM HH:mm:ss')}else{'Never'}
        [void]$row.SubItems.Add($date);[void]$row.SubItems.Add([string]$d.source)
        $row.ForeColor=if($d.state -eq 'on'){[Drawing.Color]::ForestGreen}elseif($d.state -eq 'off'){[Drawing.Color]::Firebrick}else{[Drawing.Color]::DarkOrange}
        [void]$dsList.Items.Add($row);if([string]$d.id -eq $selected){$row.Selected=$true}
    }
    $dsList.EndUpdate()
}
function Show-DsProfile {
    if($dsList.SelectedItems.Count -eq 0){return}
    $script:dsPopulating=$true
    try {
        $d=Get-DsSelected;$dsProfile.Enabled=([string]$d.id).StartsWith('ir:')
        $dsOnCommand.Items.Clear();$dsOffCommand.Items.Clear()
        if(-not $dsProfile.Enabled){return}
        $catalog=(Invoke-TowerGet '/api/v1/voice/catalog').catalog
        $device=@($catalog.irDevices|Where-Object{[string]$_.id -eq ([string]$d.id).Substring(3)})|Select-Object -First 1
        foreach($c in @($device.commands)){[void]$dsOnCommand.Items.Add([string]$c.id);[void]$dsOffCommand.Items.Add([string]$c.id)}
        $p=$d.profile
        $dsOnCommand.SelectedItem=[string]@($p.on)[0].command;$dsOffCommand.SelectedItem=[string]@($p.off)[0].command
        $dsCount.Value=[Math]::Max(1,@($p.off).Count);$dsDelay.Value=if(@($p.off).Count -gt 1){[int]$p.off[1].delay_before_seconds}else{2}
        $dsOutputs.Text=@($p.transmitters|ForEach-Object{([string]$_)-replace '^Tower-IR-TX-',''}) -join ', '
        $dsDiscrete.Checked=[bool]$p.discrete
        if(Get-Command Set-TowerDirty -ErrorAction SilentlyContinue){Set-TowerDirty $dsSave $false}
    } finally {$script:dsPopulating=$false}
}
function Set-DsState([string]$state){$d=Get-DsSelected;[void](Invoke-TowerPost '/api/v1/control/device-states' @{device=[string]$d.id;state=$state});Refresh-DsDevices}
function Send-DsPower([string]$state){$d=Get-DsSelected;[void](Invoke-TowerPost '/api/v1/control/actions' @{actions=@(@{type='device_power';device=[string]$d.id;state=$state})});Refresh-DsDevices}
function Save-DsProfile {
    $d=Get-DsSelected
    if($dsOnCommand.SelectedIndex -lt 0 -or $dsOffCommand.SelectedIndex -lt 0){throw 'Select both power commands.'}
    $on=[string]$dsOnCommand.SelectedItem;$off=[string]$dsOffCommand.SelectedItem
    if($dsDiscrete.Checked -and $on -eq $off){throw 'Separate ON/OFF signals must use different commands.'}
    $steps=@();for($i=0;$i -lt [int]$dsCount.Value;$i++){$steps+=@{command=$off;delay_before_seconds=$(if($i -eq 0){0}else{[int]$dsDelay.Value})}}
    $effects=@{};$effects[$on]='unknown';$effects[$off]='unknown'
    if($dsDiscrete.Checked){$effects[$on]='on';$effects[$off]='off'}elseif($on -eq $off -and $dsCount.Value -eq 1){$effects[$on]='toggle'}
    $outputs=@();foreach($value in ($dsOutputs.Text -split ',')){if($value.Trim()){$n=0;if(-not [int]::TryParse($value.Trim(),[ref]$n) -or $n -lt 1 -or $n -gt 6){throw 'IR outputs must be numbers 001 through 006.'};$outputs+='Tower-IR-TX-{0:000}' -f $n}}
    $profile=@{discrete=$dsDiscrete.Checked;on=@(@{command=$on});off=$steps;effects=$effects;transmitters=$outputs}
    [void](Invoke-TowerPost '/api/v1/control/power-profile' @{device=[string]$d.id;profile=$profile})
    if(Get-Command Set-TowerDirty -ErrorAction SilentlyContinue){Set-TowerDirty $dsSave $false}
    Refresh-DsDevices
}
$dsRefresh.Add_Click({Invoke-DsTask {Refresh-DsDevices}})
$dsMarkOn.Add_Click({Invoke-DsTask {Set-DsState 'on'}});$dsMarkOff.Add_Click({Invoke-DsTask {Set-DsState 'off'}});$dsMarkUnknown.Add_Click({Invoke-DsTask {Set-DsState 'unknown'}})
$dsSendOn.Add_Click({Invoke-DsTask {Send-DsPower 'on'}});$dsSendOff.Add_Click({Invoke-DsTask {Send-DsPower 'off'}})
$dsSave.Add_Click({Invoke-DsTask {Save-DsProfile}});$dsList.Add_SelectedIndexChanged({Invoke-DsTask {Show-DsProfile}})
$dsTab.Add_Enter({Invoke-DsTask {Refresh-DsDevices}})

$ssTab=New-Object System.Windows.Forms.TabPage;$ssTab.Text='Scripts';[void]$tabs.TabPages.Add($ssTab)
$ssRoot=New-Object System.Windows.Forms.TableLayoutPanel;$ssRoot.Dock='Fill';$ssRoot.ColumnCount=1;$ssRoot.RowCount=4
[void]$ssRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',44)))
[void]$ssRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',145)))
[void]$ssRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',100)))
[void]$ssRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',75)));$ssTab.Controls.Add($ssRoot)
$ssTools=New-Object System.Windows.Forms.FlowLayoutPanel;$ssTools.Dock='Fill';$ssRoot.Controls.Add($ssTools,0,0)
$ssChoice=New-Object System.Windows.Forms.ComboBox;$ssChoice.DropDownStyle='DropDownList';$ssChoice.Width=230;$ssTools.Controls.Add($ssChoice)
$ssNew=New-DsButton $ssTools 'New';$ssReload=New-DsButton $ssTools 'Reload';$ssSave=New-DsButton $ssTools 'Save to Tower';$ssRun=New-DsButton $ssTools 'Run';$ssDelete=New-DsButton $ssTools 'Delete'
$ssFields=New-Object System.Windows.Forms.TableLayoutPanel;$ssFields.Dock='Fill';$ssFields.ColumnCount=2;$ssFields.RowCount=0;$ssFields.AutoScroll=$true
[void]$ssFields.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute',160)));[void]$ssFields.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent',100)));$ssRoot.Controls.Add($ssFields,0,1)
$ssName=New-Object System.Windows.Forms.TextBox;New-DsRow $ssFields 'Name' $ssName
$ssKind=New-Object System.Windows.Forms.ComboBox;$ssKind.DropDownStyle='DropDownList';[void]$ssKind.Items.AddRange(@('Bash script','Wake-on-LAN'));New-DsRow $ssFields 'Type' $ssKind
$ssMac=New-Object System.Windows.Forms.TextBox;New-DsRow $ssFields 'MAC address (WOL)' $ssMac
$ssBroadcast=New-Object System.Windows.Forms.TextBox;$ssBroadcast.Text='255.255.255.255';New-DsRow $ssFields 'Broadcast (WOL)' $ssBroadcast
$ssBody=New-Object System.Windows.Forms.TextBox;$ssBody.Multiline=$true;$ssBody.AcceptsTab=$true;$ssBody.AcceptsReturn=$true;$ssBody.ScrollBars='Both';$ssBody.WordWrap=$false;$ssBody.Dock='Fill';$ssBody.Font=New-Object System.Drawing.Font('Consolas',11);$ssRoot.Controls.Add($ssBody,0,2)
$ssResult=New-Object System.Windows.Forms.TextBox;$ssResult.Multiline=$true;$ssResult.ReadOnly=$true;$ssResult.ScrollBars='Vertical';$ssResult.Dock='Fill';$ssResult.Text='Bash runs on the Pi as beheerder, with a 15-second timeout. Use Voice, Control or Remote buttons to call a saved script.';$ssRoot.Controls.Add($ssResult,0,3)
function Refresh-SsScripts {
    $script:ssPopulating=$true
    try {$script:ssRows=@((Invoke-TowerGet '/api/v1/control/scripts').scripts);$ssChoice.Items.Clear();foreach($s in $script:ssRows){[void]$ssChoice.Items.Add([string]$s.name)}}finally{$script:ssPopulating=$false}
}
function New-SsScript {
    $script:ssPopulating=$true
    try{$script:dsScriptId=[Guid]::NewGuid().ToString('N');$ssChoice.SelectedIndex=-1;$ssName.Text='New script';$ssKind.SelectedIndex=0;$ssBody.Text="# Runs on the Raspberry Pi`r`necho 'Hello from Tower'";$ssMac.Clear();$ssBroadcast.Text='255.255.255.255'}finally{$script:ssPopulating=$false}
    if(Get-Command Set-TowerDirty -ErrorAction SilentlyContinue){Set-TowerDirty $ssSave $true}
}
function Save-SsScript {
    if(-not $script:dsScriptId){throw 'Create or select a script first.'}
    $s=@{id=$script:dsScriptId;name=$ssName.Text;kind=$(if($ssKind.SelectedIndex -eq 1){'wol'}else{'bash'});body=$ssBody.Text;mac=$ssMac.Text.Trim();broadcast=$ssBroadcast.Text.Trim();timeout_seconds=15}
    [void](Invoke-TowerPost '/api/v1/control/scripts' @{script=$s})
    if(Get-Command Set-TowerDirty -ErrorAction SilentlyContinue){Set-TowerDirty $ssSave $false}
    $ssResult.Text='Saved on Tower.';Refresh-SsScripts
}
$ssChoice.Add_SelectedIndexChanged({
    if($script:ssPopulating -or $ssChoice.SelectedIndex -lt 0){return}
    $script:ssPopulating=$true
    try{$s=$script:ssRows[$ssChoice.SelectedIndex];$script:dsScriptId=[string]$s.id;$ssName.Text=[string]$s.name;$ssKind.SelectedIndex=if($s.kind -eq 'wol'){1}else{0};$ssBody.Text=[string]$s.body;$ssMac.Text=[string]$s.mac;$ssBroadcast.Text=[string]$s.broadcast;if(Get-Command Set-TowerDirty -ErrorAction SilentlyContinue){Set-TowerDirty $ssSave $false}}finally{$script:ssPopulating=$false}
})
$ssKind.Add_SelectedIndexChanged({$ssBody.Enabled=$ssKind.SelectedIndex -eq 0;$ssMac.Enabled=$ssKind.SelectedIndex -eq 1;$ssBroadcast.Enabled=$ssKind.SelectedIndex -eq 1})
$ssNew.Add_Click({New-SsScript});$ssReload.Add_Click({Invoke-DsTask {Refresh-SsScripts}});$ssSave.Add_Click({Invoke-DsTask {Save-SsScript}})
$ssRun.Add_Click({Invoke-DsTask {Save-SsScript;$ssResult.Text='Running...';[System.Windows.Forms.Application]::DoEvents();$r=Invoke-TowerPost '/api/v1/control/scripts/run' @{id=$script:dsScriptId};$ssResult.Text=[string]$r.message}})
$ssDelete.Add_Click({Invoke-DsTask {if(-not $script:dsScriptId){return};if([System.Windows.Forms.MessageBox]::Show('Delete this saved script?','Tower','YesNo','Question') -ne 'Yes'){return};[void](Invoke-TowerPost '/api/v1/control/scripts/delete' @{id=$script:dsScriptId});$script:dsScriptId='';Refresh-SsScripts}})
$ssTab.Add_Enter({Invoke-DsTask {Refresh-SsScripts}})
