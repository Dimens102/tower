Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

# Native top-level window movement avoids pushing every animation frame through
# the managed WinForms SetBounds/layout path.
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class TowerNativeWindow
{
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(
        IntPtr hWnd,
        IntPtr hWndInsertAfter,
        int X,
        int Y,
        int cx,
        int cy,
        uint uFlags
    );

    [DllImport("winmm.dll")]
    public static extern uint timeBeginPeriod(uint uPeriod);

    [DllImport("winmm.dll")]
    public static extern uint timeEndPeriod(uint uPeriod);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int SetWindowRgn(
        IntPtr hWnd,
        IntPtr hRgn,
        bool bRedraw
    );

    [DllImport("gdi32.dll", SetLastError = true)]
    public static extern IntPtr CreateRectRgn(
        int left,
        int top,
        int right,
        int bottom
    );

    [DllImport("gdi32.dll")]
    public static extern bool DeleteObject(IntPtr hObject);

    public const uint SWP_NOSIZE = 0x0001;
    public const uint SWP_NOZORDER = 0x0004;
    public const uint SWP_NOACTIVATE = 0x0010;
    public const uint SWP_NOOWNERZORDER = 0x0200;
}
"@

$ErrorActionPreference = 'Stop'
$configDirectory = Join-Path $env:APPDATA 'Tower'
$configPath = Join-Path $configDirectory 'client.json'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$towerHeaderIconPath = Join-Path $scriptDirectory 'assets\tower-icon-header.png'
$towerTrayIconPath = Join-Path $scriptDirectory 'assets\tower-icon-tray.ico'
$remoteAssetDirectory = Join-Path $scriptDirectory 'assets\remotes'
$deviceAssetDirectory = Join-Path $scriptDirectory 'assets\devices'
$sensorAssetDirectory = Join-Path $scriptDirectory 'assets\sensors'
$logPath = Join-Path $configDirectory 'tower-control.log'

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
    $config | ConvertTo-Json -Depth 6 | Set-Content -Path $configPath -Encoding UTF8
    return $config
}

$config = Get-TowerConfig
if ($null -eq $config) { exit }

# Add UI settings lazily so existing client.json files remain compatible.
if ($null -eq $config.PSObject.Properties['monitorIndex']) {
    $config | Add-Member -NotePropertyName monitorIndex -NotePropertyValue 0
}
if ($null -eq $config.PSObject.Properties['monitorDeviceName']) {
    $config | Add-Member -NotePropertyName monitorDeviceName -NotePropertyValue ''
}
if ($null -eq $config.PSObject.Properties['monitorBoundsX']) {
    $config | Add-Member -NotePropertyName monitorBoundsX -NotePropertyValue 0
}
if ($null -eq $config.PSObject.Properties['monitorBoundsY']) {
    $config | Add-Member -NotePropertyName monitorBoundsY -NotePropertyValue 0
}
if ($null -eq $config.PSObject.Properties['monitorBoundsWidth']) {
    $config | Add-Member -NotePropertyName monitorBoundsWidth -NotePropertyValue 0
}
if ($null -eq $config.PSObject.Properties['monitorBoundsHeight']) {
    $config | Add-Member -NotePropertyName monitorBoundsHeight -NotePropertyValue 0
}
if ($null -eq $config.PSObject.Properties['sidebarWidthPercent']) {
    $config | Add-Member -NotePropertyName sidebarWidthPercent -NotePropertyValue 33
}
if ($null -eq $config.PSObject.Properties['hideDelayMs']) {
    $config | Add-Member -NotePropertyName hideDelayMs -NotePropertyValue 1200
}
if ($null -eq $config.PSObject.Properties['animationDurationMs']) {
    $config | Add-Member -NotePropertyName animationDurationMs -NotePropertyValue 140
}
if ($null -eq $config.PSObject.Properties['showTrayIcon']) {
    $config | Add-Member -NotePropertyName showTrayIcon -NotePropertyValue $true
}

if ($null -eq $config.PSObject.Properties['rfDisplayCount']) {
    $config | Add-Member -NotePropertyName rfDisplayCount -NotePropertyValue 2
}
if ($null -eq $config.PSObject.Properties['irDisplayCount']) {
    $config | Add-Member -NotePropertyName irDisplayCount -NotePropertyValue 12
}
if ($null -eq $config.PSObject.Properties['selectedIrTransmitters']) {
    $config | Add-Member -NotePropertyName selectedIrTransmitters -NotePropertyValue @('Tower-IR-TX-001')
}
if ($null -eq $config.PSObject.Properties['irDeviceOrder']) {
    $config | Add-Member -NotePropertyName irDeviceOrder -NotePropertyValue @()
}
if ($null -eq $config.PSObject.Properties['irCommandLayouts']) {
    $config | Add-Member -NotePropertyName irCommandLayouts -NotePropertyValue @()
}

if ($null -eq $config.PSObject.Properties['rfPreset1Devices']) {
    $config | Add-Member -NotePropertyName rfPreset1Devices -NotePropertyValue @()
}
if ($null -eq $config.PSObject.Properties['rfPreset2Devices']) {
    $config | Add-Member -NotePropertyName rfPreset2Devices -NotePropertyValue @()
}
if ($null -eq $config.PSObject.Properties['rfPreset3Devices']) {
    $config | Add-Member -NotePropertyName rfPreset3Devices -NotePropertyValue @()
}

if ($null -eq $config.PSObject.Properties['rfDeviceViewMode']) {
    $config | Add-Member -NotePropertyName rfDeviceViewMode -NotePropertyValue 'cards'
}
if ([string]$config.rfDeviceViewMode -notin @('cards', 'list')) {
    $config.rfDeviceViewMode = 'cards'
}
if ($null -eq $config.PSObject.Properties['sensorViewMode']) {
    $config | Add-Member -NotePropertyName sensorViewMode -NotePropertyValue 'cards'
}
if ([string]$config.sensorViewMode -notin @('cards', 'list', 'details')) {
    $config.sensorViewMode = 'cards'
}


function Save-TowerConfig {
    New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
    $config | ConvertTo-Json -Depth 6 | Set-Content -Path $configPath -Encoding UTF8
}

$headers = @{ Authorization = "Bearer $($config.token)" }
$script:rfDevices = @()
$script:rfPresetFlows = @{}
$script:rfPresetPowerButtons = @{}
$script:rfPresetOffButtons = @{}
$script:rfDeviceCards = @()
$script:irDevices = @()
$script:irTransmitterButtons = @{}
$script:selectedIrTransmitters = @()
$script:currentIrDevice = $null
$script:denonZoneMode = 'Main'
$script:irLayoutEditMode = $false
$script:irLayoutDeviceId = ''
$script:irLayoutWorking = @{}
$script:irLayoutDraggedEntry = $null
$script:irLayoutSelectedEntry = $null
$script:irLayoutGroupCounts = @{}
$script:irLayoutScopeKey = 'Default'
$script:sensorRefreshFailures = 0
$script:remotePreviewFullTitle = 'Remote'

# Background read state. Read-only API calls run in isolated PowerShell jobs,
# never on the WinForms message thread. Button/send operations keep the proven
# direct POST path because those are short, explicit user actions.
$script:sensorReadJob = $null
$script:irReadJob = $null
$script:irReadQuiet = $false
$script:irStartupRetryCount = 0
$script:rfReadJob = $null
$script:rfReadQuiet = $false
$script:rfStartupRetryCount = 0
$script:piClockSyncJob = $null
$script:piClockHasSync = $false
$script:piClockAnchorText = ''
$script:piClockSyncLocal = [datetime]::MinValue
$script:piClockTimezone = ''
$script:sensorsHaveLoaded = $false
$script:sensorCards = @{}
$script:sensorListItems = @{}
$script:sensorPanelInitialized = $false
$script:irDevicesHaveLoaded = $false
$script:rfDevicesHaveLoaded = $false
$script:rfInventorySignature = ''
$script:irInventorySignature = ''
$script:irCacheLoaded = $false
$script:suppressIrSelectionChanged = $false
$script:renderedIrDeviceId = ''
$script:renderedIrDeviceSignature = ''
$irDeviceCachePath = Join-Path $configDirectory 'ir-devices-cache.json'
$script:rfCacheLoaded = $false
$rfDeviceCachePath = Join-Path $configDirectory 'rf-devices-cache.json'
$customRemoteImageDirectory = Join-Path $configDirectory 'remote-images'


function Get-AvailableIrTransmitters {
    return @(1..6 | ForEach-Object { 'Tower-IR-TX-{0:d3}' -f $_ })
}

function Normalize-IrTransmitterSelection {
    $known = Get-AvailableIrTransmitters
    $selected = @()
    foreach ($name in @($config.selectedIrTransmitters)) {
        $candidate = [string]$name
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if ($known -contains $candidate -and -not ($selected -contains $candidate)) {
            $selected += $candidate
        }
    }
    if ($selected.Count -eq 0) {
        $selected = @('Tower-IR-TX-001')
        $config.selectedIrTransmitters = $selected
        Save-TowerConfig
    }
    $script:selectedIrTransmitters = @($selected)
}

Normalize-IrTransmitterSelection

function Write-TowerLog([string]$level, [string]$message) {
    try {
        New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
        $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        Add-Content -Path $logPath -Encoding UTF8 -Value "$timestamp [$level] $message"
    }
    catch {
        # Logging must never prevent Tower control from operating.
    }
}

function Enable-TowerUiSchedulingBoost {
    try {
        $process = [System.Diagnostics.Process]::GetCurrentProcess()

        # AboveNormal gives the UI better scheduling latency when the machine is
        # busy, without the starvation risk of High/Realtime priority.
        if ($process.PriorityClass -ne
            [System.Diagnostics.ProcessPriorityClass]::AboveNormal) {
            $process.PriorityClass =
                [System.Diagnostics.ProcessPriorityClass]::AboveNormal
        }

        [System.Threading.Thread]::CurrentThread.Priority =
            [System.Threading.ThreadPriority]::AboveNormal

        if (-not $script:highResolutionTimerEnabled) {
            $result = [TowerNativeWindow]::timeBeginPeriod(1)
            if ($result -eq 0) {
                $script:highResolutionTimerEnabled = $true
            }
        }

        Write-TowerLog 'INFO' (
            "UI scheduling boost enabled; process=AboveNormal; " +
            "thread=AboveNormal; timer1ms=$($script:highResolutionTimerEnabled)"
        )
    }
    catch {
        Write-TowerLog 'WARN' (
            "Could not enable full UI scheduling boost: " +
            "$($_.Exception.Message)"
        )
    }
}

function Disable-TowerUiSchedulingBoost {
    if ($script:highResolutionTimerEnabled) {
        try {
            [void][TowerNativeWindow]::timeEndPeriod(1)
        }
        catch {}
        $script:highResolutionTimerEnabled = $false
    }
}

function Move-TowerWindowNative([int]$x, [int]$y) {
    $flags =
        [TowerNativeWindow]::SWP_NOSIZE -bor
        [TowerNativeWindow]::SWP_NOZORDER -bor
        [TowerNativeWindow]::SWP_NOACTIVATE -bor
        [TowerNativeWindow]::SWP_NOOWNERZORDER

    [void][TowerNativeWindow]::SetWindowPos(
        $form.Handle,
        [IntPtr]::Zero,
        $x,
        $y,
        0,
        0,
        [uint32]$flags
    )
}


function Set-SidebarMonitorClip([int]$formX) {
    if ($script:sidebarClipRight -le 0 -or
        $script:sidebarClipHeight -le 0) {
        return
    }

    $visibleWidth = $script:sidebarClipRight - $formX

    if ($visibleWidth -lt 0) {
        $visibleWidth = 0
    }
    if ($visibleWidth -gt $form.Width) {
        $visibleWidth = $form.Width
    }

    # SetWindowRgn takes coordinates relative to the form itself. By clipping
    # the right side at the selected monitor boundary, the form can physically
    # move into an adjacent monitor without any pixels being drawn there.
    $region = [TowerNativeWindow]::CreateRectRgn(
        0,
        0,
        [int]$visibleWidth,
        [int]$script:sidebarClipHeight
    )

    if ($region -eq [IntPtr]::Zero) {
        return
    }

    $accepted = [TowerNativeWindow]::SetWindowRgn(
        $form.Handle,
        $region,
        $true
    )

    # Ownership of a successfully assigned region transfers to Windows.
    if ($accepted -eq 0) {
        [void][TowerNativeWindow]::DeleteObject($region)
    }
}

function Clear-SidebarMonitorClip {
    # NULL region restores the normal full rectangular window.
    [void][TowerNativeWindow]::SetWindowRgn(
        $form.Handle,
        [IntPtr]::Zero,
        $true
    )
}

function New-TowerShapePath(
    [int]$width,
    [int]$height,
    [ValidateSet('Rounded','Chamfer','Pill')]
    [string]$shape) {

    $width = [Math]::Max(2, $width)
    $height = [Math]::Max(2, $height)

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath

    switch ($shape) {
        'Pill' {
            $radius = [Math]::Max(
                2,
                [Math]::Min(
                    [int]($height / 2),
                    [int]($width / 2)
                )
            )
            $diameter = $radius * 2

            $path.AddArc(
                0,
                0,
                $diameter,
                $diameter,
                90,
                180
            )
            $path.AddArc(
                $width - $diameter - 1,
                0,
                $diameter,
                $diameter,
                270,
                180
            )
            $path.CloseFigure()
        }

        'Chamfer' {
            $cut = [Math]::Min(
                10,
                [Math]::Max(
                    4,
                    [int]([Math]::Min($width, $height) / 4)
                )
            )

            $points = [System.Drawing.Point[]]@(
                [System.Drawing.Point]::new($cut, 0),
                [System.Drawing.Point]::new(($width - 1), 0),
                [System.Drawing.Point]::new(
                    ($width - 1),
                    ($height - $cut - 1)
                ),
                [System.Drawing.Point]::new(
                    ($width - $cut - 1),
                    ($height - 1)
                ),
                [System.Drawing.Point]::new(0, ($height - 1)),
                [System.Drawing.Point]::new(0, $cut)
            )

            $path.AddPolygon($points)
            $path.CloseFigure()
        }

        default {
            $radius = [Math]::Min(
                8,
                [Math]::Max(
                    3,
                    [int]([Math]::Min($width, $height) / 4)
                )
            )
            $diameter = $radius * 2

            $path.AddArc(
                0,
                0,
                $diameter,
                $diameter,
                180,
                90
            )
            $path.AddArc(
                $width - $diameter - 1,
                0,
                $diameter,
                $diameter,
                270,
                90
            )
            $path.AddArc(
                $width - $diameter - 1,
                $height - $diameter - 1,
                $diameter,
                $diameter,
                0,
                90
            )
            $path.AddArc(
                0,
                $height - $diameter - 1,
                $diameter,
                $diameter,
                90,
                90
            )
            $path.CloseFigure()
        }
    }

    return $path
}

function Set-TowerControlRegion(
    $control,
    [ValidateSet('Rounded','Chamfer','Pill')]
    [string]$shape) {

    if ($null -eq $control) { return }

    $path = New-TowerShapePath `
        ([int]$control.ClientSize.Width) `
        ([int]$control.ClientSize.Height) `
        $shape

    try {
        $newRegion = New-Object System.Drawing.Region($path)
        $oldRegion = $control.Region
        $control.Region = $newRegion

        if ($null -ne $oldRegion) {
            try { $oldRegion.Dispose() } catch {}
        }
    }
    finally {
        $path.Dispose()
    }
}

function Add-TowerShapeBorder(
    $button,
    [ValidateSet('Rounded','Chamfer','Pill')]
    [string]$shape,
    [System.Drawing.Color]$borderColor) {

    if ($null -eq $button) { return }

    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 0

    # IMPORTANT: never use Control.Tag for styling metadata.
    #
    # Tower Control already relies on Tag for functional data:
    # - IR transmitter identity
    # - IR pressed/base colors
    # - Settings monitor DeviceName
    #
    # Capture the style privately in these event-handler closures instead.
    $capturedShape = [string]$shape
    $capturedBorderColor = $borderColor

    Set-TowerControlRegion $button $capturedShape

    $button.Add_Resize({
        param($sender, $eventArgs)

        Set-TowerControlRegion `
            $sender `
            $capturedShape

        $sender.Invalidate()
    }.GetNewClosure())

    $button.Add_Paint({
        param($sender, $eventArgs)

        # A 1px pen centered directly on the Region boundary gets partially
        # clipped by Windows. That was especially obvious on the unfilled
        # Settings chamfer buttons: the left/right vertical edges disappeared.
        #
        # Keep the Region itself full-sized, but draw the visible outline 1px
        # inward so every segment remains inside the clipped Region.
        $paintWidth = [int]($sender.ClientSize.Width - 1)
        $paintHeight = [int]($sender.ClientSize.Height - 1)
        $translate = $false

        if ($capturedShape -eq 'Chamfer' -or
            $capturedShape -eq 'Rounded' -or
            $capturedShape -eq 'Pill') {
            # Keep the anti-aliased outline fully inside the clipped control
            # region. A line centered on the Region boundary loses half of its
            # pixels and makes rounded IR buttons look soft/jagged.
            $paintWidth = [Math]::Max(
                2,
                [int]($sender.ClientSize.Width - 3)
            )
            $paintHeight = [Math]::Max(
                2,
                [int]($sender.ClientSize.Height - 3)
            )
            $translate = $true
        }

        $path = New-TowerShapePath `
            $paintWidth `
            $paintHeight `
            $capturedShape

        try {
            if ($translate) {
                $matrix =
                    New-Object System.Drawing.Drawing2D.Matrix
                try {
                    $matrix.Translate(1.0, 1.0)
                    $path.Transform($matrix)
                }
                finally {
                    $matrix.Dispose()
                }
            }

            $eventArgs.Graphics.SmoothingMode =
                [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

            $pen = New-Object System.Drawing.Pen(
                $capturedBorderColor,
                1.0
            )

            try {
                $eventArgs.Graphics.DrawPath($pen, $path)
            }
            finally {
                $pen.Dispose()
            }
        }
        finally {
            $path.Dispose()
        }
    }.GetNewClosure())
}

function Set-IrButtonVisualStyle($button) {
    if ($null -eq $button) { return }

    Add-TowerShapeBorder `
        $button `
        'Rounded' `
        ([System.Drawing.Color]::FromArgb(155, 155, 165))
}

function Set-SettingsButtonVisualStyle(
    $button,
    [bool]$selected) {

    if ($null -eq $button) { return }

    if ($selected) {
        $button.BackColor = [System.Drawing.Color]::SteelBlue
        $button.ForeColor = [System.Drawing.Color]::White
    }
    else {
        $button.BackColor = [System.Drawing.Color]::White
        $button.ForeColor = [System.Drawing.Color]::SteelBlue
    }

    Add-TowerShapeBorder `
        $button `
        'Chamfer' `
        ([System.Drawing.Color]::SteelBlue)
}

function Get-RfBlendColor(
    [System.Drawing.Color]$baseColor,
    [System.Drawing.Color]$overlayColor,
    [double]$amount) {

    if ($amount -lt 0.0) { $amount = 0.0 }
    if ($amount -gt 1.0) { $amount = 1.0 }

    $inverse = 1.0 - $amount

    return [System.Drawing.Color]::FromArgb(
        $baseColor.A,
        [int](($baseColor.R * $inverse) + ($overlayColor.R * $amount)),
        [int](($baseColor.G * $inverse) + ($overlayColor.G * $amount)),
        [int](($baseColor.B * $inverse) + ($overlayColor.B * $amount))
    )
}

function Set-RfSmoothButtonAppearance(
    $button,
    [System.Drawing.Color]$fillColor,
    [System.Drawing.Color]$textColor,
    [System.Drawing.Color]$borderColor) {

    if ($null -eq $button) { return }

    $button.RfFillColor = $fillColor
    $button.RfBorderColor = $borderColor
    $button.ForeColor = $textColor
    $button.Invalidate()
}

function New-RfSmoothButton(
    [string]$text,
    [int]$width,
    [int]$height,
    [System.Drawing.Color]$fillColor,
    [System.Drawing.Color]$textColor =
        [System.Drawing.SystemColors]::ControlText,
    [System.Drawing.Color]$borderColor =
        [System.Drawing.Color]::FromArgb(125, 105, 165)) {

    # Use a plain Panel instead of a WinForms Button. Nothing is clipped.
    # The pill, border and text are all painted directly with anti-aliasing.
    $button = New-Object System.Windows.Forms.Panel
    $button.Size = New-Object System.Drawing.Size($width, $height)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Text = $text
    $button.ForeColor = $textColor
    $button.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $button.TabStop = $false

    $button |
        Add-Member -NotePropertyName RfFillColor -NotePropertyValue $fillColor
    $button |
        Add-Member -NotePropertyName RfBorderColor -NotePropertyValue $borderColor
    $button |
        Add-Member -NotePropertyName RfHover -NotePropertyValue $false
    $button |
        Add-Member -NotePropertyName RfPressed -NotePropertyValue $false

    # The rectangular control background is made identical to its parent.
    # Only the anti-aliased pill drawn inside remains visible.
    $button.Add_ParentChanged({
        param($sender, $eventArgs)

        if ($null -ne $sender.Parent) {
            $sender.BackColor = $sender.Parent.BackColor
        }
    })

    $button.Add_MouseEnter({
        param($sender, $eventArgs)

        if ($sender.Enabled) {
            $sender.RfHover = $true
            $sender.Invalidate()
        }
    })

    $button.Add_MouseLeave({
        param($sender, $eventArgs)

        $sender.RfHover = $false
        $sender.RfPressed = $false
        $sender.Invalidate()
    })

    $button.Add_MouseDown({
        param($sender, $eventArgs)

        if ($sender.Enabled -and
            $eventArgs.Button -eq
                [System.Windows.Forms.MouseButtons]::Left) {
            $sender.RfPressed = $true
            $sender.Invalidate()
        }
    })

    $button.Add_MouseUp({
        param($sender, $eventArgs)

        $sender.RfPressed = $false
        $sender.Invalidate()
    })

    $button.Add_EnabledChanged({
        param($sender, $eventArgs)

        $sender.Invalidate()
    })

    $button.Add_Resize({
        param($sender, $eventArgs)

        $sender.Invalidate()
    })

    $button.Add_Paint({
        param($sender, $eventArgs)

        $eventArgs.Graphics.SmoothingMode =
            [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $eventArgs.Graphics.PixelOffsetMode =
            [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

        $fill = [System.Drawing.Color]$sender.RfFillColor

        if (-not $sender.Enabled) {
            $fill = Get-RfBlendColor `
                $fill `
                ([System.Drawing.Color]::FromArgb(240, 240, 240)) `
                0.58
        }
        elseif ($sender.RfPressed) {
            $fill = Get-RfBlendColor `
                $fill `
                ([System.Drawing.Color]::Black) `
                0.10
        }
        elseif ($sender.RfHover) {
            $fill = Get-RfBlendColor `
                $fill `
                ([System.Drawing.Color]::White) `
                0.14
        }

        # Paint 1px inside the rectangular control. Since there is no Region
        # clipping, the anti-aliased edge remains intact.
        $path = New-TowerShapePath `
            ([Math]::Max(2, [int]($sender.ClientSize.Width - 3))) `
            ([Math]::Max(2, [int]($sender.ClientSize.Height - 3))) `
            'Pill'

        try {
            $matrix = New-Object System.Drawing.Drawing2D.Matrix
            try {
                $matrix.Translate(1.0, 1.0)
                $path.Transform($matrix)
            }
            finally {
                $matrix.Dispose()
            }

            $brush = New-Object System.Drawing.SolidBrush($fill)
            try {
                $eventArgs.Graphics.FillPath($brush, $path)
            }
            finally {
                $brush.Dispose()
            }

            $pen = New-Object System.Drawing.Pen(
                ([System.Drawing.Color]$sender.RfBorderColor),
                1.0
            )
            try {
                $eventArgs.Graphics.DrawPath($pen, $path)
            }
            finally {
                $pen.Dispose()
            }

            $textRectangle = New-Object System.Drawing.Rectangle(
                8,
                1,
                [Math]::Max(1, $sender.ClientSize.Width - 16),
                [Math]::Max(1, $sender.ClientSize.Height - 2)
            )

            $flags =
                [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor
                [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
                [System.Windows.Forms.TextFormatFlags]::SingleLine -bor
                [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor
                [System.Windows.Forms.TextFormatFlags]::NoPrefix

            $drawColor =
                if ($sender.Enabled) {
                    $sender.ForeColor
                }
                else {
                    [System.Drawing.SystemColors]::GrayText
                }

            [System.Windows.Forms.TextRenderer]::DrawText(
                $eventArgs.Graphics,
                [string]$sender.Text,
                $sender.Font,
                $textRectangle,
                $drawColor,
                $flags
            )
        }
        finally {
            $path.Dispose()
        }
    })

    return $button
}

function Set-RfButtonVisualStyle($button) {
    # Retained as a compatibility no-op for old call sites while v35 migrates
    # every actual RF button to New-RfSmoothButton.
    if ($null -eq $button) { return }

    if ($null -ne $button.PSObject.Properties['RfFillColor']) {
        $button.Invalidate()
    }
}


function Get-TowerHttpErrorDetails(
    [System.Management.Automation.ErrorRecord]$errorRecord,
    [string]$method,
    [string]$path,
    [hashtable]$content = $null) {

    $statusCode = $null
    $statusDescription = ''
    $responseBody = ''
    $towerStatus = ''
    $towerTransport = ''
    $towerMessage = ''
    $towerError = ''

    try {
        if ($null -ne $errorRecord.Exception.Response) {
            $response = $errorRecord.Exception.Response

            try {
                $statusCode = [int]$response.StatusCode
            } catch {}

            try {
                $statusDescription = [string]$response.StatusDescription
            } catch {}

            # Windows PowerShell 5.1 exposes the HTTP response stream here.
            try {
                $stream = $response.GetResponseStream()
                if ($null -ne $stream) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $responseBody = $reader.ReadToEnd()
                    $reader.Dispose()
                }
            } catch {}
        }

        # In some PowerShell versions Invoke-RestMethod puts the response body here.
        if ([string]::IsNullOrWhiteSpace($responseBody) -and
            $null -ne $errorRecord.ErrorDetails -and
            -not [string]::IsNullOrWhiteSpace($errorRecord.ErrorDetails.Message)) {
            $responseBody = [string]$errorRecord.ErrorDetails.Message
        }

        if (-not [string]::IsNullOrWhiteSpace($responseBody)) {
            try {
                $parsed = $responseBody | ConvertFrom-Json
                if ($null -ne $parsed.status)    { $towerStatus = [string]$parsed.status }
                if ($null -ne $parsed.transport) { $towerTransport = [string]$parsed.transport }
                if ($null -ne $parsed.message)   { $towerMessage = [string]$parsed.message }
                if ($null -ne $parsed.error)     { $towerError = [string]$parsed.error }
            } catch {}
        }
    }
    catch {}

    $requestSummary = ''
    if ($null -ne $content) {
        try {
            $requestSummary = ($content | ConvertTo-Json -Compress)
        } catch {
            $requestSummary = '<unable to serialize request body>'
        }
    }

    $health = 'not checked'
    try {
        $healthResponse = Invoke-RestMethod -Method Get `
            -Uri "$($config.server)/api/v1/status" `
            -DisableKeepAlive `
            -TimeoutSec 3
        $health = "$($healthResponse.status) v$($healthResponse.version)"
    }
    catch {
        $health = "FAILED: $($_.Exception.Message)"
    }

    $httpText = if ($null -ne $statusCode) {
        "HTTP $statusCode $statusDescription".Trim()
    } else {
        'No HTTP status available'
    }

    $bestMessage = $towerMessage
    if ([string]::IsNullOrWhiteSpace($bestMessage)) { $bestMessage = $towerError }
    if ([string]::IsNullOrWhiteSpace($bestMessage)) { $bestMessage = $errorRecord.Exception.Message }

    $lines = @(
        "$method $path failed",
        $httpText,
        "Tower status: $towerStatus",
        "Transport: $towerTransport",
        "Message: $bestMessage",
        "Tower health: $health",
        "Log: $logPath"
    )

    $logLine = "$method $path | $httpText | towerStatus=$towerStatus | transport=$towerTransport | message=$bestMessage | health=$health"
    if (-not [string]::IsNullOrWhiteSpace($requestSummary)) {
        $logLine += " | request=$requestSummary"
    }
    if (-not [string]::IsNullOrWhiteSpace($responseBody)) {
        $logLine += " | response=$responseBody"
    }
    Write-TowerLog 'ERROR' $logLine

    return [pscustomobject]@{
        Text = ($lines -join "`r`n")
        StatusCode = $statusCode
        TowerStatus = $towerStatus
        Transport = $towerTransport
        Message = $bestMessage
        Health = $health
        ResponseBody = $responseBody
    }
}

function Invoke-TowerGet([string]$path) {
    return Invoke-RestMethod -Method Get `
        -Uri "$($config.server)$path" `
        -Headers $headers `
        -DisableKeepAlive `
        -TimeoutSec 5
}

function Start-TowerReadJob([string]$path) {
    $server = [string]$config.server
    $token = [string]$config.token

    return Start-Job -ArgumentList $server, $token, $path -ScriptBlock {
        param($server, $token, $path)

        $ErrorActionPreference = 'Stop'

        # Tower is a LAN service. Do not let Windows proxy/WPAD discovery hold
        # this background worker for minutes before the local request starts.
        try {
            [System.Net.WebRequest]::DefaultWebProxy = $null
        }
        catch {}

        $jobHeaders = @{ Authorization = "Bearer $token" }
        Invoke-RestMethod -Method Get `
            -Uri "$server$path" `
            -Headers $jobHeaders `
            -DisableKeepAlive `
            -TimeoutSec 10
    }
}

function Get-TowerReadJobError($job) {
    if ($null -eq $job) { return 'Unknown background read error.' }

    try {
        $reason = $job.ChildJobs[0].JobStateInfo.Reason
        if ($null -ne $reason -and
            -not [string]::IsNullOrWhiteSpace([string]$reason.Message)) {
            return [string]$reason.Message
        }
    }
    catch {}

    try {
        $errors = @($job.ChildJobs[0].Error)
        if ($errors.Count -gt 0) {
            return [string]$errors[-1].Exception.Message
        }
    }
    catch {}

    return "Background read ended with state $($job.State)."
}

function Remove-TowerReadJob($job) {
    if ($null -eq $job) { return }
    try { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } catch {}
}

function Start-PiClockSync {
    if ($null -ne $script:piClockSyncJob) {
        return
    }

    try {
        $script:piClockSyncJob =
            Start-TowerReadJob '/api/v1/system/time'
    }
    catch {
        Write-TowerLog 'WARN' (
            "Could not start Pi clock sync: " +
            "$($_.Exception.Message)"
        )
    }
}

function Complete-PiClockSync {
    if ($null -eq $script:piClockSyncJob) {
        return
    }

    if ($script:piClockSyncJob.State -eq 'Running') {
        return
    }

    $job = $script:piClockSyncJob
    $script:piClockSyncJob = $null

    try {
        if ($job.State -ne 'Completed') {
            throw (Get-TowerReadJobError $job)
        }

        $response =
            Receive-Job -Job $job -ErrorAction Stop

        $anchorText =
            [string]$response.localTime

        if ([string]::IsNullOrWhiteSpace($anchorText)) {
            throw 'Pi time response did not contain localTime.'
        }

        # Validate the Pi-provided clock string before accepting the sync.
        [void][datetime]::ParseExact(
            $anchorText,
            'HH:mm:ss',
            [System.Globalization.CultureInfo]::InvariantCulture
        )

        $script:piClockAnchorText = $anchorText
        $script:piClockSyncLocal = [datetime]::Now
        $script:piClockTimezone =
            [string]$response.timezone
        $script:piClockHasSync = $true
    }
    catch {
        Write-TowerLog 'WARN' (
            "Pi clock sync failed: " +
            "$($_.Exception.Message)"
        )
    }
    finally {
        Remove-TowerReadJob $job
    }
}

function Get-PiClockDisplayText {
    if (-not $script:piClockHasSync) {
        return '--:--:--'
    }

    try {
        $anchor =
            [datetime]::ParseExact(
                $script:piClockAnchorText,
                'HH:mm:ss',
                [System.Globalization.CultureInfo]::InvariantCulture
            )

        $elapsed =
            [datetime]::Now -
            $script:piClockSyncLocal

        return $anchor.Add(
            $elapsed
        ).ToString('HH:mm:ss')
    }
    catch {
        return '--:--:--'
    }
}

function Start-TowerPostJob(
    [string]$path,
    [hashtable]$content,
    [int]$timeoutSec = 30) {

    $server = [string]$config.server
    $token = [string]$config.token
    $body = $content | ConvertTo-Json -Compress

    return Start-Job `
        -ArgumentList $server, $token, $path, $body, $timeoutSec `
        -ScriptBlock {

        param(
            $server,
            $token,
            $path,
            $body,
            $timeoutSec
        )

        $ErrorActionPreference = 'Stop'

        try {
            [System.Net.WebRequest]::DefaultWebProxy = $null
        }
        catch {}

        $jobHeaders = @{
            Authorization = "Bearer $token"
        }

        Invoke-RestMethod `
            -Method Post `
            -Uri "$server$path" `
            -Headers $jobHeaders `
            -ContentType 'application/json' `
            -Body $body `
            -DisableKeepAlive `
            -TimeoutSec $timeoutSec
    }
}

function Invoke-TowerPost([string]$path, [hashtable]$content) {
    $body = $content | ConvertTo-Json -Compress
    Write-TowerLog 'INFO' "POST $path request=$body"
    $response = Invoke-RestMethod -Method Post `
        -Uri "$($config.server)$path" `
        -Headers $headers `
        -ContentType 'application/json' `
        -Body $body `
        -DisableKeepAlive `
        -TimeoutSec 20
    Write-TowerLog 'INFO' "POST $path succeeded"
    return $response
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Tower Control'
$form.StartPosition = 'Manual'
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.ShowInTaskbar = $false
$form.TopMost = $true
$form.MinimumSize = New-Object System.Drawing.Size(0, 0)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

# Sidebar state.
$script:sidebarVisible = $false
$script:sidebarAnimating = $false
$script:lastInsideAt = [DateTime]::Now
$script:targetScreen = $null
$script:openBounds = $null
$script:hiddenBounds = $null

# Native, timer-driven sidebar animation state.
$script:sidebarAnimationTimer = $null
$script:sidebarAnimationClock = New-Object System.Diagnostics.Stopwatch
$script:sidebarAnimationShow = $false
$script:sidebarAnimationStartX = 0
$script:sidebarAnimationEndX = 0
$script:sidebarAnimationY = 0
$script:sidebarAnimationDurationMs = 0
$script:sidebarClipRight = 0
$script:sidebarClipHeight = 0
$script:highResolutionTimerEnabled = $false

$script:lastDisplayTopologySignature = ''
$script:displayTopologyQuietUntil = [DateTime]::MinValue
$script:lastMissingDisplayLogAt = [DateTime]::MinValue

function Get-OrderedScreens {
    return @(
        [System.Windows.Forms.Screen]::AllScreens |
            Sort-Object `
                @{ Expression = { $_.Bounds.Left } }, `
                @{ Expression = { $_.Bounds.Top } }, `
                @{ Expression = { $_.DeviceName } }
    )
}

function Get-DisplayTopologySignature {
    $parts = @()

    foreach ($screen in Get-OrderedScreens) {
        $b = $screen.Bounds
        $w = $screen.WorkingArea
        $parts += (
            "$($screen.DeviceName):" +
            "$($b.X),$($b.Y),$($b.Width),$($b.Height):" +
            "$($w.X),$($w.Y),$($w.Width),$($w.Height):" +
            "$($screen.Primary)"
        )
    }

    return ($parts -join '|')
}

function Save-TargetScreenIdentity($screen) {
    if ($null -eq $screen) { return }

    $config.monitorDeviceName = [string]$screen.DeviceName
    $config.monitorBoundsX = [int]$screen.Bounds.X
    $config.monitorBoundsY = [int]$screen.Bounds.Y
    $config.monitorBoundsWidth = [int]$screen.Bounds.Width
    $config.monitorBoundsHeight = [int]$screen.Bounds.Height

    $ordered = Get-OrderedScreens
    for ($i = 0; $i -lt $ordered.Count; $i++) {
        if ([string]$ordered[$i].DeviceName -eq
            [string]$screen.DeviceName) {
            $config.monitorIndex = $i
            break
        }
    }

    Save-TowerConfig
}

function Get-TargetScreen {
    $screens = Get-OrderedScreens
    if ($screens.Count -eq 0) { return $null }

    $savedDeviceName = [string]$config.monitorDeviceName

    # Normal path: bind by Windows display device name. Unlike array index,
    # this survives Screen.AllScreens enumeration-order changes.
    if (-not [string]::IsNullOrWhiteSpace($savedDeviceName)) {
        foreach ($screen in $screens) {
            if ([string]$screen.DeviceName -eq $savedDeviceName) {
                return $screen
            }
        }

        # If Windows recreated the display object but restored exactly the same
        # geometry, rebind to it automatically and store its new DeviceName.
        foreach ($screen in $screens) {
            if ([int]$screen.Bounds.X -eq
                    [int]$config.monitorBoundsX -and
                [int]$screen.Bounds.Y -eq
                    [int]$config.monitorBoundsY -and
                [int]$screen.Bounds.Width -eq
                    [int]$config.monitorBoundsWidth -and
                [int]$screen.Bounds.Height -eq
                    [int]$config.monitorBoundsHeight) {

                Save-TargetScreenIdentity $screen
                return $screen
            }
        }

        # Important: while TeamViewer is changing the display topology, do NOT
        # silently fall back to another monitor. Stay hidden until the selected
        # physical display returns.
        return $null
    }

    # Legacy migration. Interpret Monitor 1/2/3 in spatial left-to-right order
    # instead of WinForms enumeration order, then persist the physical identity.
    $index = [int]$config.monitorIndex
    if ($index -lt 0 -or $index -ge $screens.Count) {
        $index = 0
    }

    $screen = $screens[$index]
    Save-TargetScreenIdentity $screen
    return $screen
}

function Hide-SidebarImmediately {
    if ($null -ne $script:sidebarAnimationTimer) {
        $script:sidebarAnimationTimer.Stop()
    }
    $script:sidebarAnimationClock.Stop()
    $script:sidebarAnimating = $false
    $script:sidebarVisible = $false
    $form.Opacity = 0

    if ($null -ne $script:hiddenBounds) {
        try {
            $form.Bounds = $script:hiddenBounds

            if ($null -ne $script:targetScreen) {
                $script:sidebarClipRight =
                    [int]$script:targetScreen.WorkingArea.Right
                $script:sidebarClipHeight = [int]$form.Height
                Set-SidebarMonitorClip $script:hiddenBounds.X
            }
        }
        catch {}
    }
}

function Handle-DisplayTopologyChange {
    $signature = Get-DisplayTopologySignature

    if ([string]::IsNullOrWhiteSpace(
            $script:lastDisplayTopologySignature)) {
        $script:lastDisplayTopologySignature = $signature
        return $false
    }

    if ($signature -eq $script:lastDisplayTopologySignature) {
        return $false
    }

    $oldSignature = $script:lastDisplayTopologySignature
    $script:lastDisplayTopologySignature = $signature

    Write-TowerLog 'INFO' (
        "Display topology changed. old=$oldSignature new=$signature"
    )

    # TeamViewer can produce several rapid display events. Stop edge animation,
    # hide completely, then wait for Windows to settle before accepting another
    # edge trigger.
    Hide-SidebarImmediately
    $script:displayTopologyQuietUntil =
        [DateTime]::Now.AddMilliseconds(1500)
    $script:lastInsideAt = [DateTime]::Now

    Refresh-MonitorButtons
    Update-SidebarBounds

    return $true
}

function Update-SidebarBounds {
    $script:targetScreen = Get-TargetScreen

    if ($null -eq $script:targetScreen) {
        Hide-SidebarImmediately

        if (([DateTime]::Now -
                $script:lastMissingDisplayLogAt).TotalSeconds -ge 5) {
            Write-TowerLog 'INFO' (
                "Selected display is temporarily unavailable; " +
                "Tower Control will stay hidden until it returns."
            )
            $script:lastMissingDisplayLogAt = [DateTime]::Now
        }

        $script:openBounds = $null
        $script:hiddenBounds = $null
        return $false
    }

    $area = $script:targetScreen.WorkingArea

    $percent = [int]$config.sidebarWidthPercent
    if ($percent -lt 20) { $percent = 20 }
    if ($percent -gt 80) { $percent = 80 }

    $width = [Math]::Max(420, [int][Math]::Round($area.Width * ($percent / 100.0)))
    $width = [Math]::Min($width, $area.Width)

    $script:openBounds = New-Object System.Drawing.Rectangle(
        ($area.Right - $width), $area.Top, $width, $area.Height)

    # Hidden mode has no visible pixels at all. The form sits completely beyond
    # the right edge and is transparent; the polling timer watches the cursor.
    $script:hiddenBounds = New-Object System.Drawing.Rectangle(
        $area.Right, $area.Top, $width, $area.Height)

    if (-not $script:sidebarVisible -and -not $script:sidebarAnimating) {
        $form.Bounds = $script:hiddenBounds
        $form.Opacity = 0
    }

    return $true
}

function Finish-SidebarAnimation {
    if ($null -ne $script:sidebarAnimationTimer) {
        $script:sidebarAnimationTimer.Stop()
    }
    $script:sidebarAnimationClock.Stop()

    Move-TowerWindowNative `
        $script:sidebarAnimationEndX `
        $script:sidebarAnimationY

    if ($script:sidebarAnimationShow) {
        # Fully visible again: remove the temporary clipping region.
        Clear-SidebarMonitorClip
        $form.Opacity = 1
        $form.TopMost = $true
        $script:sidebarVisible = $true
        $script:lastInsideAt = [DateTime]::Now
    }
    else {
        # Keep it fully clipped while hidden. Opacity is still set to zero as
        # a second layer of protection against display-topology oddities.
        Set-SidebarMonitorClip $script:sidebarAnimationEndX
        $form.Opacity = 0
        $script:sidebarVisible = $false
    }

    $script:sidebarAnimating = $false
}

function Update-SidebarAnimationFrame {
    if (-not $script:sidebarAnimating) {
        if ($null -ne $script:sidebarAnimationTimer) {
            $script:sidebarAnimationTimer.Stop()
        }
        return
    }

    $duration = [double]$script:sidebarAnimationDurationMs
    if ($duration -le 0) {
        Finish-SidebarAnimation
        return
    }

    # Progress is based on real elapsed time, not on how many timer callbacks
    # happened. A delayed frame therefore catches up instead of stretching the
    # animation and producing the characteristic PowerShell stutter.
    $progress =
        $script:sidebarAnimationClock.Elapsed.TotalMilliseconds / $duration

    if ($progress -ge 1.0) {
        Finish-SidebarAnimation
        return
    }

    if ($progress -lt 0.0) { $progress = 0.0 }

    # Smoothstep easing.
    $ease = $progress * $progress * (3.0 - (2.0 * $progress))
    $x = [int][Math]::Round(
        $script:sidebarAnimationStartX +
        (($script:sidebarAnimationEndX -
          $script:sidebarAnimationStartX) * $ease)
    )

    Move-TowerWindowNative $x $script:sidebarAnimationY
    Set-SidebarMonitorClip $x
}

function Initialize-SidebarAnimationTimer {
    if ($null -ne $script:sidebarAnimationTimer) { return }

    $script:sidebarAnimationTimer =
        New-Object System.Windows.Forms.Timer

    # ~100 Hz request. Windows/WinForms may coalesce callbacks, but elapsed-time
    # positioning keeps the motion correct even when some frames are skipped.
    $script:sidebarAnimationTimer.Interval = 10
    $script:sidebarAnimationTimer.Add_Tick({
        Update-SidebarAnimationFrame
    })
}

function Animate-Sidebar([bool]$show) {
    if ($script:sidebarAnimating) { return }

    if (-not (Update-SidebarBounds)) {
        return
    }

    if ([DateTime]::Now -lt $script:displayTopologyQuietUntil) {
        return
    }

    Initialize-SidebarAnimationTimer

    $duration = [int]$config.animationDurationMs
    if ($duration -lt 0) { $duration = 0 }
    if ($duration -gt 1000) { $duration = 1000 }

    $script:sidebarAnimationShow = $show
    $script:sidebarAnimationDurationMs = $duration
    $script:sidebarAnimationY = $script:openBounds.Y

    # Clip against the selected monitor's right edge rather than the Windows
    # virtual desktop. This is what makes the sidebar disappear "behind" the
    # selected screen edge even when another physical monitor exists there.
    $script:sidebarClipRight = [int]$script:targetScreen.WorkingArea.Right
    $script:sidebarClipHeight = [int]$form.Height

    if ($show) {
        # Set size exactly once. Every animation frame after this only changes
        # the top-level window X coordinate through user32 SetWindowPos.
        $form.Bounds = $script:hiddenBounds
        Position-MainLayout

        # Apply a zero-width/edge clip before making the form visible so there
        # is no flash on a neighboring monitor.
        Set-SidebarMonitorClip $script:hiddenBounds.X

        $form.Opacity = 1
        $form.TopMost = $true
        $form.BringToFront()

        $script:sidebarAnimationStartX = $script:hiddenBounds.X
        $script:sidebarAnimationEndX = $script:openBounds.X
    }
    else {
        $script:sidebarAnimationStartX = $form.Left
        $script:sidebarAnimationEndX = $script:hiddenBounds.X
    }

    $script:sidebarAnimating = $true

    if ($duration -eq 0) {
        Finish-SidebarAnimation
        return
    }

    $script:sidebarAnimationClock.Reset()
    $script:sidebarAnimationClock.Start()
    $script:sidebarAnimationTimer.Start()
}

# Optional system tray icon ---------------------------------------------------
$script:trayIcon = $null
$script:towerTrayIcon = $null
$script:towerIconBitmap = $null

function Initialize-TowerIcon {
    if ($null -ne $script:towerTrayIcon) { return }

    try {
        if (Test-Path $towerTrayIconPath) {
            $script:towerTrayIcon = New-Object System.Drawing.Icon($towerTrayIconPath)
        }
    }
    catch {
        Write-TowerLog 'ERROR' "Could not load Tower icon: $($_.Exception.Message)"
    }
}


function Update-TrayIcon {
    if ([bool]$config.showTrayIcon) {
        if ($null -eq $script:trayIcon) {
            $script:trayIcon = New-Object System.Windows.Forms.NotifyIcon
            $script:trayIcon.Text = 'Tower Control'
            Initialize-TowerIcon
            if ($null -ne $script:towerTrayIcon) {
                $script:trayIcon.Icon = $script:towerTrayIcon
            }
            else {
                $script:trayIcon.Icon = [System.Drawing.SystemIcons]::Application
            }

            $trayMenu = New-Object System.Windows.Forms.ContextMenuStrip

            $trayShow = $trayMenu.Items.Add('Show Tower Control')
            $trayShow.Add_Click({
                if (-not $script:sidebarVisible) {
                    Animate-Sidebar $true
                }
                else {
                    $form.TopMost = $true
                    $form.BringToFront()
                }
            })

            $trayHide = $trayMenu.Items.Add('Hide Tower Control')
            $trayHide.Add_Click({
                if ($script:sidebarVisible) { Animate-Sidebar $false }
            })

            $trayRecover = $trayMenu.Items.Add(
                'Recover to rightmost display'
            )
            $trayRecover.Add_Click({
                $screens = Get-OrderedScreens
                if ($screens.Count -gt 0) {
                    $rightmost = $screens[$screens.Count - 1]
                    Save-TargetScreenIdentity $rightmost
                    Refresh-MonitorButtons
                    Hide-SidebarImmediately
                    Update-SidebarBounds
                    $script:displayTopologyQuietUntil =
                        [DateTime]::Now.AddMilliseconds(500)
                }
            })

            [void]$trayMenu.Items.Add('-')

            $trayExit = $trayMenu.Items.Add('Exit')
            $trayExit.Add_Click({ $form.Close() })

            $script:trayIcon.ContextMenuStrip = $trayMenu
            $script:trayIcon.Add_DoubleClick({
                if (-not $script:sidebarVisible) {
                    Animate-Sidebar $true
                }
                else {
                    $form.TopMost = $true
                    $form.BringToFront()
                }
            })
        }
        $script:trayIcon.Visible = $true
    }
    elseif ($null -ne $script:trayIcon) {
        $script:trayIcon.Visible = $false
    }
}

$header = New-Object System.Windows.Forms.Panel
$header.Dock = [System.Windows.Forms.DockStyle]::None
$header.Height = 82
$header.Width = $form.ClientSize.Width
$header.BackColor = [System.Drawing.Color]::FromArgb(35, 42, 52)
$form.Controls.Add($header)

$towerIconPicture = New-Object System.Windows.Forms.PictureBox
$towerIconPicture.Size = New-Object System.Drawing.Size(48, 48)
$towerIconPicture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$towerIconPicture.BackColor = [System.Drawing.Color]::Transparent
try {
    if (Test-Path $towerHeaderIconPath) {
        $towerIconPicture.Image = [System.Drawing.Image]::FromFile($towerHeaderIconPath)
    }
}
catch {
    Write-TowerLog 'ERROR' "Could not load header Tower icon: $($_.Exception.Message)"
}
$header.Controls.Add($towerIconPicture)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Tower Control'
$title.ForeColor = [System.Drawing.Color]::White
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 17)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(74, 8)
$header.Controls.Add($title)

$status = New-Object System.Windows.Forms.Label
$status.Text = 'Connecting...'
$status.ForeColor = [System.Drawing.Color]::Gainsboro
$status.AutoEllipsis = $true
$status.Location = New-Object System.Drawing.Point(74, 43)
$status.Size = New-Object System.Drawing.Size(820, 20)
$status.Anchor = 'Top,Left'
$header.Controls.Add($status)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = 'Refresh'
$refreshButton.Size = New-Object System.Drawing.Size(110, 38)
$refreshButton.Location = New-Object System.Drawing.Point(0, 18)
$refreshButton.Anchor = 'Top,Right'
$refreshButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$refreshButton.UseVisualStyleBackColor = $false
$refreshButton.BackColor = [System.Drawing.Color]::FromArgb(60, 72, 88)
$refreshButton.ForeColor = [System.Drawing.Color]::White
$refreshButton.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$refreshButton.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$refreshButton.FlatAppearance.BorderColor = [System.Drawing.Color]::White
$refreshButton.FlatAppearance.BorderSize = 1
$refreshButton.TabStop = $false
$refreshButton.CausesValidation = $false
$header.Controls.Add($refreshButton)

$piClockBox = New-Object System.Windows.Forms.Label
$piClockBox.Text = '--:--:--'
$piClockBox.AutoSize = $false
$piClockBox.Size =
    New-Object System.Drawing.Size(92, 38)
$piClockBox.Anchor = 'Top,Right'
$piClockBox.TextAlign =
    [System.Drawing.ContentAlignment]::MiddleCenter
$piClockBox.BorderStyle =
    [System.Windows.Forms.BorderStyle]::FixedSingle
$piClockBox.BackColor =
    [System.Drawing.Color]::FromArgb(60, 72, 88)
$piClockBox.ForeColor =
    [System.Drawing.Color]::White
$piClockBox.Font =
    New-Object System.Drawing.Font(
        'Consolas',
        12,
        [System.Drawing.FontStyle]::Bold
    )
$header.Controls.Add($piClockBox)

$piClockToolTip =
    New-Object System.Windows.Forms.ToolTip
$piClockToolTip.SetToolTip(
    $piClockBox,
    'Raspberry Pi system clock'
)

$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Text = 'EXIT'
$exitButton.Size = New-Object System.Drawing.Size(80, 38)
$exitButton.Anchor = 'Top,Right'
$exitButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$exitButton.UseVisualStyleBackColor = $false
$exitButton.BackColor = [System.Drawing.Color]::FromArgb(120, 35, 35)
$exitButton.ForeColor = [System.Drawing.Color]::White
$exitButton.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$exitButton.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$exitButton.FlatAppearance.BorderColor = [System.Drawing.Color]::White
$exitButton.FlatAppearance.BorderSize = 1
$exitButton.TabStop = $false
$exitButton.CausesValidation = $false
$exitButton.Add_Click({ $form.Close() })
$header.Controls.Add($exitButton)

function Position-HeaderControls {
    # Main action buttons.
    $buttonY = [Math]::Max(
        0,
        [int][Math]::Round(($header.ClientSize.Height - $exitButton.Height) / 2.0)
    )

    $exitButton.Top = $buttonY
    $refreshButton.Top = $buttonY
    $piClockBox.Top = $buttonY

    $rightPadding = 28
    $exitButton.Left = [Math]::Max(
        0,
        $header.ClientSize.Width - $rightPadding - $exitButton.Width
    )
    $refreshButton.Left = [Math]::Max(
        0,
        $exitButton.Left - 10 - $refreshButton.Width
    )
    $piClockBox.Left = [Math]::Max(
        0,
        $refreshButton.Left - 10 - $piClockBox.Width
    )

    # Tower artwork and title.
    $towerIconPicture.Left = 18
    $towerIconPicture.Top = [Math]::Max(
        0,
        [int][Math]::Round(($header.ClientSize.Height - $towerIconPicture.Height) / 2.0)
    )

    $title.Left = $towerIconPicture.Right + 8
    $title.Top = 8

    # The status label used to extend underneath the two buttons and therefore
    # painted over their lower halves. Give it a hard right boundary before
    # Refresh instead of anchoring it across the full header.
    $status.Left = $towerIconPicture.Right + 8
    $status.Top = 43
    $status.Width = [Math]::Max(
        40,
        $piClockBox.Left - $status.Left - 18
    )
    $status.Height = 22

    # Explicit sibling z-order: action buttons must always be on top.
    $piClockBox.BringToFront()
    $refreshButton.BringToFront()
    $exitButton.BringToFront()
}

$header.Add_Resize({ Position-HeaderControls })
Position-HeaderControls

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = [System.Windows.Forms.DockStyle]::None
$tabs.Padding = New-Object System.Drawing.Point(16, 7)
$tabs.Anchor = 'Top,Bottom,Left,Right'
$form.Controls.Add($tabs)

function Position-MainLayout {
    # Do not let the TabControl participate in Dock=Fill layout. Give it a hard
    # boundary below the header so it can never paint over header controls.
    $tabs.Left = 0
    $tabs.Top = $header.Bottom
    $tabs.Width = $form.ClientSize.Width
    $tabs.Height = [Math]::Max(0, $form.ClientSize.Height - $header.Height)

    $header.Left = 0
    $header.Top = 0
    $header.Width = $form.ClientSize.Width

    Position-HeaderControls
    $header.BringToFront()
}

$form.Add_Resize({ Position-MainLayout })
Position-MainLayout

# Settings tab ---------------------------------------------------------------
$settingsTab = New-Object System.Windows.Forms.TabPage
$settingsTab.Text = 'Settings'
$settingsTab.Padding = New-Object System.Windows.Forms.Padding(20)

$settingsTitle = New-Object System.Windows.Forms.Label
$settingsTitle.Text = 'Sidebar Settings'
$settingsTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
$settingsTitle.AutoSize = $true
$settingsTitle.Location = New-Object System.Drawing.Point(20, 20)
$settingsTab.Controls.Add($settingsTitle)

$settingsHint = New-Object System.Windows.Forms.Label
$settingsHint.Text = 'Changes are saved automatically.'
$settingsHint.AutoSize = $true
$settingsHint.ForeColor = [System.Drawing.Color]::DimGray
$settingsHint.Location = New-Object System.Drawing.Point(22, 55)
$settingsTab.Controls.Add($settingsHint)

# Monitor selection.
$settingsMonitorLabel = New-Object System.Windows.Forms.Label
$settingsMonitorLabel.Text = 'Display'
$settingsMonitorLabel.AutoSize = $true
$settingsMonitorLabel.Location = New-Object System.Drawing.Point(22, 100)
$settingsTab.Controls.Add($settingsMonitorLabel)

$settingsMonitorPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$settingsMonitorPanel.Location = New-Object System.Drawing.Point(22, 128)
$settingsMonitorPanel.Size = New-Object System.Drawing.Size(760, 46)
$settingsMonitorPanel.AutoSize = $false
$settingsMonitorPanel.WrapContents = $false
$settingsTab.Controls.Add($settingsMonitorPanel)

$script:monitorButtons = @()

function Refresh-MonitorButtons {
    if ($null -eq $settingsMonitorPanel) { return }

    $settingsMonitorPanel.SuspendLayout()
    $settingsMonitorPanel.Controls.Clear()
    $script:monitorButtons = @()

    $screens = Get-OrderedScreens
    $savedDeviceName = [string]$config.monitorDeviceName

    for ($i = 0; $i -lt $screens.Count; $i++) {
        $screen = $screens[$i]
        $button = New-Object System.Windows.Forms.Button

        $number = $i + 1
        $button.Text =
            "Monitor $number`n" +
            "$($screen.Bounds.Width)x$($screen.Bounds.Height)"
        if ($screen.Primary) {
            $button.Text += '  Primary'
        }

        # Store stable identity instead of a transient WinForms array index.
        $button.Tag = [string]$screen.DeviceName
        $button.Size = New-Object System.Drawing.Size(180, 38)

        $isSelectedMonitor =
            ([string]$screen.DeviceName -eq $savedDeviceName)

        Set-SettingsButtonVisualStyle `
            $button `
            $isSelectedMonitor

        $button.Add_Click({
            $deviceName = [string]$this.Tag
            $selectedScreen = $null

            foreach ($candidate in Get-OrderedScreens) {
                if ([string]$candidate.DeviceName -eq $deviceName) {
                    $selectedScreen = $candidate
                    break
                }
            }

            if ($null -eq $selectedScreen) {
                return
            }

            Save-TargetScreenIdentity $selectedScreen
            Refresh-MonitorButtons
            Hide-SidebarImmediately
            Update-SidebarBounds

            $script:displayTopologyQuietUntil =
                [DateTime]::Now.AddMilliseconds(500)
        })

        [void]$settingsMonitorPanel.Controls.Add($button)
        $script:monitorButtons += $button
    }

    if ($screens.Count -eq 0) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = 'No Windows displays detected.'
        $label.AutoSize = $true
        [void]$settingsMonitorPanel.Controls.Add($label)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($savedDeviceName) -and
            $null -eq (Get-TargetScreen)) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text =
            'Selected display temporarily unavailable - waiting for recovery.'
        $label.AutoSize = $true
        $label.ForeColor = [System.Drawing.Color]::DarkOrange
        $label.Margin = New-Object System.Windows.Forms.Padding(8, 12, 0, 0)
        [void]$settingsMonitorPanel.Controls.Add($label)
    }

    $settingsMonitorPanel.ResumeLayout()
}

Refresh-MonitorButtons

# Width setting.
$widthLabel = New-Object System.Windows.Forms.Label
$widthLabel.Text = 'Sidebar width'
$widthLabel.AutoSize = $true
$widthLabel.Location = New-Object System.Drawing.Point(22, 205)
$settingsTab.Controls.Add($widthLabel)

$widthValueLabel = New-Object System.Windows.Forms.Label
$widthValueLabel.AutoSize = $true
$widthValueLabel.Location = New-Object System.Drawing.Point(260, 205)
$settingsTab.Controls.Add($widthValueLabel)

$widthTrack = New-Object System.Windows.Forms.TrackBar
$widthTrack.Minimum = 20
$widthTrack.Maximum = 80
$widthTrack.TickFrequency = 5
$widthTrack.Value = [Math]::Max(20, [Math]::Min(80, [int]$config.sidebarWidthPercent))
$widthTrack.Location = New-Object System.Drawing.Point(20, 232)
$widthTrack.Size = New-Object System.Drawing.Size(360, 45)
$settingsTab.Controls.Add($widthTrack)
$widthValueLabel.Text = "$($widthTrack.Value)%"

$widthTrack.Add_ValueChanged({
    $widthValueLabel.Text = "$($widthTrack.Value)%"
})
$widthTrack.Add_MouseUp({
    $config.sidebarWidthPercent = [int]$widthTrack.Value
    Save-TowerConfig
    Update-SidebarBounds
    if ($script:sidebarVisible) { $form.Bounds = $script:openBounds }
})

# Hide delay setting.
$hideLabel = New-Object System.Windows.Forms.Label
$hideLabel.Text = 'Auto-hide delay'
$hideLabel.AutoSize = $true
$hideLabel.Location = New-Object System.Drawing.Point(22, 300)
$settingsTab.Controls.Add($hideLabel)

$hideNumeric = New-Object System.Windows.Forms.NumericUpDown
$hideNumeric.Minimum = 0
$hideNumeric.Maximum = 10000
$hideNumeric.Increment = 100
$hideNumeric.Value = [Math]::Max(0, [Math]::Min(10000, [int]$config.hideDelayMs))
$hideNumeric.Location = New-Object System.Drawing.Point(22, 328)
$hideNumeric.Size = New-Object System.Drawing.Size(130, 28)
$settingsTab.Controls.Add($hideNumeric)

$hideSuffix = New-Object System.Windows.Forms.Label
$hideSuffix.Text = 'ms'
$hideSuffix.AutoSize = $true
$hideSuffix.Location = New-Object System.Drawing.Point(160, 332)
$settingsTab.Controls.Add($hideSuffix)

$hideNumeric.Add_ValueChanged({
    $config.hideDelayMs = [int]$hideNumeric.Value
    Save-TowerConfig
})

# Animation duration.
$animationLabel = New-Object System.Windows.Forms.Label
$animationLabel.Text = 'Slide animation'
$animationLabel.AutoSize = $true
$animationLabel.Location = New-Object System.Drawing.Point(22, 390)
$settingsTab.Controls.Add($animationLabel)

$animationNumeric = New-Object System.Windows.Forms.NumericUpDown
$animationNumeric.Minimum = 0
$animationNumeric.Maximum = 1000
$animationNumeric.Increment = 20
$animationNumeric.Value = [Math]::Max(0, [Math]::Min(1000, [int]$config.animationDurationMs))
$animationNumeric.Location = New-Object System.Drawing.Point(22, 418)
$animationNumeric.Size = New-Object System.Drawing.Size(130, 28)
$settingsTab.Controls.Add($animationNumeric)

$animationSuffix = New-Object System.Windows.Forms.Label
$animationSuffix.Text = 'ms (0 = instant)'
$animationSuffix.AutoSize = $true
$animationSuffix.Location = New-Object System.Drawing.Point(160, 422)
$settingsTab.Controls.Add($animationSuffix)

$animationNumeric.Add_ValueChanged({
    $config.animationDurationMs = [int]$animationNumeric.Value
    Save-TowerConfig
})

$trayCheck = New-Object System.Windows.Forms.CheckBox
$trayCheck.Text = 'Show system tray icon'
$trayCheck.AutoSize = $true
$trayCheck.Checked = [bool]$config.showTrayIcon
$trayCheck.Location = New-Object System.Drawing.Point(22, 475)
$trayCheck.Add_CheckedChanged({
    $config.showTrayIcon = [bool]$trayCheck.Checked
    Save-TowerConfig
    Update-TrayIcon
})
$settingsTab.Controls.Add($trayCheck)

$settingsNote = New-Object System.Windows.Forms.Label
$settingsNote.Text = "EXIT remains available in the top bar even when the tray icon is disabled.  Esc hides immediately."
$settingsNote.AutoSize = $true
$settingsNote.ForeColor = [System.Drawing.Color]::DimGray
$settingsNote.Location = New-Object System.Drawing.Point(22, 515)
$settingsTab.Controls.Add($settingsNote)


$tabs.BringToFront()

# Home / Devices tab ---------------------------------------------------------
# Home is now the first/main landing page so device selection is immediately
# visible when Tower Control opens.
$homeTab = New-Object System.Windows.Forms.TabPage
$homeTab.Text = 'Home'
$homeTab.Padding = New-Object System.Windows.Forms.Padding(14)
[void]$tabs.TabPages.Add($homeTab)

$homeTitle = New-Object System.Windows.Forms.Label
$homeTitle.Text = 'Which device would you like to control?'
$homeTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 17)
$homeTitle.AutoSize = $true
$homeTitle.Location = New-Object System.Drawing.Point(18, 16)
$homeTab.Controls.Add($homeTitle)

$homeHint = New-Object System.Windows.Forms.Label
$homeHint.Text = 'Choose a device to open its remote controls.'
$homeHint.ForeColor = [System.Drawing.Color]::DimGray
$homeHint.AutoSize = $true
$homeHint.Location = New-Object System.Drawing.Point(20, 52)
$homeTab.Controls.Add($homeHint)

$homeDevicePanel = New-Object System.Windows.Forms.FlowLayoutPanel
$homeDevicePanel.Location = New-Object System.Drawing.Point(14, 82)
$homeDevicePanel.Anchor = 'Top,Bottom,Left,Right'
$homeDevicePanel.AutoScroll = $true
$homeDevicePanel.WrapContents = $true
$homeDevicePanel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$homeTab.Controls.Add($homeDevicePanel)

function Position-HomeLayout {
    if ($null -eq $homeDevicePanel) { return }
    $homeDevicePanel.Width = [Math]::Max(100, $homeTab.ClientSize.Width - 28)
    $homeDevicePanel.Height = [Math]::Max(100, $homeTab.ClientSize.Height - 96)
}
$homeTab.Add_Resize({ Position-HomeLayout })
Position-HomeLayout

$tabs.SelectedTab = $homeTab

$sensorsTab = New-Object System.Windows.Forms.TabPage
$sensorsTab.Text = 'Sensors'
$sensorsTab.Padding = New-Object System.Windows.Forms.Padding(12)
$tabs.TabPages.Add($sensorsTab)

$sensorRoot = New-Object System.Windows.Forms.TableLayoutPanel
$sensorRoot.Dock = 'Fill'
$sensorRoot.ColumnCount = 2
$sensorRoot.RowCount = 1
$sensorRoot.Margin = New-Object System.Windows.Forms.Padding(0)
$sensorRoot.Padding = New-Object System.Windows.Forms.Padding(0)

[void]$sensorRoot.ColumnStyles.Add(
    (New-Object System.Windows.Forms.ColumnStyle(
        [System.Windows.Forms.SizeType]::Percent,
        100
    ))
)
[void]$sensorRoot.ColumnStyles.Add(
    (New-Object System.Windows.Forms.ColumnStyle(
        [System.Windows.Forms.SizeType]::Absolute,
        112
    ))
)

$sensorsTab.Controls.Add($sensorRoot)

$sensorContent = New-Object System.Windows.Forms.Panel
$sensorContent.Dock = 'Fill'
$sensorContent.Margin = New-Object System.Windows.Forms.Padding(0)
$sensorRoot.Controls.Add($sensorContent, 0, 0)

# Cards view ---------------------------------------------------------------
$sensorPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$sensorPanel.Dock = 'Fill'
$sensorPanel.AutoScroll = $true
$sensorPanel.WrapContents = $false
$sensorPanel.FlowDirection =
    [System.Windows.Forms.FlowDirection]::TopDown
$sensorPanel.Padding = New-Object System.Windows.Forms.Padding(0)
$sensorPanel.Margin = New-Object System.Windows.Forms.Padding(0)
$sensorContent.Controls.Add($sensorPanel)

# Compact details view -----------------------------------------------------
$sensorListView = New-Object System.Windows.Forms.ListView
$sensorListView.Dock = 'Fill'
$sensorListView.View = [System.Windows.Forms.View]::Details
$sensorListView.FullRowSelect = $true
$sensorListView.GridLines = $false
$sensorListView.HideSelection = $false
$sensorListView.MultiSelect = $false
$sensorListView.HeaderStyle =
    [System.Windows.Forms.ColumnHeaderStyle]::Nonclickable
$sensorListView.Font =
    New-Object System.Drawing.Font('Segoe UI', 9.5)
$sensorListView.BackColor =
    [System.Drawing.Color]::FromArgb(240, 240, 240)
$sensorListView.BorderStyle =
    [System.Windows.Forms.BorderStyle]::FixedSingle
$sensorContent.Controls.Add($sensorListView)

[void]$sensorListView.Columns.Add('Sensor', 128)
[void]$sensorListView.Columns.Add('Measurements', 360)
[void]$sensorListView.Columns.Add('Updated', 132)

$sensorWaitingLabel = New-Object System.Windows.Forms.Label
$sensorWaitingLabel.Text = 'Waiting for the first sensor refresh...'
$sensorWaitingLabel.AutoSize = $true
$sensorWaitingLabel.ForeColor = [System.Drawing.Color]::DimGray
$sensorWaitingLabel.Margin = New-Object System.Windows.Forms.Padding(14, 18, 0, 0)
[void]$sensorPanel.Controls.Add($sensorWaitingLabel)

# Settings-style View selector --------------------------------------------
$sensorViewRail = New-Object System.Windows.Forms.Panel
$sensorViewRail.Dock = 'Fill'
$sensorViewRail.Margin = New-Object System.Windows.Forms.Padding(4, 6, 0, 0)
$sensorRoot.Controls.Add($sensorViewRail, 1, 0)

$sensorViewLabel = New-Object System.Windows.Forms.Label
$sensorViewLabel.Text = 'View'
$sensorViewLabel.Location =
    New-Object System.Drawing.Point(6, 8)
$sensorViewLabel.Size =
    New-Object System.Drawing.Size(96, 22)
$sensorViewLabel.TextAlign =
    [System.Drawing.ContentAlignment]::MiddleCenter
$sensorViewLabel.Font =
    New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$sensorViewRail.Controls.Add($sensorViewLabel)

$sensorCardsViewButton =
    New-Object System.Windows.Forms.Button
$sensorCardsViewButton.Text = 'Cards'
$sensorCardsViewButton.Size =
    New-Object System.Drawing.Size(96, 38)
$sensorCardsViewButton.Location =
    New-Object System.Drawing.Point(6, 36)
$sensorCardsViewButton.Font =
    New-Object System.Drawing.Font('Segoe UI', 9)
$sensorCardsViewButton.TabStop = $false
$sensorViewRail.Controls.Add($sensorCardsViewButton)

$sensorListViewButton =
    New-Object System.Windows.Forms.Button
$sensorListViewButton.Text = 'List'
$sensorListViewButton.Size =
    New-Object System.Drawing.Size(96, 38)
$sensorListViewButton.Location =
    New-Object System.Drawing.Point(6, 80)
$sensorListViewButton.Font =
    New-Object System.Drawing.Font('Segoe UI', 9)
$sensorListViewButton.TabStop = $false
$sensorViewRail.Controls.Add($sensorListViewButton)

$sensorDetailsViewButton =
    New-Object System.Windows.Forms.Button
$sensorDetailsViewButton.Text = 'Details'
$sensorDetailsViewButton.Size =
    New-Object System.Drawing.Size(96, 38)
$sensorDetailsViewButton.Location =
    New-Object System.Drawing.Point(6, 124)
$sensorDetailsViewButton.Font =
    New-Object System.Drawing.Font('Segoe UI', 9)
$sensorDetailsViewButton.TabStop = $false
$sensorViewRail.Controls.Add($sensorDetailsViewButton)

$sensorPanel.Visible =
    ([string]$config.sensorViewMode -ne 'details')
$sensorListView.Visible =
    ([string]$config.sensorViewMode -eq 'details')


$rfTab = New-Object System.Windows.Forms.TabPage
$rfTab.Text = 'RF Power'
$rfTab.Padding = New-Object System.Windows.Forms.Padding(10)
$tabs.TabPages.Add($rfTab)

$rfToolTip = New-Object System.Windows.Forms.ToolTip
$rfToolTip.AutoPopDelay = 15000
$rfToolTip.InitialDelay = 350
$rfToolTip.ReshowDelay = 150

$rfRoot = New-Object System.Windows.Forms.TableLayoutPanel
$rfRoot.Dock = 'Fill'
$rfRoot.ColumnCount = 1
$rfRoot.RowCount = 3
$rfRoot.Margin = New-Object System.Windows.Forms.Padding(0)
$rfRoot.Padding = New-Object System.Windows.Forms.Padding(0)
[void]$rfRoot.RowStyles.Add(
    (New-Object System.Windows.Forms.RowStyle(
        [System.Windows.Forms.SizeType]::Absolute,
        54
    ))
)
[void]$rfRoot.RowStyles.Add(
    (New-Object System.Windows.Forms.RowStyle(
        [System.Windows.Forms.SizeType]::Absolute,
        188
    ))
)
[void]$rfRoot.RowStyles.Add(
    (New-Object System.Windows.Forms.RowStyle(
        [System.Windows.Forms.SizeType]::Percent,
        100
    ))
)
$rfTab.Controls.Add($rfRoot)

# Header actions -------------------------------------------------------------
$rfTop = New-Object System.Windows.Forms.Panel
$rfTop.Dock = 'Fill'
$rfRoot.Controls.Add($rfTop, 0, 0)

$rfPageTitle = New-Object System.Windows.Forms.Label
$rfPageTitle.Text = 'RF Power'
$rfPageTitle.Font =
    New-Object System.Drawing.Font('Segoe UI Semibold', 12)
$rfPageTitle.AutoSize = $true
$rfPageTitle.Location = New-Object System.Drawing.Point(2, 14)
$rfTop.Controls.Add($rfPageTitle)

$rfTopActions = New-Object System.Windows.Forms.FlowLayoutPanel
$rfTopActions.Dock = [System.Windows.Forms.DockStyle]::Right
$rfTopActions.Width = 390
$rfTopActions.FlowDirection =
    [System.Windows.Forms.FlowDirection]::RightToLeft
$rfTopActions.WrapContents = $false
$rfTopActions.Padding = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
$rfTop.Controls.Add($rfTopActions)

$rfAddButton = New-RfSmoothButton `
    '+ Add RF Device' `
    130 `
    34 `
    ([System.Drawing.Color]::FromArgb(224, 238, 248))
$rfAddButton.Margin =
    New-Object System.Windows.Forms.Padding(6, 0, 0, 0)
[void]$rfTopActions.Controls.Add($rfAddButton)

$allOffButton = New-RfSmoothButton `
    'ALL OFF' `
    105 `
    34 `
    ([System.Drawing.Color]::FromArgb(250, 218, 218))
$allOffButton.Margin =
    New-Object System.Windows.Forms.Padding(6, 0, 0, 0)
[void]$rfTopActions.Controls.Add($allOffButton)

$allOnButton = New-RfSmoothButton `
    'ALL ON' `
    105 `
    34 `
    ([System.Drawing.Color]::FromArgb(210, 242, 218))
$allOnButton.Margin =
    New-Object System.Windows.Forms.Padding(6, 0, 0, 0)
[void]$rfTopActions.Controls.Add($allOnButton)

$rfToolTip.SetToolTip(
    $rfAddButton,
    "Add a new RF power device. Modern KAKU uses a unique transmitter " +
    "ID/address; all current devices share the Tower's 433 MHz RF hardware."
)



# Presets --------------------------------------------------------------------
$rfPresetsGroup = New-Object System.Windows.Forms.GroupBox
$rfPresetsGroup.Text = 'Presets'
$rfPresetsGroup.Dock = 'Fill'
$rfPresetsGroup.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 8)
$rfRoot.Controls.Add($rfPresetsGroup, 0, 1)

$rfPresetLayout = New-Object System.Windows.Forms.TableLayoutPanel
$rfPresetLayout.Dock = 'Fill'
$rfPresetLayout.ColumnCount = 1
$rfPresetLayout.RowCount = 3
$rfPresetLayout.Padding = New-Object System.Windows.Forms.Padding(6, 5, 6, 5)
$rfPresetLayout.Margin = New-Object System.Windows.Forms.Padding(0)

for ($presetRow = 0; $presetRow -lt 3; $presetRow++) {
    [void]$rfPresetLayout.RowStyles.Add(
        (New-Object System.Windows.Forms.RowStyle(
            [System.Windows.Forms.SizeType]::Percent,
            33.333
        ))
    )
}
$rfPresetsGroup.Controls.Add($rfPresetLayout)

for ($preset = 1; $preset -le 3; $preset++) {
    $presetRowPanel = New-Object System.Windows.Forms.Panel
    $presetRowPanel.Dock = 'Fill'
    $presetRowPanel.Margin =
        New-Object System.Windows.Forms.Padding(2, 1, 2, 1)

    $presetLabel = New-Object System.Windows.Forms.Label
    $presetLabel.Text = "Preset $preset"
    $presetLabel.Location = New-Object System.Drawing.Point(7, 8)
    $presetLabel.Size = New-Object System.Drawing.Size(70, 30)
    $presetLabel.TextAlign =
        [System.Drawing.ContentAlignment]::MiddleLeft
    $presetLabel.Font =
        New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
    $presetRowPanel.Controls.Add($presetLabel)

    $presetFlow = New-Object System.Windows.Forms.FlowLayoutPanel
    $presetFlow.Location = New-Object System.Drawing.Point(82, 4)
    $presetFlow.Height = 36
    $presetFlow.FlowDirection =
        [System.Windows.Forms.FlowDirection]::LeftToRight
    $presetFlow.WrapContents = $false
    $presetFlow.AutoScroll = $true
    $presetFlow.Margin = New-Object System.Windows.Forms.Padding(0)
    $presetFlow.Padding = New-Object System.Windows.Forms.Padding(2, 1, 2, 0)
    $presetRowPanel.Controls.Add($presetFlow)

    $presetOn = New-RfSmoothButton `
        'POWER ON' `
        108 `
        30 `
        ([System.Drawing.Color]::FromArgb(210, 242, 218))
    $presetRowPanel.Controls.Add($presetOn)

    $presetOff = New-RfSmoothButton `
        'POWER OFF' `
        108 `
        30 `
        ([System.Drawing.Color]::FromArgb(250, 218, 218))
    $presetRowPanel.Controls.Add($presetOff)

    $separator = New-Object System.Windows.Forms.Panel
    $separator.Height = 1
    $separator.BackColor =
        [System.Drawing.Color]::FromArgb(218, 218, 218)
    $presetRowPanel.Controls.Add($separator)

    $presetRowPanel.Tag = [pscustomobject]@{
        Flow = $presetFlow
        PowerOn = $presetOn
        PowerOff = $presetOff
        Separator = $separator
    }

    $presetRowPanel.Add_Resize({
        $flow = $this.Tag.Flow
        $powerOn = $this.Tag.PowerOn
        $powerOff = $this.Tag.PowerOff
        $separator = $this.Tag.Separator

        $powerOff.Left =
            [Math]::Max(
                282,
                $this.ClientSize.Width - $powerOff.Width - 7
            )
        $powerOff.Top =
            [Math]::Max(
                3,
                [int](($this.ClientSize.Height - $powerOff.Height - 1) / 2)
            )

        $powerOn.Left =
            [Math]::Max(
                170,
                $powerOff.Left - $powerOn.Width - 7
            )
        $powerOn.Top =
            [Math]::Max(
                3,
                [int](($this.ClientSize.Height - $powerOn.Height - 1) / 2)
            )

        $flow.Width =
            [Math]::Max(
                90,
                $powerOn.Left - $flow.Left - 12
            )
        $flow.Top =
            [Math]::Max(
                3,
                [int](($this.ClientSize.Height - $flow.Height - 1) / 2)
            )

        $separator.Left = 4
        $separator.Top =
            [Math]::Max(0, $this.ClientSize.Height - 1)
        $separator.Width =
            [Math]::Max(0, $this.ClientSize.Width - 8)
    })

    $capturedPreset = $preset
    $presetOn.Add_Click({
        Send-RfPresetAction $capturedPreset 'on'
    }.GetNewClosure())

    $presetOff.Add_Click({
        Send-RfPresetAction $capturedPreset 'off'
    }.GetNewClosure())

    $rfPresetLayout.Controls.Add($presetRowPanel, 0, ($preset - 1))

    $script:rfPresetFlows[$preset] = $presetFlow
    $script:rfPresetPowerButtons[$preset] = $presetOn
    $script:rfPresetOffButtons[$preset] = $presetOff
}

# Device list ----------------------------------------------------------------
$rfDevicesGroup = New-Object System.Windows.Forms.GroupBox
$rfDevicesGroup.Text = 'RF Power devices'
$rfDevicesGroup.Dock = 'Fill'
$rfDevicesGroup.Margin = New-Object System.Windows.Forms.Padding(0)
$rfRoot.Controls.Add($rfDevicesGroup, 0, 2)

$rfDeviceAreaLayout = New-Object System.Windows.Forms.TableLayoutPanel
$rfDeviceAreaLayout.Dock = 'Fill'
$rfDeviceAreaLayout.ColumnCount = 2
$rfDeviceAreaLayout.RowCount = 1
$rfDeviceAreaLayout.Margin = New-Object System.Windows.Forms.Padding(0)
$rfDeviceAreaLayout.Padding = New-Object System.Windows.Forms.Padding(0)
[void]$rfDeviceAreaLayout.ColumnStyles.Add(
    (New-Object System.Windows.Forms.ColumnStyle(
        [System.Windows.Forms.SizeType]::Percent,
        100
    ))
)
[void]$rfDeviceAreaLayout.ColumnStyles.Add(
    (New-Object System.Windows.Forms.ColumnStyle(
        [System.Windows.Forms.SizeType]::Absolute,
        112
    ))
)
$rfDevicesGroup.Controls.Add($rfDeviceAreaLayout)

$rfPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$rfPanel.Dock = 'Fill'
$rfPanel.AutoScroll = $true
$rfPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$rfPanel.WrapContents = $true
$rfPanel.Padding = New-Object System.Windows.Forms.Padding(5, 5, 5, 5)
$rfPanel.Margin = New-Object System.Windows.Forms.Padding(0)

# FlowLayoutPanel.DoubleBuffered is protected. Enable it through reflection
# so explicit RF redraws are composed off-screen instead of painting controls
# one-by-one.
try {
    $doubleBufferedProperty =
        $rfPanel.GetType().GetProperty(
            'DoubleBuffered',
            [System.Reflection.BindingFlags]::Instance -bor
            [System.Reflection.BindingFlags]::NonPublic
        )

    if ($null -ne $doubleBufferedProperty) {
        $doubleBufferedProperty.SetValue(
            $rfPanel,
            $true,
            $null
        )
    }
}
catch {
    Write-TowerLog 'WARN' (
        "Could not enable RF panel double buffering: " +
        "$($_.Exception.Message)"
    )
}

$rfDeviceAreaLayout.Controls.Add($rfPanel, 0, 0)

$rfViewRail = New-Object System.Windows.Forms.Panel
$rfViewRail.Dock = 'Fill'
$rfViewRail.Margin = New-Object System.Windows.Forms.Padding(3, 6, 4, 0)
$rfDeviceAreaLayout.Controls.Add($rfViewRail, 1, 0)

$rfViewLabel = New-Object System.Windows.Forms.Label
$rfViewLabel.Text = 'View'
$rfViewLabel.Location = New-Object System.Drawing.Point(8, 8)
$rfViewLabel.Size = New-Object System.Drawing.Size(88, 20)
$rfViewLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$rfViewLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$rfViewRail.Controls.Add($rfViewLabel)

$rfCardsViewButton = New-RfSmoothButton `
    'Cards' `
    92 `
    32 `
    ([System.Drawing.Color]::White) `
    ([System.Drawing.Color]::SteelBlue) `
    ([System.Drawing.Color]::SteelBlue)
$rfCardsViewButton.Location = New-Object System.Drawing.Point(7, 34)
$rfViewRail.Controls.Add($rfCardsViewButton)

$rfListViewButton = New-RfSmoothButton `
    'List' `
    92 `
    32 `
    ([System.Drawing.Color]::White) `
    ([System.Drawing.Color]::SteelBlue) `
    ([System.Drawing.Color]::SteelBlue)
$rfListViewButton.Location = New-Object System.Drawing.Point(7, 72)
$rfViewRail.Controls.Add($rfListViewButton)

$rfToolTip.SetToolTip(
    $rfCardsViewButton,
    'Compact RF device cards that wrap left-to-right.'
)
$rfToolTip.SetToolTip(
    $rfListViewButton,
    'One RF device per row from top to bottom.'
)

$irTab = New-Object System.Windows.Forms.TabPage
$irTab.Text = 'IR Remotes'
$irTab.Padding = New-Object System.Windows.Forms.Padding(8)
$tabs.TabPages.Add($irTab)

$irSplit = New-Object System.Windows.Forms.SplitContainer
$irSplit.Dock = 'Fill'
$irSplit.SplitterDistance = 180
$irSplit.FixedPanel = [System.Windows.Forms.FixedPanel]::None
$irTab.Controls.Add($irSplit)

$irLeftLayout = New-Object System.Windows.Forms.TableLayoutPanel
$irLeftLayout.Dock = 'Fill'
$irLeftLayout.RowCount = 3
$irLeftLayout.ColumnCount = 1
[void]$irLeftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 36)))
[void]$irLeftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 205)))
[void]$irLeftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$irSplit.Panel1.Controls.Add($irLeftLayout)

$irDeviceHeaderPanel = New-Object System.Windows.Forms.Panel
$irDeviceHeaderPanel.Dock = 'Fill'
$irLeftLayout.Controls.Add($irDeviceHeaderPanel, 0, 0)

# Shared tooltip object must exist before any IR toolbar/preview control uses it.
$toolTip = New-Object System.Windows.Forms.ToolTip

# Dedicated toolbar on the right. Using its own FlowLayoutPanel prevents the
# dock-filled "IR devices" label from ever painting over the management buttons.
$irDeviceToolbar = New-Object System.Windows.Forms.FlowLayoutPanel
$irDeviceToolbar.Dock = [System.Windows.Forms.DockStyle]::Right
$irDeviceToolbar.Width = 176
$irDeviceToolbar.FlowDirection =
    [System.Windows.Forms.FlowDirection]::LeftToRight
$irDeviceToolbar.WrapContents = $false
$irDeviceToolbar.AutoSize = $false
$irDeviceToolbar.Margin = New-Object System.Windows.Forms.Padding(0)
$irDeviceToolbar.Padding = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
$irDeviceHeaderPanel.Controls.Add($irDeviceToolbar)

$irDeviceListLabel = New-Object System.Windows.Forms.Label
$irDeviceListLabel.Text = 'IR devices'
$irDeviceListLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$irDeviceListLabel.TextAlign = 'MiddleLeft'
$irDeviceListLabel.Font =
    New-Object System.Drawing.Font('Segoe UI Semibold', 10.5)
$irDeviceListLabel.Padding =
    New-Object System.Windows.Forms.Padding(0, 0, 4, 0)
$irDeviceHeaderPanel.Controls.Add($irDeviceListLabel)

# Explicit z-order: toolbar always stays above/right of the fill label.
$irDeviceToolbar.BringToFront()

$irDeviceAddButton = New-Object System.Windows.Forms.Button
$irDeviceAddButton.Text = '+'
$irDeviceAddButton.Size = New-Object System.Drawing.Size(30, 28)
$irDeviceAddButton.Margin = New-Object System.Windows.Forms.Padding(2, 0, 2, 0)
$irDeviceAddButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$irDeviceAddButton.BackColor =
    [System.Drawing.Color]::FromArgb(224, 244, 228)
$irDeviceAddButton.Font =
    New-Object System.Drawing.Font('Segoe UI Semibold', 12)
[void]$irDeviceToolbar.Controls.Add($irDeviceAddButton)

$irDeviceUpButton = New-Object System.Windows.Forms.Button
$irDeviceUpButton.Text = [char]0x2191
$irDeviceUpButton.Size = New-Object System.Drawing.Size(30, 28)
$irDeviceUpButton.Margin = New-Object System.Windows.Forms.Padding(2, 0, 2, 0)
$irDeviceUpButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$irDeviceUpButton.Font =
    New-Object System.Drawing.Font('Segoe UI Semibold', 11)
[void]$irDeviceToolbar.Controls.Add($irDeviceUpButton)

$irDeviceDownButton = New-Object System.Windows.Forms.Button
$irDeviceDownButton.Text = [char]0x2193
$irDeviceDownButton.Size = New-Object System.Drawing.Size(30, 28)
$irDeviceDownButton.Margin = New-Object System.Windows.Forms.Padding(2, 0, 2, 0)
$irDeviceDownButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$irDeviceDownButton.Font =
    New-Object System.Drawing.Font('Segoe UI Semibold', 11)
[void]$irDeviceToolbar.Controls.Add($irDeviceDownButton)

$irDeviceRenameButton =
    New-Object System.Windows.Forms.Button
$irDeviceRenameButton.Text = [char]0x270E
$irDeviceRenameButton.Size =
    New-Object System.Drawing.Size(30, 28)
$irDeviceRenameButton.Margin =
    New-Object System.Windows.Forms.Padding(2, 0, 2, 0)
$irDeviceRenameButton.FlatStyle =
    [System.Windows.Forms.FlatStyle]::Flat
$irDeviceRenameButton.BackColor =
    [System.Drawing.Color]::FromArgb(
        232,
        239,
        249
    )
$irDeviceRenameButton.Font =
    New-Object System.Drawing.Font(
        'Segoe UI Symbol',
        11
    )
[void]$irDeviceToolbar.Controls.Add(
    $irDeviceRenameButton
)

$irDeviceDeleteButton = New-Object System.Windows.Forms.Button
$irDeviceDeleteButton.Text = 'X'
$irDeviceDeleteButton.Size = New-Object System.Drawing.Size(30, 28)
$irDeviceDeleteButton.Margin = New-Object System.Windows.Forms.Padding(2, 0, 2, 0)
$irDeviceDeleteButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$irDeviceDeleteButton.BackColor =
    [System.Drawing.Color]::FromArgb(246, 226, 226)
$irDeviceDeleteButton.Font =
    New-Object System.Drawing.Font('Segoe UI Semibold', 10)
[void]$irDeviceToolbar.Controls.Add($irDeviceDeleteButton)

$toolTip.SetToolTip($irDeviceAddButton, 'Add a new IR remote')
$toolTip.SetToolTip($irDeviceUpButton, 'Move selected remote up')
$toolTip.SetToolTip($irDeviceDownButton, 'Move selected remote down')
$toolTip.SetToolTip($irDeviceRenameButton, 'Edit selected remote')
$toolTip.SetToolTip($irDeviceDeleteButton, 'Delete selected remote')

$irDeviceList = New-Object System.Windows.Forms.ListBox
$irDeviceList.Dock = 'Fill'
$irDeviceList.IntegralHeight = $false
$irLeftLayout.Controls.Add($irDeviceList, 0, 1)

$remotePreviewGroup = New-Object System.Windows.Forms.GroupBox
$remotePreviewGroup.Text = 'Remote'
$remotePreviewGroup.Dock = 'Fill'
$remotePreviewGroup.Padding = New-Object System.Windows.Forms.Padding(5, 18, 5, 5)
$remotePreviewGroup.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
$irLeftLayout.Controls.Add($remotePreviewGroup, 0, 2)

$remotePreviewLayout = New-Object System.Windows.Forms.TableLayoutPanel
$remotePreviewLayout.Dock = 'Fill'
$remotePreviewLayout.Margin = New-Object System.Windows.Forms.Padding(0)
$remotePreviewLayout.Padding = New-Object System.Windows.Forms.Padding(0)
$remotePreviewLayout.RowCount = 2
$remotePreviewLayout.ColumnCount = 1
[void]$remotePreviewLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$remotePreviewLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 0)))
$remotePreviewGroup.Controls.Add($remotePreviewLayout)

$remotePreviewSurface = New-Object System.Windows.Forms.Panel
$remotePreviewSurface.Dock = 'Fill'
$remotePreviewSurface.Margin = New-Object System.Windows.Forms.Padding(0)
$remotePreviewSurface.BackColor = [System.Drawing.Color]::WhiteSmoke
$remotePreviewLayout.Controls.Add($remotePreviewSurface, 0, 0)

$remotePreviewPicture = New-Object System.Windows.Forms.PictureBox
$remotePreviewPicture.Dock = 'Fill'
$remotePreviewPicture.Margin = New-Object System.Windows.Forms.Padding(0)
$remotePreviewPicture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$remotePreviewPicture.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
$remotePreviewPicture.Cursor = [System.Windows.Forms.Cursors]::Hand
$remotePreviewSurface.Controls.Add($remotePreviewPicture)

$remotePreviewAddImageButton = New-Object System.Windows.Forms.Button
$remotePreviewAddImageButton.Text = "+`n`nClick here to add image"
$remotePreviewAddImageButton.Size = New-Object System.Drawing.Size(150, 150)
$remotePreviewAddImageButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$remotePreviewAddImageButton.BackColor = [System.Drawing.Color]::White
$remotePreviewAddImageButton.ForeColor = [System.Drawing.Color]::DimGray
$remotePreviewAddImageButton.Font =
    New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$remotePreviewAddImageButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$remotePreviewAddImageButton.Visible = $false
$remotePreviewSurface.Controls.Add($remotePreviewAddImageButton)
$remotePreviewAddImageButton.BringToFront()

function Position-RemotePreviewAddImageButton {
    if ($null -eq $remotePreviewSurface) { return }

    $size = [Math]::Min(
        150,
        [Math]::Max(
            90,
            [Math]::Min(
                $remotePreviewSurface.ClientSize.Width - 20,
                $remotePreviewSurface.ClientSize.Height - 20
            )
        )
    )

    if ($size -lt 60) { return }

    $remotePreviewAddImageButton.Size =
        New-Object System.Drawing.Size($size, $size)

    $remotePreviewAddImageButton.Left =
        [Math]::Max(
            0,
            [int](($remotePreviewSurface.ClientSize.Width - $size) / 2)
        )
    $remotePreviewAddImageButton.Top =
        [Math]::Max(
            0,
            [int](($remotePreviewSurface.ClientSize.Height - $size) / 2)
        )
}

$remotePreviewSurface.Add_Resize({
    Position-RemotePreviewAddImageButton
})
Position-RemotePreviewAddImageButton

$toolTip.SetToolTip(
    $remotePreviewPicture,
    'Click to choose or replace this remote image'
)
$toolTip.SetToolTip(
    $remotePreviewAddImageButton,
    'Choose an image for this remote'
)

$remotePreviewHint = New-Object System.Windows.Forms.Label
$remotePreviewHint.Text = 'Remote photo preview'
$remotePreviewHint.Dock = 'Fill'
$remotePreviewHint.TextAlign = 'MiddleLeft'
$remotePreviewHint.ForeColor = [System.Drawing.Color]::DimGray
$remotePreviewHint.Padding = New-Object System.Windows.Forms.Padding(6, 0, 6, 0)
$remotePreviewLayout.Controls.Add($remotePreviewHint, 0, 1)


function Update-IrRemotePaneLayout {
    if ($null -eq $irSplit) { return }

    $availableWidth = [int]$irSplit.ClientSize.Width

    # During WinForms construction the SplitContainer may temporarily be only a
    # few pixels wide. Do nothing until it has a meaningful runtime width.
    if ($availableWidth -lt 450) { return }

    $desiredLeftWidth = [int][Math]::Round($availableWidth * 0.34)

    $minimumLeftWidth = 180
    $maximumLeftWidth = 520
    $minimumCommandWidth = 360

    $maximumAllowedLeft = $availableWidth - $minimumCommandWidth - $irSplit.SplitterWidth
    if ($maximumAllowedLeft -lt $minimumLeftWidth) {
        return
    }

    $leftWidth = [Math]::Max(
        $minimumLeftWidth,
        [Math]::Min(
            $maximumLeftWidth,
            [Math]::Min($desiredLeftWidth, $maximumAllowedLeft)
        )
    )

    # SplitterDistance throws if the value is outside the control's current
    # valid range, so clamp it against the live size immediately before setting.
    $maxDistance = $availableWidth - $irSplit.SplitterWidth - 1
    if ($maxDistance -le 1) { return }

    $leftWidth = [Math]::Min($leftWidth, $maxDistance)
    if ($leftWidth -gt 0) {
        try {
            $irSplit.SplitterDistance = [int]$leftWidth
        }
        catch {
            # A resize can race WinForms layout by one event. Ignore that
            # transient frame; the next Resize event recalculates it.
        }
    }

    $remotePreviewPicture.Invalidate()
}

$irSplit.Add_Resize({ Update-IrRemotePaneLayout })
$irTab.Add_Resize({ Update-IrRemotePaneLayout })

$irRightLayout = New-Object System.Windows.Forms.TableLayoutPanel
$irRightLayout.Dock = 'Fill'
$irRightLayout.RowCount = 2
$irRightLayout.ColumnCount = 1
[void]$irRightLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 152)))
[void]$irRightLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$irSplit.Panel2.Controls.Add($irRightLayout)

$irHeaderLayout = New-Object System.Windows.Forms.TableLayoutPanel
$irHeaderLayout.Dock = 'Fill'
$irHeaderLayout.RowCount = 7
$irHeaderLayout.ColumnCount = 1
[void]$irHeaderLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 40)))
[void]$irHeaderLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 0)))
[void]$irHeaderLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 0)))
[void]$irHeaderLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 25)))
[void]$irHeaderLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 23)))
[void]$irHeaderLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 40)))
[void]$irHeaderLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 24)))
$irRightLayout.Controls.Add($irHeaderLayout, 0, 0)

$irHeadingPanel = New-Object System.Windows.Forms.Panel
$irHeadingPanel.Dock = 'Fill'
$irHeaderLayout.Controls.Add($irHeadingPanel, 0, 0)

$irLayoutEditButton = New-RfSmoothButton `
    'Edit Layout' `
    92 `
    29 `
    ([System.Drawing.Color]::FromArgb(232, 239, 249)) `
    ([System.Drawing.Color]::FromArgb(30, 65, 105)) `
    ([System.Drawing.Color]::FromArgb(120, 155, 195))
$irLayoutEditButton.Margin = New-Object System.Windows.Forms.Padding(4, 0, 0, 0)

$irLayoutSaveButton = New-RfSmoothButton `
    'Save Layout' `
    92 `
    29 `
    ([System.Drawing.Color]::FromArgb(224, 244, 228)) `
    ([System.Drawing.Color]::FromArgb(30, 80, 40)) `
    ([System.Drawing.Color]::FromArgb(130, 175, 135))
$irLayoutSaveButton.Margin = New-Object System.Windows.Forms.Padding(4, 0, 0, 0)
$irLayoutSaveButton.Visible = $false

$irLayoutCancelButton = New-RfSmoothButton `
    'Cancel' `
    72 `
    29 `
    ([System.Drawing.Color]::White) `
    ([System.Drawing.Color]::FromArgb(50, 50, 50)) `
    ([System.Drawing.Color]::FromArgb(155, 155, 155))
$irLayoutCancelButton.Margin = New-Object System.Windows.Forms.Padding(4, 0, 0, 0)
$irLayoutCancelButton.Visible = $false

$irLayoutColorPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$irLayoutColorPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$irLayoutColorPanel.FlowDirection =
    [System.Windows.Forms.FlowDirection]::LeftToRight
$irLayoutColorPanel.WrapContents = $false
$irLayoutColorPanel.Padding = New-Object System.Windows.Forms.Padding(10, 2, 0, 0)
$irLayoutColorPanel.Visible = $false
$irHeaderLayout.Controls.Add($irLayoutColorPanel, 0, 1)

$irLayoutColorLabel = New-Object System.Windows.Forms.Label
$irLayoutColorLabel.Text = 'Button color:'
$irLayoutColorLabel.AutoSize = $true
$irLayoutColorLabel.Margin = New-Object System.Windows.Forms.Padding(0, 5, 8, 0)
[void]$irLayoutColorPanel.Controls.Add($irLayoutColorLabel)

$irLayoutColorChoices = @(
    @{ Key = 'Auto';   Name = 'Auto / original'; Color = [System.Drawing.Color]::White },
    @{ Key = 'Red';    Name = 'Red';    Color = [System.Drawing.Color]::FromArgb(246, 226, 226) },
    @{ Key = 'Blue';   Name = 'Blue';   Color = [System.Drawing.Color]::FromArgb(229, 238, 250) },
    @{ Key = 'Green';  Name = 'Green';  Color = [System.Drawing.Color]::FromArgb(230, 244, 232) },
    @{ Key = 'Purple'; Name = 'Purple'; Color = [System.Drawing.Color]::FromArgb(238, 233, 246) },
    @{ Key = 'Gold';   Name = 'Gold';   Color = [System.Drawing.Color]::FromArgb(251, 241, 224) },
    @{ Key = 'Gray';   Name = 'Gray';   Color = [System.Drawing.Color]::FromArgb(242, 242, 242) }
)

foreach ($choice in $irLayoutColorChoices) {
    $swatch = New-Object System.Windows.Forms.Button
    $swatch.Size = New-Object System.Drawing.Size(28, 24)
    $swatch.Margin = New-Object System.Windows.Forms.Padding(2, 1, 2, 0)
    $swatch.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $swatch.FlatAppearance.BorderSize = 1
    $swatch.FlatAppearance.BorderColor =
        [System.Drawing.Color]::FromArgb(150, 150, 150)
    $swatch.BackColor = $choice.Color
    $swatch.Text = if ($choice.Key -eq 'Auto') { 'A' } else { '' }
    $swatch.Tag = [string]$choice.Key
    $toolTip.SetToolTip($swatch, [string]$choice.Name)
    $swatch.Add_Click({
        param($sender, $eventArgs)
        Set-IrSelectedLayoutColor ([string]$sender.Tag)
    })
    [void]$irLayoutColorPanel.Controls.Add($swatch)
}

$irLayoutSizePanel = New-Object System.Windows.Forms.FlowLayoutPanel
$irLayoutSizePanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$irLayoutSizePanel.FlowDirection =
    [System.Windows.Forms.FlowDirection]::LeftToRight
$irLayoutSizePanel.WrapContents = $false
$irLayoutSizePanel.Padding = New-Object System.Windows.Forms.Padding(10, 2, 0, 0)
$irLayoutSizePanel.Visible = $false
$irHeaderLayout.Controls.Add($irLayoutSizePanel, 0, 2)

$irLayoutSizeLabel = New-Object System.Windows.Forms.Label
$irLayoutSizeLabel.Text = 'Button size:'
$irLayoutSizeLabel.AutoSize = $true
$irLayoutSizeLabel.Margin = New-Object System.Windows.Forms.Padding(0, 5, 8, 0)
[void]$irLayoutSizePanel.Controls.Add($irLayoutSizeLabel)

# Width x height in logical grid cells. Add larger presets here later without
# changing the persistence or layout engine.
$irLayoutSizeChoices = @(
    @{ Key = 'Default'; Label = 'Default'; ColumnSpan = 0; RowSpan = 0 },
    @{ Key = '1x1';     Label = '1x1';     ColumnSpan = 1; RowSpan = 1 },
    @{ Key = '2x1';     Label = '2x1';     ColumnSpan = 2; RowSpan = 1 },
    @{ Key = '1x2';     Label = '1x2';     ColumnSpan = 1; RowSpan = 2 },
    @{ Key = '2x2';     Label = '2x2';     ColumnSpan = 2; RowSpan = 2 }
)

foreach ($choice in $irLayoutSizeChoices) {
    $sizeButtonWidth = if ($choice.Key -eq 'Default') { 64 } else { 48 }
    $sizeButton = New-RfSmoothButton `
        ([string]$choice.Label) `
        $sizeButtonWidth `
        24 `
        ([System.Drawing.Color]::FromArgb(244, 244, 244)) `
        ([System.Drawing.Color]::FromArgb(45, 45, 45)) `
        ([System.Drawing.Color]::FromArgb(155, 155, 155))
    $sizeButton.Margin = New-Object System.Windows.Forms.Padding(2, 1, 2, 0)
    $sizeButton.Tag = [string]$choice.Key
    $sizeTip = if ($choice.Key -eq 'Default') {
        'Restore this command button to its original renderer size.'
    }
    else {
        ('Set button size to ' + [string]$choice.Label + ' grid cells.')
    }
    $toolTip.SetToolTip($sizeButton, $sizeTip)
    $sizeButton.Add_Click({
        param($sender, $eventArgs)
        Set-IrSelectedLayoutSize ([string]$sender.Tag)
    })
    [void]$irLayoutSizePanel.Controls.Add($sizeButton)
}

$irHeading = New-Object System.Windows.Forms.Label
$irHeading.Dock = 'Fill'
$irHeading.Padding = New-Object System.Windows.Forms.Padding(10, 6, 4, 0)
$irHeading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 14)
$irHeading.Text = 'Select an IR device'
$irHeadingPanel.Controls.Add($irHeading)

$irDetailLabel = New-Object System.Windows.Forms.Label
$irDetailLabel.Dock = 'Fill'
$irDetailLabel.Padding = New-Object System.Windows.Forms.Padding(11, 0, 4, 0)
$irDetailLabel.ForeColor = [System.Drawing.Color]::DimGray
$irHeaderLayout.Controls.Add($irDetailLabel, 0, 3)

$irTxLabel = New-Object System.Windows.Forms.Label
$irTxLabel.Text = 'Active IR transmitters'
$irTxLabel.Dock = 'Fill'
$irTxLabel.Padding = New-Object System.Windows.Forms.Padding(11, 2, 4, 0)
$irTxLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$irHeaderLayout.Controls.Add($irTxLabel, 0, 4)

$irTransmitterRow = New-Object System.Windows.Forms.TableLayoutPanel
$irTransmitterRow.Dock = 'Fill'
$irTransmitterRow.RowCount = 1
$irTransmitterRow.ColumnCount = 2
$irTransmitterRow.Margin = New-Object System.Windows.Forms.Padding(0)
$irTransmitterRow.Padding = New-Object System.Windows.Forms.Padding(0)
[void]$irTransmitterRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$irTransmitterRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
$irHeaderLayout.Controls.Add($irTransmitterRow, 0, 5)

$irTransmitterPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$irTransmitterPanel.Dock = 'Fill'
$irTransmitterPanel.Padding = New-Object System.Windows.Forms.Padding(8, 2, 0, 2)
$irTransmitterPanel.WrapContents = $false
$irTransmitterPanel.Margin = New-Object System.Windows.Forms.Padding(0)
$irTransmitterRow.Controls.Add($irTransmitterPanel, 0, 0)

# Keep Edit/Save/Cancel on the transmitter row, aligned against the far-right
# edge while transmitter selectors and Calibrate remain grouped on the left.
$irLayoutToolbar = New-Object System.Windows.Forms.FlowLayoutPanel
$irLayoutToolbar.AutoSize = $true
$irLayoutToolbar.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
$irLayoutToolbar.Dock = 'Fill'
$irLayoutToolbar.FlowDirection =
    [System.Windows.Forms.FlowDirection]::RightToLeft
$irLayoutToolbar.WrapContents = $false
$irLayoutToolbar.Margin = New-Object System.Windows.Forms.Padding(0)
$irLayoutToolbar.Padding = New-Object System.Windows.Forms.Padding(0, 2, 11, 2)
$irTransmitterRow.Controls.Add($irLayoutToolbar, 1, 0)
[void]$irLayoutToolbar.Controls.Add($irLayoutEditButton)
[void]$irLayoutToolbar.Controls.Add($irLayoutSaveButton)
[void]$irLayoutToolbar.Controls.Add($irLayoutCancelButton)

$irTxHintLabel = New-Object System.Windows.Forms.Label
$irTxHintLabel.Dock = 'Fill'
$irTxHintLabel.Padding = New-Object System.Windows.Forms.Padding(11, 2, 4, 0)
$irTxHintLabel.ForeColor = [System.Drawing.Color]::DimGray
$irHeaderLayout.Controls.Add($irTxHintLabel, 0, 6)

$irCommandPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$irCommandPanel.Dock = 'Fill'
$irCommandPanel.AutoScroll = $true
$irCommandPanel.WrapContents = $false
$irCommandPanel.FlowDirection = 'TopDown'
$irCommandPanel.Padding = New-Object System.Windows.Forms.Padding(7)
$irRightLayout.Controls.Add($irCommandPanel, 0, 1)

function Set-TowerStatus([string]$text, [bool]$isError = $false) {
    $status.Text = $text
    $status.ForeColor = if ($isError) {
        [System.Drawing.Color]::FromArgb(255, 170, 170)
    } else {
        [System.Drawing.Color]::Gainsboro
    }
}

function Get-ShortTransmitterLabel([string]$name) {
    if ($name -match '([0-9]{3})$') { return $Matches[1] }
    return $name
}

function Save-SelectedIrTransmitters {
    $config.selectedIrTransmitters = @($script:selectedIrTransmitters)
    Save-TowerConfig
}

function Set-IrTransmitterButtonState($button, [bool]$selected) {
    if ($selected) {
        $button.BackColor = [System.Drawing.Color]::SteelBlue
        $button.ForeColor = [System.Drawing.Color]::White
    }
    else {
        $button.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
        $button.ForeColor = [System.Drawing.SystemColors]::ControlText
    }
}

function Refresh-IrTransmitterButtons {
    foreach ($name in $script:irTransmitterButtons.Keys) {
        Set-IrTransmitterButtonState $script:irTransmitterButtons[$name] ($script:selectedIrTransmitters -contains $name)
    }

    $display = @($script:selectedIrTransmitters | ForEach-Object { Get-ShortTransmitterLabel $_ })
    if ($display.Count -eq 0) { $display = @('none') }
    $irTxHintLabel.Text = 'Selected outputs: ' + ($display -join ', ')
}

function Toggle-IrTransmitterSelection([string]$name) {
    if ($script:selectedIrTransmitters -contains $name) {
        if ($script:selectedIrTransmitters.Count -le 1) {
            return
        }
        $script:selectedIrTransmitters = @($script:selectedIrTransmitters | Where-Object { $_ -ne $name })
    }
    else {
        $script:selectedIrTransmitters += $name
    }
    $script:selectedIrTransmitters = @($script:selectedIrTransmitters | Select-Object -Unique)
    Save-SelectedIrTransmitters
    Refresh-IrTransmitterButtons
}

foreach ($txName in Get-AvailableIrTransmitters) {
    $txButton = New-Object System.Windows.Forms.Button
    $txButton.Text = Get-ShortTransmitterLabel $txName
    $txButton.Tag = $txName
    $txButton.Size = New-Object System.Drawing.Size(60, 28)
    $txButton.Margin = New-Object System.Windows.Forms.Padding(3)
    Set-IrButtonVisualStyle $txButton
    $txButton.Add_Click({ Toggle-IrTransmitterSelection ([string]$this.Tag) })
    $script:irTransmitterButtons[$txName] = $txButton
    [void]$irTransmitterPanel.Controls.Add($txButton)
}
Refresh-IrTransmitterButtons

$irCalibrateButton = New-RfSmoothButton `
    'Calibrate' `
    88 `
    28 `
    ([System.Drawing.Color]::FromArgb(224, 236, 250)) `
    ([System.Drawing.Color]::FromArgb(30, 70, 115)) `
    ([System.Drawing.Color]::FromArgb(115, 155, 195))
$irCalibrateButton.Margin =
    New-Object System.Windows.Forms.Padding(8, 3, 3, 3)

$irCalibrateButton.Add_Click({
    if ($null -eq $script:currentIrDevice) {
        [System.Windows.Forms.MessageBox]::Show(
            'Select an IR device first.',
            'IR Calibration',
            'OK',
            'Information'
        ) | Out-Null
        return
    }

    [void](Show-IrCalibrationWizard `
        ([string]$script:currentIrDevice.id) `
        $form)
})

$rfToolTip.SetToolTip(
    $irCalibrateButton,
    'Run IR transmission calibration for the selected device.'
)

[void]$irTransmitterPanel.Controls.Add(
    $irCalibrateButton
)

function Resolve-RemoteImageKey($device) {
    if ($null -eq $device) { return $null }

    $name = [string]$device.name
    $manufacturer = [string]$device.manufacturer

    if ($manufacturer -match 'Denon' -or $name -match 'AVR') { return 'Denon' }
    if ($manufacturer -match 'KPN' -or $name -match 'KPN') { return 'KPN' }
    if ($manufacturer -match 'EUROM' -or $name -match 'PAC') { return 'EUROM' }
    if ($manufacturer -match 'Logitech' -or $name -match 'Z5500') { return 'Logitech' }
    if ($manufacturer -match 'Dell' -or $name -match '1610HD') { return 'Dell' }
    if ($manufacturer -match 'Sony') { return 'Sony' }
    if ($name -match 'HDMI') { return 'HDMI' }
    if ($name -match 'LED\s*Light\s*Bar|Led\s*Light\s*Bar') { return 'LEDBar' }

    return $null
}

function Get-OrderedIrDevices($devices) {
    $deviceList = @($devices)
    if ($deviceList.Count -eq 0) { return @() }

    $byId = @{}
    foreach ($device in $deviceList) {
        $byId[[string]$device.id] = $device
    }

    $ordered = @()
    $seen = @{}
    foreach ($id in @($config.irDeviceOrder)) {
        $key = [string]$id
        if ($byId.ContainsKey($key) -and -not $seen.ContainsKey($key)) {
            $ordered += $byId[$key]
            $seen[$key] = $true
        }
    }

    foreach ($device in @($deviceList | Sort-Object name, id)) {
        $key = [string]$device.id
        if (-not $seen.ContainsKey($key)) {
            $ordered += $device
            $seen[$key] = $true
        }
    }

    $normalizedOrder = @($ordered | ForEach-Object { [string]$_.id })
    $oldOrder = @($config.irDeviceOrder | ForEach-Object { [string]$_ })
    if (($normalizedOrder -join "`n") -ne ($oldOrder -join "`n")) {
        $config.irDeviceOrder = $normalizedOrder
        Save-TowerConfig
    }

    return @($ordered)
}

function Get-DeviceImagePath($device) {
    if ($null -eq $device) { return $null }

    if (-not (Test-Path $deviceAssetDirectory)) {
        New-Item -ItemType Directory -Path $deviceAssetDirectory -Force | Out-Null
    }

    $names = @([string]$device.id, [string]$device.name)
    foreach ($name in $names) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        foreach ($extension in @('.jpg','.jpeg','.png','.bmp')) {
            $candidate = Join-Path $deviceAssetDirectory ($name + $extension)
            if (Test-Path $candidate) { return $candidate }
        }
    }

    # Until dedicated device photos are supplied, use the existing remote photo
    # as a useful visual fallback instead of an empty tile.
    return Resolve-RemoteImagePath $device
}

function Get-SensorImagePath($sensorName) {
    if ([string]::IsNullOrWhiteSpace([string]$sensorName)) {
        return $null
    }

    if (-not (Test-Path $sensorAssetDirectory)) {
        return $null
    }

    switch -Regex ([string]$sensorName) {
        '^Aquarium$' {
            foreach ($extension in @('.png','.jpg','.jpeg','.bmp')) {
                $candidate = Join-Path $sensorAssetDirectory ('aquarium' + $extension)
                if (Test-Path $candidate) {
                    return $candidate
                }
            }
        }
    }

    return $null
}

function Load-UnlockedImage([string]$path) {

    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path $path)) {

        return $null

    }



    try {

        $stream = [System.IO.File]::Open(

            $path,

            [System.IO.FileMode]::Open,

            [System.IO.FileAccess]::Read,

            [System.IO.FileShare]::ReadWrite)

        try {

            $source = [System.Drawing.Image]::FromStream($stream)

            try {

                return New-Object System.Drawing.Bitmap($source)

            }

            finally {

                $source.Dispose()

            }

        }

        finally {

            $stream.Dispose()

        }

    }

    catch {

        Write-TowerLog 'WARN' "Could not load image $path`: $($_.Exception.Message)"

        return $null

    }

}



function Open-IrDeviceFromHome([string]$deviceId) {
    for ($i = 0; $i -lt $irDeviceList.Items.Count; $i++) {
        if ([string]$irDeviceList.Items[$i].id -eq $deviceId) {
            $irDeviceList.SelectedIndex = $i
            $tabs.SelectedTab = $irTab
            return
        }
    }
}

function Refresh-IrInventoryAfterWizard {
    $script:irDevicesHaveLoaded = $false

    if ($null -eq $script:irReadJob) {
        Start-IrDeviceRead
    }
}

function Show-IrCalibrationWizard(
    [string]$deviceId,
    $owner = $form) {

    if ([string]::IsNullOrWhiteSpace($deviceId)) {
        return $false
    }

    $calibrationSucceeded = $false

    try {
        $prepare = Invoke-TowerPost '/api/v1/ir/calibration/prepare' @{
            device = $deviceId
        }
    }
    catch {
        $details = Get-TowerHttpErrorDetails `
            $_ `
            'POST' `
            '/api/v1/ir/calibration/prepare' `
            @{ device = $deviceId }

        [System.Windows.Forms.MessageBox]::Show(
            $details.Text,
            'IR Calibration',
            'OK',
            'Error'
        ) | Out-Null
        return $false
    }

    $commands = @($prepare.commands)

    if ($commands.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            'This device has no learned IR commands available for calibration.',
            'IR Calibration',
            'OK',
            'Information'
        ) | Out-Null
        return $false
    }

    $calForm = New-Object System.Windows.Forms.Form
    $calForm.Text = "IR Calibration - $deviceId"
    $calForm.StartPosition = 'CenterParent'
    $calForm.FormBorderStyle =
        [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $calForm.MaximizeBox = $false
    $calForm.MinimizeBox = $false
    $calForm.ShowInTaskbar = $false
    $calForm.ClientSize =
        New-Object System.Drawing.Size(720, 650)
    $calForm.Font =
        New-Object System.Drawing.Font('Segoe UI', 10)

    $calState = [pscustomobject]@{
        Job = $null
        Phase = 'idle'
        CenterCarrier = 38
        CurrentCarrier = 38
        CurrentDuty = 33
        DutyCandidates = @()
        DutyIndex = 0
        FirstObserved = -1
        SelectedDuty = 0
        CarrierCandidates = @()
        CarrierIndex = 0
        BestCarrier = 38
        BestHits = 10
        Completed = $false
        BatchMode = 'idle'
        BatchTapIndex = 0
        BatchCountdown = 0
        NextActionAt = [datetime]::MinValue
    }

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'IR Transmission Calibration'
    $title.Font =
        New-Object System.Drawing.Font('Segoe UI Semibold', 15)
    $title.Location =
        New-Object System.Drawing.Point(26, 20)
    $title.Size =
        New-Object System.Drawing.Size(650, 34)
    $calForm.Controls.Add($title)

    $intro = New-Object System.Windows.Forms.Label
    $intro.Text =
        "Calibration uses Tower-IR-TX-001 and 10 discrete taps per batch. " +
        "Count how many visible device actions occur. The existing Tower " +
        "calibration rules are used unchanged."
    $intro.Location =
        New-Object System.Drawing.Point(28, 58)
    $intro.Size =
        New-Object System.Drawing.Size(660, 48)
    $intro.ForeColor = [System.Drawing.Color]::DimGray
    $calForm.Controls.Add($intro)

    $commandLabel = New-Object System.Windows.Forms.Label
    $commandLabel.Text = 'Calibration command'
    $commandLabel.Location =
        New-Object System.Drawing.Point(30, 122)
    $commandLabel.Size =
        New-Object System.Drawing.Size(155, 24)
    $calForm.Controls.Add($commandLabel)

    $commandBox = New-Object System.Windows.Forms.ComboBox
    $commandBox.Location =
        New-Object System.Drawing.Point(195, 119)
    $commandBox.Size =
        New-Object System.Drawing.Size(300, 28)
    $commandBox.DropDownStyle =
        [System.Windows.Forms.ComboBoxStyle]::DropDownList

    foreach ($command in $commands) {
        [void]$commandBox.Items.Add([string]$command.id)
    }

    $calForm.Controls.Add($commandBox)

    $profileLabel = New-Object System.Windows.Forms.Label
    $profileLabel.Location =
        New-Object System.Drawing.Point(30, 160)
    $profileLabel.Size =
        New-Object System.Drawing.Size(650, 42)
    $profileLabel.ForeColor = [System.Drawing.Color]::DimGray
    $calForm.Controls.Add($profileLabel)

    $testGroup = New-Object System.Windows.Forms.GroupBox
    $testGroup.Text = 'Current test'
    $testGroup.Location =
        New-Object System.Drawing.Point(30, 214)
    $testGroup.Size =
        New-Object System.Drawing.Size(660, 118)
    $calForm.Controls.Add($testGroup)

    $candidateLabel = New-Object System.Windows.Forms.Label
    $candidateLabel.Text = 'Ready.'
    $candidateLabel.Location =
        New-Object System.Drawing.Point(18, 27)
    $candidateLabel.Size =
        New-Object System.Drawing.Size(610, 26)
    $candidateLabel.Font =
        New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $testGroup.Controls.Add($candidateLabel)

    $batchStatus = New-Object System.Windows.Forms.Label
    $batchStatus.Text =
        'Select a command and press Start Calibration.'
    $batchStatus.Location =
        New-Object System.Drawing.Point(18, 55)
    $batchStatus.Size =
        New-Object System.Drawing.Size(610, 24)
    $batchStatus.ForeColor = [System.Drawing.Color]::DimGray
    $testGroup.Controls.Add($batchStatus)

    $tapPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $tapPanel.Location =
        New-Object System.Drawing.Point(18, 82)
    $tapPanel.Size =
        New-Object System.Drawing.Size(390, 28)
    $tapPanel.FlowDirection =
        [System.Windows.Forms.FlowDirection]::LeftToRight
    $tapPanel.WrapContents = $false
    $tapPanel.Margin = New-Object System.Windows.Forms.Padding(0)
    $tapPanel.Padding = New-Object System.Windows.Forms.Padding(0)
    $testGroup.Controls.Add($tapPanel)

    $tapBoxes = @()

    for ($tap = 1; $tap -le 10; $tap++) {
        $box = New-Object System.Windows.Forms.Label
        $box.Text = ''
        $box.Size =
            New-Object System.Drawing.Size(28, 24)
        $box.Margin =
            New-Object System.Windows.Forms.Padding(0, 0, 7, 0)
        $box.BorderStyle =
            [System.Windows.Forms.BorderStyle]::FixedSingle
        $box.TextAlign =
            [System.Drawing.ContentAlignment]::MiddleCenter
        $box.Font =
            New-Object System.Drawing.Font(
                'Segoe UI Semibold',
                10
            )
        $box.BackColor =
            [System.Drawing.Color]::White

        [void]$tapPanel.Controls.Add($box)
        $tapBoxes += $box
    }

    $tapCountLabel = New-Object System.Windows.Forms.Label
    $tapCountLabel.Text = '0 / 10 sent'
    $tapCountLabel.Location =
        New-Object System.Drawing.Point(428, 83)
    $tapCountLabel.Size =
        New-Object System.Drawing.Size(180, 24)
    $tapCountLabel.TextAlign =
        [System.Drawing.ContentAlignment]::MiddleLeft
    $tapCountLabel.ForeColor =
        [System.Drawing.Color]::DimGray
    $testGroup.Controls.Add($tapCountLabel)

    $observedLabel = New-Object System.Windows.Forms.Label
    $observedLabel.Text = 'Observed device actions'
    $observedLabel.Location =
        New-Object System.Drawing.Point(30, 351)
    $observedLabel.Size =
        New-Object System.Drawing.Size(170, 24)
    $calForm.Controls.Add($observedLabel)

    $observedBox = New-Object System.Windows.Forms.NumericUpDown
    $observedBox.Location =
        New-Object System.Drawing.Point(205, 348)
    $observedBox.Size =
        New-Object System.Drawing.Size(80, 28)
    $observedBox.Minimum = 0
    $observedBox.Maximum = 30
    $observedBox.Enabled = $false
    $calForm.Controls.Add($observedBox)

    $submitObserved = New-RfSmoothButton `
        'Submit Result' `
        125 `
        30 `
        ([System.Drawing.Color]::White) `
        ([System.Drawing.Color]::FromArgb(35, 35, 35)) `
        ([System.Drawing.Color]::FromArgb(150, 145, 185))
    $submitObserved.Location =
        New-Object System.Drawing.Point(300, 346)
    $submitObserved.Enabled = $false
    $calForm.Controls.Add($submitObserved)

    $logGroup = New-Object System.Windows.Forms.GroupBox
    $logGroup.Text = 'Calibration progress'
    $logGroup.Location =
        New-Object System.Drawing.Point(30, 394)
    $logGroup.Size =
        New-Object System.Drawing.Size(660, 180)
    $calForm.Controls.Add($logGroup)

    $logBox = New-Object System.Windows.Forms.ListBox
    $logBox.Location =
        New-Object System.Drawing.Point(14, 25)
    $logBox.Size =
        New-Object System.Drawing.Size(630, 140)
    $logBox.Font =
        New-Object System.Drawing.Font('Consolas', 9)
    $logGroup.Controls.Add($logBox)

    $closeButton = New-RfSmoothButton `
        'Close' `
        100 `
        38 `
        ([System.Drawing.Color]::White) `
        ([System.Drawing.Color]::FromArgb(35, 35, 35)) `
        ([System.Drawing.Color]::FromArgb(150, 145, 185))
    $closeButton.Location =
        New-Object System.Drawing.Point(30, 594)
    $calForm.Controls.Add($closeButton)

    $startButton = New-RfSmoothButton `
        'Start Calibration' `
        150 `
        38 `
        ([System.Drawing.Color]::FromArgb(224, 236, 250)) `
        ([System.Drawing.Color]::FromArgb(30, 70, 115)) `
        ([System.Drawing.Color]::FromArgb(115, 155, 195))
    $startButton.Location =
        New-Object System.Drawing.Point(540, 594)
    $calForm.Controls.Add($startButton)

    $appendLog = {
        param([string]$text)

        [void]$logBox.Items.Add($text)

        if ($logBox.Items.Count -gt 0) {
            $logBox.TopIndex =
                $logBox.Items.Count - 1
        }
    }.GetNewClosure()

    $selectedCommandInfo = {
        $selected = [string]$commandBox.SelectedItem

        return @(
            $commands |
                Where-Object {
                    [string]$_.id -eq $selected
                }
        )[0]
    }.GetNewClosure()

    $updateProfileLabel = {
        $info = & $selectedCommandInfo

        if ($null -eq $info) {
            return
        }

        $existingText = ''
        if ([bool]$prepare.alreadyCalibrated) {
            $existingText =
                " | Existing profile: " +
                "$([string]$prepare.existingCarrierKhz) kHz / " +
                "$([string]$prepare.existingDutyPercent)%"
        }

        $profileLabel.Text =
            "RX carrier candidate: $([string]$info.carrierKhz) kHz" +
            " | Transmitter: $([string]$prepare.transmitter)" +
            $existingText
    }.GetNewClosure()

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 100

    $resetTapProgress = {
        foreach ($box in $tapBoxes) {
            $box.Text = ''
            $box.BackColor =
                [System.Drawing.Color]::White
        }

        $tapCountLabel.Text = '0 / 10 sent'
    }.GetNewClosure()

    $markTapSending = {
        param([int]$index)

        if ($index -ge 0 -and
            $index -lt $tapBoxes.Count) {

            $tapBoxes[$index].Text = '•'
        }
    }.GetNewClosure()

    $markTapComplete = {
        param([int]$index)

        if ($index -ge 0 -and
            $index -lt $tapBoxes.Count) {

            $tapBoxes[$index].Text = 'X'
            $tapBoxes[$index].BackColor =
                [System.Drawing.Color]::FromArgb(
                    224,
                    244,
                    228
                )
        }

        $tapCountLabel.Text =
            "$([int]$index + 1) / 10 sent"
    }.GetNewClosure()

    $startBatch = {
        param(
            [int]$carrier,
            [int]$duty,
            [string]$phase
        )

        if ($null -ne $calState.Job -or
            $calState.BatchMode -notin @(
                'idle',
                'await-result'
            )) {
            return
        }

        $calState.CurrentCarrier = $carrier
        $calState.CurrentDuty = $duty
        $calState.Phase = $phase
        $calState.BatchTapIndex = 0
        $calState.BatchCountdown = 5
        $calState.BatchMode = 'countdown'
        $calState.NextActionAt =
            [datetime]::Now.AddSeconds(1)

        & $resetTapProgress

        $candidateLabel.Text =
            "Testing $carrier kHz at $duty% duty on Tower-IR-TX-001"

        $batchStatus.Text =
            'Starting in 5 seconds...'

        $observedBox.Enabled = $false
        $submitObserved.Enabled = $false
        $startButton.Enabled = $false
        $commandBox.Enabled = $false

        & $appendLog (
            "SEND  $carrier kHz / $duty%  [$phase]"
        )

        $timer.Start()
    }.GetNewClosure()

    $saveCalibration = {
        try {
            $response = Invoke-TowerPost `
                '/api/v1/ir/calibration/save' `
                @{
                    device = $deviceId
                    command = [string]$commandBox.SelectedItem
                    carrierKhz = [int]$calState.BestCarrier
                    dutyPercent = [int]$calState.SelectedDuty
                }

            & $appendLog (
                "SAVED $([string]$response.carrierKhz) kHz / " +
                "$([string]$response.dutyPercent)% / TX-001"
            )

            $candidateLabel.Text =
                'Calibration complete'

            $batchStatus.Text =
                "Saved profile: $([string]$response.carrierKhz) kHz / " +
                "$([string]$response.dutyPercent)% duty / Tower-IR-TX-001"

            $observedBox.Enabled = $false
            $submitObserved.Enabled = $false
            $startButton.Text = 'Calibrated'
            $startButton.Enabled = $false
            $commandBox.Enabled = $false
            $calState.Completed = $true
            $calState.BatchMode = 'idle'
            $calibrationSucceeded = $true

            Refresh-IrInventoryAfterWizard
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                'IR Calibration',
                'OK',
                'Error'
            ) | Out-Null

            $startButton.Enabled = $true
            $commandBox.Enabled = $true
        }
    }.GetNewClosure()

    $startNextCarrier = {
        if ($calState.CarrierIndex -ge
            $calState.CarrierCandidates.Count) {

            & $saveCalibration
            return
        }

        $candidate =
            [int]$calState.CarrierCandidates[
                $calState.CarrierIndex
            ]

        $calState.CarrierIndex =
            [int]$calState.CarrierIndex + 1

        & $startBatch `
            $candidate `
            ([int]$calState.SelectedDuty) `
            'carrier'
    }.GetNewClosure()

    $startNextDuty = {
        if ($calState.DutyIndex -ge
            $calState.DutyCandidates.Count) {

            $candidateLabel.Text =
                'No clean duty pass found'

            $batchStatus.Text =
                'No calibration profile was saved. Existing profile remains unchanged.'

            & $appendLog 'STOP  no clean duty candidate'

            $startButton.Enabled = $true
            $commandBox.Enabled = $true
            $calState.Phase = 'idle'
            $calState.BatchMode = 'idle'
            return
        }

        $candidate =
            [int]$calState.DutyCandidates[
                $calState.DutyIndex
            ]

        $calState.DutyIndex =
            [int]$calState.DutyIndex + 1

        $calState.FirstObserved = -1

        & $startBatch `
            ([int]$calState.CenterCarrier) `
            $candidate `
            'duty-first'
    }.GetNewClosure()

    $timer.Add_Tick({
        $now = [datetime]::Now

        if ($calState.BatchMode -eq 'countdown') {
            if ($now -lt $calState.NextActionAt) {
                return
            }

            $calState.BatchCountdown =
                [int]$calState.BatchCountdown - 1

            if ($calState.BatchCountdown -gt 0) {
                $batchStatus.Text =
                    "Starting in $([int]$calState.BatchCountdown) seconds..."
                $calState.NextActionAt =
                    $now.AddSeconds(1)
                return
            }

            $calState.BatchMode = 'ready-tap'
        }

        if ($calState.BatchMode -eq 'gap') {
            if ($now -lt $calState.NextActionAt) {
                return
            }

            $calState.BatchMode = 'ready-tap'
        }

        if ($calState.BatchMode -eq 'ready-tap') {
            if ($null -ne $calState.Job) {
                return
            }

            $tapNumber =
                [int]$calState.BatchTapIndex + 1

            $batchStatus.Text =
                "Sending tap $tapNumber of 10..."

            & $markTapSending `
                ([int]$calState.BatchTapIndex)

            $calState.Job = Start-TowerPostJob `
                '/api/v1/ir/calibration/batch' `
                @{
                    device = $deviceId
                    command =
                        [string]$commandBox.SelectedItem
                    carrierKhz =
                        [int]$calState.CurrentCarrier
                    dutyPercent =
                        [int]$calState.CurrentDuty
                    count = 1
                    preDelaySeconds = 0
                    intervalMilliseconds = 0
                } `
                10

            $calState.BatchMode = 'sending'
            return
        }

        if ($calState.BatchMode -ne 'sending') {
            if ($calState.BatchMode -eq 'idle' -and
                $null -eq $calState.Job) {
                $timer.Stop()
            }

            return
        }

        if ($null -eq $calState.Job) {
            return
        }

        if ($calState.Job.State -eq 'Running') {
            return
        }

        $job = $calState.Job
        $calState.Job = $null

        if ($job.State -ne 'Completed') {
            $errorText =
                Get-TowerReadJobError $job

            Remove-TowerReadJob $job

            $batchStatus.Text =
                'Calibration transmission failed.'

            & $appendLog (
                "ERROR $errorText"
            )

            $calState.BatchMode = 'idle'
            $startButton.Enabled = $true
            $commandBox.Enabled = $true
            $timer.Stop()

            [System.Windows.Forms.MessageBox]::Show(
                $errorText,
                'IR Calibration',
                'OK',
                'Error'
            ) | Out-Null

            return
        }

        try {
            [void](Receive-Job -Job $job -ErrorAction Stop)
        }
        catch {
            $errorText = $_.Exception.Message
            Remove-TowerReadJob $job

            $batchStatus.Text =
                'Calibration transmission failed.'

            & $appendLog (
                "ERROR $errorText"
            )

            $calState.BatchMode = 'idle'
            $startButton.Enabled = $true
            $commandBox.Enabled = $true
            $timer.Stop()

            return
        }

        Remove-TowerReadJob $job

        & $markTapComplete `
            ([int]$calState.BatchTapIndex)

        $calState.BatchTapIndex =
            [int]$calState.BatchTapIndex + 1

        if ($calState.BatchTapIndex -ge 10) {
            $calState.BatchMode = 'await-result'
            $timer.Stop()

            $batchStatus.Text =
                'Batch complete. Enter how many visible device actions occurred.'

            $observedBox.Value = 0
            $observedBox.Enabled = $true
            $submitObserved.Enabled = $true
            $observedBox.Focus()
            return
        }

        $calState.BatchMode = 'gap'
        $calState.NextActionAt =
            [datetime]::Now.AddSeconds(1)

        $batchStatus.Text =
            "Tap $([int]$calState.BatchTapIndex) of 10 sent. " +
            "Next tap in 1 second..."
    })

    $submitObserved.Add_Click({
        $observed = [int]$observedBox.Value

        $observedBox.Enabled = $false
        $submitObserved.Enabled = $false
        $calState.BatchMode = 'idle'

        switch ([string]$calState.Phase) {
            'duty-first' {
                & $appendLog (
                    "RESULT $([int]$calState.CurrentCarrier) kHz / " +
                    "$([int]$calState.CurrentDuty)% = $observed/10"
                )

                if ($observed -gt 10) {
                    $candidateLabel.Text =
                        'Over-triggering detected'
                    $batchStatus.Text =
                        'This command is unsuitable for calibration. Choose another command.'
                    $startButton.Enabled = $true
                    $commandBox.Enabled = $true
                    $calState.Phase = 'idle'
                    $calState.BatchMode = 'idle'
                    return
                }

                if ($observed -lt
                    [int]$prepare.confirmThreshold) {

                    & $startNextDuty
                    return
                }

                $calState.FirstObserved =
                    $observed

                & $startBatch `
                    ([int]$calState.CenterCarrier) `
                    ([int]$calState.CurrentDuty) `
                    'duty-confirm'
            }

            'duty-confirm' {
                & $appendLog (
                    "CONFIRM $([int]$calState.CurrentCarrier) kHz / " +
                    "$([int]$calState.CurrentDuty)% = $observed/10"
                )

                if ($observed -gt 10) {
                    $candidateLabel.Text =
                        'Over-triggering detected'
                    $batchStatus.Text =
                        'This command is unsuitable for calibration. Choose another command.'
                    $startButton.Enabled = $true
                    $commandBox.Enabled = $true
                    $calState.Phase = 'idle'
                    $calState.BatchMode = 'idle'
                    return
                }

                if ($calState.FirstObserved -eq 10 -and
                    $observed -eq 10) {

                    $calState.SelectedDuty =
                        [int]$calState.CurrentDuty
                    $calState.BestCarrier =
                        [int]$calState.CenterCarrier
                    $calState.BestHits = 10

                    & $appendLog (
                        "PASS  duty $([int]$calState.SelectedDuty)%"
                    )

                    $candidates = @()

                    if (($calState.CenterCarrier - 1) -ge 20) {
                        $candidates +=
                            [int]($calState.CenterCarrier - 1)
                    }

                    if (($calState.CenterCarrier + 1) -le 60) {
                        $candidates +=
                            [int]($calState.CenterCarrier + 1)
                    }

                    $calState.CarrierCandidates =
                        @($candidates)
                    $calState.CarrierIndex = 0

                    & $startNextCarrier
                    return
                }

                if ($calState.FirstObserved -ge
                        [int]$prepare.confirmThreshold -and
                    $observed -ge
                        [int]$prepare.confirmThreshold) {

                    & $appendLog (
                        "MARGINAL duty $([int]$calState.CurrentDuty)%"
                    )
                }

                & $startNextDuty
            }

            'carrier' {
                & $appendLog (
                    "CARRIER $([int]$calState.CurrentCarrier) kHz = $observed/10"
                )

                if ($observed -le 10 -and
                    $observed -gt
                        [int]$calState.BestHits) {

                    $calState.BestHits =
                        $observed
                    $calState.BestCarrier =
                        [int]$calState.CurrentCarrier
                }
                elseif ($observed -gt 10) {
                    & $appendLog (
                        "IGNORE over-trigger at " +
                        "$([int]$calState.CurrentCarrier) kHz"
                    )
                }

                & $startNextCarrier
            }
        }
    })

    $commandBox.Add_SelectedIndexChanged({
        & $updateProfileLabel
    })

    $startButton.Add_Click({
        if ($calState.Job -ne $null) {
            return
        }

        $info = & $selectedCommandInfo

        if ($null -eq $info) {
            return
        }

        $logBox.Items.Clear()

        $calState.CenterCarrier =
            [int]$info.carrierKhz

        $calState.BestCarrier =
            [int]$info.carrierKhz

        $calState.DutyCandidates =
            @($prepare.dutyCandidates)

        $calState.DutyIndex = 0
        $calState.SelectedDuty = 0
        $calState.FirstObserved = -1
        $calState.Completed = $false
        $calState.BatchMode = 'idle'
        $calState.BatchTapIndex = 0

        & $resetTapProgress

        & $appendLog (
            "START command '$([string]$commandBox.SelectedItem)'"
        )
        & $appendLog (
            "RX candidate $([int]$calState.CenterCarrier) kHz"
        )

        & $startNextDuty
    })

    $closeButton.Add_Click({
        if ($null -ne $calState.Job -or
            $calState.BatchMode -in @(
                'countdown',
                'ready-tap',
                'sending',
                'gap'
            )) {
            return
        }

        $calForm.Close()
    })

    $calForm.Add_FormClosing({
        param($sender, $eventArgs)

        if ($null -ne $calState.Job -or
            $calState.BatchMode -in @(
                'countdown',
                'ready-tap',
                'sending',
                'gap'
            )) {
            $eventArgs.Cancel = $true

            [System.Windows.Forms.MessageBox]::Show(
                'A calibration batch is still running. Wait for it to finish before closing.',
                'IR Calibration',
                'OK',
                'Information'
            ) | Out-Null
        }
    })

    $suggestedIndex = -1
    for ($i = 0; $i -lt $commandBox.Items.Count; $i++) {
        if ([string]$commandBox.Items[$i] -eq
            [string]$prepare.suggestedCommand) {
            $suggestedIndex = $i
            break
        }
    }

    if ($suggestedIndex -ge 0) {
        $commandBox.SelectedIndex =
            $suggestedIndex
    }
    else {
        $commandBox.SelectedIndex = 0
    }

    & $updateProfileLabel

    [void]$calForm.ShowDialog($owner)

    $timer.Stop()
    $calState.BatchMode = 'idle'

    if ($null -ne $calState.Job) {
        try {
            Stop-Job -Job $calState.Job -ErrorAction SilentlyContinue
        }
        catch {}

        Remove-TowerReadJob $calState.Job
        $calState.Job = $null
    }

    $calForm.Dispose()

    return [bool]$calibrationSucceeded
}

function Show-AddIrDeviceWizard {
    $wizard = New-Object System.Windows.Forms.Form
    $wizard.Text = 'Add IR Remote'
    $wizard.StartPosition = 'CenterParent'
    $wizard.FormBorderStyle =
        [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $wizard.MaximizeBox = $false
    $wizard.MinimizeBox = $false
    $wizard.ShowInTaskbar = $false
    $wizard.ClientSize =
        New-Object System.Drawing.Size(650, 665)
    $wizard.Font =
        New-Object System.Drawing.Font('Segoe UI', 10)

    $state = [pscustomobject]@{
        Device = $null
        LastCapture = $null
        Recorded = 0
        CleanupApproved = $false
    }

    # -----------------------------------------------------------------------
    # STEP 1 - REMOTE DETAILS
    # -----------------------------------------------------------------------
    $detailsPanel = New-Object System.Windows.Forms.Panel
    $detailsPanel.Dock = 'Fill'
    $wizard.Controls.Add($detailsPanel)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'Add IR Remote'
    $title.Font =
        New-Object System.Drawing.Font('Segoe UI Semibold', 15)
    $title.Location =
        New-Object System.Drawing.Point(28, 24)
    $title.Size =
        New-Object System.Drawing.Size(570, 34)
    $detailsPanel.Controls.Add($title)

    $subtitle = New-Object System.Windows.Forms.Label
    $subtitle.Text =
        'Create the remote profile first. IR commands are learned in the next step.'
    $subtitle.Location =
        New-Object System.Drawing.Point(30, 62)
    $subtitle.Size =
        New-Object System.Drawing.Size(570, 24)
    $subtitle.ForeColor = [System.Drawing.Color]::DimGray
    $detailsPanel.Controls.Add($subtitle)

    $manufacturerLabel = New-Object System.Windows.Forms.Label
    $manufacturerLabel.Text = 'Manufacturer'
    $manufacturerLabel.Location =
        New-Object System.Drawing.Point(30, 112)
    $manufacturerLabel.Size =
        New-Object System.Drawing.Size(160, 24)
    $detailsPanel.Controls.Add($manufacturerLabel)

    $manufacturerBox = New-Object System.Windows.Forms.TextBox
    $manufacturerBox.Location =
        New-Object System.Drawing.Point(205, 109)
    $manufacturerBox.Size =
        New-Object System.Drawing.Size(390, 28)
    $detailsPanel.Controls.Add($manufacturerBox)

    $remoteNameLabel = New-Object System.Windows.Forms.Label
    $remoteNameLabel.Text = 'Remote name'
    $remoteNameLabel.Location =
        New-Object System.Drawing.Point(30, 158)
    $remoteNameLabel.Size =
        New-Object System.Drawing.Size(160, 24)
    $detailsPanel.Controls.Add($remoteNameLabel)

    $remoteNameBox = New-Object System.Windows.Forms.TextBox
    $remoteNameBox.Location =
        New-Object System.Drawing.Point(205, 155)
    $remoteNameBox.Size =
        New-Object System.Drawing.Size(390, 28)
    $detailsPanel.Controls.Add($remoteNameBox)

    $deviceNameLabel = New-Object System.Windows.Forms.Label
    $deviceNameLabel.Text = 'Device name'
    $deviceNameLabel.Location =
        New-Object System.Drawing.Point(30, 204)
    $deviceNameLabel.Size =
        New-Object System.Drawing.Size(160, 24)
    $detailsPanel.Controls.Add($deviceNameLabel)

    $deviceNameBox = New-Object System.Windows.Forms.TextBox
    $deviceNameBox.Location =
        New-Object System.Drawing.Point(205, 201)
    $deviceNameBox.Size =
        New-Object System.Drawing.Size(390, 28)
    $detailsPanel.Controls.Add($deviceNameBox)

    $deviceNameHint = New-Object System.Windows.Forms.Label
    $deviceNameHint.Text =
        'This becomes the device name in Tower Control and the IR data folder.'
    $deviceNameHint.Location =
        New-Object System.Drawing.Point(205, 232)
    $deviceNameHint.Size =
        New-Object System.Drawing.Size(390, 40)
    $deviceNameHint.ForeColor = [System.Drawing.Color]::DimGray
    $detailsPanel.Controls.Add($deviceNameHint)

    $locationLabel = New-Object System.Windows.Forms.Label
    $locationLabel.Text = 'Location'
    $locationLabel.Location =
        New-Object System.Drawing.Point(30, 292)
    $locationLabel.Size =
        New-Object System.Drawing.Size(160, 24)
    $detailsPanel.Controls.Add($locationLabel)

    $locationBox = New-Object System.Windows.Forms.ComboBox
    $locationBox.Location =
        New-Object System.Drawing.Point(205, 289)
    $locationBox.Size =
        New-Object System.Drawing.Size(390, 28)
    $locationBox.DropDownStyle =
        [System.Windows.Forms.ComboBoxStyle]::DropDownList

    [void]$locationBox.Items.Add('Living Room')
    [void]$locationBox.Items.Add('Bedroom')
    [void]$locationBox.Items.Add('Facilities')

    $locationBox.SelectedIndex = 0
    $detailsPanel.Controls.Add($locationBox)

    $advancedButton = New-RfSmoothButton `
        'Advanced...' `
        110 `
        30 `
        ([System.Drawing.Color]::White) `
        ([System.Drawing.Color]::FromArgb(35, 35, 35)) `
        ([System.Drawing.Color]::FromArgb(150, 145, 185))
    $advancedButton.Location =
        New-Object System.Drawing.Point(205, 344)
    $detailsPanel.Controls.Add($advancedButton)

    $advancedPanel = New-Object System.Windows.Forms.Panel
    $advancedPanel.Location =
        New-Object System.Drawing.Point(330, 334)
    $advancedPanel.Size =
        New-Object System.Drawing.Size(265, 58)
    $advancedPanel.Visible = $false
    $detailsPanel.Controls.Add($advancedPanel)

    $transmitterLabel = New-Object System.Windows.Forms.Label
    $transmitterLabel.Text = 'Default transmitter'
    $transmitterLabel.Location =
        New-Object System.Drawing.Point(0, 8)
    $transmitterLabel.Size =
        New-Object System.Drawing.Size(120, 24)
    $advancedPanel.Controls.Add($transmitterLabel)

    $transmitterBox = New-Object System.Windows.Forms.ComboBox
    $transmitterBox.Location =
        New-Object System.Drawing.Point(126, 5)
    $transmitterBox.Size =
        New-Object System.Drawing.Size(135, 28)
    $transmitterBox.DropDownStyle =
        [System.Windows.Forms.ComboBoxStyle]::DropDownList

    foreach ($tx in 1..6) {
        [void]$transmitterBox.Items.Add(
            ('Tower-IR-TX-{0:d3}' -f $tx)
        )
    }

    $transmitterBox.SelectedIndex = 0
    $advancedPanel.Controls.Add($transmitterBox)

    $txHint = New-Object System.Windows.Forms.Label
    $txHint.Text = 'Normal default: TX-001'
    $txHint.Location =
        New-Object System.Drawing.Point(126, 34)
    $txHint.Size =
        New-Object System.Drawing.Size(135, 20)
    $txHint.Font =
        New-Object System.Drawing.Font('Segoe UI', 8.5)
    $txHint.ForeColor = [System.Drawing.Color]::DimGray
    $advancedPanel.Controls.Add($txHint)

    $advancedButton.Add_Click({
        $advancedPanel.Visible = -not $advancedPanel.Visible

        if ($advancedPanel.Visible) {
            $advancedButton.Text = 'Advanced <<'
        }
        else {
            $advancedButton.Text = 'Advanced...'
        }

        $advancedButton.Invalidate()
    })

    $cancelButton = New-RfSmoothButton `
        'Cancel' `
        100 `
        38 `
        ([System.Drawing.Color]::White) `
        ([System.Drawing.Color]::FromArgb(35, 35, 35)) `
        ([System.Drawing.Color]::FromArgb(150, 145, 185))
    $cancelButton.Location =
        New-Object System.Drawing.Point(30, 444)
    $detailsPanel.Controls.Add($cancelButton)

    $createButton = New-RfSmoothButton `
        'Create Remote' `
        145 `
        38 `
        ([System.Drawing.Color]::FromArgb(224, 244, 228)) `
        ([System.Drawing.Color]::FromArgb(30, 80, 40)) `
        ([System.Drawing.Color]::FromArgb(130, 175, 135))
    $createButton.Location =
        New-Object System.Drawing.Point(450, 444)
    $detailsPanel.Controls.Add($createButton)

    $cancelButton.Add_Click({
        $wizard.Close()
    })

    # -----------------------------------------------------------------------
    # STEP 2 - LEARN COMMANDS
    # -----------------------------------------------------------------------
    $learnPanel = New-Object System.Windows.Forms.Panel
    $learnPanel.Dock = 'Fill'
    $learnPanel.Visible = $false
    $wizard.Controls.Add($learnPanel)

    $learnTitle = New-Object System.Windows.Forms.Label
    $learnTitle.Text = 'Learn IR Commands'
    $learnTitle.Font =
        New-Object System.Drawing.Font('Segoe UI Semibold', 15)
    $learnTitle.Location =
        New-Object System.Drawing.Point(28, 22)
    $learnTitle.Size =
        New-Object System.Drawing.Size(570, 34)
    $learnPanel.Controls.Add($learnTitle)

    $learnDevice = New-Object System.Windows.Forms.Label
    $learnDevice.Location =
        New-Object System.Drawing.Point(30, 60)
    $learnDevice.Size =
        New-Object System.Drawing.Size(570, 24)
    $learnDevice.ForeColor = [System.Drawing.Color]::DimGray
    $learnPanel.Controls.Add($learnDevice)

    $commandLabel = New-Object System.Windows.Forms.Label
    $commandLabel.Text = 'Command name'
    $commandLabel.Location =
        New-Object System.Drawing.Point(30, 108)
    $commandLabel.Size =
        New-Object System.Drawing.Size(150, 24)
    $learnPanel.Controls.Add($commandLabel)

    $commandBox = New-Object System.Windows.Forms.TextBox
    $commandBox.Location =
        New-Object System.Drawing.Point(190, 105)
    $commandBox.Size =
        New-Object System.Drawing.Size(405, 28)
    $learnPanel.Controls.Add($commandBox)

    $commandDescriptionLabel = New-Object System.Windows.Forms.Label
    $commandDescriptionLabel.Text = 'Description'
    $commandDescriptionLabel.Location =
        New-Object System.Drawing.Point(30, 150)
    $commandDescriptionLabel.Size =
        New-Object System.Drawing.Size(150, 24)
    $learnPanel.Controls.Add($commandDescriptionLabel)

    $commandDescriptionBox = New-Object System.Windows.Forms.TextBox
    $commandDescriptionBox.Location =
        New-Object System.Drawing.Point(190, 147)
    $commandDescriptionBox.Size =
        New-Object System.Drawing.Size(405, 28)
    $learnPanel.Controls.Add($commandDescriptionBox)

    $instruction = New-Object System.Windows.Forms.Label
    $instruction.Text =
        "Aim the remote at the receiver array. When you press READY, " +
        "Tower records all six receivers for 8 seconds. Press the same " +
        "remote button several times during that recording."
    $instruction.Location =
        New-Object System.Drawing.Point(30, 194)
    $instruction.Size =
        New-Object System.Drawing.Size(565, 58)
    $instruction.ForeColor = [System.Drawing.Color]::DimGray
    $learnPanel.Controls.Add($instruction)

    $resultGroup = New-Object System.Windows.Forms.GroupBox
    $resultGroup.Text = 'Capture result'
    $resultGroup.Location =
        New-Object System.Drawing.Point(30, 267)
    $resultGroup.Size =
        New-Object System.Drawing.Size(565, 286)
    $learnPanel.Controls.Add($resultGroup)

    $resultText = New-Object System.Windows.Forms.Label
    $resultText.Text =
        'No capture yet.'
    $resultText.Location =
        New-Object System.Drawing.Point(16, 26)
    $resultText.Size =
        New-Object System.Drawing.Size(532, 92)
    $resultText.Font =
        New-Object System.Drawing.Font(
            'Consolas',
            9)
    $resultGroup.Controls.Add($resultText)

    $receiverList = New-Object System.Windows.Forms.ListView
    $receiverList.Location =
        New-Object System.Drawing.Point(16, 124)
    $receiverList.Size =
        New-Object System.Drawing.Size(532, 146)
    $receiverList.View =
        [System.Windows.Forms.View]::Details
    $receiverList.FullRowSelect = $true
    $receiverList.GridLines = $true
    $receiverList.HeaderStyle =
        [System.Windows.Forms.ColumnHeaderStyle]::Nonclickable
    $receiverList.Font =
        New-Object System.Drawing.Font('Consolas', 8.5)

    [void]$receiverList.Columns.Add('GPIO', 46)
    [void]$receiverList.Columns.Add('Receiver', 92)
    [void]$receiverList.Columns.Add('kHz', 44)
    [void]$receiverList.Columns.Add('Timings', 60)
    [void]$receiverList.Columns.Add('Pulses', 55)
    [void]$receiverList.Columns.Add('Frames', 54)
    [void]$receiverList.Columns.Add('Valid', 48)
    [void]$receiverList.Columns.Add('Result', 76)

    $resultGroup.Controls.Add($receiverList)

    $finishButton = New-RfSmoothButton `
        'Cancel' `
        100 `
        38 `
        ([System.Drawing.Color]::White) `
        ([System.Drawing.Color]::FromArgb(35, 35, 35)) `
        ([System.Drawing.Color]::FromArgb(150, 145, 185))
    $finishButton.Location =
        New-Object System.Drawing.Point(30, 580)
    $learnPanel.Controls.Add($finishButton)

    $retryButton = New-RfSmoothButton `
        'Retry' `
        95 `
        38 `
        ([System.Drawing.Color]::White) `
        ([System.Drawing.Color]::FromArgb(35, 35, 35)) `
        ([System.Drawing.Color]::FromArgb(150, 145, 185))
    $retryButton.Location =
        New-Object System.Drawing.Point(345, 580)
    $retryButton.Visible = $false
    $learnPanel.Controls.Add($retryButton)

    $saveButton = New-RfSmoothButton `
        'Save & Next' `
        115 `
        38 `
        ([System.Drawing.Color]::FromArgb(224, 244, 228)) `
        ([System.Drawing.Color]::FromArgb(30, 80, 40)) `
        ([System.Drawing.Color]::FromArgb(130, 175, 135))
    $saveButton.Location =
        New-Object System.Drawing.Point(480, 580)
    $saveButton.Visible = $false
    $learnPanel.Controls.Add($saveButton)

    $readyButton = New-RfSmoothButton `
        'READY - RECORD' `
        145 `
        38 `
        ([System.Drawing.Color]::FromArgb(224, 236, 250)) `
        ([System.Drawing.Color]::FromArgb(30, 70, 115)) `
        ([System.Drawing.Color]::FromArgb(115, 155, 195))
    $readyButton.Location =
        New-Object System.Drawing.Point(480, 580)
    $learnPanel.Controls.Add($readyButton)

    $completePanel = New-Object System.Windows.Forms.Panel
    $completePanel.Dock = 'Fill'
    $completePanel.Visible = $false
    $wizard.Controls.Add($completePanel)

    $completeTitle = New-Object System.Windows.Forms.Label
    $completeTitle.Text = 'IR Remote Created'
    $completeTitle.Font =
        New-Object System.Drawing.Font('Segoe UI Semibold', 15)
    $completeTitle.Location =
        New-Object System.Drawing.Point(30, 34)
    $completeTitle.Size =
        New-Object System.Drawing.Size(570, 34)
    $completePanel.Controls.Add($completeTitle)

    $completeText = New-Object System.Windows.Forms.Label
    $completeText.Location =
        New-Object System.Drawing.Point(32, 92)
    $completeText.Size =
        New-Object System.Drawing.Size(560, 110)
    $completePanel.Controls.Add($completeText)

    $calibrationQuestion = New-Object System.Windows.Forms.Label
    $calibrationQuestion.Text =
        'Would you like to calibrate IR transmission now?'
    $calibrationQuestion.Font =
        New-Object System.Drawing.Font('Segoe UI Semibold', 11)
    $calibrationQuestion.Location =
        New-Object System.Drawing.Point(32, 232)
    $calibrationQuestion.Size =
        New-Object System.Drawing.Size(560, 32)
    $completePanel.Controls.Add($calibrationQuestion)

    $calibrationHint = New-Object System.Windows.Forms.Label
    $calibrationHint.Text =
        'Calibration is optional and can also be started later from the IR device screen.'
    $calibrationHint.Location =
        New-Object System.Drawing.Point(32, 274)
    $calibrationHint.Size =
        New-Object System.Drawing.Size(560, 42)
    $calibrationHint.ForeColor =
        [System.Drawing.Color]::DimGray
    $completePanel.Controls.Add($calibrationHint)

    $completeSkip = New-RfSmoothButton `
        'Skip & Finish' `
        130 `
        40 `
        ([System.Drawing.Color]::White) `
        ([System.Drawing.Color]::FromArgb(35, 35, 35)) `
        ([System.Drawing.Color]::FromArgb(150, 145, 185))
    $completeSkip.Location =
        New-Object System.Drawing.Point(32, 565)
    $completePanel.Controls.Add($completeSkip)

    $completeCalibrate = New-RfSmoothButton `
        'Calibrate' `
        130 `
        40 `
        ([System.Drawing.Color]::FromArgb(224, 236, 250)) `
        ([System.Drawing.Color]::FromArgb(30, 70, 115)) `
        ([System.Drawing.Color]::FromArgb(115, 155, 195))
    $completeCalibrate.Location =
        New-Object System.Drawing.Point(462, 565)
    $completePanel.Controls.Add($completeCalibrate)

    $completeSkip.Add_Click({
        $state.CleanupApproved = $true
        Refresh-IrInventoryAfterWizard
        $wizard.Close()
    })

    $completeCalibrate.Add_Click({
        $calibrated = Show-IrCalibrationWizard `
            ([string]$state.Device.deviceId) `
            $wizard

        if ([bool]$calibrated) {
            $state.CleanupApproved = $true
            Refresh-IrInventoryAfterWizard
            $wizard.Close()
        }
    })

    $finishButton.Add_Click({
        if ([int]$state.Recorded -gt 0) {
            $completeText.Text =
                "$([string]$state.Device.deviceName) is ready.`r`n`r`n" +
                "Commands learned this session: $([string]$state.Recorded)`r`n" +
                "Location: $([string]$state.Device.location)`r`n" +
                "Default transmitter: $([string]$state.Device.transmitter)"

            $learnPanel.Visible = $false
            $completePanel.Visible = $true
            $completePanel.BringToFront()
            return
        }

        # Before the first successful command save the remote profile is only
        # provisional. Cancelling must clean it up so no invisible/orphan
        # device profile remains on the Pi.
        if ([int]$state.Recorded -eq 0 -and
            $null -ne $state.Device) {

            $deviceId = [string]$state.Device.deviceId
            $deviceName = [string]$state.Device.deviceName

            $answer = [System.Windows.Forms.MessageBox]::Show(
                "Cancel creating '$deviceName'?`r`n`r`n" +
                "No IR commands have been saved yet. The provisional " +
                "device profile will be deleted from PI3A.",
                'Cancel IR Remote',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question,
                [System.Windows.Forms.MessageBoxDefaultButton]::Button2
            )

            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
                return
            }

            try {
                Invoke-TowerPost '/api/v1/devices/delete' @{
                    device = $deviceId
                } | Out-Null

                Set-TowerStatus "Cancelled IR remote $deviceName"
            }
            catch {
                $details = Get-TowerHttpErrorDetails `
                    $_ `
                    'POST' `
                    '/api/v1/devices/delete' `
                    @{ device = $deviceId }

                [System.Windows.Forms.MessageBox]::Show(
                    "The wizard was not closed because the provisional " +
                    "device could not be cleaned up.`r`n`r`n" +
                    $details.Text,
                    'Cancel IR Remote',
                    'OK',
                    'Error'
                ) | Out-Null

                return
            }
        }

        $state.CleanupApproved = $true
        Refresh-IrInventoryAfterWizard
        $wizard.Close()
    })

    $retryButton.Add_Click({
        $state.LastCapture = $null
        $resultText.Text = 'No capture yet.'
        $receiverList.Items.Clear()
        $retryButton.Visible = $false
        $saveButton.Visible = $false
        $readyButton.Visible = $true
        $commandBox.Focus()
    })

    $readyButton.Add_Click({
        $commandName = $commandBox.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($commandName)) {
            [System.Windows.Forms.MessageBox]::Show(
                'Enter a command name first.',
                'Learn IR Command',
                'OK',
                'Warning'
            ) | Out-Null
            $commandBox.Focus()
            return
        }

        try {
            $readyButton.Enabled = $false
            $resultText.Text =
                "RECORDING NOW...`r`n`r`n" +
                "Press '$commandName' several times during the 8-second capture."
            $wizard.Refresh()

            $response = Invoke-TowerPost '/api/v1/ir/learn/capture' @{
                device = [string]$state.Device.deviceId
                command = $commandName
                description = $commandDescriptionBox.Text.Trim()
                seconds = 8.0
                force = $false
            }

            $state.LastCapture = $response

            $receiverList.BeginUpdate()
            $receiverList.Items.Clear()

            foreach ($receiver in @($response.receivers)) {
                $item = New-Object System.Windows.Forms.ListViewItem(
                    [string]$receiver.gpio
                )

                [void]$item.SubItems.Add(
                    [string]$receiver.receiver
                )
                [void]$item.SubItems.Add(
                    [string]$receiver.carrierKhz
                )
                [void]$item.SubItems.Add(
                    [string]$receiver.timings
                )
                [void]$item.SubItems.Add(
                    [string]$receiver.pulses
                )
                [void]$item.SubItems.Add(
                    [string]$receiver.frames
                )
                [void]$item.SubItems.Add(
                    [string]$receiver.valid
                )
                [void]$item.SubItems.Add(
                    [string]$receiver.result
                )

                [void]$receiverList.Items.Add($item)
            }

            $receiverList.EndUpdate()

            $protocol = [string]$response.protocol
            if ([string]::IsNullOrWhiteSpace($protocol)) {
                $protocol = 'RAW'
            }

            $addressText = if ($protocol -eq 'RAW') {
                '-'
            }
            else {
                ('0x{0:X}' -f [uint32]$response.address)
            }

            $commandCodeText = if ($protocol -eq 'RAW') {
                '-'
            }
            else {
                ('0x{0:X2}' -f [uint32]$response.decodedCommand)
            }

            $duplicateText = ''
            $duplicates = @($response.duplicates)
            if ($duplicates.Count -gt 0) {
                $duplicateText =
                    "`r`nDUPLICATE: " +
                    ($duplicates -join ', ')
            }

            $noteText = ''
            if (-not [string]::IsNullOrWhiteSpace([string]$response.note)) {
                $noteText =
                    "`r`n" +
                    [string]$response.note
            }

            $resultText.Text =
                "Protocol : $protocol`r`n" +
                "Address  : $addressText    Command: $commandCodeText`r`n" +
                "Carrier  : $([string]$response.carrierKhz) kHz`r`n" +
                "Receiver : GPIO$([string]$response.receiverGpio) " +
                "$([string]$response.receiverModel)`r`n" +
                "Frames   : $([string]$response.initialFrames) initial / " +
                "$([string]$response.repeatFrames) repeat" +
                $duplicateText +
                $noteText

            $readyButton.Visible = $false
            $retryButton.Visible = $true
            $saveButton.Visible = $true
        }
        catch {
            $state.LastCapture = $null
            $readyButton.Enabled = $true

            $details = Get-TowerHttpErrorDetails `
                $_ `
                'POST' `
                '/api/v1/ir/learn/capture' `
                @{
                    device = [string]$state.Device.deviceId
                    command = $commandName
                    description = $commandDescriptionBox.Text.Trim()
                    seconds = 8.0
                    force = $false
                }

            $resultText.Text =
                "Recording was not saved.`r`n`r`n" +
                $details.Text

            $retryButton.Visible = $true
            $saveButton.Visible = $false
            $readyButton.Visible = $false
        }
        finally {
            $readyButton.Enabled = $true
        }
    })

    $saveButton.Add_Click({
        if ($null -eq $state.LastCapture) {
            return
        }

        $duplicates = @($state.LastCapture.duplicates)
        $acceptDuplicate = $false

        if ($duplicates.Count -gt 0) {
            $answer = [System.Windows.Forms.MessageBox]::Show(
                "This IR signal is already stored as:`r`n`r`n" +
                ($duplicates -join "`r`n") +
                "`r`n`r`nKeep this duplicate command anyway?",
                'Duplicate IR signal',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning,
                [System.Windows.Forms.MessageBoxDefaultButton]::Button2
            )

            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
                return
            }

            $acceptDuplicate = $true
        }

        try {
            $saveButton.Enabled = $false

            Invoke-TowerPost '/api/v1/ir/learn/save' @{
                captureId = [string]$state.LastCapture.captureId
                device = [string]$state.Device.deviceId
                command = $commandBox.Text.Trim()
                description = $commandDescriptionBox.Text.Trim()
                force = $false
                acceptDuplicate = $acceptDuplicate
            } | Out-Null

            if ([int]$state.Recorded -eq 0) {
                $config.irDisplayCount =
                    [int]$config.irDisplayCount + 1
                Save-TowerConfig

                # First successfully saved command commits the provisional
                # remote. From this point the left button is a normal Finish.
                $finishButton.Text = 'Finish'
                $finishButton.Invalidate()
            }

            $state.Recorded = [int]$state.Recorded + 1
            $state.LastCapture = $null

            Refresh-IrInventoryAfterWizard

            $resultText.Text =
                "Saved successfully.`r`n`r`n" +
                "Commands learned this session: " +
                [string]$state.Recorded

            $receiverList.Items.Clear()

            $commandBox.Text = ''
            $commandDescriptionBox.Text = ''
            $retryButton.Visible = $false
            $saveButton.Visible = $false
            $readyButton.Visible = $true
            $commandBox.Focus()
        }
        catch {
            $details = Get-TowerHttpErrorDetails `
                $_ `
                'POST' `
                '/api/v1/ir/learn/save' `
                @{
                    captureId = [string]$state.LastCapture.captureId
                    device = [string]$state.Device.deviceId
                    command = $commandBox.Text.Trim()
                    description = $commandDescriptionBox.Text.Trim()
                    force = $false
                    acceptDuplicate = $acceptDuplicate
                }

            [System.Windows.Forms.MessageBox]::Show(
                $details.Text,
                'Save IR Command',
                'OK',
                'Error'
            ) | Out-Null
        }
        finally {
            $saveButton.Enabled = $true
        }
    })

    $createButton.Add_Click({
        $deviceName = $deviceNameBox.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($deviceName)) {
            [System.Windows.Forms.MessageBox]::Show(
                'Enter a device name first.',
                'Add IR Remote',
                'OK',
                'Warning'
            ) | Out-Null
            $deviceNameBox.Focus()
            return
        }

        try {
            $createButton.Enabled = $false

            $response = Invoke-TowerPost '/api/v1/ir/devices/create' @{
                manufacturer = $manufacturerBox.Text.Trim()
                remoteName = $remoteNameBox.Text.Trim()
                deviceName = $deviceName
                location = [string]$locationBox.SelectedItem
                transmitter = [string]$transmitterBox.SelectedItem
            }

            $state.Device = $response

            $learnDevice.Text =
                "$([string]$response.deviceName)  |  " +
                "$([string]$response.manufacturer)  |  " +
                "$([string]$response.remoteName)  |  " +
                "$([string]$response.location)  |  " +
                "$([string]$response.transmitter)"

            $detailsPanel.Visible = $false
            $learnPanel.Visible = $true
            $learnPanel.BringToFront()

            Set-TowerStatus 'IR remote created - ready to learn commands'
            $commandBox.Focus()
        }
        catch {
            $createButton.Enabled = $true

            $details = Get-TowerHttpErrorDetails `
                $_ `
                'POST' `
                '/api/v1/ir/devices/create' `
                @{
                    manufacturer = $manufacturerBox.Text.Trim()
                    remoteName = $remoteNameBox.Text.Trim()
                    deviceName = $deviceName
                    location = [string]$locationBox.SelectedItem
                    transmitter = [string]$transmitterBox.SelectedItem
                }

            [System.Windows.Forms.MessageBox]::Show(
                $details.Text,
                'Add IR Remote',
                'OK',
                'Error'
            ) | Out-Null
        }
    })

    $wizard.Add_FormClosing({
        param($sender, $eventArgs)

        if ($state.CleanupApproved) {
            return
        }

        # Closing via the title-bar X before the first saved command must have
        # the same semantics as Cancel.
        if ([int]$state.Recorded -eq 0 -and
            $null -ne $state.Device) {

            $deviceId = [string]$state.Device.deviceId
            $deviceName = [string]$state.Device.deviceName

            $answer = [System.Windows.Forms.MessageBox]::Show(
                "Cancel creating '$deviceName'?`r`n`r`n" +
                "No IR commands have been saved yet. The provisional " +
                "device profile will be deleted from PI3A.",
                'Cancel IR Remote',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question,
                [System.Windows.Forms.MessageBoxDefaultButton]::Button2
            )

            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
                $eventArgs.Cancel = $true
                return
            }

            try {
                Invoke-TowerPost '/api/v1/devices/delete' @{
                    device = $deviceId
                } | Out-Null

                $state.CleanupApproved = $true
                Set-TowerStatus "Cancelled IR remote $deviceName"
                Refresh-IrInventoryAfterWizard
            }
            catch {
                $eventArgs.Cancel = $true

                $details = Get-TowerHttpErrorDetails `
                    $_ `
                    'POST' `
                    '/api/v1/devices/delete' `
                    @{ device = $deviceId }

                [System.Windows.Forms.MessageBox]::Show(
                    "The wizard was not closed because the provisional " +
                    "device could not be cleaned up.`r`n`r`n" +
                    $details.Text,
                    'Cancel IR Remote',
                    'OK',
                    'Error'
                ) | Out-Null

                return
            }
        }
        else {
            $state.CleanupApproved = $true
        }
    })

    $manufacturerBox.Focus()
    [void]$wizard.ShowDialog($form)
    $wizard.Dispose()
}


function Set-HomeTileButtonStyle($button) {
    if ($null -eq $button) { return }

    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.UseVisualStyleBackColor = $false
    $button.BackColor = [System.Drawing.Color]::White
    $button.ForeColor = [System.Drawing.Color]::Black
    $button.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $button.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $button.FlatAppearance.BorderSize = 0
    Set-IrButtonVisualStyle $button
}

function Clear-HomeDeviceTiles {
    foreach ($control in @($homeDevicePanel.Controls)) {
        if ($control -is [System.Windows.Forms.Panel]) {
            foreach ($child in @($control.Controls)) {
                if ($child -is [System.Windows.Forms.PictureBox] -and
                    $null -ne $child.Image) {
                    try { $child.Image.Dispose() } catch {}
                    $child.Image = $null
                }
            }
        }
    }
    $homeDevicePanel.Controls.Clear()
}

function Refresh-HomeDevices {
    if ($null -eq $homeDevicePanel) { return }

    $homeDevicePanel.SuspendLayout()
    Clear-HomeDeviceTiles

    foreach ($device in @($script:irDevices)) {
        $card = New-Object System.Windows.Forms.Panel
        $card.Size = New-Object System.Drawing.Size(174, 196)
        $card.Margin = New-Object System.Windows.Forms.Padding(8)
        $card.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $card.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)

        $picture = New-Object System.Windows.Forms.PictureBox
        $picture.Location = New-Object System.Drawing.Point(8, 8)
        $picture.Size = New-Object System.Drawing.Size(156, 140)
        $picture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
        $picture.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
        $card.Controls.Add($picture)

        $path = Get-DeviceImagePath $device
        $image = Load-UnlockedImage $path
        if ($null -ne $image) { $picture.Image = $image }

        $button = New-Object System.Windows.Forms.Button
        $button.Text = [string]$device.name
        $button.Location = New-Object System.Drawing.Point(10, 153)
        $button.Size = New-Object System.Drawing.Size(154, 32)
        Set-HomeTileButtonStyle $button
        $capturedId = [string]$device.id
        $button.Add_Click({ Open-IrDeviceFromHome $capturedId }.GetNewClosure())
        $picture.Add_Click({ Open-IrDeviceFromHome $capturedId }.GetNewClosure())
        $card.Controls.Add($button)

        $toolTip.SetToolTip($picture, [string]$device.name)
        $toolTip.SetToolTip($button, [string]$device.name)
        [void]$homeDevicePanel.Controls.Add($card)
    }

    $addCard = New-Object System.Windows.Forms.Panel
    $addCard.Size = New-Object System.Drawing.Size(174, 196)
    $addCard.Margin = New-Object System.Windows.Forms.Padding(8)
    $addCard.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $addCard.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)

    $addButton = New-Object System.Windows.Forms.Button
    $addButton.Text = "+`nAdd Device"
    $addButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 18)
    $addButton.Location = New-Object System.Drawing.Point(8, 8)
    $addButton.Size = New-Object System.Drawing.Size(156, 178)
    $addButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $addButton.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
    $addButton.Add_Click({ Show-AddIrDeviceWizard })
    $addCard.Controls.Add($addButton)
    [void]$homeDevicePanel.Controls.Add($addCard)

    $homeDevicePanel.ResumeLayout()
}

function Update-RemotePreviewHeading($device) {
    if ($null -eq $device) {
        $script:remotePreviewFullTitle = 'Remote'
    }
    elseif (-not [string]::IsNullOrWhiteSpace(
            [string]$device.remoteName)) {
        $script:remotePreviewFullTitle =
            [string]$device.remoteName
    }
    else {
        $script:remotePreviewFullTitle =
            ([string]$device.name + ' remote')
    }

    $titleText =
        $script:remotePreviewFullTitle

    $maxWidth = [Math]::Max(
        70,
        $remotePreviewGroup.ClientSize.Width - 28
    )

    if ([System.Windows.Forms.TextRenderer]::MeasureText(
            $titleText,
            $remotePreviewGroup.Font).Width -le $maxWidth) {

        $remotePreviewGroup.Text = $titleText
        return
    }

    $candidate = $titleText

    while ($candidate.Length -gt 4) {
        $candidate =
            $candidate.Substring(
                0,
                $candidate.Length - 1
            )

        $display = $candidate + '...'

        if ([System.Windows.Forms.TextRenderer]::MeasureText(
                $display,
                $remotePreviewGroup.Font).Width -le $maxWidth) {

            $remotePreviewGroup.Text = $display
            return
        }
    }

    $remotePreviewGroup.Text = 'Remote'
}

$remotePreviewGroup.Add_Resize({
    Update-RemotePreviewHeading `
        $script:currentIrDevice
})

function Ensure-RemoteAssets {
    if (-not (Test-Path $remoteAssetDirectory)) {
        New-Item -ItemType Directory -Path $remoteAssetDirectory -Force | Out-Null
    }

    $existingImages = @(Get-ChildItem -Path $remoteAssetDirectory -File -ErrorAction SilentlyContinue | Where-Object {
        $_.Extension -match '^\.(jpg|jpeg|png|bmp)$'
    })
    if ($existingImages.Count -gt 0) { return }

    $rarPath = Join-Path $remoteAssetDirectory 'Remotes.rar'
    if (-not (Test-Path $rarPath)) { return }

    try {
        $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
        if ($null -ne $tar) {
            & $tar.Path -xf $rarPath -C $remoteAssetDirectory 2>$null
        }
    }
    catch {
        Write-TowerLog 'ERROR' "Could not auto-extract remote image archive: $($_.Exception.Message)"
    }
}

function Get-SafeRemoteImageStem($device) {
    if ($null -eq $device) { return '' }

    $stem = [string]$device.id
    if ([string]::IsNullOrWhiteSpace($stem)) {
        $stem = [string]$device.name
    }

    if ([string]::IsNullOrWhiteSpace($stem)) {
        return ''
    }

    foreach ($character in [System.IO.Path]::GetInvalidFileNameChars()) {
        $stem = $stem.Replace([string]$character, '_')
    }

    return $stem.Trim()
}

function Get-CustomRemoteImagePath($device) {
    $stem = Get-SafeRemoteImageStem $device
    if ([string]::IsNullOrWhiteSpace($stem)) { return $null }

    if (-not (Test-Path $customRemoteImageDirectory)) {
        return $null
    }

    foreach ($extension in @('.jpg','.jpeg','.png','.bmp')) {
        $candidate =
            Join-Path $customRemoteImageDirectory ($stem + $extension)
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Remove-CustomRemoteImage($device) {
    $stem = Get-SafeRemoteImageStem $device
    if ([string]::IsNullOrWhiteSpace($stem)) { return }

    if (-not (Test-Path $customRemoteImageDirectory)) { return }

    foreach ($extension in @('.jpg','.jpeg','.png','.bmp')) {
        $candidate =
            Join-Path $customRemoteImageDirectory ($stem + $extension)
        if (Test-Path $candidate) {
            try {
                Remove-Item -Path $candidate -Force
            }
            catch {
                Write-TowerLog 'WARN' (
                    "Could not remove custom remote image '$candidate': " +
                    "$($_.Exception.Message)"
                )
            }
        }
    }
}

function Select-CustomRemoteImage {
    $device = $script:currentIrDevice
    if ($null -eq $device) {
        [System.Windows.Forms.MessageBox]::Show(
            'Select an IR remote first.',
            'Choose remote image',
            'OK',
            'Information'
        ) | Out-Null
        return
    }

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title =
        "Choose image for $([string]$device.name)"
    $dialog.Filter =
        'Image files|*.jpg;*.jpeg;*.png;*.bmp|' +
        'JPEG files|*.jpg;*.jpeg|' +
        'PNG files|*.png|' +
        'Bitmap files|*.bmp|' +
        'All files|*.*'
    $dialog.CheckFileExists = $true
    $dialog.Multiselect = $false

    try {
        if ($dialog.ShowDialog() -ne
            [System.Windows.Forms.DialogResult]::OK) {
            return
        }

        $stem = Get-SafeRemoteImageStem $device
        if ([string]::IsNullOrWhiteSpace($stem)) {
            throw 'The selected device has no usable ID or name.'
        }

        New-Item `
            -ItemType Directory `
            -Path $customRemoteImageDirectory `
            -Force |
            Out-Null

        Remove-CustomRemoteImage $device

        $extension =
            [System.IO.Path]::GetExtension($dialog.FileName).ToLowerInvariant()

        if (@('.jpg','.jpeg','.png','.bmp') -notcontains $extension) {
            throw 'Unsupported image format.'
        }

        $destination =
            Join-Path $customRemoteImageDirectory ($stem + $extension)

        Copy-Item `
            -LiteralPath $dialog.FileName `
            -Destination $destination `
            -Force

        Write-TowerLog 'INFO' (
            "Custom remote image set for '$([string]$device.name)': " +
            "$destination"
        )

        Update-RemotePreview $device
        Refresh-HomeDevices
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Could not set the remote image.`n`n$($_.Exception.Message)",
            'Remote image',
            'OK',
            'Error'
        ) | Out-Null
    }
    finally {
        $dialog.Dispose()
    }
}

function Resolve-RemoteImagePath($device) {
    $customPath = Get-CustomRemoteImagePath $device
    if (-not [string]::IsNullOrWhiteSpace($customPath)) {
        return $customPath
    }

    $key = Resolve-RemoteImageKey $device
    if ([string]::IsNullOrWhiteSpace($key)) { return $null }

    Ensure-RemoteAssets

    $match = Get-ChildItem -Path $remoteAssetDirectory -File -ErrorAction SilentlyContinue | Where-Object {
        $_.BaseName -ieq $key -and $_.Extension -match '^\.(jpg|jpeg|png|bmp)$'
    } | Select-Object -First 1

    if ($null -ne $match) { return $match.FullName }
    return $null
}

function Set-RemotePreviewMessage([string]$message) {
    if ([string]::IsNullOrWhiteSpace($message)) {
        # Never call this function recursively here. The old implementation
        # called Set-RemotePreviewMessage '' from inside the empty-message
        # branch, causing unbounded PowerShell recursion whenever a remote
        # image loaded successfully.
        $remotePreviewHint.Text = ''
        $remotePreviewHint.Visible = $false
        $remotePreviewLayout.RowStyles[1].Height = 0
    }
    else {
        $remotePreviewHint.Text = $message
        $remotePreviewHint.Visible = $true
        $remotePreviewLayout.RowStyles[1].Height = 34
    }
}

function Update-RemotePreview($device) {
    try {
        if ($null -ne $remotePreviewPicture.Image) {
            $remotePreviewPicture.Image.Dispose()
            $remotePreviewPicture.Image = $null
        }
    }
    catch {}

    $remotePreviewAddImageButton.Visible = $false
    Update-RemotePreviewHeading $device

    if ($null -eq $device) {
        Set-RemotePreviewMessage ''
        return
    }

    $path = Resolve-RemoteImagePath $device
    if ([string]::IsNullOrWhiteSpace($path)) {
        Set-RemotePreviewMessage ''
        $remotePreviewAddImageButton.Visible = $true
        Position-RemotePreviewAddImageButton
        $remotePreviewAddImageButton.BringToFront()
        return
    }

    try {
        $image = Load-UnlockedImage $path
        if ($null -eq $image) {
            throw 'Image could not be loaded.'
        }

        $remotePreviewPicture.Image = $image
        $remotePreviewAddImageButton.Visible = $false
        Set-RemotePreviewMessage ''
    }
    catch {
        Set-RemotePreviewMessage 'Could not load remote image.'
        $remotePreviewAddImageButton.Visible = $true
        Position-RemotePreviewAddImageButton
        $remotePreviewAddImageButton.BringToFront()
    }
}

function Get-IrCommandCategory([string]$name) {
    if ($name -match 'Power|Standby|Sleep') { return 'Power' }
    if ($name -match 'Volume|Mute|Sub|Center|Surround|Effect') { return 'Audio' }
    if ($name -match 'InternetRadio|Source|Input|HDMI|MediaPlayer|Blu-ray|Game|Aux|TV Audio|CD|Tuner|USB|Phone|Bluetooth|HEOS|Aspect Ratio|Auto-Adjust|Blank Screen|Video Mode|Freeze|VGA|S-Video|Video ') { return 'Sources / Display' }
    if ($name -match 'Arrow|\bOK\b|Menu|Guide|Gids|Back|Info|Option|Setup|TV Quick|Radio') { return 'Navigation' }
    if ($name -match 'Play|Pause|Stop|Forward|Rewind|Record|Fast') { return 'Media' }
    if ($name -match '^[0-9]$|Channel') { return 'Numbers / Channels' }
    if ($name -match 'Red|Green|Blue|Yellow|White|Lime|Purple|Brightness|Mode|Timer|Temp|Speed|RGB|Strobe|Fade|Smooth') { return 'Modes / Colors' }
    return 'Other'
}

function Get-IrCategoryOrder([string]$category) {
    switch ($category) {
        'Power' { return 1 }
        'Navigation' { return 2 }
        'Audio' { return 3 }
        'Media' { return 4 }
        'Numbers / Channels' { return 5 }
        'Sources / Display' { return 6 }
        'Modes / Colors' { return 7 }
        default { return 8 }
    }
}

function Get-IrButtonBaseColor([string]$category) {
    switch ($category) {
        'Power' { return [System.Drawing.Color]::FromArgb(246, 226, 226) }
        'Navigation' { return [System.Drawing.Color]::FromArgb(229, 238, 250) }
        'Audio' { return [System.Drawing.Color]::FromArgb(230, 244, 232) }
        'Media' { return [System.Drawing.Color]::FromArgb(238, 233, 246) }
        'Numbers / Channels' { return [System.Drawing.Color]::FromArgb(242, 242, 242) }
        'Sources / Display' { return [System.Drawing.Color]::FromArgb(251, 241, 224) }
        'Modes / Colors' { return [System.Drawing.Color]::FromArgb(241, 236, 248) }
        default { return [System.Drawing.Color]::FromArgb(241, 241, 241) }
    }
}

function Get-IrButtonPressedColor([string]$category) {
    switch ($category) {
        'Power' { return [System.Drawing.Color]::FromArgb(223, 188, 188) }
        'Navigation' { return [System.Drawing.Color]::FromArgb(184, 208, 239) }
        'Audio' { return [System.Drawing.Color]::FromArgb(188, 224, 194) }
        'Media' { return [System.Drawing.Color]::FromArgb(212, 198, 231) }
        'Numbers / Channels' { return [System.Drawing.Color]::FromArgb(219, 219, 219) }
        'Sources / Display' { return [System.Drawing.Color]::FromArgb(240, 216, 176) }
        'Modes / Colors' { return [System.Drawing.Color]::FromArgb(223, 208, 242) }
        default { return [System.Drawing.Color]::FromArgb(220, 220, 220) }
    }
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
    $capturedDisplayName = "$($device.name) - $displayText"
    $button.Add_Click({
        if ($script:irLayoutEditMode) { return }
        Send-IrCommand $capturedDeviceId $capturedCommandId $capturedDisplayName
    }.GetNewClosure())

    if (-not [string]::IsNullOrWhiteSpace([string]$command.description)) {
        $toolTip.SetToolTip($button, [string]$command.description)
    }

    return $button
}

function Get-IrCommandDisplayName($command) {
    if ($null -eq $command) { return '' }

    if ([string]::IsNullOrWhiteSpace([string]$command.name)) {
        return [string]$command.id
    }
    return [string]$command.name
}

function Find-IrCommand($commands, [string]$name) {
    foreach ($command in @($commands)) {
        if ((Get-IrCommandDisplayName $command) -eq $name) {
            return $command
        }
    }
    return $null
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

    # Start from the renderer's default group membership, then move any command
    # that has a persisted manual group override into its saved target group.
    foreach ($sourceGroup in $groups) {
        foreach ($entry in @($sourceGroup.Tag.Entries)) {
            $saved = Get-IrSavedLayoutEntryForCommand `
                $deviceId `
                ([string]$entry.CommandId)

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
        }
    }
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

    if ($script:irLayoutEditMode) {
        $irHeaderLayout.RowStyles[1].Height = 32
        $irHeaderLayout.RowStyles[2].Height = 32
        $irRightLayout.RowStyles[0].Height = 216
    }
    else {
        $irHeaderLayout.RowStyles[1].Height = 0
        $irHeaderLayout.RowStyles[2].Height = 0
        $irRightLayout.RowStyles[0].Height = 152
    }
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
        'Edit Layout: drag buttons between groups or select one to change color/size.'
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

$irLayoutEditButton.Add_Click({ Start-IrCommandLayoutEdit })
$irLayoutSaveButton.Add_Click({ Save-IrCommandLayoutEdit })
$irLayoutCancelButton.Add_Click({ Cancel-IrCommandLayoutEdit })
Update-IrLayoutToolbarState

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
    $button.Dock = [System.Windows.Forms.DockStyle]::Fill

    $groupTag = $bundle.Group.Tag
    if ([string]::IsNullOrWhiteSpace([string]$groupTag.DeviceId)) {
        $groupTag.DeviceId = [string]$device.id
    }

    $entry = [pscustomobject]@{
        Button = $button
        CommandId = [string]$command.id
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


function Add-IrGridPlaceholder(
    $bundle,
    [string]$text,
    [int]$row,
    [int]$column,
    [int]$rowSpan = 1,
    [int]$columnSpan = 1) {

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $text
    $button.Dock = [System.Windows.Forms.DockStyle]::Fill
    $button.Margin = New-Object System.Windows.Forms.Padding(6)
    $button.Enabled = $false
    $button.BackColor = [System.Drawing.Color]::FromArgb(238, 238, 238)
    Set-IrButtonVisualStyle $button
    $button.ForeColor = [System.Drawing.Color]::DimGray

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


function Render-IrGenericGroups($device, $commands) {
    $categorized = @{}

    foreach ($command in @($commands)) {
        $displayText = Get-IrCommandDisplayName $command
        $category = Get-IrCommandCategory $displayText

        if (-not $categorized.ContainsKey($category)) {
            $categorized[$category] =
                New-Object System.Collections.ArrayList
        }
        [void]$categorized[$category].Add($command)
    }

    $categories = @(
        $categorized.Keys |
            Sort-Object { Get-IrCategoryOrder $_ }, { $_ }
    )

    foreach ($category in $categories) {
        $sorted = @(
            $categorized[$category] |
                Sort-Object {
                    Get-IrCommandDisplayName $_
                }
        )
        Add-IrFlowGroup $device $category $sorted
    }
}

function Refresh-IrCommandGroupWidths {
    foreach ($group in @($irCommandPanel.Controls)) {
        if ($group -is [System.Windows.Forms.GroupBox] -and
            $null -ne $group.Tag) {
            Resize-IrCommandGroup $group
        }
    }
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

function Test-DenonZone2Command($command) {
    $name = Get-IrCommandDisplayName $command
    return $name -match '^(?:Zone\s*2|Z2|Z)[\s:_-]*'
}

function Get-DenonBaseName($command) {
    $name = Get-IrCommandDisplayName $command
    return (
        $name -replace '^(?:Zone\s*2|Z2|Z)[\s:_-]*', ''
    )
}

function Find-DenonCommand($commands, [string]$baseName) {
    foreach ($command in @($commands)) {
        if ((Get-DenonBaseName $command) -eq $baseName) {
            return $command
        }
    }
    return $null
}

function Find-DenonPowerCommand($commands) {
    $exact = Find-DenonCommand $commands 'Power'
    if ($null -ne $exact) { return $exact }

    foreach ($command in @($commands)) {
        $baseName = Get-DenonBaseName $command

        if ($baseName -match '^(?i:Power)(?:\s|$|[-_/])' -or
            $baseName -match '^(?i:On[/ -]?Off|Power Toggle)$') {
            return $command
        }
    }

    return $null
}

function Get-DenonButtonLabel($command, [string]$baseLabel = '') {
    if ($null -eq $command) { return '' }

    $label = if ([string]::IsNullOrWhiteSpace($baseLabel)) {
        Get-DenonBaseName $command
    }
    else {
        $baseLabel
    }

    if ($script:denonZoneMode -eq 'Zone2') {
        return "Z $label"
    }
    return $label
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


function Render-DenonGenericGroups($device, $commands) {
    $categorized = @{}

    foreach ($command in @($commands)) {
        $baseName = Get-DenonBaseName $command
        $category = Get-IrCommandCategory $baseName

        if (-not $categorized.ContainsKey($category)) {
            $categorized[$category] =
                New-Object System.Collections.ArrayList
        }
        [void]$categorized[$category].Add($command)
    }

    $categories = @(
        $categorized.Keys |
            Sort-Object { Get-IrCategoryOrder $_ }, { $_ }
    )

    foreach ($category in $categories) {
        $sorted = @(
            $categorized[$category] |
                Sort-Object {
                    Get-DenonBaseName $_
                }
        )
        Add-DenonFlowGroup $device $category $sorted
    }
}

function Render-DenonRemote($device, $commands) {
    Add-DenonModeSelector

    $filtered = @(
        $commands | Where-Object {
            if ($script:denonZoneMode -eq 'Zone2') {
                Test-DenonZone2Command $_
            }
            else {
                -not (Test-DenonZone2Command $_)
            }
        }
    )

    if ($filtered.Count -eq 0) {
        $message = New-Object System.Windows.Forms.Label
        $message.AutoSize = $true
        $message.Margin = New-Object System.Windows.Forms.Padding(10)
        $message.Text = if ($script:denonZoneMode -eq 'Zone2') {
            'No Zone 2 (Z...) commands are present in this profile.'
        }
        else {
            'No Main-zone commands are present in this profile.'
        }
        [void]$irCommandPanel.Controls.Add($message)
        return
    }

    $used = @()

    $power = New-IrGridGroup 'Power' 2 1

    $powerCmd = Find-DenonPowerCommand $filtered

    # The physical Denon remote uses the normal Power command while the UI is
    # switched to Zone 2. Reuse that exact command rather than requiring a
    # separate Z2-Power recording.
    if ($null -eq $powerCmd -and $script:denonZoneMode -eq 'Zone2') {
        $powerCmd = Find-IrCommand $commands 'Power'
    }

    if ($null -ne $powerCmd) {
        $powerLabel = if ($script:denonZoneMode -eq 'Zone2') {
            'Z Power'
        }
        else {
            'Power'
        }

        Add-IrGridButton `
            $power $device $powerCmd 'Power' 0 0 $powerLabel

        # Only exclude it from the remaining Zone 2 command set when it really
        # came from that set; the borrowed Main Power command is not present in
        # $filtered anyway.
        if (@($filtered | Where-Object { [string]$_.id -eq [string]$powerCmd.id }).Count -gt 0) {
            $used += [string]$powerCmd.id
        }
    }

    $sleepCmd = Find-DenonCommand $filtered 'Sleep'
    if ($null -ne $sleepCmd) {
        Add-IrGridButton `
            $power $device $sleepCmd 'Power' 0 1 `
            (Get-DenonButtonLabel $sleepCmd 'Sleep')
        $used += [string]$sleepCmd.id
    }

    if ($power.Grid.Controls.Count -gt 0) {
        [void]$irCommandPanel.Controls.Add($power.Group)
    }

    $hasDpad = $false
    foreach ($dpadName in @(
        'Arrow Up',
        'Arrow Left',
        'Arrow Enter',
        'Arrow Right',
        'Arrow Down',
        'Menu'
    )) {
        if ($null -ne (Find-DenonCommand $filtered $dpadName)) {
            $hasDpad = $true
            break
        }
    }

    if ($hasDpad) {
        $nav = New-IrGridGroup 'Navigation' 3 5
        $navEntries = @(
            @('Arrow Up',0,1,'Arrow UP'),
            @('Arrow Left',1,0,'Arrow Left'),
            @('Arrow Enter',1,1,'OK'),
            @('Arrow Right',1,2,'Arrow Right'),
            @('Arrow Down',2,1,'Arrow Down'),
            @('Menu',2,2,'Menu'),
            @('Info',3,0,'Info'),
            @('Option',3,1,'Option'),
            @('Setup',3,2,'Setup'),
            @('Back',4,0,'Back'),
            @('Page Up',4,1,'Page Up'),
            @('Page Down',4,2,'Page Down')
        )

        foreach ($entry in $navEntries) {
            $cmd = Find-DenonCommand $filtered $entry[0]
            if ($null -ne $cmd) {
                Add-IrGridButton `
                    $nav $device $cmd 'Navigation' `
                    ([int]$entry[1]) ([int]$entry[2]) `
                    (Get-DenonButtonLabel $cmd $entry[3])
                $used += [string]$cmd.id
            }
        }

        if ($nav.Grid.Controls.Count -gt 0) {
            [void]$irCommandPanel.Controls.Add($nav.Group)
        }
    }
    else {
        # Zone 2 profiles often only contain Back/Page Up/Page Down rather than
        # a complete arrow pad. Render those compactly instead of leaving four
        # empty rows above them.
        $zoneNav = New-IrGridGroup 'Navigation' 3 1
        $zoneNavEntries = @(
            @('Back',0,'Back'),
            @('Page Up',1,'Page Up'),
            @('Page Down',2,'Page Down')
        )

        foreach ($entry in $zoneNavEntries) {
            $cmd = Find-DenonCommand $filtered $entry[0]
            if ($null -ne $cmd) {
                Add-IrGridButton `
                    $zoneNav $device $cmd 'Navigation' 0 ([int]$entry[1]) `
                    (Get-DenonButtonLabel $cmd $entry[2])
                $used += [string]$cmd.id
            }
        }

        if ($zoneNav.Grid.Controls.Count -gt 0) {
            [void]$irCommandPanel.Controls.Add($zoneNav.Group)
        }
    }

    $audio = New-IrGridGroup 'Audio' 2 2
    $volumeUp = Find-DenonCommand $filtered 'Volume Up'
    $volumeDown = Find-DenonCommand $filtered 'Volume Down'
    $mute = Find-DenonCommand $filtered 'Mute'

    if ($null -ne $volumeUp) {
        Add-IrGridButton `
            $audio $device $volumeUp 'Audio' 0 0 `
            (Get-DenonButtonLabel $volumeUp 'Volume Up')
        $used += [string]$volumeUp.id
    }
    if ($null -ne $volumeDown) {
        Add-IrGridButton `
            $audio $device $volumeDown 'Audio' 1 0 `
            (Get-DenonButtonLabel $volumeDown 'Volume Down')
        $used += [string]$volumeDown.id
    }
    if ($null -ne $mute) {
        Add-IrGridButton `
            $audio $device $mute 'Audio' 0 1 `
            (Get-DenonButtonLabel $mute 'Mute') 2 1
        $used += [string]$mute.id
    }
    if ($audio.Grid.Controls.Count -gt 0) {
        [void]$irCommandPanel.Controls.Add($audio.Group)
    }

    $media = New-IrGridGroup 'Media' 3 1
    $mediaNames = @('Rewind','Play-Pause','Forward')
    for ($i = 0; $i -lt $mediaNames.Count; $i++) {
        $cmd = Find-DenonCommand $filtered $mediaNames[$i]
        if ($null -ne $cmd) {
            Add-IrGridButton `
                $media $device $cmd 'Media' 0 $i `
                (Get-DenonButtonLabel $cmd $mediaNames[$i])
            $used += [string]$cmd.id
        }
    }
    if ($media.Grid.Controls.Count -gt 0) {
        [void]$irCommandPanel.Controls.Add($media.Group)
    }

    $remaining = @(
        $filtered |
            Where-Object {
                $used -notcontains [string]$_.id
            }
    )
    Render-DenonGenericGroups $device $remaining
}

function Render-KpnRemote($device, $commands) {
    $used = @()

    $powerCmd = Find-IrCommand $commands 'Power'
    if ($null -ne $powerCmd) {
        $power = New-IrGridGroup 'Power' 1 1
        Add-IrGridButton $power $device $powerCmd 'Power' 0 0
        [void]$irCommandPanel.Controls.Add($power.Group)
        $used += [string]$powerCmd.id
    }

    # 3x3 D-pad with four empty corner positions, then a row for Gids/Radio/Menu.
    $nav = New-IrGridGroup 'Navigation' 3 4
    $navEntries = @(
        @('Arrow Up',0,1,'Arrow Up'),
        @('Arrow Left',1,0,'Arrow Left'),
        @('Arrow OK',1,1,'OK'),
        @('Arrow Right',1,2,'Arrow Right'),
        @('Arrow Down',2,1,'Arrow Down'),
        @('Gids',3,0,'Gids'),
        @('Radio',3,1,'Radio'),
        @('Menu',3,2,'Menu')
    )

    foreach ($entry in $navEntries) {
        $cmd = Find-IrCommand $commands $entry[0]
        if ($null -ne $cmd) {
            Add-IrGridButton `
                $nav $device $cmd 'Navigation' `
                ([int]$entry[1]) ([int]$entry[2]) $entry[3]
            $used += [string]$cmd.id
        }
    }
    if ($nav.Grid.Controls.Count -gt 0) {
        [void]$irCommandPanel.Controls.Add($nav.Group)
    }

    # Explicitly keep Fast Forward with the media controls.
    $media = New-IrGridGroup 'Media' 3 2
    $mediaEntries = @(
        @('Fast Backward',0,0),
        @('Pause-Play',0,1),
        @('Fast Forward',0,2),
        @('Record',1,0),
        @('Stop',1,1)
    )

    foreach ($entry in $mediaEntries) {
        $cmd = Find-IrCommand $commands $entry[0]
        if ($null -ne $cmd) {
            Add-IrGridButton `
                $media $device $cmd 'Media' `
                ([int]$entry[1]) ([int]$entry[2])
            $used += [string]$cmd.id
        }
    }
    if ($media.Grid.Controls.Count -gt 0) {
        [void]$irCommandPanel.Controls.Add($media.Group)
    }

    $remaining = @(
        $commands |
            Where-Object {
                $used -notcontains [string]$_.id
            }
    )
    Render-IrGenericGroups $device $remaining
}

function Render-LedLightBarRemote($device, $commands) {
    $used = @()

    $power = New-IrGridGroup 'Power' 2 1
    foreach ($entry in @(
        @('Power On',0),
        @('Power Off',1)
    )) {
        $cmd = Find-IrCommand $commands $entry[0]
        if ($null -ne $cmd) {
            Add-IrGridButton `
                $power $device $cmd 'Power' 0 ([int]$entry[1])
            $used += [string]$cmd.id
        }
    }
    if ($power.Grid.Controls.Count -gt 0) {
        [void]$irCommandPanel.Controls.Add($power.Group)
    }

    $colors = New-IrGridGroup 'Colors' 3 2
    $colorEntries = @(
        @('Red',0,0), @('Green',0,1), @('Blue',0,2),
        @('Lime',1,0), @('Purple',1,1), @('White',1,2)
    )
    foreach ($entry in $colorEntries) {
        $cmd = Find-IrCommand $commands $entry[0]
        if ($null -ne $cmd) {
            Add-IrGridButton `
                $colors $device $cmd 'Colors' `
                ([int]$entry[1]) ([int]$entry[2])
            $used += [string]$cmd.id
        }
    }
    if ($colors.Grid.Controls.Count -gt 0) {
        [void]$irCommandPanel.Controls.Add($colors.Group)
    }

    # Six-button block:
    # Brightness Up    RGB Mode      Strobe Mode
    # Brightness Down  Fade Mode     Smooth Mode
    $modes = New-IrGridGroup 'Modes' 3 2
    $modeEntries = @(
        @('Brightness Up',0,0), @('RGB Mode',0,1), @('Strobe Mode',0,2),
        @('Brightness Down',1,0), @('Fade Mode',1,1), @('Smooth Mode',1,2)
    )
    foreach ($entry in $modeEntries) {
        $cmd = Find-IrCommand $commands $entry[0]
        if ($null -ne $cmd) {
            Add-IrGridButton `
                $modes $device $cmd 'Modes' `
                ([int]$entry[1]) ([int]$entry[2])
            $used += [string]$cmd.id
        }
    }
    if ($modes.Grid.Controls.Count -gt 0) {
        [void]$irCommandPanel.Controls.Add($modes.Group)
    }

    $remaining = @(
        $commands |
            Where-Object {
                $used -notcontains [string]$_.id
            }
    )
    Render-IrGenericGroups $device $remaining
}

function Render-PacRemote($device, $commands) {
    $used = @()

    $powerCmd = Find-IrCommand $commands 'Power'
    if ($null -ne $powerCmd) {
        $power = New-IrGridGroup 'Power' 1 1
        Add-IrGridButton $power $device $powerCmd 'Power' 0 0
        [void]$irCommandPanel.Controls.Add($power.Group)
        $used += [string]$powerCmd.id
    }

    $controls = New-IrGridGroup 'Controls' 2 1
    foreach ($entry in @(
        @('Speed',0),
        @('Mode',1)
    )) {
        $cmd = Find-IrCommand $commands $entry[0]
        if ($null -ne $cmd) {
            Add-IrGridButton `
                $controls $device $cmd 'Controls' 0 ([int]$entry[1])
            $used += [string]$cmd.id
        }
    }
    if ($controls.Grid.Controls.Count -gt 0) {
        [void]$irCommandPanel.Controls.Add($controls.Group)
    }

    $temperature = New-IrGridGroup 'Temperature' 1 2
    $tempUp = Find-IrCommand $commands 'Temp Up'
    $tempDown = Find-IrCommand $commands 'Temp Down'

    if ($null -ne $tempUp) {
        Add-IrGridButton `
            $temperature $device $tempUp 'Temperature' 0 0
        $used += [string]$tempUp.id
    }
    if ($null -ne $tempDown) {
        Add-IrGridButton `
            $temperature $device $tempDown 'Temperature' 1 0
        $used += [string]$tempDown.id
    }
    if ($temperature.Grid.Controls.Count -gt 0) {
        [void]$irCommandPanel.Controls.Add($temperature.Group)
    }

    # UI aliases only: Hour Up/Down invoke the existing Temp Up/Down command IDs.
    $timerCmd = Find-IrCommand $commands 'Timer'
    $timer = New-IrGridGroup 'Timer' 2 2

    if ($null -ne $tempUp) {
        Add-IrGridButton `
            $timer $device $tempUp 'Timer' 0 0 'Hour Up'
    }
    if ($null -ne $tempDown) {
        Add-IrGridButton `
            $timer $device $tempDown 'Timer' 1 0 'Hour Down'
    }
    if ($null -ne $timerCmd) {
        Add-IrGridButton `
            $timer $device $timerCmd 'Timer' 0 1 'Timer' 2 1
        $used += [string]$timerCmd.id
    }
    if ($timer.Grid.Controls.Count -gt 0) {
        [void]$irCommandPanel.Controls.Add($timer.Group)
    }

    $remaining = @(
        $commands |
            Where-Object {
                $used -notcontains [string]$_.id
            }
    )
    Render-IrGenericGroups $device $remaining
}

function Render-Z5500Remote($device, $commands) {
    $used = @()

    $standby = Find-IrCommand $commands 'Standby'
    if ($null -ne $standby) {
        $power = New-IrGridGroup 'Power' 1 1
        Add-IrGridButton $power $device $standby 'Power' 0 0
        [void]$irCommandPanel.Controls.Add($power.Group)
        $used += [string]$standby.id
    }

    # Volume Up above Volume Down, Mute beside them.
    $volume = New-IrGridGroup 'Volume' 2 2
    $volUp = Find-IrCommand $commands 'Volume Up'
    $volDown = Find-IrCommand $commands 'Volume Down'
    $mute = Find-IrCommand $commands 'Mute'

    if ($null -ne $volUp) {
        Add-IrGridButton $volume $device $volUp 'Volume' 0 0
        $used += [string]$volUp.id
    }
    if ($null -ne $volDown) {
        Add-IrGridButton $volume $device $volDown 'Volume' 1 0
        $used += [string]$volDown.id
    }
    if ($null -ne $mute) {
        Add-IrGridButton `
            $volume $device $mute 'Volume' 0 1 'Mute' 2 1
        $used += [string]$mute.id
    }
    if ($volume.Grid.Controls.Count -gt 0) {
        [void]$irCommandPanel.Controls.Add($volume.Group)
    }

    # Sub / Center / Surround with Down directly below Up.
    $controls = New-IrGridGroup 'Controls' 3 3
    $controlEntries = @(
        @('Sub Up',0,0), @('Center Up',0,1), @('Surround Up',0,2),
        @('Sub Down',1,0), @('Center Down',1,1), @('Surround Down',1,2),
        @('Effect',2,0), @('Settings',2,1)
    )
    foreach ($entry in $controlEntries) {
        $cmd = Find-IrCommand $commands $entry[0]
        if ($null -ne $cmd) {
            Add-IrGridButton `
                $controls $device $cmd 'Controls' `
                ([int]$entry[1]) ([int]$entry[2])
            $used += [string]$cmd.id
        }
    }
    if ($controls.Grid.Controls.Count -gt 0) {
        [void]$irCommandPanel.Controls.Add($controls.Group)
    }

    # Three physical sources.
    $input = New-IrGridGroup 'Input' 3 1
    $inputNames = @('Direct','Optical','Coax')
    for ($i = 0; $i -lt $inputNames.Count; $i++) {
        $cmd = Find-IrCommand $commands $inputNames[$i]
        if ($null -ne $cmd) {
            Add-IrGridButton $input $device $cmd 'Input' 0 $i
            $used += [string]$cmd.id
        }
    }
    if ($input.Grid.Controls.Count -gt 0) {
        [void]$irCommandPanel.Controls.Add($input.Group)
    }

    $testCmd = Find-IrCommand $commands 'Test'
    if ($null -ne $testCmd) {
        $test = New-IrGridGroup 'Test' 1 1
        Add-IrGridButton $test $device $testCmd 'Test' 0 0
        [void]$irCommandPanel.Controls.Add($test.Group)
        $used += [string]$testCmd.id
    }

    $remaining = @(
        $commands |
            Where-Object {
                $used -notcontains [string]$_.id
            }
    )
    Render-IrGenericGroups $device $remaining
}

$irCommandPanel.Add_Resize({ Refresh-IrCommandGroupWidths })

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

function Initialize-SensorCards($response) {
    if ($script:sensorPanelInitialized) {
        return
    }

    $sensorPanel.SuspendLayout()
    try {
        $sensorPanel.Controls.Clear()
        $sensorListView.Items.Clear()

        $script:sensorCards = @{}
        $script:sensorListItems = @{}

        foreach ($sensor in @($response.sensors)) {
            $sensorName = [string]$sensor.name

            $card = New-Object System.Windows.Forms.GroupBox
            $card.Text = $sensorName
            $card.Size = New-Object System.Drawing.Size(315, 210)
            $card.Margin = New-Object System.Windows.Forms.Padding(8)
            $card.Padding = New-Object System.Windows.Forms.Padding(12)

            $cardState = [pscustomobject]@{
                Card = $card
                UnavailableLabel = $null
                MeasurementNames = @()
                MeasurementValues = @()
                AgeLabel = $null
                Picture = $null
            }

            $unavailable = New-Object System.Windows.Forms.Label
            $unavailable.Text = 'No reading available'
            $unavailable.ForeColor = [System.Drawing.Color]::DarkRed
            $unavailable.AutoSize = $true
            $unavailable.Location = New-Object System.Drawing.Point(15, 34)
            $unavailable.Visible = $false
            $card.Controls.Add($unavailable)
            $cardState.UnavailableLabel = $unavailable

            $y = 31
            foreach ($measurement in @($sensor.measurements)) {
                $nameLabel = New-Object System.Windows.Forms.Label
                $nameLabel.Text = [string]$measurement.name
                $nameLabel.Location = New-Object System.Drawing.Point(15, $y)
                $nameLabel.Size = New-Object System.Drawing.Size(135, 25)
                $card.Controls.Add($nameLabel)

                $valueLabel = New-Object System.Windows.Forms.Label
                $valueLabel.Text = ''
                $valueLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
                $valueLabel.TextAlign = 'MiddleRight'
                $valueLabel.Location = New-Object System.Drawing.Point(148, ($y - 2))
                $valueLabel.Size = New-Object System.Drawing.Size(145, 27)
                $card.Controls.Add($valueLabel)

                $cardState.MeasurementNames += $nameLabel
                $cardState.MeasurementValues += $valueLabel
                $y += 32
            }

            $sensorImagePath =
                Get-SensorImagePath $sensorName

            if ($sensorImagePath) {
                try {
                    $sensorPicture = New-Object System.Windows.Forms.PictureBox
                    # Center the image in the free lower-middle portion of the card.
                    $sensorPicture.Location = New-Object System.Drawing.Point(89, 58)
                    $sensorPicture.Size = New-Object System.Drawing.Size(138, 112)
                    $sensorPicture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
                    $sensorPicture.BorderStyle = [System.Windows.Forms.BorderStyle]::None
                    $sensorPicture.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
                    $sensorPicture.Image = [System.Drawing.Image]::FromFile($sensorImagePath)
                    $card.Controls.Add($sensorPicture)
                    $sensorPicture.SendToBack()
                    $cardState.Picture = $sensorPicture
                }
                catch {
                    Write-TowerLog 'WARN' (
                        "Unable to load sensor image for " +
                        "$sensorName`: $($_.Exception.Message)"
                    )
                }
            }

            $ageLabel = New-Object System.Windows.Forms.Label
            $ageLabel.Text = ''
            $ageLabel.ForeColor = [System.Drawing.Color]::DimGray
            $ageLabel.Location = New-Object System.Drawing.Point(15, 178)
            $ageLabel.Size = New-Object System.Drawing.Size(275, 23)
            $card.Controls.Add($ageLabel)
            $cardState.AgeLabel = $ageLabel

            $listItem =
                New-Object System.Windows.Forms.ListViewItem(
                    $sensorName
                )
            [void]$listItem.SubItems.Add('')
            [void]$listItem.SubItems.Add('')

            $script:sensorListItems[$sensorName] =
                $listItem

            [void]$sensorListView.Items.Add($listItem)

            $script:sensorCards[$sensorName] = $cardState
            [void]$sensorPanel.Controls.Add($card)
        }

        $script:sensorPanelInitialized = $true
    }
    finally {
        $sensorPanel.ResumeLayout()
    }
}

function Apply-SensorResponse($response) {
    $previousFailures = [int]$script:sensorRefreshFailures
    $script:sensorRefreshFailures = 0
    $script:sensorsHaveLoaded = $true

    if (-not $script:sensorPanelInitialized) {
        Initialize-SensorCards $response
    }

    foreach ($sensor in @($response.sensors)) {
        $sensorName = [string]$sensor.name

        if (-not $script:sensorCards.ContainsKey($sensorName)) {
            # Sensor inventory changed; rebuild once, not on every reading.
            $script:sensorPanelInitialized = $false
            Initialize-SensorCards $response
            break
        }
    }

    foreach ($sensor in @($response.sensors)) {
        $sensorName = [string]$sensor.name
        if (-not $script:sensorCards.ContainsKey($sensorName)) {
            continue
        }

        $state = $script:sensorCards[$sensorName]
        $available = [bool]$sensor.available

        $state.UnavailableLabel.Visible = (-not $available)

        for ($i = 0; $i -lt $state.MeasurementNames.Count; $i++) {
            $visible =
                $available -and
                $i -lt @($sensor.measurements).Count

            $state.MeasurementNames[$i].Visible = $visible
            $state.MeasurementValues[$i].Visible = $visible

            if ($visible) {
                $measurement = @($sensor.measurements)[$i]
                $state.MeasurementNames[$i].Text =
                    [string]$measurement.name
                $state.MeasurementValues[$i].Text =
                    Format-SensorValue $measurement
            }
        }

        if ($null -ne $state.Picture) {
            # Static visual: never replace/reload it during sensor refreshes.
            $state.Picture.Visible = $available
        }

        if ($available) {
            $state.AgeLabel.Text =
                Format-SensorAge ([long]$sensor.ageSeconds)
            $state.AgeLabel.Visible = $true
        }
        else {
            $state.AgeLabel.Visible = $false
        }

        if ($script:sensorListItems.ContainsKey(
                $sensorName)) {

            $listItem =
                $script:sensorListItems[$sensorName]

            if ($available) {
                $parts = @()

                foreach ($measurement in
                    @($sensor.measurements)) {

                    $parts += (
                        [string]$measurement.name +
                        ': ' +
                        (Format-SensorValue $measurement)
                    )
                }

                $listItem.SubItems[1].Text =
                    ($parts -join '   |   ')

                $listItem.SubItems[2].Text =
                    Format-SensorAge(
                        [long]$sensor.ageSeconds
                    )

                $listItem.ForeColor =
                    [System.Drawing.SystemColors]::ControlText
            }
            else {
                $listItem.SubItems[1].Text =
                    'No reading available'

                $listItem.SubItems[2].Text = ''

                $listItem.ForeColor =
                    [System.Drawing.Color]::DarkRed
            }
        }
    }

    if ($previousFailures -ge 3) {
        Set-TowerStatus (
            "Sensor refresh recovered - " +
            "Connected to $($config.server)"
        )
    }
}

function Register-SensorRefreshFailure([string]$message) {
    $script:sensorRefreshFailures++

    Write-TowerLog 'WARN' (
        "Sensor refresh failed ($($script:sensorRefreshFailures) consecutive): " +
        $message
    )

    # A single transient sensor miss must not paint the whole application red.
    # Only escalate after three consecutive failures, matching the original
    # Tower Control behavior.
    if ($script:sensorRefreshFailures -ge 3) {
        Set-TowerStatus (
            "Sensors temporarily unavailable - " +
            "$($script:sensorRefreshFailures) failed refreshes"
        ) $true
    }
}

function Start-SensorRead {
    if ($null -ne $script:sensorReadJob) { return }

    try {
        $script:sensorReadJob = Start-TowerReadJob '/api/v1/sensors'
    }
    catch {
        Register-SensorRefreshFailure $_.Exception.Message
    }
}

function Complete-SensorRead {
    if ($null -eq $script:sensorReadJob) { return }
    if ($script:sensorReadJob.State -eq 'Running' -or
        $script:sensorReadJob.State -eq 'NotStarted') { return }

    $job = $script:sensorReadJob
    $script:sensorReadJob = $null

    try {
        if ($job.State -ne 'Completed') {
            throw (Get-TowerReadJobError $job)
        }

        $response = Receive-Job -Job $job -ErrorAction Stop
        Apply-SensorResponse $response

        if ($null -eq $script:irReadJob -and
            $null -eq $script:rfReadJob) {
            Set-TowerStatus (
                "Connected to $($config.server) - " +
                "$($config.rfDisplayCount) RF devices, " +
                "$($config.irDisplayCount) IR devices"
            )
        }
    }
    catch {
        Register-SensorRefreshFailure $_.Exception.Message
    }
    finally {
        Remove-TowerReadJob $job
    }
}


function Resize-SensorListColumns {
    if ($null -eq $sensorListView) {
        return
    }

    $availableWidth =
        [Math]::Max(
            360,
            $sensorListView.ClientSize.Width - 8
        )

    $sensorWidth =
        [Math]::Min(
            150,
            [Math]::Max(
                105,
                [int]($availableWidth * 0.22)
            )
        )

    $ageWidth =
        [Math]::Min(
            145,
            [Math]::Max(
                110,
                [int]($availableWidth * 0.20)
            )
        )

    $measurementWidth =
        [Math]::Max(
            140,
            $availableWidth -
            $sensorWidth -
            $ageWidth
        )

    $sensorListView.Columns[0].Width =
        $sensorWidth

    $sensorListView.Columns[1].Width =
        $measurementWidth

    $sensorListView.Columns[2].Width =
        $ageWidth
}

function Apply-SensorCardLayout([string]$mode) {
    if ($mode -eq 'list') {
        # Same full sensor cards, arranged left-to-right.
        $sensorPanel.FlowDirection =
            [System.Windows.Forms.FlowDirection]::LeftToRight
        $sensorPanel.WrapContents = $true
    }
    else {
        # Cards = vertical stack.
        $sensorPanel.FlowDirection =
            [System.Windows.Forms.FlowDirection]::TopDown
        $sensorPanel.WrapContents = $false
    }

    $sensorPanel.PerformLayout()
}

function Refresh-SensorViewButtons {
    $mode =
        [string]$config.sensorViewMode

    $cardsSelected =
        ($mode -eq 'cards')
    $listSelected =
        ($mode -eq 'list')
    $detailsSelected =
        ($mode -eq 'details')

    Set-SettingsButtonVisualStyle `
        $sensorCardsViewButton `
        $cardsSelected

    Set-SettingsButtonVisualStyle `
        $sensorListViewButton `
        $listSelected

    Set-SettingsButtonVisualStyle `
        $sensorDetailsViewButton `
        $detailsSelected

    if ($detailsSelected) {
        $sensorPanel.Visible = $false
        $sensorListView.Visible = $true
        Resize-SensorListColumns
    }
    else {
        $sensorListView.Visible = $false
        $sensorPanel.Visible = $true
        Apply-SensorCardLayout $mode
    }
}

function Set-SensorViewMode([string]$mode) {
    if ($mode -notin @(
            'cards',
            'list',
            'details')) {
        return
    }

    if ([string]$config.sensorViewMode -ne $mode) {
        $config.sensorViewMode = $mode
        Save-TowerConfig
    }

    # All three modes reuse already-created controls.
    # No sensor API call and no image/card rebuild occurs here.
    Refresh-SensorViewButtons
}

function Refresh-RfViewButtons {
    $cardsSelected =
        ([string]$config.rfDeviceViewMode -eq 'cards')

    if ($cardsSelected) {
        Set-RfSmoothButtonAppearance `
            $rfCardsViewButton `
            ([System.Drawing.Color]::SteelBlue) `
            ([System.Drawing.Color]::White) `
            ([System.Drawing.Color]::SteelBlue)

        Set-RfSmoothButtonAppearance `
            $rfListViewButton `
            ([System.Drawing.Color]::White) `
            ([System.Drawing.Color]::SteelBlue) `
            ([System.Drawing.Color]::SteelBlue)
    }
    else {
        Set-RfSmoothButtonAppearance `
            $rfListViewButton `
            ([System.Drawing.Color]::SteelBlue) `
            ([System.Drawing.Color]::White) `
            ([System.Drawing.Color]::SteelBlue)

        Set-RfSmoothButtonAppearance `
            $rfCardsViewButton `
            ([System.Drawing.Color]::White) `
            ([System.Drawing.Color]::SteelBlue) `
            ([System.Drawing.Color]::SteelBlue)
    }
}

function Set-RfDeviceViewMode([string]$mode) {
    if ($mode -notin @('cards', 'list')) {
        return
    }

    if ([string]$config.rfDeviceViewMode -eq $mode) {
        return
    }

    $config.rfDeviceViewMode = $mode
    Save-TowerConfig
    Refresh-RfViewButtons
    Render-RfDevices
}

function Get-RfPresetDeviceIds([int]$preset) {
    switch ($preset) {
        1 { return @($config.rfPreset1Devices) }
        2 { return @($config.rfPreset2Devices) }
        3 { return @($config.rfPreset3Devices) }
    }
    return @()
}

function Set-RfPresetDeviceIds([int]$preset, $ids) {
    $normalized = @(
        @($ids) |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )

    switch ($preset) {
        1 { $config.rfPreset1Devices = $normalized }
        2 { $config.rfPreset2Devices = $normalized }
        3 { $config.rfPreset3Devices = $normalized }
        default { return }
    }

    Save-TowerConfig
}

function Get-RfProtocolDisplayName([string]$protocol) {
    switch ($protocol) {
        'kaku_ac' { return 'Modern KAKU' }
        'kaku_old' { return 'Legacy KAKU' }
        default {
            if ([string]::IsNullOrWhiteSpace($protocol)) {
                return 'RF power device'
            }
            return $protocol
        }
    }
}

function Get-RfPairingState($device) {
    if ($null -eq $device) {
        return 'unknown'
    }

    $status = ([string]$device.status).Trim().ToLowerInvariant()

    if ($status -eq 'paired') {
        return 'paired'
    }

    if ($status -in @(
        'unpaired',
        'not_paired',
        'not-paired',
        'not paired',
        'new',
        'pending'
    )) {
        return 'unpaired'
    }

    if ([string]::IsNullOrWhiteSpace($status)) {
        return 'unknown'
    }

    return 'other'
}

function Show-RfPairingInfo($device) {
    if ($null -eq $device) { return }

    $state = Get-RfPairingState $device

    if ($state -eq 'paired') {
        [System.Windows.Forms.MessageBox]::Show(
            "$([string]$device.name) is marked as paired in its Tower RF " +
            "definition.`n`n" +
            "Stored status: $([string]$device.status)",
            'RF Pairing Status',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    $pairDevice = [pscustomobject]@{
        recordId = [string]$device.id
        deviceName = [string]$device.name
        repeat = [int]$device.repeat
    }

    Show-RfPairWizard $pairDevice
}

function Remove-RfDeviceFromPresets([string]$deviceId) {
    for ($preset = 1; $preset -le 3; $preset++) {
        $remaining = @(
            Get-RfPresetDeviceIds $preset |
                Where-Object { [string]$_ -ne $deviceId }
        )

        Set-RfPresetDeviceIds $preset $remaining
    }
}

function Save-CurrentRfDeviceCache {
    try {
        $snapshot = [pscustomobject]@{
            devices = @($script:rfDevices)
        }
        Save-RfDeviceCache $snapshot
    }
    catch {
        Write-TowerLog 'WARN' (
            "Could not update local RF cache: $($_.Exception.Message)"
        )
    }
}

function Show-RfRenameDialog(
    [string]$currentName) {

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Rename RF power device'
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle =
        [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.ClientSize =
        New-Object System.Drawing.Size(430, 158)
    $dialog.Font =
        New-Object System.Drawing.Font(
            'Segoe UI',
            10
        )

    $label = New-Object System.Windows.Forms.Label
    $label.Text = 'Device name'
    $label.Location =
        New-Object System.Drawing.Point(22, 22)
    $label.Size =
        New-Object System.Drawing.Size(110, 24)
    $dialog.Controls.Add($label)

    $nameBox = New-Object System.Windows.Forms.TextBox
    $nameBox.Text = $currentName
    $nameBox.Location =
        New-Object System.Drawing.Point(136, 19)
    $nameBox.Size =
        New-Object System.Drawing.Size(270, 27)
    $nameBox.MaxLength = 120
    $dialog.Controls.Add($nameBox)

    $note = New-Object System.Windows.Forms.Label
    $note.Text =
        'Only the displayed name changes. The internal RF record ID and address stay unchanged.'
    $note.Location =
        New-Object System.Drawing.Point(24, 59)
    $note.Size =
        New-Object System.Drawing.Size(382, 38)
    $note.ForeColor =
        [System.Drawing.Color]::DimGray
    $dialog.Controls.Add($note)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.Size =
        New-Object System.Drawing.Size(92, 34)
    $cancel.Location =
        New-Object System.Drawing.Point(22, 108)
    $cancel.DialogResult =
        [System.Windows.Forms.DialogResult]::Cancel
    Set-IrButtonVisualStyle $cancel
    $dialog.Controls.Add($cancel)

    $rename = New-Object System.Windows.Forms.Button
    $rename.Text = 'Rename'
    $rename.Size =
        New-Object System.Drawing.Size(100, 34)
    $rename.Location =
        New-Object System.Drawing.Point(306, 108)
    Set-IrButtonVisualStyle $rename
    $dialog.Controls.Add($rename)

    $dialog.CancelButton = $cancel
    $dialog.Tag = $null

    $rename.Add_Click({
        $candidate =
            $nameBox.Text.Trim()

        if ([string]::IsNullOrWhiteSpace(
                $candidate)) {

            [System.Windows.Forms.MessageBox]::Show(
                'Enter a name for the RF power device.',
                'Rename RF power device',
                'OK',
                'Information'
            ) | Out-Null

            $nameBox.Focus()
            return
        }

        $dialog.Tag = $candidate

        $dialog.DialogResult =
            [System.Windows.Forms.DialogResult]::OK

        $dialog.Close()
    })

    $dialog.Add_Shown({
        $nameBox.SelectAll()
        $nameBox.Focus()
    })

    $dialogResult =
        $dialog.ShowDialog($form)

    $renamedValue =
        [string]$dialog.Tag

    $dialog.Dispose()

    if ($dialogResult -eq
            [System.Windows.Forms.DialogResult]::OK -and
        -not [string]::IsNullOrWhiteSpace(
            $renamedValue)) {

        return $renamedValue
    }

    return $null
}

function Rename-RfDevice($device) {
    if ($null -eq $device) {
        return
    }

    $deviceId =
        [string]$device.id

    $oldName =
        [string]$device.name

    if ([string]::IsNullOrWhiteSpace(
            $deviceId)) {
        return
    }

    $newName =
        Show-RfRenameDialog $oldName

    if ([string]::IsNullOrWhiteSpace(
            $newName) -or
        $newName -eq $oldName) {
        return
    }

    try {
        Set-TowerStatus (
            "Renaming $oldName..."
        )

        $response =
            Invoke-TowerPost `
                '/api/v1/rf/rename' `
                @{
                    device = $deviceId
                    name = $newName
                }

        foreach ($candidate in
            @($script:rfDevices)) {

            if ([string]$candidate.id -eq
                $deviceId) {

                $candidate.name =
                    [string]$response.name
            }
        }

        Save-CurrentRfDeviceCache

        $script:rfInventorySignature =
            Get-RfInventorySignature `
                $script:rfDevices

        # Rename is rare and changes labels in the card/list plus preset
        # selectors, so redraw once from the already-local inventory.
        Render-RfDevices

        Set-TowerStatus (
            [string]$response.message
        )

        # Quiet authoritative verification. A transient verification miss must
        # not turn the global status red after a successful local rename.
        if ($null -eq $script:rfReadJob) {
            Start-RfDeviceRead $true
        }
    }
    catch {
        $details =
            Get-TowerHttpErrorDetails `
                $_ `
                'POST' `
                '/api/v1/rf/rename' `
                @{
                    device = $deviceId
                    name = $newName
                }

        [System.Windows.Forms.MessageBox]::Show(
            $details.Text,
            'Rename RF power device failed',
            'OK',
            'Error'
        ) | Out-Null
    }
}

function Delete-RfDevice($device) {
    if ($null -eq $device) { return }

    $deviceId = [string]$device.id
    $deviceName = [string]$device.name

    if ([string]::IsNullOrWhiteSpace($deviceId)) {
        return
    }

    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Delete RF power device '$deviceName'?`n`n" +
        "This permanently removes the Tower RF definition:`n" +
        "$deviceId.rf`n`n" +
        "It will also be removed from all RF presets.`n`n" +
        "Are you sure?",
        'Delete RF Power Device',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2
    )

    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    try {
        Set-TowerStatus "Deleting RF device $deviceName..."
        $form.Refresh()

        $response = Invoke-TowerPost '/api/v1/rf/delete' @{
            device = $deviceId
        }

        Remove-RfDeviceFromPresets $deviceId

        $script:rfDevices = @(
            $script:rfDevices |
                Where-Object {
                    [string]$_.id -ne $deviceId
                }
        )

        Save-CurrentRfDeviceCache
        $script:rfInventorySignature =
            Get-RfInventorySignature $script:rfDevices
        Render-RfDevices

        Set-TowerStatus ([string]$response.message)

        # Verify against authoritative Pi state without blocking the UI.
        if ($null -eq $script:rfReadJob) {
            Start-RfDeviceRead
        }
    }
    catch {
        Set-TowerStatus "Delete RF device failed" $true

        $details = Get-TowerHttpErrorDetails `
            $_ `
            'POST' `
            '/api/v1/rf/delete' `
            @{ device = $deviceId }

        [System.Windows.Forms.MessageBox]::Show(
            $details.Text,
            'Delete RF Power Device',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

function New-RfRenameButton($device) {
    $renameButton =
        New-Object System.Windows.Forms.Panel

    $renameButton.Size =
        New-Object System.Drawing.Size(18, 18)

    $renameButton.Cursor =
        [System.Windows.Forms.Cursors]::Hand

    $renameButton.TabStop = $false

    $renameButton |
        Add-Member `
            -NotePropertyName RfRenameHover `
            -NotePropertyValue $false

    $renameButton |
        Add-Member `
            -NotePropertyName RfRenamePressed `
            -NotePropertyValue $false

    $renameButton.Add_ParentChanged({
        param($sender, $eventArgs)

        if ($null -ne $sender.Parent) {
            $sender.BackColor =
                $sender.Parent.BackColor
        }
    })

    $renameButton.Add_MouseEnter({
        param($sender, $eventArgs)

        $sender.RfRenameHover = $true
        $sender.Invalidate()
    })

    $renameButton.Add_MouseLeave({
        param($sender, $eventArgs)

        $sender.RfRenameHover = $false
        $sender.RfRenamePressed = $false
        $sender.Invalidate()
    })

    $renameButton.Add_MouseDown({
        param($sender, $eventArgs)

        if ($eventArgs.Button -eq
            [System.Windows.Forms.MouseButtons]::Left) {

            $sender.RfRenamePressed = $true
            $sender.Invalidate()
        }
    })

    $renameButton.Add_MouseUp({
        param($sender, $eventArgs)

        $sender.RfRenamePressed = $false
        $sender.Invalidate()
    })

    $renameButton.Add_Paint({
        param($sender, $eventArgs)

        $eventArgs.Graphics.SmoothingMode =
            [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

        $eventArgs.Graphics.PixelOffsetMode =
            [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

        $fill =
            [System.Drawing.Color]::FromArgb(
                224,
                238,
                248
            )

        if ($sender.RfRenamePressed) {
            $fill =
                Get-RfBlendColor `
                    $fill `
                    ([System.Drawing.Color]::Black) `
                    0.08
        }
        elseif ($sender.RfRenameHover) {
            $fill =
                Get-RfBlendColor `
                    $fill `
                    ([System.Drawing.Color]::White) `
                    0.12
        }

        $rect =
            New-Object System.Drawing.RectangleF(
                1.0,
                1.0,
                [Math]::Max(
                    1.0,
                    $sender.ClientSize.Width - 2.0
                ),
                [Math]::Max(
                    1.0,
                    $sender.ClientSize.Height - 2.0
                )
            )

        $brush =
            New-Object System.Drawing.SolidBrush(
                $fill
            )

        try {
            $eventArgs.Graphics.FillEllipse(
                $brush,
                $rect
            )
        }
        finally {
            $brush.Dispose()
        }

        $borderPen =
            New-Object System.Drawing.Pen(
                ([System.Drawing.Color]::FromArgb(
                    90,
                    135,
                    170
                )),
                1.0
            )

        try {
            $eventArgs.Graphics.DrawEllipse(
                $borderPen,
                $rect
            )
        }
        finally {
            $borderPen.Dispose()
        }

        # Draw a tiny diagonal pencil explicitly so the symbol remains crisp
        # at 18x18 and does not depend on font/glyph rendering.
        $pencilPen =
            New-Object System.Drawing.Pen(
                ([System.Drawing.Color]::FromArgb(
                    55,
                    95,
                    125
                )),
                1.5
            )

        $pencilPen.StartCap =
            [System.Drawing.Drawing2D.LineCap]::Round

        $pencilPen.EndCap =
            [System.Drawing.Drawing2D.LineCap]::Round

        try {
            $eventArgs.Graphics.DrawLine(
                $pencilPen,
                5.0,
                12.5,
                12.3,
                5.2
            )

            $eventArgs.Graphics.DrawLine(
                $pencilPen,
                6.2,
                13.0,
                4.8,
                13.2
            )

            $eventArgs.Graphics.DrawLine(
                $pencilPen,
                12.0,
                4.9,
                13.2,
                6.1
            )
        }
        finally {
            $pencilPen.Dispose()
        }
    })

    $capturedDevice = $device

    $renameButton.Add_Click({
        Rename-RfDevice $capturedDevice
    }.GetNewClosure())

    $rfToolTip.SetToolTip(
        $renameButton,
        'Rename this RF power device.'
    )

    return $renameButton
}

function New-RfDeleteButton($device) {
    # Dedicated owner-painted delete control.
    #
    # Do not use the generic RF pill text renderer here. At 24px wide its
    # ellipsis handling can reduce a literal "X" to dots/pixels.
    $deleteButton = New-Object System.Windows.Forms.Panel
    $deleteButton.Size = New-Object System.Drawing.Size(18, 18)
    $deleteButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $deleteButton.TabStop = $false

    $deleteButton |
        Add-Member -NotePropertyName RfDeleteHover -NotePropertyValue $false
    $deleteButton |
        Add-Member -NotePropertyName RfDeletePressed -NotePropertyValue $false

    $deleteButton.Add_ParentChanged({
        param($sender, $eventArgs)

        if ($null -ne $sender.Parent) {
            $sender.BackColor = $sender.Parent.BackColor
        }
    })

    $deleteButton.Add_MouseEnter({
        param($sender, $eventArgs)

        $sender.RfDeleteHover = $true
        $sender.Invalidate()
    })

    $deleteButton.Add_MouseLeave({
        param($sender, $eventArgs)

        $sender.RfDeleteHover = $false
        $sender.RfDeletePressed = $false
        $sender.Invalidate()
    })

    $deleteButton.Add_MouseDown({
        param($sender, $eventArgs)

        if ($eventArgs.Button -eq
            [System.Windows.Forms.MouseButtons]::Left) {
            $sender.RfDeletePressed = $true
            $sender.Invalidate()
        }
    })

    $deleteButton.Add_MouseUp({
        param($sender, $eventArgs)

        $sender.RfDeletePressed = $false
        $sender.Invalidate()
    })

    $deleteButton.Add_Paint({
        param($sender, $eventArgs)

        $eventArgs.Graphics.SmoothingMode =
            [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $eventArgs.Graphics.PixelOffsetMode =
            [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

        # Match the normal RF OFF buttons exactly.
        $fill = [System.Drawing.Color]::FromArgb(248, 226, 226)

        if ($sender.RfDeletePressed) {
            $fill = Get-RfBlendColor `
                $fill `
                ([System.Drawing.Color]::Black) `
                0.08
        }
        elseif ($sender.RfDeleteHover) {
            $fill = Get-RfBlendColor `
                $fill `
                ([System.Drawing.Color]::White) `
                0.10
        }

        $rect = New-Object System.Drawing.RectangleF(
            1.0,
            1.0,
            [Math]::Max(1.0, $sender.ClientSize.Width - 2.0),
            [Math]::Max(1.0, $sender.ClientSize.Height - 2.0)
        )

        $brush = New-Object System.Drawing.SolidBrush($fill)
        try {
            $eventArgs.Graphics.FillEllipse($brush, $rect)
        }
        finally {
            $brush.Dispose()
        }

        $borderPen = New-Object System.Drawing.Pen(
            ([System.Drawing.Color]::FromArgb(125, 105, 165)),
            1.0
        )
        try {
            $eventArgs.Graphics.DrawEllipse($borderPen, $rect)
        }
        finally {
            $borderPen.Dispose()
        }

        # Explicitly draw the X instead of rendering it as tiny text.
        $xPen = New-Object System.Drawing.Pen(
            ([System.Drawing.Color]::FromArgb(145, 55, 55)),
            1.25
        )
        $xPen.StartCap =
            [System.Drawing.Drawing2D.LineCap]::Round
        $xPen.EndCap =
            [System.Drawing.Drawing2D.LineCap]::Round

        try {
            $left = 5.5
            $right = [double]$sender.ClientSize.Width - 5.5
            $top = 5.5
            $bottom = [double]$sender.ClientSize.Height - 5.5

            $eventArgs.Graphics.DrawLine(
                $xPen,
                $left,
                $top,
                $right,
                $bottom
            )
            $eventArgs.Graphics.DrawLine(
                $xPen,
                $right,
                $top,
                $left,
                $bottom
            )
        }
        finally {
            $xPen.Dispose()
        }
    })

    $capturedDevice = $device
    $deleteButton.Add_Click({
        Delete-RfDevice $capturedDevice
    }.GetNewClosure())

    $rfToolTip.SetToolTip(
        $deleteButton,
        "Delete this RF power device."
    )

    return $deleteButton
}

function New-RfPairingIndicator($device) {
    $state = Get-RfPairingState $device

    switch ($state) {
        'paired' {
            $text = 'PAIRED'
            $fill = [System.Drawing.Color]::FromArgb(219, 242, 224)
            $textColor = [System.Drawing.Color]::FromArgb(24, 110, 48)
            $border = [System.Drawing.Color]::FromArgb(95, 170, 112)
        }

        'unpaired' {
            $text = 'NOT PAIRED'
            $fill = [System.Drawing.Color]::FromArgb(255, 242, 204)
            $textColor = [System.Drawing.Color]::FromArgb(145, 95, 0)
            $border = [System.Drawing.Color]::FromArgb(205, 160, 65)
        }

        default {
            $text = 'UNKNOWN'
            $fill = [System.Drawing.Color]::FromArgb(236, 236, 236)
            $textColor = [System.Drawing.Color]::DimGray
            $border = [System.Drawing.Color]::FromArgb(165, 165, 165)
        }
    }

    $indicator = New-RfSmoothButton `
        $text `
        84 `
        22 `
        $fill `
        $textColor `
        $border

    $indicator.Font =
        New-Object System.Drawing.Font('Segoe UI Semibold', 7.5)

    $capturedDevice = $device
    $indicator.Add_Click({
        Show-RfPairingInfo $capturedDevice
    }.GetNewClosure())

    if ($state -eq 'paired') {
        $rfToolTip.SetToolTip(
            $indicator,
            "Paired according to the Tower RF definition. " +
            "Stored status: $([string]$device.status)"
        )
    }
    elseif ($state -eq 'unpaired') {
        $rfToolTip.SetToolTip(
            $indicator,
            "Not paired. Click here to start the pairing wizard once it is " +
            "added."
        )
    }
    else {
        $rfToolTip.SetToolTip(
            $indicator,
            "Pairing status is unknown. Stored status: " +
            "$([string]$device.status)"
        )
    }

    return $indicator
}

function Get-RfTechnicalDetails($device) {
    if ($null -eq $device) { return '' }

    $lines = New-Object System.Collections.Generic.List[string]

    $lines.Add([string]$device.name)
    $lines.Add("Record ID: $([string]$device.id)")

    if (-not [string]::IsNullOrWhiteSpace([string]$device.protocol)) {
        $lines.Add(
            "Protocol: " +
            (Get-RfProtocolDisplayName ([string]$device.protocol)) +
            " ($([string]$device.protocol))"
        )
    }

    # All current RF power devices use the Tower's shared FS1000A-class
    # 433 MHz transmitter. Modern devices differ by address, not carrier.
    $lines.Add('RF carrier: shared Tower 433 MHz transmitter')

    if ([string]$device.protocol -eq 'kaku_ac') {
        if (-not [string]::IsNullOrWhiteSpace(
                [string]$device.transmitterId)) {
            $lines.Add(
                "Unique transmitter ID: $([string]$device.transmitterId)"
            )
        }
        if ($null -ne $device.unit) {
            $lines.Add("Unit: $([string]$device.unit)")
        }
    }
    elseif ([string]$device.protocol -eq 'kaku_old') {
        if (-not [string]::IsNullOrWhiteSpace([string]$device.house)) {
            $lines.Add("House: $([string]$device.house)")
        }
        if ($null -ne $device.unit) {
            $lines.Add("Unit: $([string]$device.unit)")
        }
        if ($null -ne $device.onCode -and
            [string]$device.onCode -ne '0') {
            $lines.Add("ON code: $([string]$device.onCode)")
        }
        if ($null -ne $device.offCode -and
            [string]$device.offCode -ne '0') {
            $lines.Add("OFF code: $([string]$device.offCode)")
        }
    }

    if ($null -ne $device.pulseUs -and
        [string]$device.pulseUs -ne '0') {
        $lines.Add("Pulse: $([string]$device.pulseUs) us")
    }

    if ($null -ne $device.repeat -and
        [string]$device.repeat -ne '0') {
        $lines.Add("Repeat: $([string]$device.repeat)")
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$device.status)) {
        $lines.Add("Status: $([string]$device.status)")
    }

    if ([string]::IsNullOrWhiteSpace([string]$device.protocol)) {
        $lines.Add(
            'Detailed protocol/address info will appear after the Pi API ' +
            'has been updated and RF devices have refreshed.'
        )
    }

    return ($lines -join [Environment]::NewLine)
}

function Toggle-RfPresetDevice(
    [int]$preset,
    [string]$deviceId) {

    $ids = @(Get-RfPresetDeviceIds $preset)

    if ($ids -contains $deviceId) {
        $ids = @($ids | Where-Object { $_ -ne $deviceId })
    }
    else {
        $ids += $deviceId
    }

    Set-RfPresetDeviceIds $preset $ids
    Refresh-RfPresetControls
}

function Refresh-RfPresetControls {
    $validIds = @($script:rfDevices | ForEach-Object { [string]$_.id })

    for ($preset = 1; $preset -le 3; $preset++) {
        $flow = $script:rfPresetFlows[$preset]
        $powerButton = $script:rfPresetPowerButtons[$preset]
        $powerOffButton = $script:rfPresetOffButtons[$preset]

        if ($null -eq $flow) { continue }

        # Drop stale device IDs from persistent presets.
        $selected = @(
            Get-RfPresetDeviceIds $preset |
                Where-Object { $validIds -contains [string]$_ }
        )
        Set-RfPresetDeviceIds $preset $selected

        $flow.SuspendLayout()
        $flow.Controls.Clear()

        foreach ($device in @($script:rfDevices)) {
            $deviceId = [string]$device.id
            $deviceName = [string]$device.name

            $isSelected = $selected -contains $deviceId

            if ($isSelected) {
                $presetFill = [System.Drawing.Color]::SteelBlue
                $presetText = [System.Drawing.Color]::White
            }
            else {
                $presetFill = [System.Drawing.Color]::White
                $presetText =
                    [System.Drawing.SystemColors]::ControlText
            }

            $button = New-RfSmoothButton `
                $deviceName `
                96 `
                30 `
                $presetFill `
                $presetText

            $button.Margin =
                New-Object System.Windows.Forms.Padding(2)

            if ($isSelected) {
                $button.Font =
                    New-Object System.Drawing.Font(
                        'Segoe UI Semibold',
                        8.5
                    )
            }
            else {
                $button.Font =
                    New-Object System.Drawing.Font(
                        'Segoe UI',
                        8.5
                    )
            }

            $capturedPreset = $preset
            $capturedId = $deviceId
            $button.Add_Click({
                Toggle-RfPresetDevice $capturedPreset $capturedId
            }.GetNewClosure())

            $rfToolTip.SetToolTip(
                $button,
                (Get-RfTechnicalDetails $device)
            )

            [void]$flow.Controls.Add($button)
        }

        $flow.ResumeLayout()

        if ($null -ne $powerButton) {
            $powerButton.Enabled = ($selected.Count -gt 0)

            if ($selected.Count -gt 0) {
                $presetToolTipText =
                    "Power on the $($selected.Count) selected device(s) " +
                    "in Preset $preset."
            }
            else {
                $presetToolTipText =
                    "Select one or more RF devices above first."
            }

            $rfToolTip.SetToolTip(
                $powerButton,
                $presetToolTipText
            )
        }

        if ($null -ne $powerOffButton) {
            $powerOffButton.Enabled = ($selected.Count -gt 0)

            if ($selected.Count -gt 0) {
                $presetOffToolTipText =
                    "Power off the $($selected.Count) selected device(s) " +
                    "in Preset $preset."
            }
            else {
                $presetOffToolTipText =
                    "Select one or more RF devices above first."
            }

            $rfToolTip.SetToolTip(
                $powerOffButton,
                $presetOffToolTipText
            )
        }
    }
}

function Send-RfAction(
    [string]$deviceId,
    [string]$action,
    [string]$displayName) {

    try {
        Set-TowerStatus "Sending $action to $displayName..."
        $form.Refresh()
        Invoke-TowerPost '/api/v1/rf/send' @{
            device = $deviceId
            action = $action
        } | Out-Null
        Set-TowerStatus "${displayName}: $action sent"
    }
    catch {
        Set-TowerStatus "${displayName}: $action failed" $true
        $details = Get-TowerHttpErrorDetails $_ 'POST' '/api/v1/rf/send' @{
            device = $deviceId
            action = $action
        }
        [System.Windows.Forms.MessageBox]::Show(
            $details.Text,
            'Tower RF error',
            'OK',
            'Error'
        ) | Out-Null
    }
}

function Send-RfPresetAction([int]$preset, [string]$action) {
    $deviceIds = @(Get-RfPresetDeviceIds $preset)

    if ($deviceIds.Count -eq 0) {
        Set-TowerStatus "Preset $preset has no RF devices selected" $true
        return
    }

    try {
        Set-TowerStatus (
            "Sending $action to Preset $preset " +
            "($($deviceIds.Count) devices)..."
        )
        $form.Refresh()

        $response = Invoke-TowerPost '/api/v1/rf/group' @{
            action = $action
            devices = @($deviceIds)
        }

        $succeeded = @($response.results | Where-Object { $_.ok }).Count
        $total = @($response.results).Count

        Set-TowerStatus (
            "Preset ${preset}: $action sent to $succeeded/$total devices"
        )
    }
    catch {
        Set-TowerStatus "Preset $preset RF action failed" $true
        $details = Get-TowerHttpErrorDetails $_ 'POST' '/api/v1/rf/group' @{
            action = $action
            devices = @($deviceIds)
        }
        [System.Windows.Forms.MessageBox]::Show(
            $details.Text,
            "Tower RF Preset $preset error",
            'OK',
            'Error'
        ) | Out-Null
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
        $details = Get-TowerHttpErrorDetails $_ 'POST' '/api/v1/rf/all' @{
            action = $action
        }
        [System.Windows.Forms.MessageBox]::Show(
            $details.Text,
            'Tower RF All error',
            'OK',
            'Error'
        ) | Out-Null
    }
}

function Resize-RfDeviceCards {
    if ($null -eq $rfPanel) { return }

    $available = [Math]::Max(230, $rfPanel.ClientSize.Width - 28)

    if ([string]$config.rfDeviceViewMode -eq 'list') {
        # Keep the list row wide enough to leave comfortable space after
        # the pencil/delete controls. This used to cap at 560 px, which
        # silently undid the wider row size set in Render-RfDevices.
        $width = [Math]::Min(590, $available)
    }
    else {
        $width = [Math]::Min(270, $available)
    }

    foreach ($card in @($script:rfDeviceCards)) {
        if ($null -ne $card) {
            $card.Width = $width
            $card.Invalidate()
        }
    }
}

function Refresh-RfInventoryAfterWizard {
    $script:rfDevicesHaveLoaded = $false

    if ($null -eq $script:rfReadJob) {
        Start-RfDeviceRead
    }
}

function Show-RfPairWizard($device) {
    if ($null -eq $device) { return }

    $recordId = [string]$device.recordId
    $deviceName = [string]$device.deviceName
    $repeatCount = [int]$device.repeat

    if ($repeatCount -le 0) {
        $repeatCount = 16
    }

    $pairForm = New-Object System.Windows.Forms.Form
    $pairForm.Text = "Pair RF Receiver - $deviceName"
    $pairForm.StartPosition = 'CenterParent'
    $pairForm.FormBorderStyle =
        [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $pairForm.MaximizeBox = $false
    $pairForm.MinimizeBox = $false
    $pairForm.ShowInTaskbar = $false
    $pairForm.ClientSize =
        New-Object System.Drawing.Size(560, 300)
    $pairForm.Font =
        New-Object System.Drawing.Font('Segoe UI', 10)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'Pair the physical receiver'
    $title.Font =
        New-Object System.Drawing.Font('Segoe UI Semibold', 15)
    $title.Location =
        New-Object System.Drawing.Point(24, 20)
    $title.Size =
        New-Object System.Drawing.Size(500, 32)
    $pairForm.Controls.Add($title)

    $instruction = New-Object System.Windows.Forms.Label
    $instruction.Text =
        "Power on the receiver or put it into learn/pair mode.`r`n" +
        "When it is ready, press READY. Tower immediately sends the new ON " +
        "signal $repeatCount times."
    $instruction.Location =
        New-Object System.Drawing.Point(26, 66)
    $instruction.Size =
        New-Object System.Drawing.Size(505, 72)
    $pairForm.Controls.Add($instruction)

    $status = New-Object System.Windows.Forms.Label
    $status.Text = 'Waiting for receiver...'
    $status.Location =
        New-Object System.Drawing.Point(26, 148)
    $status.Size =
        New-Object System.Drawing.Size(505, 42)
    $status.ForeColor = [System.Drawing.Color]::DimGray
    $pairForm.Controls.Add($status)

    $skip = New-Object System.Windows.Forms.Button
    $skip.Text = 'Skip'
    $skip.Size = New-Object System.Drawing.Size(90, 38)
    $skip.Location = New-Object System.Drawing.Point(26, 232)
    Set-IrButtonVisualStyle $skip
    $pairForm.Controls.Add($skip)

    $secondary = New-Object System.Windows.Forms.Button
    $secondary.Text = 'Send ON Again'
    $secondary.Size = New-Object System.Drawing.Size(135, 38)
    $secondary.Location = New-Object System.Drawing.Point(246, 232)
    $secondary.Visible = $false
    Set-IrButtonVisualStyle $secondary
    $pairForm.Controls.Add($secondary)

    $primary = New-Object System.Windows.Forms.Button
    $primary.Text = 'READY - SEND PAIRING'
    $primary.Size = New-Object System.Drawing.Size(165, 38)
    $primary.Location = New-Object System.Drawing.Point(389, 232)
    Set-IrButtonVisualStyle $primary
    $pairForm.Controls.Add($primary)

    $pairState = [pscustomobject]@{ Value = 'ready' }

    $skip.Add_Click({
        $pairForm.Close()
    })

    $secondary.Add_Click({
        try {
            if ($pairState.Value -eq 'on-sent') {
                $status.Text = 'Sending ON again...'
                $pairForm.Refresh()

                Invoke-TowerPost '/api/v1/rf/pair/start' @{
                    device = $recordId
                } | Out-Null

                $status.Text =
                    'ON sent again. Did the receiver switch ON?'
            }
            elseif ($pairState.Value -eq 'off-sent') {
                $status.Text = 'Sending OFF again...'
                $pairForm.Refresh()

                Invoke-TowerPost '/api/v1/rf/send' @{
                    device = $recordId
                    action = 'off'
                } | Out-Null

                $status.Text =
                    'OFF sent again. Did the receiver switch OFF?'
            }
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                'RF Pairing',
                'OK',
                'Error'
            ) | Out-Null
        }
    }.GetNewClosure())

    $primary.Add_Click({
        try {
            switch ($pairState.Value) {
                'ready' {
                    $status.Text = 'Sending pairing ON now...'
                    $pairForm.Refresh()

                    Invoke-TowerPost '/api/v1/rf/pair/start' @{
                        device = $recordId
                    } | Out-Null

                    $pairState.Value = 'on-sent'
                    $status.Text =
                        'ON was sent. Did the receiver switch ON?'
                    $secondary.Text = 'Send ON Again'
                    $secondary.Visible = $true
                    $primary.Text = 'YES - TEST OFF'
                }

                'on-sent' {
                    $status.Text = 'Sending OFF test now...'
                    $pairForm.Refresh()

                    Invoke-TowerPost '/api/v1/rf/send' @{
                        device = $recordId
                        action = 'off'
                    } | Out-Null

                    $pairState.Value = 'off-sent'
                    $status.Text =
                        'OFF was sent. Did the receiver switch OFF?'
                    $secondary.Text = 'Send OFF Again'
                    $primary.Text = 'YES - MARK PAIRED'
                }

                'off-sent' {
                    Invoke-TowerPost '/api/v1/rf/pair/status' @{
                        device = $recordId
                        paired = $true
                    } | Out-Null

                    Refresh-RfInventoryAfterWizard

                    [System.Windows.Forms.MessageBox]::Show(
                        "$deviceName is now marked as paired.",
                        'RF Pairing Complete',
                        'OK',
                        'Information'
                    ) | Out-Null

                    $pairForm.Close()
                }
            }
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                'RF Pairing',
                'OK',
                'Error'
            ) | Out-Null
        }
    }.GetNewClosure())

    [void]$pairForm.ShowDialog($form)
    $pairForm.Dispose()

    # Also refresh after a skipped/cancelled pairing attempt so a newly-created
    # status=unpaired device appears immediately in the RF page.
    Refresh-RfInventoryAfterWizard
}

function Show-AddRfDeviceWizard {
    try {
        Set-TowerStatus 'Preparing RF add-device wizard...'
        $defaults = Invoke-TowerGet '/api/v1/rf/modern/next'
    }
    catch {
        Set-TowerStatus 'RF add-device wizard failed' $true
        $details =
            Get-TowerHttpErrorDetails `
                $_ `
                'GET' `
                '/api/v1/rf/modern/next'

        [System.Windows.Forms.MessageBox]::Show(
            $details.Text,
            'Add RF Device',
            'OK',
            'Error'
        ) | Out-Null
        return
    }

    $wizard = New-Object System.Windows.Forms.Form
    $wizard.Text = 'Add RF Power Device'
    $wizard.StartPosition = 'CenterParent'
    $wizard.FormBorderStyle =
        [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $wizard.MaximizeBox = $false
    $wizard.MinimizeBox = $false
    $wizard.ShowInTaskbar = $false
    $wizard.ClientSize =
        New-Object System.Drawing.Size(610, 430)
    $wizard.Font =
        New-Object System.Drawing.Font('Segoe UI', 10)

    # -----------------------------------------------------------------------
    # STEP 1 - CREATE
    # -----------------------------------------------------------------------
    $createPanel = New-Object System.Windows.Forms.Panel
    $createPanel.Dock = 'Fill'
    $wizard.Controls.Add($createPanel)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'Add Modern KAKU RF Power Device'
    $title.Font =
        New-Object System.Drawing.Font('Segoe UI Semibold', 15)
    $title.Location =
        New-Object System.Drawing.Point(24, 20)
    $title.Size =
        New-Object System.Drawing.Size(550, 32)
    $createPanel.Controls.Add($title)

    $labelRecord = New-Object System.Windows.Forms.Label
    $labelRecord.Text = 'RF definition'
    $labelRecord.Location =
        New-Object System.Drawing.Point(28, 82)
    $labelRecord.Size =
        New-Object System.Drawing.Size(165, 24)
    $createPanel.Controls.Add($labelRecord)

    $recordValue = New-Object System.Windows.Forms.Label
    $recordValue.Text = [string]$defaults.fileName
    $recordValue.Location =
        New-Object System.Drawing.Point(205, 82)
    $recordValue.Size =
        New-Object System.Drawing.Size(360, 24)
    $recordValue.Font =
        New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $createPanel.Controls.Add($recordValue)

    $labelName = New-Object System.Windows.Forms.Label
    $labelName.Text = 'Device name'
    $labelName.Location =
        New-Object System.Drawing.Point(28, 124)
    $labelName.Size =
        New-Object System.Drawing.Size(165, 24)
    $createPanel.Controls.Add($labelName)

    $nameBox = New-Object System.Windows.Forms.TextBox
    $nameBox.Location =
        New-Object System.Drawing.Point(205, 121)
    $nameBox.Size =
        New-Object System.Drawing.Size(360, 28)
    $createPanel.Controls.Add($nameBox)

    $labelDescription = New-Object System.Windows.Forms.Label
    $labelDescription.Text = 'Description'
    $labelDescription.Location =
        New-Object System.Drawing.Point(28, 166)
    $labelDescription.Size =
        New-Object System.Drawing.Size(165, 24)
    $createPanel.Controls.Add($labelDescription)

    $descriptionBox = New-Object System.Windows.Forms.TextBox
    $descriptionBox.Location =
        New-Object System.Drawing.Point(205, 163)
    $descriptionBox.Size =
        New-Object System.Drawing.Size(360, 28)
    $descriptionBox.Text = [string]$defaults.description
    $createPanel.Controls.Add($descriptionBox)

    $labelTransmitter = New-Object System.Windows.Forms.Label
    $labelTransmitter.Text = 'Transmitter ID'
    $labelTransmitter.Location =
        New-Object System.Drawing.Point(28, 208)
    $labelTransmitter.Size =
        New-Object System.Drawing.Size(165, 24)
    $createPanel.Controls.Add($labelTransmitter)

    $transmitterBox = New-Object System.Windows.Forms.TextBox
    $transmitterBox.Location =
        New-Object System.Drawing.Point(205, 205)
    $transmitterBox.Size =
        New-Object System.Drawing.Size(180, 28)
    $transmitterBox.Text =
        [string]$defaults.suggestedTransmitterId
    $createPanel.Controls.Add($transmitterBox)

    $recommended = New-Object System.Windows.Forms.Label
    $recommended.Text =
        "Preferred next: $([string]$defaults.suggestedTransmitterId)"
    $recommended.Location =
        New-Object System.Drawing.Point(398, 208)
    $recommended.Size =
        New-Object System.Drawing.Size(180, 24)
    $recommended.ForeColor = [System.Drawing.Color]::SteelBlue
    $createPanel.Controls.Add($recommended)

    $hexNote = New-Object System.Windows.Forms.Label
    $hexNote.Text =
        'Modern KAKU IDs are hexadecimal; this field remains editable.'
    $hexNote.Location =
        New-Object System.Drawing.Point(205, 236)
    $hexNote.Size =
        New-Object System.Drawing.Size(370, 42)
    $hexNote.ForeColor = [System.Drawing.Color]::DimGray
    $createPanel.Controls.Add($hexNote)

    # Advanced section is collapsed by default. Unit remains 1 for the normal
    # Tower workflow and is only exposed when deliberately requested.
    $advancedButton = New-RfSmoothButton `
        'Advanced...' `
        110 `
        30 `
        ([System.Drawing.Color]::White) `
        ([System.Drawing.Color]::FromArgb(35, 35, 35)) `
        ([System.Drawing.Color]::FromArgb(150, 145, 185))
    $advancedButton.Location =
        New-Object System.Drawing.Point(205, 288)
    $createPanel.Controls.Add($advancedButton)

    $advancedPanel = New-Object System.Windows.Forms.Panel
    $advancedPanel.Location =
        New-Object System.Drawing.Point(320, 280)
    $advancedPanel.Size =
        New-Object System.Drawing.Size(245, 78)
    $advancedPanel.Visible = $false
    $createPanel.Controls.Add($advancedPanel)

    $labelUnit = New-Object System.Windows.Forms.Label
    $labelUnit.Text = 'Unit'
    $labelUnit.Location =
        New-Object System.Drawing.Point(0, 8)
    $labelUnit.Size =
        New-Object System.Drawing.Size(50, 24)
    $advancedPanel.Controls.Add($labelUnit)

    $unitBox = New-Object System.Windows.Forms.NumericUpDown
    $unitBox.Location =
        New-Object System.Drawing.Point(56, 5)
    $unitBox.Size =
        New-Object System.Drawing.Size(72, 28)
    $unitBox.Minimum = 0
    $unitBox.Maximum = 15
    $unitBox.Value = [decimal][int]$defaults.unit
    $advancedPanel.Controls.Add($unitBox)

    $advancedNote = New-Object System.Windows.Forms.Label
    $advancedNote.Text =
        "Normal Tower use keeps Unit at 1.`r`n" +
        "GPIO $([string]$defaults.gpio), " +
        "pulse $([string]$defaults.pulseUs) us, " +
        "repeat $([string]$defaults.repeat)."
    $advancedNote.Location =
        New-Object System.Drawing.Point(0, 38)
    $advancedNote.Size =
        New-Object System.Drawing.Size(240, 36)
    $advancedNote.Font =
        New-Object System.Drawing.Font('Segoe UI', 8.5)
    $advancedNote.ForeColor = [System.Drawing.Color]::DimGray
    $advancedPanel.Controls.Add($advancedNote)

    $advancedButton.Add_Click({
        $advancedPanel.Visible = -not $advancedPanel.Visible

        if ($advancedPanel.Visible) {
            $advancedButton.Text = 'Advanced <<'
        }
        else {
            $advancedButton.Text = 'Advanced...'
        }

        $advancedButton.Invalidate()
    })

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.Size = New-Object System.Drawing.Size(90, 38)
    $cancel.Location =
        New-Object System.Drawing.Point(28, 370)
    Set-IrButtonVisualStyle $cancel
    $createPanel.Controls.Add($cancel)

    $create = New-Object System.Windows.Forms.Button
    $create.Text = 'Create Device'
    $create.Size = New-Object System.Drawing.Size(140, 38)
    $create.Location =
        New-Object System.Drawing.Point(425, 370)
    Set-IrButtonVisualStyle $create
    $createPanel.Controls.Add($create)

    $cancel.Add_Click({
        $wizard.Close()
    })

    # -----------------------------------------------------------------------
    # STEP 2 - CREATED / PAIR OR FINISH
    # -----------------------------------------------------------------------
    $finishPanel = New-Object System.Windows.Forms.Panel
    $finishPanel.Dock = 'Fill'
    $finishPanel.Visible = $false
    $wizard.Controls.Add($finishPanel)

    $finishTitle = New-Object System.Windows.Forms.Label
    $finishTitle.Text = 'RF Device Created'
    $finishTitle.Font =
        New-Object System.Drawing.Font('Segoe UI Semibold', 15)
    $finishTitle.Location =
        New-Object System.Drawing.Point(24, 24)
    $finishTitle.Size =
        New-Object System.Drawing.Size(550, 32)
    $finishPanel.Controls.Add($finishTitle)

    $finishText = New-Object System.Windows.Forms.Label
    $finishText.Location =
        New-Object System.Drawing.Point(28, 78)
    $finishText.Size =
        New-Object System.Drawing.Size(535, 120)
    $finishText.Font =
        New-Object System.Drawing.Font('Segoe UI', 10)
    $finishPanel.Controls.Add($finishText)

    $pairQuestion = New-Object System.Windows.Forms.Label
    $pairQuestion.Text = 'Would you like to pair the receiver now?'
    $pairQuestion.Font =
        New-Object System.Drawing.Font('Segoe UI Semibold', 11)
    $pairQuestion.Location =
        New-Object System.Drawing.Point(28, 220)
    $pairQuestion.Size =
        New-Object System.Drawing.Size(535, 30)
    $finishPanel.Controls.Add($pairQuestion)

    $finishSkip = New-Object System.Windows.Forms.Button
    $finishSkip.Text = 'Skip && Finish'
    $finishSkip.Size =
        New-Object System.Drawing.Size(130, 40)
    $finishSkip.Location =
        New-Object System.Drawing.Point(28, 320)
    Set-IrButtonVisualStyle $finishSkip
    $finishPanel.Controls.Add($finishSkip)

    $pairNowButton = New-Object System.Windows.Forms.Button
    $pairNowButton.Text = 'Pair Now'
    $pairNowButton.Size =
        New-Object System.Drawing.Size(130, 40)
    $pairNowButton.Location =
        New-Object System.Drawing.Point(435, 320)
    Set-IrButtonVisualStyle $pairNowButton
    $finishPanel.Controls.Add($pairNowButton)

    $createdResponse = $null

    $finishSkip.Add_Click({
        Refresh-RfInventoryAfterWizard
        $wizard.Close()
    })

    $pairNowButton.Add_Click({
        if ($null -eq $createdResponse) {
            return
        }

        $wizard.Hide()
        Show-RfPairWizard $createdResponse
        Refresh-RfInventoryAfterWizard
        $wizard.Close()
    })

    $create.Add_Click({
        $deviceName = $nameBox.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($deviceName)) {
            [System.Windows.Forms.MessageBox]::Show(
                'Enter a device name first.',
                'Add RF Device',
                'OK',
                'Warning'
            ) | Out-Null
            $nameBox.Focus()
            return
        }

        try {
            $create.Enabled = $false

            $createdResponse = Invoke-TowerPost '/api/v1/rf/create' @{
                deviceName = $deviceName
                description = $descriptionBox.Text.Trim()
                transmitterId = $transmitterBox.Text.Trim()
                unit = [int]$unitBox.Value
            }

            $finishText.Text =
                "$([string]$createdResponse.deviceName) has been created " +
                "on PI3A as:`r`n`r`n" +
                "$([string]$createdResponse.fileName)`r`n`r`n" +
                "The RF definition is currently NOT PAIRED."

            $createPanel.Visible = $false
            $finishPanel.Visible = $true
            $finishPanel.BringToFront()

            Set-TowerStatus 'RF device created'
        }
        catch {
            $create.Enabled = $true

            $details = Get-TowerHttpErrorDetails `
                $_ `
                'POST' `
                '/api/v1/rf/create' `
                @{
                    deviceName = $deviceName
                    description = $descriptionBox.Text.Trim()
                    transmitterId = $transmitterBox.Text.Trim()
                    unit = [int]$unitBox.Value
                }

            [System.Windows.Forms.MessageBox]::Show(
                $details.Text,
                'Add RF Device',
                'OK',
                'Error'
            ) | Out-Null
        }
    })

    Set-TowerStatus 'Connected'
    $nameBox.Focus()
    [void]$wizard.ShowDialog($form)
    $wizard.Dispose()
}


function New-RfActionButton(
    [string]$text,
    [System.Drawing.Color]$backColor,
    [string]$deviceId,
    [string]$deviceName,
    [string]$action,
    [string]$technicalDetails) {

    $button = New-RfSmoothButton `
        $text `
        116 `
        34 `
        $backColor

    $button.Margin =
        New-Object System.Windows.Forms.Padding(3)

    $capturedId = $deviceId
    $capturedName = $deviceName
    $capturedAction = $action

    $button.Add_Click({
        Send-RfAction `
            $capturedId `
            $capturedAction `
            $capturedName
    }.GetNewClosure())

    $rfToolTip.SetToolTip($button, $technicalDetails)
    return $button
}

function Add-RfPanelBorder($panel) {
    if ($null -eq $panel) { return }

    $panel.Add_Paint({
        param($sender, $eventArgs)

        $pen = New-Object System.Drawing.Pen(
            ([System.Drawing.Color]::FromArgb(198, 198, 198)),
            1.0
        )

        try {
            $rect = New-Object System.Drawing.Rectangle(
                0,
                0,
                [Math]::Max(0, $sender.ClientSize.Width - 1),
                [Math]::Max(0, $sender.ClientSize.Height - 1)
            )
            $eventArgs.Graphics.DrawRectangle($pen, $rect)
        }
        finally {
            $pen.Dispose()
        }
    })
}

function Render-RfDevices {
    $script:rfDeviceCards = @()

    $rfPanel.SuspendLayout()
    $rfPanel.Controls.Clear()

    $listMode =
        ([string]$config.rfDeviceViewMode -eq 'list')

    if ($listMode) {
        $rfPanel.FlowDirection =
            [System.Windows.Forms.FlowDirection]::TopDown
        $rfPanel.WrapContents = $false
    }
    else {
        $rfPanel.FlowDirection =
            [System.Windows.Forms.FlowDirection]::LeftToRight
        $rfPanel.WrapContents = $true
    }

    foreach ($device in @($script:rfDevices)) {
        $deviceId = [string]$device.id
        $deviceName = [string]$device.name
        $technicalDetails = Get-RfTechnicalDetails $device
        $protocolName =
            Get-RfProtocolDisplayName ([string]$device.protocol)

        if ($listMode) {
            $row = New-Object System.Windows.Forms.Panel
            # Leave a little visual breathing room after the rename/delete
            # controls instead of ending the row almost directly on the X.
            $row.Width = 590
            $row.Height = 62
            $row.Margin =
                New-Object System.Windows.Forms.Padding(5, 4, 5, 5)
            $row.BackColor =
                [System.Drawing.Color]::FromArgb(250, 250, 250)
            Add-RfPanelBorder $row

            $nameLabel = New-Object System.Windows.Forms.Label
            $nameLabel.Text = $deviceName
            $nameLabel.Location =
                New-Object System.Drawing.Point(10, 7)
            $nameLabel.Size =
                New-Object System.Drawing.Size(185, 22)
            $nameLabel.Font =
                New-Object System.Drawing.Font(
                    'Segoe UI Semibold',
                    9.5
                )
            $nameLabel.AutoEllipsis = $true
            $row.Controls.Add($nameLabel)

            $protocolLabel = New-Object System.Windows.Forms.Label
            $protocolLabel.Text = $protocolName
            $protocolLabel.Location =
                New-Object System.Drawing.Point(10, 31)
            $protocolLabel.Size =
                New-Object System.Drawing.Size(185, 19)
            $protocolLabel.ForeColor =
                [System.Drawing.Color]::DimGray
            $protocolLabel.AutoEllipsis = $true
            $row.Controls.Add($protocolLabel)

            $onButton = New-RfActionButton `
                'ON' `
                ([System.Drawing.Color]::FromArgb(220, 242, 224)) `
                $deviceId `
                $deviceName `
                'on' `
                $technicalDetails
            $onButton.Location =
                New-Object System.Drawing.Point(205, 13)
            $row.Controls.Add($onButton)

            $offButton = New-RfActionButton `
                'OFF' `
                ([System.Drawing.Color]::FromArgb(248, 226, 226)) `
                $deviceId `
                $deviceName `
                'off' `
                $technicalDetails
            $offButton.Location =
                New-Object System.Drawing.Point(327, 13)
            $row.Controls.Add($offButton)

            $pairingIndicator = New-RfPairingIndicator $device
            $pairingIndicator.Width = 72
            $pairingIndicator.Location =
                New-Object System.Drawing.Point(443, 19)
            $row.Controls.Add($pairingIndicator)

            $renameButton = New-RfRenameButton $device
            $renameButton.Location =
                New-Object System.Drawing.Point(518, 21)
            $row.Controls.Add($renameButton)

            $deleteButton = New-RfDeleteButton $device
            $deleteButton.Location =
                New-Object System.Drawing.Point(540, 21)
            $row.Controls.Add($deleteButton)

            $rfToolTip.SetToolTip($row, $technicalDetails)
            $rfToolTip.SetToolTip($nameLabel, $technicalDetails)
            $rfToolTip.SetToolTip($protocolLabel, $technicalDetails)

            [void]$rfPanel.Controls.Add($row)
            $script:rfDeviceCards += $row
        }
        else {
            $card = New-Object System.Windows.Forms.Panel
            $card.Width = 270
            $card.Height = 98
            $card.Margin =
                New-Object System.Windows.Forms.Padding(5, 4, 6, 7)
            $card.BackColor =
                [System.Drawing.Color]::FromArgb(250, 250, 250)
            Add-RfPanelBorder $card

            $nameLabel = New-Object System.Windows.Forms.Label
            $nameLabel.Text = $deviceName
            $nameLabel.Location =
                New-Object System.Drawing.Point(10, 8)
            $nameLabel.Size =
                New-Object System.Drawing.Size(118, 22)
            $nameLabel.Font =
                New-Object System.Drawing.Font(
                    'Segoe UI Semibold',
                    9.5
                )
            $nameLabel.AutoEllipsis = $true
            $card.Controls.Add($nameLabel)

            $pairingIndicator = New-RfPairingIndicator $device
            $pairingIndicator.Location =
                New-Object System.Drawing.Point(134, 5)
            $card.Controls.Add($pairingIndicator)

            $renameButton = New-RfRenameButton $device
            $renameButton.Location =
                New-Object System.Drawing.Point(222, 7)
            $card.Controls.Add($renameButton)

            $deleteButton = New-RfDeleteButton $device
            $deleteButton.Location =
                New-Object System.Drawing.Point(244, 7)
            $card.Controls.Add($deleteButton)

            $protocolLabel = New-Object System.Windows.Forms.Label
            $protocolLabel.Text = $protocolName
            $protocolLabel.Location =
                New-Object System.Drawing.Point(10, 31)
            $protocolLabel.Size =
                New-Object System.Drawing.Size(250, 18)
            $protocolLabel.ForeColor =
                [System.Drawing.Color]::DimGray
            $protocolLabel.Font =
                New-Object System.Drawing.Font('Segoe UI', 8.5)
            $protocolLabel.AutoEllipsis = $true
            $card.Controls.Add($protocolLabel)

            $onButton = New-RfActionButton `
                'ON' `
                ([System.Drawing.Color]::FromArgb(220, 242, 224)) `
                $deviceId `
                $deviceName `
                'on' `
                $technicalDetails
            $onButton.Location =
                New-Object System.Drawing.Point(10, 54)
            $card.Controls.Add($onButton)

            $offButton = New-RfActionButton `
                'OFF' `
                ([System.Drawing.Color]::FromArgb(248, 226, 226)) `
                $deviceId `
                $deviceName `
                'off' `
                $technicalDetails
            $offButton.Location =
                New-Object System.Drawing.Point(134, 54)
            $card.Controls.Add($offButton)

            $rfToolTip.SetToolTip($card, $technicalDetails)
            $rfToolTip.SetToolTip($nameLabel, $technicalDetails)
            $rfToolTip.SetToolTip($protocolLabel, $technicalDetails)

            [void]$rfPanel.Controls.Add($card)
            $script:rfDeviceCards += $card
        }
    }

    $rfPanel.ResumeLayout()
    Resize-RfDeviceCards
    Refresh-RfPresetControls
    Refresh-RfViewButtons
}

function Apply-RfDevicesResponse($response) {
    $incoming =
        @($response.devices)

    $signature =
        Get-RfInventorySignature $incoming

    $alreadyRendered =
        $script:rfDevicesHaveLoaded -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$script:rfInventorySignature
        )

    if ($alreadyRendered -and
        $signature -eq
            [string]$script:rfInventorySignature) {

        # The Pi returned exactly the inventory already on screen.
        # Keep the existing WinForms controls intact so cards/presets do not
        # flash white merely because a background refresh completed.
        $script:rfDevicesHaveLoaded = $true
        return
    }

    $script:rfDevices = $incoming
    $script:rfDevicesHaveLoaded = $true
    $script:rfInventorySignature =
        $signature

    Render-RfDevices
}

function Get-RfInventorySignature($devices) {
    try {
        return (
            @($devices) |
                ConvertTo-Json -Depth 12 -Compress
        )
    }
    catch {
        return ''
    }
}

function Save-RfDeviceCache($response) {
    try {
        New-Item -ItemType Directory -Path $configDirectory -Force |
            Out-Null

        $response |
            ConvertTo-Json -Depth 12 |
            Set-Content -Path $rfDeviceCachePath -Encoding UTF8
    }
    catch {
        Write-TowerLog 'WARN' (
            "Could not save RF device cache: $($_.Exception.Message)"
        )
    }
}

function Try-LoadRfDeviceCache {
    if ($script:rfCacheLoaded) {
        return $script:rfDevicesHaveLoaded
    }

    $script:rfCacheLoaded = $true

    if (-not (Test-Path $rfDeviceCachePath)) {
        return $false
    }

    try {
        $response =
            Get-Content $rfDeviceCachePath -Raw |
            ConvertFrom-Json

        Apply-RfDevicesResponse $response
        Write-TowerLog 'INFO' 'Loaded RF devices from local cache'
        return $true
    }
    catch {
        Write-TowerLog 'WARN' (
            "Could not load RF device cache: $($_.Exception.Message)"
        )
        return $false
    }
}

function Start-RfDeviceRead([bool]$quiet = $false) {
    if ($null -ne $script:rfReadJob) { return }

    $script:rfReadQuiet = $quiet

    try {
        if (-not $quiet) {
            Set-TowerStatus 'Loading RF devices...'
        }

        $script:rfReadJob =
            Start-TowerReadJob '/api/v1/rf/devices'
    }
    catch {
        $script:rfReadQuiet = $false

        if ($quiet -and
            $script:rfDevicesHaveLoaded) {
            Write-TowerLog 'WARN' (
                "Quiet startup RF read could not start: " +
                "$($_.Exception.Message)"
            )
        }
        else {
            Set-TowerStatus 'RF device refresh failed' $true
            Write-TowerLog 'ERROR' (
                "Could not start RF read: " +
                "$($_.Exception.Message)"
            )
        }
    }
}

function Complete-RfDeviceRead {
    if ($null -eq $script:rfReadJob) { return }
    if ($script:rfReadJob.State -eq 'Running' -or
        $script:rfReadJob.State -eq 'NotStarted') { return }

    $job = $script:rfReadJob
    $quiet = [bool]$script:rfReadQuiet
    $script:rfReadJob = $null
    $script:rfReadQuiet = $false

    try {
        if ($job.State -ne 'Completed') {
            throw (Get-TowerReadJobError $job)
        }

        $response = Receive-Job -Job $job -ErrorAction Stop
        Apply-RfDevicesResponse $response
        Save-RfDeviceCache $response
        $script:rfStartupRetryCount = 0

        Set-TowerStatus (
            "Connected to $($config.server) - " +
            "$($config.rfDisplayCount) RF devices, " +
            "$($config.irDisplayCount) IR devices"
        )
    }
    catch {
        $errorText = [string]$_.Exception.Message

        if ($quiet -and
            $script:rfDevicesHaveLoaded) {

            Write-TowerLog 'WARN' (
                "Quiet startup RF refresh failed; cached RF inventory " +
                "remains active: $errorText"
            )

            Set-TowerStatus (
                "Connected to $($config.server) - " +
                "$($config.rfDisplayCount) RF devices, " +
                "$($config.irDisplayCount) IR devices"
            )

            if ($script:rfStartupRetryCount -lt 1) {
                $script:rfStartupRetryCount++
                $rfStartupRetryTimer.Start()
            }
        }
        else {
            Set-TowerStatus 'RF device refresh failed' $true
            Write-TowerLog 'ERROR' (
                "RF device read failed: $errorText"
            )
        }
    }
    finally {
        Remove-TowerReadJob $job
    }
}

function Send-IrCommand([string]$deviceId, [string]$commandId, [string]$displayName) {
    $request = @{
        device = $deviceId
        command = $commandId
        transmitters = @($script:selectedIrTransmitters)
    }

    try {
        $txDisplay = @($script:selectedIrTransmitters | ForEach-Object { Get-ShortTransmitterLabel $_ }) -join ', '
        Set-TowerStatus "Sending $displayName via $txDisplay..."
        $form.Refresh()
        $response = Invoke-TowerPost '/api/v1/execute' $request
        Set-TowerStatus "${displayName}: $($response.message)"
    }
    catch {
        Set-TowerStatus "$displayName failed" $true
        $details = Get-TowerHttpErrorDetails $_ 'POST' '/api/v1/execute' $request
        [System.Windows.Forms.MessageBox]::Show(
            $details.Text, 'Tower IR error', 'OK', 'Error') | Out-Null
    }
}

function Get-IrDeviceRenderSignature($device) {
    if ($null -eq $device) { return '' }

    $parts = New-Object System.Collections.Generic.List[string]

    $parts.Add([string]$device.id)
    $parts.Add([string]$device.name)
    $parts.Add([string]$device.manufacturer)
    $parts.Add([string]$device.location)
    $parts.Add([string]$device.remoteName)
    $parts.Add([string]$device.transmitter)

    foreach ($command in @(
        $device.commands |
            Where-Object { $_.transport -eq 'IR' -and $_.enabled } |
            Sort-Object `
                @{ Expression = { [string]$_.id } }, `
                @{ Expression = { [string]$_.name } }
    )) {
        $parts.Add(
            ([string]$command.id) + '|' +
            ([string]$command.name) + '|' +
            ([string]$command.transport) + '|' +
            ([string]$command.enabled)
        )
    }

    return ($parts -join ';;')
}

function Test-IrDevicePaneCurrent($device) {
    if ($null -eq $device) {
        return (
            [string]::IsNullOrWhiteSpace(
                [string]$script:renderedIrDeviceId
            ) -and
            $irCommandPanel.Controls.Count -eq 0
        )
    }

    $deviceId = [string]$device.id
    if ([string]::IsNullOrWhiteSpace($deviceId)) {
        return $false
    }

    if ([string]$script:renderedIrDeviceId -ne $deviceId) {
        return $false
    }

    $signature = Get-IrDeviceRenderSignature $device
    if ([string]$script:renderedIrDeviceSignature -ne $signature) {
        return $false
    }

    # A device with zero commands legitimately has one "No commands" label.
    # Any rendered device should therefore leave at least one control behind.
    return ($irCommandPanel.Controls.Count -gt 0)
}

function Ensure-IrDeviceRendered($device) {
    if (Test-IrDevicePaneCurrent $device) {
        return
    }

    Show-IrDevice $device
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

function Apply-IrDevicesResponse($response) {
    $allDevices = @($response.devices)
    $irCapable = @($allDevices | Where-Object {
        @($_.commands | Where-Object {
            $_.transport -eq 'IR' -and $_.enabled
        }).Count -gt 0
    })

    $orderedDevices =
        @(Get-OrderedIrDevices $irCapable)

    $signature =
        Get-IrInventorySignature $orderedDevices

    $script:irDeviceTotalCount =
        $orderedDevices.Count

    $alreadyRendered =
        $script:irDevicesHaveLoaded -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$script:irInventorySignature
        )

    if ($alreadyRendered -and
        $signature -eq
            [string]$script:irInventorySignature) {

        # Keep the existing device list, Home cards, remote image and command
        # controls intact when the server response contains no actual change.
        $script:irDevicesHaveLoaded = $true
        return
    }

    $script:irDevices = $orderedDevices
    $script:irDevicesHaveLoaded = $true
    $script:irInventorySignature =
        $signature

    $selectedDeviceId = if ($irDeviceList.SelectedItem) {
        [string]$irDeviceList.SelectedItem.id
    }
    else {
        $null
    }

    $script:suppressIrSelectionChanged = $true
    try {
        $irDeviceList.Items.Clear()
        foreach ($device in $script:irDevices) {
            [void]$irDeviceList.Items.Add($device)
        }
        $irDeviceList.DisplayMember = 'name'

        if ($irDeviceList.Items.Count -gt 0) {
            $indexToSelect = 0
            if (-not [string]::IsNullOrWhiteSpace($selectedDeviceId)) {
                for ($i = 0; $i -lt $irDeviceList.Items.Count; $i++) {
                    if ([string]$irDeviceList.Items[$i].id -eq $selectedDeviceId) {
                        $indexToSelect = $i
                        break
                    }
                }
            }
            $irDeviceList.SelectedIndex = $indexToSelect
        }
    }
    finally {
        $script:suppressIrSelectionChanged = $false
    }

    if ($irDeviceList.Items.Count -eq 0) {
        Show-IrDevice $null
    }
    elseif ($tabs.SelectedTab -eq $irTab) {
        # Only rebuild the visible command pane if the selected device/profile
        # actually changed. A background inventory refresh with identical data
        # should not recreate dozens of WinForms controls.
        Ensure-IrDeviceRendered $irDeviceList.SelectedItem
    }

    Refresh-HomeDevices
    Update-IrDeviceManagementButtons
}

function Get-IrInventorySignature($devices) {
    try {
        return (
            @($devices) |
                ConvertTo-Json -Depth 24 -Compress
        )
    }
    catch {
        return ''
    }
}

function Save-IrDeviceCache($response) {
    try {
        New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
        $response |
            ConvertTo-Json -Depth 24 |
            Set-Content -Path $irDeviceCachePath -Encoding UTF8
    }
    catch {
        Write-TowerLog 'WARN' (
            "Could not save IR device cache: $($_.Exception.Message)"
        )
    }
}

function Try-LoadIrDeviceCache {
    if ($script:irCacheLoaded) { return $script:irDevicesHaveLoaded }
    $script:irCacheLoaded = $true

    if (-not (Test-Path $irDeviceCachePath)) { return $false }

    try {
        $response = Get-Content $irDeviceCachePath -Raw | ConvertFrom-Json
        Apply-IrDevicesResponse $response
        $homeHint.Text = 'Choose a device to open its remote controls.'
        Write-TowerLog 'INFO' 'Loaded IR devices from local cache'
        return $true
    }
    catch {
        Write-TowerLog 'WARN' (
            "Could not load IR device cache: $($_.Exception.Message)"
        )
        return $false
    }
}

function Start-IrDeviceRead([bool]$quiet = $false) {
    if ($null -ne $script:irReadJob) { return }

    $script:irReadQuiet = $quiet

    try {
        if (-not $quiet) {
            $homeHint.Text = 'Loading devices...'
            Set-TowerStatus 'Loading IR devices...'
        }

        $script:irReadJob =
            Start-TowerReadJob '/api/v1/devices'
    }
    catch {
        $script:irReadQuiet = $false

        if ($quiet -and
            $script:irDevicesHaveLoaded) {

            $homeHint.Text =
                'Choose a device to open its remote controls.'

            Write-TowerLog 'WARN' (
                "Quiet startup IR read could not start; cached inventory " +
                "remains active: $($_.Exception.Message)"
            )
        }
        else {
            $homeHint.Text =
                'Could not load devices. Press Refresh to retry.'

            Set-TowerStatus 'IR device refresh failed' $true

            Write-TowerLog 'ERROR' (
                "Could not start IR read: " +
                "$($_.Exception.Message)"
            )
        }
    }
}

function Complete-IrDeviceRead {
    if ($null -eq $script:irReadJob) { return }

    if ($script:irReadJob.State -eq 'Running' -or
        $script:irReadJob.State -eq 'NotStarted') {
        return
    }

    $job = $script:irReadJob
    $quiet = [bool]$script:irReadQuiet

    $script:irReadJob = $null
    $script:irReadQuiet = $false

    try {
        if ($job.State -ne 'Completed') {
            throw (Get-TowerReadJobError $job)
        }

        $response =
            Receive-Job -Job $job -ErrorAction Stop

        Apply-IrDevicesResponse $response
        Save-IrDeviceCache $response

        $script:irStartupRetryCount = 0

        $homeHint.Text =
            'Choose a device to open its remote controls.'

        Update-IrRemotePaneLayout

        Set-TowerStatus (
            "Connected to $($config.server) - " +
            "$($config.rfDisplayCount) RF devices, " +
            "$($config.irDisplayCount) IR devices"
        )
    }
    catch {
        $errorText =
            [string]$_.Exception.Message

        if ($quiet -and
            $script:irDevicesHaveLoaded) {

            $homeHint.Text =
                'Choose a device to open its remote controls.'

            Write-TowerLog 'WARN' (
                "Quiet startup IR refresh failed; cached IR inventory " +
                "remains active: $errorText"
            )

            Set-TowerStatus (
                "Connected to $($config.server) - " +
                "$($config.rfDisplayCount) RF devices, " +
                "$($config.irDisplayCount) IR devices"
            )

            if ($script:irStartupRetryCount -lt 1) {
                $script:irStartupRetryCount++
                $irStartupRetryTimer.Start()
            }
        }
        else {
            $homeHint.Text =
                'Could not load devices. Press Refresh to retry.'

            Set-TowerStatus 'IR device refresh failed' $true

            Write-TowerLog 'ERROR' (
                "IR device read failed: $errorText"
            )
        }
    }
    finally {
        Remove-TowerReadJob $job
    }
}

function Refresh-IrDeviceListFromMemory([string]$selectedId = '') {
    $script:suppressIrSelectionChanged = $true
    try {
        $irDeviceList.Items.Clear()
        foreach ($device in @($script:irDevices)) {
            [void]$irDeviceList.Items.Add($device)
        }
        $irDeviceList.DisplayMember = 'name'

        if ($irDeviceList.Items.Count -gt 0) {
            $indexToSelect = 0

            if (-not [string]::IsNullOrWhiteSpace($selectedId)) {
                for ($i = 0; $i -lt $irDeviceList.Items.Count; $i++) {
                    if ([string]$irDeviceList.Items[$i].id -eq $selectedId) {
                        $indexToSelect = $i
                        break
                    }
                }
            }

            $irDeviceList.SelectedIndex = $indexToSelect
        }
    }
    finally {
        $script:suppressIrSelectionChanged = $false
    }

    Refresh-HomeDevices
    Update-IrDeviceManagementButtons
}

function Save-CurrentIrDeviceCache {
    try {
        $snapshot = [pscustomobject]@{
            devices = @($script:irDevices)
        }
        Save-IrDeviceCache $snapshot
    }
    catch {
        Write-TowerLog 'WARN' (
            "Could not update local IR cache: $($_.Exception.Message)"
        )
    }
}

function Update-IrDeviceManagementButtons {
    if ($null -eq $irDeviceList) { return }

    $count = $irDeviceList.Items.Count
    $index = $irDeviceList.SelectedIndex
    $hasSelection = ($index -ge 0 -and $index -lt $count)

    $irDeviceUpButton.Enabled =
        ($hasSelection -and $index -gt 0)

    $irDeviceDownButton.Enabled =
        ($hasSelection -and $index -lt ($count - 1))

    $irDeviceRenameButton.Enabled = $hasSelection
    $irDeviceDeleteButton.Enabled = $hasSelection
    $irDeviceAddButton.Enabled = $true
}

function Move-SelectedIrDevice([int]$direction) {
    if ($null -eq $irDeviceList.SelectedItem) { return }
    if ($direction -ne -1 -and $direction -ne 1) { return }

    $selectedId = [string]$irDeviceList.SelectedItem.id
    $devices = @($script:irDevices)

    $index = -1
    for ($i = 0; $i -lt $devices.Count; $i++) {
        if ([string]$devices[$i].id -eq $selectedId) {
            $index = $i
            break
        }
    }

    if ($index -lt 0) { return }

    $targetIndex = $index + $direction
    if ($targetIndex -lt 0 -or $targetIndex -ge $devices.Count) {
        return
    }

    $temp = $devices[$index]
    $devices[$index] = $devices[$targetIndex]
    $devices[$targetIndex] = $temp

    $script:irDevices = @($devices)
    $config.irDeviceOrder =
        @($script:irDevices | ForEach-Object { [string]$_.id })

    Save-TowerConfig
    Save-CurrentIrDeviceCache
    Refresh-IrDeviceListFromMemory $selectedId
}

function Show-IrCommandLearnDialog(
    $device,
    $command = $null,
    [bool]$replaceExisting = $false,
    $owner = $form) {

    if ($null -eq $device) { return $null }

    $deviceId = [string]$device.id
    $deviceName = [string]$device.name

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = if ($replaceExisting) {
        'Re-record IR Command'
    }
    else {
        'Add IR Command'
    }
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle =
        [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.ClientSize =
        New-Object System.Drawing.Size(650, 665)
    $dialog.Font =
        New-Object System.Drawing.Font('Segoe UI', 10)

    $state = [pscustomobject]@{
        LastCapture = $null
        Saved = $false
    }

    $title = New-Object System.Windows.Forms.Label
    $title.Text = if ($replaceExisting) {
        'Re-record IR Command'
    }
    else {
        'Add IR Command'
    }
    $title.Font =
        New-Object System.Drawing.Font('Segoe UI Semibold', 15)
    $title.Location =
        New-Object System.Drawing.Point(28, 22)
    $title.Size =
        New-Object System.Drawing.Size(570, 34)
    $dialog.Controls.Add($title)

    $deviceLabel = New-Object System.Windows.Forms.Label
    $deviceLabel.Text = $deviceName
    $deviceLabel.Location =
        New-Object System.Drawing.Point(30, 60)
    $deviceLabel.Size =
        New-Object System.Drawing.Size(570, 24)
    $deviceLabel.ForeColor = [System.Drawing.Color]::DimGray
    $dialog.Controls.Add($deviceLabel)

    $commandLabel = New-Object System.Windows.Forms.Label
    $commandLabel.Text = 'Command name'
    $commandLabel.Location =
        New-Object System.Drawing.Point(30, 108)
    $commandLabel.Size =
        New-Object System.Drawing.Size(150, 24)
    $dialog.Controls.Add($commandLabel)

    $commandBox = New-Object System.Windows.Forms.TextBox
    $commandBox.Location =
        New-Object System.Drawing.Point(190, 105)
    $commandBox.Size =
        New-Object System.Drawing.Size(405, 28)
    $commandBox.MaxLength = 120
    $dialog.Controls.Add($commandBox)

    $descriptionLabel = New-Object System.Windows.Forms.Label
    $descriptionLabel.Text = 'Description'
    $descriptionLabel.Location =
        New-Object System.Drawing.Point(30, 150)
    $descriptionLabel.Size =
        New-Object System.Drawing.Size(150, 24)
    $dialog.Controls.Add($descriptionLabel)

    $descriptionBox = New-Object System.Windows.Forms.TextBox
    $descriptionBox.Location =
        New-Object System.Drawing.Point(190, 147)
    $descriptionBox.Size =
        New-Object System.Drawing.Size(405, 28)
    $descriptionBox.MaxLength = 240
    $dialog.Controls.Add($descriptionBox)

    if ($replaceExisting -and $null -ne $command) {
        $commandBox.Text = [string]$command.id
        $commandBox.ReadOnly = $true
        $descriptionBox.Text = [string]$command.description
    }

    $instruction = New-Object System.Windows.Forms.Label
    $instruction.Text =
        "Aim the remote at the receiver array. When you press READY, " +
        "Tower records all six receivers for 8 seconds. Press the same " +
        "remote button several times during that recording."
    $instruction.Location =
        New-Object System.Drawing.Point(30, 194)
    $instruction.Size =
        New-Object System.Drawing.Size(565, 58)
    $instruction.ForeColor = [System.Drawing.Color]::DimGray
    $dialog.Controls.Add($instruction)

    $resultGroup = New-Object System.Windows.Forms.GroupBox
    $resultGroup.Text = 'Capture result'
    $resultGroup.Location =
        New-Object System.Drawing.Point(30, 267)
    $resultGroup.Size =
        New-Object System.Drawing.Size(565, 286)
    $dialog.Controls.Add($resultGroup)

    $resultText = New-Object System.Windows.Forms.Label
    $resultText.Text = 'No capture yet.'
    $resultText.Location =
        New-Object System.Drawing.Point(16, 26)
    $resultText.Size =
        New-Object System.Drawing.Size(532, 92)
    $resultText.Font =
        New-Object System.Drawing.Font('Consolas', 9)
    $resultGroup.Controls.Add($resultText)

    $receiverList = New-Object System.Windows.Forms.ListView
    $receiverList.Location =
        New-Object System.Drawing.Point(16, 124)
    $receiverList.Size =
        New-Object System.Drawing.Size(532, 146)
    $receiverList.View =
        [System.Windows.Forms.View]::Details
    $receiverList.FullRowSelect = $true
    $receiverList.GridLines = $true
    $receiverList.HeaderStyle =
        [System.Windows.Forms.ColumnHeaderStyle]::Nonclickable
    $receiverList.Font =
        New-Object System.Drawing.Font('Consolas', 8.5)

    [void]$receiverList.Columns.Add('GPIO', 46)
    [void]$receiverList.Columns.Add('Receiver', 92)
    [void]$receiverList.Columns.Add('kHz', 44)
    [void]$receiverList.Columns.Add('Timings', 60)
    [void]$receiverList.Columns.Add('Pulses', 55)
    [void]$receiverList.Columns.Add('Frames', 54)
    [void]$receiverList.Columns.Add('Valid', 48)
    [void]$receiverList.Columns.Add('Result', 76)
    $resultGroup.Controls.Add($receiverList)

    $cancelButton = New-RfSmoothButton `
        'Cancel' `
        100 `
        38 `
        ([System.Drawing.Color]::White) `
        ([System.Drawing.Color]::FromArgb(35, 35, 35)) `
        ([System.Drawing.Color]::FromArgb(150, 145, 185))
    $cancelButton.Location =
        New-Object System.Drawing.Point(30, 580)
    $dialog.Controls.Add($cancelButton)

    $retryButton = New-RfSmoothButton `
        'Retry' `
        95 `
        38 `
        ([System.Drawing.Color]::White) `
        ([System.Drawing.Color]::FromArgb(35, 35, 35)) `
        ([System.Drawing.Color]::FromArgb(150, 145, 185))
    $retryButton.Location =
        New-Object System.Drawing.Point(345, 580)
    $retryButton.Visible = $false
    $dialog.Controls.Add($retryButton)

    $saveButton = New-RfSmoothButton `
        'Save Command' `
        125 `
        38 `
        ([System.Drawing.Color]::FromArgb(224, 244, 228)) `
        ([System.Drawing.Color]::FromArgb(30, 80, 40)) `
        ([System.Drawing.Color]::FromArgb(130, 175, 135))
    $saveButton.Location =
        New-Object System.Drawing.Point(470, 580)
    $saveButton.Visible = $false
    $dialog.Controls.Add($saveButton)

    $readyButton = New-RfSmoothButton `
        'READY - RECORD' `
        145 `
        38 `
        ([System.Drawing.Color]::FromArgb(224, 236, 250)) `
        ([System.Drawing.Color]::FromArgb(30, 70, 115)) `
        ([System.Drawing.Color]::FromArgb(115, 155, 195))
    $readyButton.Location =
        New-Object System.Drawing.Point(450, 580)
    $dialog.Controls.Add($readyButton)

    $cancelButton.Add_Click({
        $dialog.Close()
    })

    $retryButton.Add_Click({
        $state.LastCapture = $null
        $resultText.Text = 'No capture yet.'
        $receiverList.Items.Clear()
        $retryButton.Visible = $false
        $saveButton.Visible = $false
        $readyButton.Visible = $true

        if (-not $replaceExisting) {
            $commandBox.Focus()
        }
    })

    $readyButton.Add_Click({
        $commandName = $commandBox.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($commandName)) {
            [System.Windows.Forms.MessageBox]::Show(
                'Enter a command name first.',
                'Learn IR Command',
                'OK',
                'Warning'
            ) | Out-Null
            $commandBox.Focus()
            return
        }

        try {
            $readyButton.Enabled = $false
            $resultText.Text =
                "RECORDING NOW...`r`n`r`n" +
                "Press '$commandName' several times during the 8-second capture."
            $dialog.Refresh()

            $response = Invoke-TowerPost '/api/v1/ir/learn/capture' @{
                device = $deviceId
                command = $commandName
                description = $descriptionBox.Text.Trim()
                seconds = 8.0
                force = $replaceExisting
            }

            $state.LastCapture = $response
            $receiverList.BeginUpdate()
            $receiverList.Items.Clear()

            foreach ($receiver in @($response.receivers)) {
                $item = New-Object System.Windows.Forms.ListViewItem(
                    [string]$receiver.gpio
                )
                [void]$item.SubItems.Add([string]$receiver.receiver)
                [void]$item.SubItems.Add([string]$receiver.carrierKhz)
                [void]$item.SubItems.Add([string]$receiver.timings)
                [void]$item.SubItems.Add([string]$receiver.pulses)
                [void]$item.SubItems.Add([string]$receiver.frames)
                [void]$item.SubItems.Add([string]$receiver.valid)
                [void]$item.SubItems.Add([string]$receiver.result)
                [void]$receiverList.Items.Add($item)
            }
            $receiverList.EndUpdate()

            $protocol = [string]$response.protocol
            if ([string]::IsNullOrWhiteSpace($protocol)) {
                $protocol = 'RAW'
            }

            $addressText = if ($protocol -eq 'RAW') {
                '-'
            }
            else {
                ('0x{0:X}' -f [uint32]$response.address)
            }

            $commandCodeText = if ($protocol -eq 'RAW') {
                '-'
            }
            else {
                ('0x{0:X2}' -f [uint32]$response.decodedCommand)
            }

            $duplicateText = ''
            $duplicates = @($response.duplicates)
            if ($duplicates.Count -gt 0) {
                $duplicateText =
                    "`r`nDUPLICATE: " +
                    ($duplicates -join ', ')
            }

            $noteText = ''
            if (-not [string]::IsNullOrWhiteSpace([string]$response.note)) {
                $noteText = "`r`n" + [string]$response.note
            }

            $resultText.Text =
                "Protocol : $protocol`r`n" +
                "Address  : $addressText    Command: $commandCodeText`r`n" +
                "Carrier  : $([string]$response.carrierKhz) kHz`r`n" +
                "Receiver : GPIO$([string]$response.receiverGpio) " +
                "$([string]$response.receiverModel)`r`n" +
                "Frames   : $([string]$response.initialFrames) initial / " +
                "$([string]$response.repeatFrames) repeat" +
                $duplicateText +
                $noteText

            $readyButton.Visible = $false
            $retryButton.Visible = $true
            $saveButton.Visible = $true
        }
        catch {
            $state.LastCapture = $null
            $details = Get-TowerHttpErrorDetails `
                $_ `
                'POST' `
                '/api/v1/ir/learn/capture' `
                @{
                    device = $deviceId
                    command = $commandName
                    description = $descriptionBox.Text.Trim()
                    seconds = 8.0
                    force = $replaceExisting
                }

            $resultText.Text =
                "Recording was not saved.`r`n`r`n" +
                $details.Text
            $retryButton.Visible = $true
            $saveButton.Visible = $false
            $readyButton.Visible = $false
        }
        finally {
            $readyButton.Enabled = $true
        }
    })

    $saveButton.Add_Click({
        if ($null -eq $state.LastCapture) { return }

        $duplicates = @($state.LastCapture.duplicates)
        $acceptDuplicate = $false

        if ($duplicates.Count -gt 0) {
            $answer = [System.Windows.Forms.MessageBox]::Show(
                "This IR signal is already stored as:`r`n`r`n" +
                ($duplicates -join "`r`n") +
                "`r`n`r`nKeep this duplicate command anyway?",
                'Duplicate IR signal',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning,
                [System.Windows.Forms.MessageBoxDefaultButton]::Button2
            )

            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
                return
            }

            $acceptDuplicate = $true
        }

        try {
            $saveButton.Enabled = $false
            $commandName = $commandBox.Text.Trim()
            $description = $descriptionBox.Text.Trim()

            Invoke-TowerPost '/api/v1/ir/learn/save' @{
                captureId = [string]$state.LastCapture.captureId
                device = $deviceId
                command = $commandName
                description = $description
                force = $replaceExisting
                acceptDuplicate = $acceptDuplicate
            } | Out-Null

            $state.Saved = $true
            $dialog.Tag = [pscustomobject]@{
                id = $commandName
                name = $commandName
                description = $description
                transport = 'IR'
                enabled = $true
            }

            $statusText = if ($replaceExisting) {
                "Re-recorded IR command $commandName"
            }
            else {
                "Added IR command $commandName"
            }

            Set-TowerStatus $statusText

            $dialog.DialogResult =
                [System.Windows.Forms.DialogResult]::OK
            $dialog.Close()
        }
        catch {
            $details = Get-TowerHttpErrorDetails `
                $_ `
                'POST' `
                '/api/v1/ir/learn/save' `
                @{
                    captureId = [string]$state.LastCapture.captureId
                    device = $deviceId
                    command = $commandBox.Text.Trim()
                    description = $descriptionBox.Text.Trim()
                    force = $replaceExisting
                    acceptDuplicate = $acceptDuplicate
                }

            [System.Windows.Forms.MessageBox]::Show(
                $details.Text,
                'Save IR Command',
                'OK',
                'Error'
            ) | Out-Null
        }
        finally {
            $saveButton.Enabled = $true
        }
    })

    $dialog.Add_Shown({
        if ($replaceExisting) {
            $descriptionBox.Focus()
        }
        else {
            $commandBox.Focus()
        }
    })

    [void]$dialog.ShowDialog($owner)
    $savedCommand = $dialog.Tag
    $dialog.Dispose()

    if ([bool]$state.Saved) {
        return $savedCommand
    }

    return $null
}

function Show-EditIrDeviceDialog($device) {
    if ($null -eq $device) { return }

    $deviceId = [string]$device.id

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Edit IR Remote'
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle =
        [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.ClientSize =
        New-Object System.Drawing.Size(720, 555)
    $dialog.Font =
        New-Object System.Drawing.Font('Segoe UI', 10)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'Edit IR Remote'
    $title.Font =
        New-Object System.Drawing.Font('Segoe UI Semibold', 15)
    $title.Location =
        New-Object System.Drawing.Point(24, 20)
    $title.Size =
        New-Object System.Drawing.Size(650, 34)
    $dialog.Controls.Add($title)

    $nameLabel = New-Object System.Windows.Forms.Label
    $nameLabel.Text = 'Remote name'
    $nameLabel.Location =
        New-Object System.Drawing.Point(26, 70)
    $nameLabel.Size =
        New-Object System.Drawing.Size(115, 24)
    $dialog.Controls.Add($nameLabel)

    $nameBox = New-Object System.Windows.Forms.TextBox
    $nameBox.Text = [string]$device.name
    $nameBox.Location =
        New-Object System.Drawing.Point(146, 67)
    $nameBox.Size =
        New-Object System.Drawing.Size(420, 28)
    $nameBox.MaxLength = 120
    $dialog.Controls.Add($nameBox)

    $saveNameButton = New-RfSmoothButton `
        'Save Name' `
        105 `
        30 `
        ([System.Drawing.Color]::FromArgb(224, 236, 250)) `
        ([System.Drawing.Color]::FromArgb(30, 70, 115)) `
        ([System.Drawing.Color]::FromArgb(115, 155, 195))
    $saveNameButton.Location =
        New-Object System.Drawing.Point(580, 66)
    $dialog.Controls.Add($saveNameButton)

    $nameHint = New-Object System.Windows.Forms.Label
    $nameHint.Text =
        'The internal Tower device ID stays unchanged.'
    $nameHint.Location =
        New-Object System.Drawing.Point(147, 100)
    $nameHint.Size =
        New-Object System.Drawing.Size(420, 22)
    $nameHint.ForeColor = [System.Drawing.Color]::DimGray
    $dialog.Controls.Add($nameHint)

    $commandsLabel = New-Object System.Windows.Forms.Label
    $commandsLabel.Text = 'Commands'
    $commandsLabel.Font =
        New-Object System.Drawing.Font('Segoe UI Semibold', 11)
    $commandsLabel.Location =
        New-Object System.Drawing.Point(26, 137)
    $commandsLabel.Size =
        New-Object System.Drawing.Size(200, 26)
    $dialog.Controls.Add($commandsLabel)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location =
        New-Object System.Drawing.Point(26, 166)
    $grid.Size =
        New-Object System.Drawing.Size(660, 300)
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AllowUserToResizeRows = $false
    $grid.RowHeadersVisible = $false
    $grid.MultiSelect = $false
    $grid.SelectionMode =
        [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $grid.AutoGenerateColumns = $false
    $grid.ReadOnly = $true
    $grid.BackgroundColor = [System.Drawing.Color]::White
    $grid.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $grid.AutoSizeRowsMode =
        [System.Windows.Forms.DataGridViewAutoSizeRowsMode]::AllCells
    $grid.DefaultCellStyle.WrapMode =
        [System.Windows.Forms.DataGridViewTriState]::False

    $commandColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $commandColumn.Name = 'Command'
    $commandColumn.HeaderText = 'Command'
    $commandColumn.Width = 180
    [void]$grid.Columns.Add($commandColumn)

    $descriptionColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $descriptionColumn.Name = 'Description'
    $descriptionColumn.HeaderText = 'Description'
    $descriptionColumn.Width = 260
    [void]$grid.Columns.Add($descriptionColumn)

    $rerecordColumn = New-Object System.Windows.Forms.DataGridViewButtonColumn
    $rerecordColumn.Name = 'Rerecord'
    $rerecordColumn.HeaderText = ''
    $rerecordColumn.Text = 'Re-record'
    $rerecordColumn.UseColumnTextForButtonValue = $true
    $rerecordColumn.Width = 88
    [void]$grid.Columns.Add($rerecordColumn)

    $removeColumn = New-Object System.Windows.Forms.DataGridViewButtonColumn
    $removeColumn.Name = 'Remove'
    $removeColumn.HeaderText = ''
    $removeColumn.Text = 'Remove'
    $removeColumn.UseColumnTextForButtonValue = $true
    $removeColumn.Width = 76
    [void]$grid.Columns.Add($removeColumn)

    $dialog.Controls.Add($grid)

    $commandMap = @{}

    $refreshGrid = {
        param([string]$selectCommandId = '')

        $grid.Rows.Clear()
        $commandMap.Clear()
        $rowToSelect = -1

        foreach ($item in @($device.commands | Where-Object {
            $_.transport -eq 'IR'
        })) {
            $row = $grid.Rows.Add(
                [string]$item.id,
                [string]$item.description,
                'Re-record',
                'Remove'
            )
            $commandMap[[int]$row] = $item

            if (-not [string]::IsNullOrWhiteSpace($selectCommandId) -and
                [string]$item.id -eq $selectCommandId) {
                $rowToSelect = [int]$row
            }
        }

        if ($rowToSelect -ge 0 -and $rowToSelect -lt $grid.Rows.Count) {
            $grid.ClearSelection()
            $grid.Rows[$rowToSelect].Selected = $true
            $grid.CurrentCell = $grid.Rows[$rowToSelect].Cells[0]
            try {
                $grid.FirstDisplayedScrollingRowIndex = $rowToSelect
            }
            catch {}
        }
    }

    & $refreshGrid

    $addButton = New-RfSmoothButton `
        '+ Add Command' `
        135 `
        38 `
        ([System.Drawing.Color]::FromArgb(224, 244, 228)) `
        ([System.Drawing.Color]::FromArgb(30, 80, 40)) `
        ([System.Drawing.Color]::FromArgb(130, 175, 135))
    $addButton.Location =
        New-Object System.Drawing.Point(26, 484)
    $dialog.Controls.Add($addButton)

    $closeButton = New-RfSmoothButton `
        'Close' `
        100 `
        38 `
        ([System.Drawing.Color]::White) `
        ([System.Drawing.Color]::FromArgb(35, 35, 35)) `
        ([System.Drawing.Color]::FromArgb(150, 145, 185))
    $closeButton.Location =
        New-Object System.Drawing.Point(586, 484)
    $dialog.Controls.Add($closeButton)

    $saveNameButton.Add_Click({
        $newName = $nameBox.Text.Trim()
        $oldName = [string]$device.name

        if ([string]::IsNullOrWhiteSpace($newName)) {
            [System.Windows.Forms.MessageBox]::Show(
                'Enter a name for the IR remote.',
                'Edit IR Remote',
                'OK',
                'Information'
            ) | Out-Null
            $nameBox.Focus()
            return
        }

        if ($newName -eq $oldName) {
            Set-TowerStatus 'IR remote name is unchanged'
            return
        }

        try {
            $saveNameButton.Enabled = $false
            $response = Invoke-TowerPost '/api/v1/devices/rename' @{
                device = $deviceId
                name = $newName
            }

            $device.name = [string]$response.name

            foreach ($candidate in @($script:irDevices)) {
                if ([string]$candidate.id -eq $deviceId) {
                    $candidate.name = [string]$response.name
                }
            }

            Save-CurrentIrDeviceCache
            $script:irInventorySignature =
                Get-IrInventorySignature $script:irDevices
            Refresh-IrDeviceListFromMemory $deviceId
            Refresh-HomeDevices
            Set-TowerStatus ([string]$response.message)
        }
        catch {
            $details = Get-TowerHttpErrorDetails `
                $_ `
                'POST' `
                '/api/v1/devices/rename' `
                @{
                    device = $deviceId
                    name = $newName
                }

            [System.Windows.Forms.MessageBox]::Show(
                $details.Text,
                'Rename IR remote failed',
                'OK',
                'Error'
            ) | Out-Null
        }
        finally {
            $saveNameButton.Enabled = $true
        }
    })

    $addButton.Add_Click({
        $created = Show-IrCommandLearnDialog `
            $device `
            $null `
            $false `
            $dialog

        if ($null -eq $created) { return }

        $device.commands = @($device.commands) + @($created)
        & $refreshGrid ([string]$created.id)
        Refresh-IrInventoryAfterWizard
    })

    $grid.Add_CellContentClick({
        param($sender, $eventArgs)

        if ($eventArgs.RowIndex -lt 0 -or
            $eventArgs.ColumnIndex -lt 0) {
            return
        }

        $selectedCommand = $commandMap[[int]$eventArgs.RowIndex]
        if ($null -eq $selectedCommand) { return }

        $columnName =
            [string]$grid.Columns[$eventArgs.ColumnIndex].Name

        if ($columnName -eq 'Rerecord') {
            $updated = Show-IrCommandLearnDialog `
                $device `
                $selectedCommand `
                $true `
                $dialog

            if ($null -eq $updated) { return }

            foreach ($candidate in @($device.commands)) {
                if ([string]$candidate.id -eq [string]$updated.id) {
                    $candidate.name = [string]$updated.name
                    $candidate.description = [string]$updated.description
                    $candidate.enabled = $true
                    break
                }
            }

            & $refreshGrid ([string]$updated.id)
            Refresh-IrInventoryAfterWizard
            return
        }

        if ($columnName -eq 'Remove') {
            $irCommands = @($device.commands | Where-Object {
                $_.transport -eq 'IR'
            })

            if ($irCommands.Count -le 1) {
                [System.Windows.Forms.MessageBox]::Show(
                    'The last command cannot be removed. Delete the remote instead.',
                    'Remove IR Command',
                    'OK',
                    'Information'
                ) | Out-Null
                return
            }

            $commandId = [string]$selectedCommand.id
            $answer = [System.Windows.Forms.MessageBox]::Show(
                "Remove '$commandId' from this remote?`r`n`r`n" +
                'Its dedicated IR recording will also be removed when it is not shared.',
                'Remove IR Command',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning,
                [System.Windows.Forms.MessageBoxDefaultButton]::Button2
            )

            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
                return
            }

            try {
                Invoke-TowerPost '/api/v1/ir/commands/delete' @{
                    device = $deviceId
                    command = $commandId
                } | Out-Null

                $device.commands = @($device.commands | Where-Object {
                    [string]$_.id -ne $commandId
                })

                & $refreshGrid
                Refresh-IrInventoryAfterWizard
                Set-TowerStatus "Removed IR command $commandId"
            }
            catch {
                $details = Get-TowerHttpErrorDetails `
                    $_ `
                    'POST' `
                    '/api/v1/ir/commands/delete' `
                    @{
                        device = $deviceId
                        command = $commandId
                    }

                [System.Windows.Forms.MessageBox]::Show(
                    $details.Text,
                    'Remove IR Command failed',
                    'OK',
                    'Error'
                ) | Out-Null
            }
        }
    })

    $closeButton.Add_Click({
        $dialog.Close()
    })

    $dialog.Add_FormClosed({
        $script:renderedIrDeviceId = ''
        $script:renderedIrDeviceSignature = ''
        Refresh-IrInventoryAfterWizard
    })

    [void]$dialog.ShowDialog($form)
    $dialog.Dispose()
}

function Edit-SelectedIrDevice {
    if ($null -eq $irDeviceList.SelectedItem) {
        return
    }

    Show-EditIrDeviceDialog $irDeviceList.SelectedItem
}

function Delete-SelectedIrDevice {
    if ($null -eq $irDeviceList.SelectedItem) { return }

    $device = $irDeviceList.SelectedItem
    $deviceId = [string]$device.id
    $deviceName = [string]$device.name

    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Are you sure you want to permanently delete '$deviceName'?`n`n" +
        "The Tower device profile will be deleted from PI3A. Its dedicated " +
        "IR recordings are also removed when they are not shared by another device.`n`n" +
        "This cannot be undone from Tower Control.",
        'Delete IR device?',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2
    )

    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    try {
        Set-TowerStatus "Deleting $deviceName..."
        $response = Invoke-TowerPost '/api/v1/devices/delete' @{
            device = $deviceId
        }

        $config.irDeviceOrder = @(
            @($config.irDeviceOrder) |
                Where-Object { [string]$_ -ne $deviceId }
        )
        if ([int]$config.irDisplayCount -gt 0) {
            $config.irDisplayCount = [int]$config.irDisplayCount - 1
        }
        Save-TowerConfig

        Remove-CustomRemoteImage $device

        $script:irDevices = @(
            $script:irDevices |
                Where-Object {
                    [string]$_.id -ne $deviceId
                }
        )

        $script:renderedIrDeviceId = ''
        $script:renderedIrDeviceSignature = ''

        Save-CurrentIrDeviceCache
        Refresh-IrDeviceListFromMemory

        if ($irDeviceList.Items.Count -eq 0) {
            Show-IrDevice $null
        }
        elseif ($tabs.SelectedTab -eq $irTab) {
            Ensure-IrDeviceRendered $irDeviceList.SelectedItem
        }

        Set-TowerStatus ([string]$response.message)

        # Verify against the authoritative Pi inventory without blocking UI.
        if ($null -eq $script:irReadJob) {
            Start-IrDeviceRead
        }
    }
    catch {
        $details = Get-TowerHttpErrorDetails $_ 'POST' '/api/v1/devices/delete' @{
            device = $deviceId
        }
        [System.Windows.Forms.MessageBox]::Show(
            $details.Text,
            'Tower device deletion failed',
            'OK',
            'Error'
        ) | Out-Null
    }
}

function Refresh-CurrentTab {
    if ($tabs.SelectedTab -eq $sensorsTab) {
        Start-SensorRead
        return
    }

    if ($tabs.SelectedTab -eq $homeTab -or
        $tabs.SelectedTab -eq $irTab) {
        Start-IrDeviceRead
        return
    }

    if ($tabs.SelectedTab -eq $rfTab) {
        Start-RfDeviceRead
        return
    }

    Set-TowerStatus (
        "Connected to $($config.server) - " +
        "$($config.rfDisplayCount) RF devices, " +
        "$($config.irDisplayCount) IR devices"
    )
}

function Load-SelectedTabIfNeeded {
    if ($tabs.SelectedTab -eq $sensorsTab) {
        if (-not $script:sensorsHaveLoaded) {
            Start-SensorRead
        }
        return
    }

    if ($tabs.SelectedTab -eq $homeTab -or
        $tabs.SelectedTab -eq $irTab) {

        if (-not $script:irDevicesHaveLoaded) {
            [void](Try-LoadIrDeviceCache)

            # No cache exists: this is a genuine first load, so fetch once.
            if (-not $script:irDevicesHaveLoaded -and
                $null -eq $script:irReadJob) {
                Start-IrDeviceRead
            }
        }

        if ($tabs.SelectedTab -eq $irTab -and
            $script:irDevicesHaveLoaded -and
            $null -ne $irDeviceList.SelectedItem) {
            Ensure-IrDeviceRendered `
                $irDeviceList.SelectedItem
        }

        # Do NOT refresh merely because Home/IR was selected. The cached
        # controls remain persistent; startup/manual refresh owns syncing.
        return
    }

    if ($tabs.SelectedTab -eq $rfTab) {
        if (-not $script:rfDevicesHaveLoaded) {
            [void](Try-LoadRfDeviceCache)

            # No cache exists: fetch once. Otherwise keep the already-rendered
            # RF cards/presets untouched while switching tabs/sidebar states.
            if (-not $script:rfDevicesHaveLoaded -and
                $null -eq $script:rfReadJob) {
                Start-RfDeviceRead
            }
        }

        return
    }
}

$sensorCardsViewButton.Add_Click({
    Set-SensorViewMode 'cards'
})
$sensorListViewButton.Add_Click({
    Set-SensorViewMode 'list'
})
$sensorDetailsViewButton.Add_Click({
    Set-SensorViewMode 'details'
})
$sensorListView.Add_Resize({
    Resize-SensorListColumns
})
Refresh-SensorViewButtons

$allOnButton.Add_Click({ Send-AllRfAction 'on' })
$rfAddButton.Add_Click({ Show-AddRfDeviceWizard })
$rfCardsViewButton.Add_Click({ Set-RfDeviceViewMode 'cards' })
$rfListViewButton.Add_Click({ Set-RfDeviceViewMode 'list' })
$rfPanel.Add_Resize({ Resize-RfDeviceCards })
Refresh-RfViewButtons
$allOffButton.Add_Click({ Send-AllRfAction 'off' })
$refreshButton.Add_Click({
    Refresh-CurrentTab

    try {
        $tabs.Focus()
    }
    catch {}
})
$irDeviceList.Add_SelectedIndexChanged({
    Update-IrDeviceManagementButtons

    if (-not $script:suppressIrSelectionChanged -and
        $tabs.SelectedTab -eq $irTab) {
        Ensure-IrDeviceRendered $irDeviceList.SelectedItem
    }
})
$tabs.Add_SelectedIndexChanged({ Load-SelectedTabIfNeeded })
$irDeviceUpButton.Add_Click({ Move-SelectedIrDevice -1 })
$irDeviceDownButton.Add_Click({ Move-SelectedIrDevice 1 })
$irDeviceRenameButton.Add_Click({ Edit-SelectedIrDevice })
$irDeviceDeleteButton.Add_Click({ Delete-SelectedIrDevice })
$irDeviceAddButton.Add_Click({ Show-AddIrDeviceWizard })
$remotePreviewAddImageButton.Add_Click({ Select-CustomRemoteImage })
$remotePreviewPicture.Add_Click({
    if ($null -ne $script:currentIrDevice) {
        Select-CustomRemoteImage
    }
})
Update-IrDeviceManagementButtons

[void]$tabs.TabPages.Add($settingsTab)

$sensorTimer = New-Object System.Windows.Forms.Timer
$sensorTimer.Interval = 10000
$sensorTimer.Add_Tick({
    if ($tabs.SelectedTab -eq $sensorsTab) {
        Start-SensorRead
    }
})

# Poll only the state of isolated PowerShell jobs. No network I/O or Wait-Job
# occurs on this timer, so it cannot block tray menus or sidebar animation.
$readJobTimer = New-Object System.Windows.Forms.Timer
$readJobTimer.Interval = 250
$readJobTimer.Add_Tick({
    Complete-SensorRead
    Complete-IrDeviceRead
    Complete-RfDeviceRead
})

# Start the first sensor read shortly after Form.Shown has returned. This only
# launches the background job; the HTTP request itself remains outside the UI
# thread.
$initialSensorTimer = New-Object System.Windows.Forms.Timer
$initialSensorTimer.Interval = 500
$initialSensorTimer.Add_Tick({
    $initialSensorTimer.Stop()
    Start-SensorRead
})


# Home is the startup page. Load its cached IR inventory immediately and then
# refresh the authoritative Pi inventory in a background job.
$initialIrTimer = New-Object System.Windows.Forms.Timer
$initialIrTimer.Interval = 1200
$initialIrTimer.Add_Tick({
    $initialIrTimer.Stop()

    if ($null -eq $script:irReadJob) {
        $quiet =
            [bool]$script:irDevicesHaveLoaded

        Start-IrDeviceRead $quiet
    }
})

# One quiet retry for a transient startup IR inventory failure.
$irStartupRetryTimer =
    New-Object System.Windows.Forms.Timer
$irStartupRetryTimer.Interval = 3000
$irStartupRetryTimer.Add_Tick({
    $irStartupRetryTimer.Stop()

    if ($null -eq $script:irReadJob) {
        Start-IrDeviceRead $true
    }
})


# Pre-warm the tiny RF inventory after startup. If a cache exists, the RF tab
# is already instant; if it doesn't, this makes the first-ever RF visit much
# more likely to be ready before the user opens it.
$initialRfTimer = New-Object System.Windows.Forms.Timer
$initialRfTimer.Interval = 2500
$initialRfTimer.Add_Tick({
    $initialRfTimer.Stop()

    if (-not $script:rfDevicesHaveLoaded) {
        [void](Try-LoadRfDeviceCache)
    }

    if ($null -eq $script:rfReadJob) {
        Start-RfDeviceRead $true
    }
})

# One quiet retry handles transient startup races without painting the global
# status red. A later user-requested Refresh still reports a real failure.
$rfStartupRetryTimer = New-Object System.Windows.Forms.Timer
$rfStartupRetryTimer.Interval = 3000
$rfStartupRetryTimer.Add_Tick({
    $rfStartupRetryTimer.Stop()

    if ($null -eq $script:rfReadJob) {
        Start-RfDeviceRead $true
    }
})

# Header clock is synchronized from PI3A. Between syncs the display advances
# from the Pi-provided time anchor; Windows' timezone is never used.
$piClockTimer = New-Object System.Windows.Forms.Timer
$piClockTimer.Interval = 250
$piClockTimer.Add_Tick({
    Complete-PiClockSync

    if ($script:piClockHasSync) {
        $syncAge =
            ([datetime]::Now -
             $script:piClockSyncLocal).TotalSeconds

        if ($syncAge -ge 30 -and
            $null -eq $script:piClockSyncJob) {
            Start-PiClockSync
        }
    }
    elseif ($null -eq $script:piClockSyncJob) {
        Start-PiClockSync
    }

    $piClockBox.Text =
        Get-PiClockDisplayText

    if ($script:piClockHasSync) {
        $zone =
            [string]$script:piClockTimezone

        if ([string]::IsNullOrWhiteSpace($zone)) {
            $zone = 'Pi system time'
        }

        $piClockToolTip.SetToolTip(
            $piClockBox,
            "Raspberry Pi system clock ($zone)"
        )
    }
})

# Edge watcher remains active while the sidebar itself is completely invisible.
$edgeTimer = New-Object System.Windows.Forms.Timer
$edgeTimer.Interval = 100
$edgeTimer.Add_Tick({
    if (Handle-DisplayTopologyChange) { return }
    if ($script:sidebarAnimating) { return }

    if ([DateTime]::Now -lt $script:displayTopologyQuietUntil) {
        return
    }

    $screen = Get-TargetScreen
    if ($null -eq $screen) {
        Hide-SidebarImmediately
        return
    }

    $bounds = $screen.Bounds
    $cursor = [System.Windows.Forms.Cursor]::Position

    # Trigger only on the selected monitor's physical right edge.
    $atRightEdge =
        $cursor.X -ge ($bounds.Right - 2) -and
        $cursor.X -le ($bounds.Right + 1) -and
        $cursor.Y -ge $bounds.Top -and
        $cursor.Y -lt $bounds.Bottom

    if (-not $script:sidebarVisible) {
        if ($atRightEdge) {
            Animate-Sidebar $true
        }
        return
    }

    $inside =
        $cursor.X -ge $form.Left -and
        $cursor.X -lt $form.Right -and
        $cursor.Y -ge $form.Top -and
        $cursor.Y -lt $form.Bottom

    if ($inside) {
        $script:lastInsideAt = [DateTime]::Now
        return
    }

    $elapsed = ([DateTime]::Now - $script:lastInsideAt).TotalMilliseconds
    if ($elapsed -ge [int]$config.hideDelayMs) {
        Animate-Sidebar $false
    }
})

$form.KeyPreview = $true
$form.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape -and $script:sidebarVisible) {
        Animate-Sidebar $false
        $_.Handled = $true
        return
    }

    if ($_.Control -and $_.Shift -and $_.KeyCode -eq [System.Windows.Forms.Keys]::Q) {
        $form.Close()
        $_.Handled = $true
    }
})

$form.Add_Shown({
    Enable-TowerUiSchedulingBoost
    Update-IrRemotePaneLayout
    Write-TowerLog 'INFO' "Tower Control started; server=$($config.server); sidebar=right-edge; topmost=true; HTTP keep-alive disabled"
    # Resolve/migrate the selected monitor before building the settings UI.
    [void](Get-TargetScreen)
    Refresh-MonitorButtons
    Update-TrayIcon
    [void](Update-SidebarBounds)
    $script:lastDisplayTopologySignature =
        Get-DisplayTopologySignature
    Position-MainLayout

    if ($null -ne $script:hiddenBounds) {
        $form.Bounds = $script:hiddenBounds
    }
    $form.Opacity = 0
    $form.TopMost = $true

    # Important: no HTTP/API call is allowed during Form.Shown. Returning from
    # this handler immediately gives Windows a live message loop for the tray
    # icon and right-edge sidebar.
    # Home must not appear empty while waiting for its first API round-trip.
    # Reading the local cache is synchronous disk I/O only; no network request
    # occurs here.
    if (-not $script:irDevicesHaveLoaded) {
        [void](Try-LoadIrDeviceCache)
    }

    if ($script:irDevicesHaveLoaded) {
        Refresh-HomeDevices
    }

    # Build the cached RF page now, while the form is still fully hidden.
    # Previously this waited for the 2.5-second RF prewarm timer, so opening
    # RF Power early could expose the controls being created top-to-bottom.
    if (-not $script:rfDevicesHaveLoaded) {
        [void](Try-LoadRfDeviceCache)
    }

    $sensorTimer.Start()
    $readJobTimer.Start()
    $edgeTimer.Start()
    $initialSensorTimer.Start()
    $initialIrTimer.Start()
    $initialRfTimer.Start()
    Start-PiClockSync
    $piClockTimer.Start()
})
$form.Add_FormClosed({
    try { Clear-SidebarMonitorClip } catch {}

    if ($null -ne $script:sidebarAnimationTimer) {
        $script:sidebarAnimationTimer.Stop()
        $script:sidebarAnimationTimer.Dispose()
        $script:sidebarAnimationTimer = $null
    }
    $script:sidebarAnimationClock.Stop()
    Disable-TowerUiSchedulingBoost

    $sensorTimer.Stop()
    $initialSensorTimer.Stop()
    $initialIrTimer.Stop()
    $irStartupRetryTimer.Stop()
    $initialRfTimer.Stop()
    $rfStartupRetryTimer.Stop()
    $piClockTimer.Stop()
    $readJobTimer.Stop()
    $edgeTimer.Stop()

    foreach ($job in @(
        $script:sensorReadJob,
        $script:irReadJob,
        $script:rfReadJob,
        $script:piClockSyncJob
    )) {
        if ($null -eq $job) { continue }
        try { Stop-Job -Job $job -ErrorAction SilentlyContinue } catch {}
        Remove-TowerReadJob $job
    }
    if ($null -ne $script:trayIcon) {
        $script:trayIcon.Visible = $false
        $script:trayIcon.Dispose()
        $script:trayIcon = $null
    }
    if ($null -ne $towerIconPicture.Image) {
        $towerIconPicture.Image.Dispose()
        $towerIconPicture.Image = $null
    }
    if ($null -ne $script:towerIconBitmap) {
        $script:towerIconBitmap.Dispose()
        $script:towerIconBitmap = $null
    }
})

[void]$form.ShowDialog()
