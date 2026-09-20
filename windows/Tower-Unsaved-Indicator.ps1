# One unobtrusive icon inside each Save to Tower button; no extra header width.
$script:towerDirtyButtons=@{}
$script:towerDirtyIcon=New-Object System.Drawing.Bitmap(14,14)
$dirtyGraphics=[System.Drawing.Graphics]::FromImage($script:towerDirtyIcon)
$dirtyGraphics.Clear([Drawing.Color]::Transparent)
$dirtyGraphics.FillRectangle([Drawing.Brushes]::Firebrick,1,1,12,12)
$dirtyGraphics.FillRectangle([Drawing.Brushes]::White,4,2,6,4)
$dirtyGraphics.FillRectangle([Drawing.Brushes]::White,3,8,8,4)
$dirtyGraphics.FillRectangle([Drawing.Brushes]::Firebrick,8,2,1,3)
$dirtyGraphics.Dispose()
function Set-TowerDirty($button,[bool]$dirty=$true) {
    if($null -eq $button){return}
    $key=$button.GetHashCode()
    $script:towerDirtyButtons[$key]=@{Button=$button;Dirty=$dirty}
    $button.ImageAlign=[Drawing.ContentAlignment]::MiddleLeft
    $button.TextImageRelation=[System.Windows.Forms.TextImageRelation]::ImageBeforeText
    $button.Image=if($dirty){$script:towerDirtyIcon}else{$null}
}
function Watch-TowerFields($container,$saveButton) {
    foreach($control in $container.Controls) {
        $handler={
            if($this.ContainsFocus -and $this.Enabled){Set-TowerDirty $saveButton $true}
        }.GetNewClosure()
        if($control -is [System.Windows.Forms.TextBox]){$control.Add_TextChanged($handler)}
        elseif($control -is [System.Windows.Forms.ComboBox]){$control.Add_SelectionChangeCommitted($handler)}
        elseif($control -is [System.Windows.Forms.CheckBox]){$control.Add_CheckedChanged($handler)}
        elseif($control -is [System.Windows.Forms.NumericUpDown]){$control.Add_ValueChanged($handler)}
        elseif($control -is [System.Windows.Forms.DateTimePicker]){$control.Add_ValueChanged($handler)}
        if($control.HasChildren){Watch-TowerFields $control $saveButton}
    }
}
function Watch-TowerEditButton($button,$saveButton) {
    if($null -ne $button){$button.Add_Click({Set-TowerDirty $saveButton $true}.GetNewClosure())}
}
Watch-TowerFields $voiceEditor $voiceSaveButton
Watch-TowerFields $controlEditor $controlSaveButton
Watch-TowerFields $remoteEditor $remoteSaveHeader
Watch-TowerFields $dsFields $dsSave
Watch-TowerFields $ssFields $ssSave
Watch-TowerFields $ssRoot $ssSave
foreach($b in @($voiceAddActionButton,$voiceRemoveActionButton,$voiceMoveActionUpButton,$voiceMoveActionDownButton,$voiceAddButton,$voiceDeleteButton)){Watch-TowerEditButton $b $voiceSaveButton}
foreach($b in @($controlAddButton,$controlNewHeaderButton)){Watch-TowerEditButton $b $controlSaveButton}
foreach($b in @($remoteAdd,$remoteNewHeader)){Watch-TowerEditButton $b $remoteSaveHeader}
$script:towerDirtyPhase=$true
$script:towerDirtyTimer=New-Object System.Windows.Forms.Timer
$script:towerDirtyTimer.Interval=900
$script:towerDirtyTimer.Add_Tick({
    $script:towerDirtyPhase=-not $script:towerDirtyPhase
    foreach($entry in $script:towerDirtyButtons.Values){
        if(-not $entry.Button.IsDisposed){$entry.Button.Image=if($entry.Dirty -and $script:towerDirtyPhase){$script:towerDirtyIcon}else{$null}}
    }
})
$script:towerDirtyTimer.Start()
$form.Add_FormClosed({$script:towerDirtyTimer.Stop();$script:towerDirtyTimer.Dispose();$script:towerDirtyIcon.Dispose()})
