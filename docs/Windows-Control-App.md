# Tower Windows Control Application

> Status: Phase 1 complete, Phase 2 started
> Last updated: 2026-08-30

This document is the dedicated design, backlog, and implementation log for the
Tower Windows desktop application.

The application is becoming Tower's primary desktop control surface. Tower on
the Raspberry Pi remains authoritative for Tower devices, command execution,
automation schedules, and Tower configuration. The `PC` tab is a deliberate
local exception: it reads workstation thermal telemetry directly through Dell
Command | Monitor on the Windows machine running Tower Control.

## Voice tab

The `Voice` tab is implemented in the separate
`windows/Tower-Voice-Tab.ps1` module and is loaded by `Tower-Control.ps1`.
Keeping it separate prevents the already-large main WinForms script from
absorbing the recursive editor implementation.

The tab edits the Pi-owned voice command tree from the wake phrase downward.
Selecting a level shows its phrase, comma-separated recognition aliases and
one of four types: another branch, RF preset, individual RF device, or IR
command. Target selectors are populated from the live Tower catalog. Selecting
an IR device filters the command selector to that device's enabled IR commands.
For IR leaves, outputs 001-006 are selected explicitly. A new or older action
without an output override initially inherits the current IR Remotes-tab output
selection; saving stores those outputs with the voice action on the Pi.

`Apply level` updates the in-memory tree. `Save to Tower` validates and stores
the complete tree through `/api/v1/voice/config`; the listener reloads it while
running. `Test action` executes a selected leaf directly for troubleshooting.
The Windows application is not required after the configuration has been
saved.

A leaf has an ordered `Command actions` list. `Add action`, `Update action`,
and `Remove action` build a reusable command set from any mixture of RF
presets, RF devices, and filtered IR remote commands. `Test action` executes
the full list in order. Each action has a 0-300 second `Delay before` value;
zero executes immediately and a non-zero value pauses before that action. The
same stored action arrays can later be selected by
the scheduler/control tab rather than maintaining a second command format.

# Product goals

The desktop application should provide a fast visual control interface that can
stay available without occupying normal desktop space.

Primary goals:

- Reliable command execution without manual Tower service restarts.
- Right-edge auto-hiding sidebar.
- Multi-monitor support.
- Original-remote artwork.
- Categorized and spatially intuitive controls.
- Clear pressed/held feedback.
- Per-device multi-transmitter IR routing.
- Custom repeat/macro actions.
- Visual RF icons.
- Tower-side program/schedule editing.
- Future voice-action mapping.
- Safe device/profile deletion.
- Configurable appearance and sidebar behaviour.

# Phase 1 - Stability and sidebar shell

## 1. HTTP 400 / service restart defect

Status: TODO

Problem:

The existing Windows client periodically encounters an HTTP 400 failure. The
current workaround is to restart services, after which commands work again.

Required investigation:

- Capture the exact failing HTTP request and response body.
- Identify whether the 400 originates in the Windows request, API parser,
  service state, or stale connection/session state.
- Add useful client and server diagnostics.
- Add a lightweight health/status check.
- Automatically recover from genuinely transient connection failures where safe.
- Do not hide malformed requests behind endless retries.

Acceptance criterion:

Normal operation must not require manually restarting Tower services.

## 2. Right-edge sidebar

Status: TODO

Required:

- Window remains hidden at the right edge of the selected monitor.
- Pointer hitting the right edge reveals the panel.
- Default open width is approximately one third of that monitor.
- Panel automatically hides after the configured delay when no longer in use.
- Optional pin/open mode can be added.
- Animation must feel immediate enough for frequent remote-control use.

## 3. Multi-monitor support

Status: TODO

Required:

- Enumerate Windows displays.
- Allow explicit target-monitor selection.
- Remember the setting.
- Correctly handle monitors with different resolutions/scaling.
- Re-evaluate placement if a monitor is disconnected.

## 4. Client settings

Status: TODO

Planned settings:

- Target monitor.
- Sidebar width.
- Auto-hide delay.
- Animation duration.
- Background/accent appearance.
- Future remote-image scaling/layout options.

# Phase 2 - Remote-control interface

## 5. Original remote artwork

Status: IN PROGRESS

Current implementation:

- Added a dedicated original-remote preview panel on the left side of the IR tab.
- Added automatic filename-based matching for the supplied remote photo set.
- The sidebar now looks for matching images under `windows/assets/remotes/`.
- A README placeholder is included so the image folder structure is tracked in the project.

Layout target:

```text
+-------------------------------------------------------------+
| Original remote image          | Tower controls             |
|                                |                            |
|                                | categories / buttons       |
|                                |                            |
|                                | TX selectors               |
|                                | custom actions             |
+-------------------------------------------------------------+
```

Remote images may be cleaned and converted to transparent-background assets.
The user has supplied a remote-image archive for this purpose.

## 6. Categorized command controls

Status: IN PROGRESS

Current implementation:

- IR commands are now grouped into functional categories such as Power, Navigation, Audio, Media, Numbers / Channels, Sources / Display, and Modes / Colors.
- Buttons are rendered in grouped blocks to make each remote easier to understand at a glance.

Controls should be grouped by function and placed in intuitive relationships.

Examples:

```text
Volume Up
Volume Down

Channel Up
Channel Down
```

Candidate categories:

- Power.
- Navigation.
- Volume/audio.
- Playback.
- Channels/numeric.
- Inputs.
- Sound modes.
- Lighting/color.
- Device-specific functions.

The exact category set may vary per device.

## 7. Pressed and held feedback

Status: PARTIAL

Current implementation:

- IR command buttons now show a pressed state while the mouse button is held down.
- True repeat/hold behaviour for safe commands remains a later step.

Buttons need a visible active state while pressed/held so the user can see that
a continuous action is in progress.

Hold/repeat is particularly useful for commands such as:

- Denon Volume Up.
- Denon Volume Down.
- Channel Up/Down.
- Navigation where appropriate.
- Brightness where appropriate.

The UI must not assume every command is safe to repeat.

## 8. IR transmitter selection

Status: IN PROGRESS

Current implementation:

- The Windows client now shows TX-001 through TX-006 as independent toggle buttons.
- The selected transmitter set is stored in the client config and sent to Tower with each IR execute request.
- Tower API support has been extended so one IR command can be targeted to one or more selected transmitters from the Windows app.

Every IR remote/device screen must show all six transmitter selectors:

```text
TX-001  TX-002  TX-003  TX-004  TX-005  TX-006
```

Selectors are independent toggle buttons.

Example:

```text
TX-001 = selected
TX-002 = selected
TX-003 = selected
TX-004 = unselected
TX-005 = unselected
TX-006 = unselected
```

Requirements:

- One or more transmitters may be active.
- Active transmitters must have a clear visual state.
- All six remain visible even when some are currently unverified.
- The selected set should be associated with the selected remote/device.
- Tower's API must ultimately accept and validate the transmitter set.
- The client should not implement six separate protocol-specific sends itself.

Current hardware note:

TX-001 is presently the only trusted transmitter while the multi-output power
distribution is being investigated. The UI is nevertheless designed for all
six from the start.

## 9. Custom actions

Status: TODO

Custom actions appear below the standard remote buttons.

Initial example:

```text
Name    : Volume +10
Device  : AVR X2800H
Command : Volume Up
Count   : 10
```

Planned fields:

- Friendly name.
- Device.
- Command.
- Count.
- Transmitter set.
- Optional delay between repeats.

Later, custom actions can evolve into general Tower action sequences/scenes.

## 10. Device/profile deletion

Status: TODO

Provide a Delete Remote/Profile control at the bottom of the appropriate
management page.

Requirements:

- User selects the device/profile.
- Explicit confirmation is required.
- Windows sends a delete request to Tower.
- Tower removes the authoritative device/command data.
- Dependencies such as programs must be checked.
- Client refreshes after deletion.

# Phase 3 - Programs, automation, and polish

## 11. Programs tab

Status: TODO

Programs are configured in Windows but stored and executed on the Raspberry Pi.

The Windows PC must not be required for execution.

Initial program features:

- Friendly program name.
- Enabled/disabled state.
- Time/date trigger.
- Recurrence.
- One or more logical device commands.
- Repeat count.
- Delay between actions.
- Edit/delete.
- Manual Run Now.
- Execution status/history later.

Example:

```text
Program: Evening shutdown
Time   : 23:30 every day

1. LED Light Bar -> Power Off
2. AVR X2800H    -> Power
3. KPN Media Box -> Power
```

Backend target:

```text
Windows UI
    -> Tower API
    -> Automation database
    -> Scheduler / AutomationEngine
    -> shared CommandExecutor
```

## 12. Voice mapping preparation

Status: TODO

A later voice-processing Raspberry Pi will perform speech recognition / intent
detection and invoke Tower remotely.

Programs/actions should therefore use logical identifiers that can also be
mapped to phrases such as:

```text
"volume up ten"
"movie mode"
"turn the outside light off"
```

The voice Pi should use the same API as the Windows client.

## 13. RF icons

Status: TODO

RF controls should include small visual icons/thumbnails beside names where
useful. The goal is quick visual recognition rather than decorative artwork.

Icon sources/layout must be kept replaceable so assets can be improved later.

## 14. Appearance configuration

Status: TODO

Planned setup options:

- Sidebar/background color.
- Accent color.
- Panel width.
- Hide delay.
- Animation behaviour.
- Target monitor.
- Remote-artwork scale.
- Possibly per-device layout choices.

# Implementation log

## 2026-08-13 - Windows application v2 defined

- Agreed to rebuild the Windows client in three phases.
- Phase 1 will address the HTTP 400/service-restart defect first.
- Right-edge auto-hide sidebar and multi-monitor support are Phase 1.
- Remote artwork, categorized controls, hold feedback, transmitter selection,
  custom actions, and profile deletion are Phase 2.
- Programs/schedules, RF icons, appearance polish, and voice mapping preparation
  are Phase 3.
- IR transmitter selection must expose TX-001 through TX-006 as multi-select
  controls.
- Tower remains responsible for persistent programs and their execution.
- Voice recognition will run on a separate processing node and use Tower's
  shared logical command API.

# Development rule

Every meaningful Windows-client implementation change should update this file:

- mark completed backlog items,
- record new architectural decisions,
- record significant bugs/fixes,
- note required Tower API changes,
- and preserve unfinished follow-up work.


## 2026-08-13 - Phase 1 sidebar shell v1

Implemented initial desktop shell behaviour:

- Borderless right-edge sidebar.
- Window is always-on-top while visible.
- Hidden state is fully transparent and positioned completely beyond the
  selected monitor's right edge; no visible handle/tab remains.
- Pointer touching the selected monitor's right edge reveals the sidebar.
- Sidebar opens to 33% of the selected monitor by default.
- Auto-hide is currently 1200 ms after the pointer leaves the panel.
- Multi-monitor enumeration and a monitor selector were added to the header.
- Selected monitor is persisted in the existing Windows client config.
- Existing IR, RF, sensor, HTTP diagnostics, and fresh-connection behaviour are
  retained.
- Escape immediately hides the sidebar.
- Temporary maintenance shortcut Ctrl+Shift+Q closes the borderless application.

Still TODO before Phase 1 is complete:

- Proper Settings page for monitor/sidebar width/hide delay/appearance.
- Validate mixed-DPI and monitor hot-plug behaviour.
- Refine animation and edge trigger after real desktop testing.
- Redesign current fixed-width controls for the narrower sidebar.


## 2026-08-13 - Phase 1 Settings tab v1

Implemented a dedicated Settings tab and removed monitor selection from the
main header.

Current settings:

- Target monitor, shown as explicit Monitor 1 / Monitor 2 / Monitor 3 buttons
  rather than the standard WinForms dropdown.
- Sidebar width from 20% through 80%; default remains 33%.
- Auto-hide delay from 0 through 10000 ms.
- Slide animation duration from 0 through 1000 ms.

All settings are persisted in the existing Windows `client.json`.

The selected monitor button has a clear active state. Hidden mode remains fully
invisible and the sidebar remains always-on-top while visible.


## 2026-08-13 - Phase 1 Settings tab v2

Refinements from desktop testing:

- Added a permanent `EXIT` button in the top bar.
- Added an optional system tray icon.
- Tray icon setting is stored in `client.json`.
- Tray menu provides Show, Hide, and Exit.
- Disabling the tray icon does not remove the top-bar EXIT fallback.
- Settings is forced to the final tab position.
- Device count text was corrected for the current inventory: 2 RF devices and
  12 IR devices.


## 2026-08-13 - Header alignment and Tower artwork

Polish from live desktop testing:

- Refresh All and EXIT are vertically centered inside the header.
- EXIT now has comfortable padding from the right edge.
- The supplied radio-tower artwork appears immediately left of `Tower Control`.
- The same artwork is used for the optional system tray icon.
- The top status now reports the total number of IR device profiles returned by
  Tower, rather than counting only profiles that currently contain an enabled
  IR command. This resolves the misleading 9-device count when the actual
  inventory contains 12 IR device profiles.


## 2026-08-13 - Header layout refresh

- Tightened the top header layout so it matches the cleaner desktop mock-up more
  closely.
- Reduced the title/icon block slightly and raised/lowered elements for better
  visual balance.
- Kept `Refresh All` and `EXIT` vertically centered, with a little more right
  padding.
- Added explicit `rfDisplayCount` and `irDisplayCount` values in `client.json`
  so the header can show the intended project inventory totals even when the
  current API responses are not a reliable summary source.


## 2026-08-13 - Icon polish v3

- Reworked the tower artwork for UI usage:
  - white symbol on transparent background for the header
  - proper multi-size `.ico` for the system tray
- Lowered the title icon slightly to sit better in the header.
- Increased the button height and explicitly centered button text to avoid the
  clipped `Refresh All` / `EXIT` appearance on the user's Windows desktop.


## 2026-08-13 - Header z-order fix v4

- Fixed the real cause of the apparently shrinking/cut-off `Refresh All` and
  `EXIT` buttons: the Fill-docked TabControl was created after the header and
  could paint over the lower part of the header. The header is now explicitly
  brought to the front.
- Restored the buttons to normal full dimensions and centered them vertically.
- Increased the tower logo from 26x26 to 48x48 and vertically centered it.


## 2026-08-13 - Header hard boundary v5

- Removed `Dock = Fill` from the main TabControl after repeated visual clipping
  of the lower part of the header buttons.
- The TabControl now receives an explicit rectangle whose top edge starts at
  `header.Bottom`.
- The header and tabs therefore cannot occupy the same pixels, independent of
  WinForms z-order/docking behaviour.
- The larger 48x48 tower logo from v4 is retained.


## 2026-08-13 - Header status overlap fix v6

The repeated apparent clipping of `Refresh All` and `EXIT` was traced to the
header status label rather than the TabControl.

The status label had `Top,Left,Right` anchoring and extended underneath both
buttons. Because it was a sibling control created earlier in the same header,
it could paint over the lower portion of the buttons and their text.

Fix:

- Removed the status label's right anchor.
- Its width is now calculated to end before `Refresh All`.
- Refresh All and EXIT are explicitly brought to the front.
- The 48x48 tower logo is retained.


## 2026-08-13 - Phase 2 IR layout correction

Live testing exposed two layout problems in the first Phase 2 IR screen: the
command GroupBoxes could collapse to almost zero width, and the left device list
consumed too much vertical space.

Corrections:

- IR device list now uses a fixed ~10-row height.
- Left remote/image pane widened from 320 to 380 pixels.
- Remaining left-side space is dedicated to the original-remote preview.
- IR command groups now receive explicit width/height calculations instead of
  relying on AutoSize, preventing the command controls from collapsing into
  narrow vertical strips.
- IR header controls now use an explicit ordered TableLayoutPanel so device name,
  details, transmitter label, transmitter buttons and selected-output summary
  appear in the intended order.
- `Remotes.rar` is shipped under `windows/assets/remotes/`; Tower Control attempts
  to extract it automatically with Windows `tar.exe` when no remote images have
  yet been extracted.
- Image lookup is case-insensitive and accepts JPG/JPEG/PNG/BMP assets.


## 2026-08-13 - Responsive remote preview v3

- The IR device/image column is no longer treated as a fixed-width pane.
- Its width is recalculated from the live IR-tab width (about 34%), with
  minimum/maximum constraints so the command area remains usable.
- The layout recalculates when the sidebar, tab, monitor, or resolution changes.
- The original-remote PictureBox continues to use `Zoom`, so the full image is
  scaled proportionally to the available preview region rather than cropped.
- Reduced unnecessary padding around the preview to give the JPG more usable
  drawing area.


## 2026-08-13 - Responsive remote preview v4

Startup fix:

- Removed hard `Panel1MinSize` / `Panel2MinSize` assignments from the IR
  SplitContainer. WinForms can construct the control at a temporary width that
  is smaller than those combined limits, which can abort the PowerShell app.
- Responsive sizing now waits until the SplitContainer has a meaningful runtime
  width.
- `SplitterDistance` is clamped and guarded during resize events.
- The responsive approximately-one-third image/device pane behaviour is retained.


## 2026-08-13 - Device-specific remote layouts v5

This is a Windows/PowerShell-only layout pass. Tower command IDs and Raspberry
Pi protocol code are unchanged.

### Denon AVR X2800H

- Added mutually exclusive MAIN and ZONE 2 view buttons.
- MAIN shows normal command names.
- ZONE 2 shows commands beginning with Z, Z2, or Zone 2.
- Denon navigation now uses a real D-pad layout:
  Up above; Left / OK / Right; Down centered; Menu lower-right.
- Volume Up/Down are vertically paired with Mute beside them.

### KPN Media Box

- Navigation uses a 3x3 D-pad with four empty corner positions.
- Gids, Radio, and Menu sit directly below the D-pad.
- Fast Forward is explicitly rendered in Media.

### LED Light Bar

- Added separate Colors and Modes categories.
- Colors form a 3x2 block.
- Modes form a 3x2 block with Brightness Down below Brightness Up.

### PAC 7.2

- Temp Down is directly below Temp Up.
- Timer has its own category.
- Hour Up and Hour Down are UI aliases for the existing Temp Up/Temp Down
  commands, so no device profile or Pi changes are required.

### Logitech Z5500

Five primary categories are rendered:

1. Power
2. Volume
3. Controls
4. Input
5. Test

Sub, Center, and Surround Down buttons sit directly below their Up buttons.


## 2026-08-13 - Device layout crash fix v6

Fixed a PowerShell WinForms method invocation error in the explicit remote grids.

`TableLayoutPanel.SetRowSpan` and `SetColumnSpan` were incorrectly invoked as
static methods. They are now called on the actual TableLayoutPanel instance.

This affected layouts using vertically spanning buttons, including Denon Mute,
PAC Timer, and Logitech Z5500 Mute.


## 2026-08-13 - Grid border repair v7

- Fixed broken GroupBox borders around explicit device layouts. The child
  TableLayoutPanel now has an explicit location below the caption and the
  GroupBox has a calculated fixed size.
- Applied to Denon, KPN, LED Light Bar, PAC 7.2, and Logitech Z5500 layouts.
- Denon Zone 2 power lookup now accepts several power-name variants.
- If no Zone 2 power command exists in the live device profile, a disabled
  `Z Power (not learned)` placeholder is shown rather than silently omitting
  the expected control.
- Zone 2 Navigation collapses to a compact Back / Page Up / Page Down row when
  no Zone 2 D-pad commands exist.
- Denon Zone 2 remainder buttons are categorized using their base names, so
  `Z2-InternetRadio` belongs to Sources / Display rather than Navigation.


## 2026-08-13 - TX selector clipping and Denon Zone 2 Power v8

- Increased the IR transmitter-selector row from 34 px to 40 px. The old row
  exactly equalled the 28 px button plus its top/bottom margins, causing the
  lower FlatStyle border to be clipped on Windows.
- Added a small 2 px vertical padding around the TX selector row.
- Denon Zone 2 `Z Power` now intentionally invokes the existing normal `Power`
  command. A separate Zone-2 Power recording is not required.


## 2026-08-19 - TeamViewer/display-topology recovery v9

Tower Control previously persisted only a numeric `monitorIndex`. Remote-control
software such as TeamViewer can temporarily recreate, reorder, resize, or hide
Windows displays. The same numeric index could then point at a different
physical screen, causing the sidebar to appear on the wrong monitor and rapidly
open/hide against stale edge coordinates.

v9 changes the sidebar display model:

- Persists the selected `Screen.DeviceName` and last-known display bounds.
- Treats the old monitor index only as a one-time legacy migration value.
- Monitor numbering in Settings is spatial (left-to-right), not dependent on
  the unstable `Screen.AllScreens` enumeration order.
- Detects live display-topology changes from the existing edge timer.
- Immediately hides Tower Control while Windows/TeamViewer is rearranging
  displays and ignores edge triggers for 1.5 seconds while the topology settles.
- Never silently jumps to another monitor when the selected physical display is
  temporarily missing.
- Automatically resumes when the configured display reappears.
- Rebuilds the Settings monitor buttons after display changes.
- Adds a tray-menu recovery action: `Recover to rightmost display`, so a Windows
  display rename can be repaired without rebooting the PC.

## 2026-08-21 - Home / device management / sensor resilience v10

### Home / Devices page

- Added a `Home` tab after `Sensors`; the application still starts on the
  existing Sensors tab rather than forcing Home as the startup page.
- Home asks `Which device would you like to control?` and renders visual tiles
  for the current IR devices.
- Clicking a device tile selects that device and opens the IR Remotes tab.
- Dedicated device photos can be placed in `windows/assets/devices/` using the
  device id/name as the filename. Until dedicated photos are supplied, Home
  falls back to the matching original-remote image.
- Added an `Add Device` tile. The visual entry point is ready; for now it tells
  the operator to use `tr learn` and Refresh All. A full Windows learn wizard is
  still a separate follow-up task.

### IR device-list management

- Added Up and Down controls next to `IR devices`.
- Device order is saved in `client.json` as `irDeviceOrder` and is reused by
  both the IR list and Home tiles.
- Added Delete with a warning dialog whose default answer is No.
- Deletion calls the Tower API and permanently removes the logical device
  profile. Dedicated IR transport data is removed only when no remaining
  logical device references that transport device.

### Remote-image heading

- Replaced the generic `Original remote preview` caption with the device's
  `remoteName` when available.
- If the name is wider than the preview panel it is shortened with an ellipsis.
- The filename-only `Preview: ...` text is no longer shown after a successful
  image load; the lower status line is reserved for image errors.

### Sensor polling resilience

- A single failed 10-second sensor poll no longer overwrites the global header
  with `Sensor refresh failed`.
- The last good sensor cards remain visible during transient failures.
- Sensor poll failures are logged with their real exception message.
- The UI warns only after three consecutive failed polls.
- A subsequent successful poll clears the failure counter and restores the
  normal Connected header.

### API additions

- `/api/v1/devices/delete` deletes a logical device profile after authenticated
  confirmation from the Windows client.
- IR transport folders are removed only when no remaining device shares them.
- The combined TowerApiServer patch retains the previous direct RF service fix
  and the multi-transmitter `/api/v1/execute` support.


## 2026-08-22 - Stable lazy refresh v13

v11/v12 introduced a second HTTP stack (`System.Net.Http.HttpClient`) in an
attempt to make startup refresh asynchronous. Real-world testing showed new
regressions: sensor reads failed and opening IR Remotes could terminate the
client.

v13 intentionally rolls the networking model back to the proven v10
`Invoke-RestMethod` implementation while retaining all v10 UI features and the
v9 TeamViewer/display recovery logic.

Changes:

- `Refresh All` is completely removed.
- No API/network calls occur from `Form.Shown`.
- The tray icon and edge watcher become active before any server work.
- The header button is now `Refresh` and refreshes only the selected tab.
- IR inventory is loaded only when Home/IR Remotes is first selected.
- RF inventory is loaded only when RF Power is first selected.
- Sensors show a harmless waiting message initially and receive their first
  automatic poll from the existing 10-second timer.
- Sensor polling occurs only while the Sensors tab is active.
- All reads use the original `Invoke-RestMethod`, `-DisableKeepAlive`, and
  5-second timeout behavior.
- Read failures are logged and reflected in the status bar; lazy-load failures
  never create modal MessageBoxes.
- The existing three-consecutive-failure sensor warning remains intact.
- No `System.Net.Http` asynchronous task machinery remains in this version.

This is a deliberate stability rollback, not another layer on top of v12.


## 2026-08-22 - Isolated background API reads v14

v13 proved that the remaining white-screen/freeze was not caused by the Home
layout itself. Selecting Home/IR Remotes synchronously called
`Invoke-RestMethod /api/v1/devices` from the WinForms tab-change event. If the
first Windows/LAN request stalled, the entire message loop stalled with it.

v14 keeps the proven v10/v13 HTTP command semantics but isolates all read-only
GET requests in standard Windows PowerShell background jobs:

- Home/IR device inventory GET runs outside the WinForms process message loop.
- RF inventory GET runs outside the WinForms message loop.
- Sensor GET runs outside the WinForms message loop.
- A 250 ms UI timer checks only job state; it never waits on a job or network.
- A slow/hung first LAN request can leave `Loading...` visible but cannot freeze
  the tray icon, sidebar animation, tabs, repainting or EXIT button.
- The background worker disables .NET default proxy/WPAD discovery because this
  Tower endpoint is a LAN service; this specifically avoids multi-minute proxy
  discovery stalls.
- Successful IR inventory is cached in `%APPDATA%\\Tower\\ir-devices-cache.json`.
  Home and IR Remotes can therefore render immediately on later launches while
  a fresh inventory is fetched in the background.
- `Refresh` remains per-tab; `Refresh All` remains removed.
- POST/send operations are unchanged.

This patch is based on v13, not v11/v12, and does not reintroduce the HttpClient
async/task experiment.


## 2026-08-22 - Remote preview recursion / Home freeze fix v15

The repeated white-window freeze when opening Home or IR Remotes was traced to
a deterministic PowerShell recursion bug, not to the Tower API.

`Set-RemotePreviewMessage` handled an empty message by calling
`Set-RemotePreviewMessage ''` again from inside the same empty-message branch.
A successful remote-image load therefore recursively called the helper until
PowerShell hit its call-depth limit. Because this happened on the WinForms UI
thread, the application stopped painting and Windows eventually marked the form
Not Responding.

v15:

- Removes the recursive call completely; clearing the preview hint now directly
  clears/hides the label.
- Suppresses `SelectedIndexChanged` while the IR inventory is being populated.
- Home no longer builds the hidden IR remote command pane just because the first
  device was selected programmatically.
- IR Remotes explicitly renders the selected device when that tab is actually
  opened.
- A successful sensor background read now changes the permanent `Connecting...`
  header to the normal Connected status, unless another device read is still in
  progress.
- The first sensor background read starts 500 ms after the UI is shown instead
  of waiting for the first 10-second polling interval.
- Retains the v14 background read jobs for Sensors/IR/RF.

Background PowerShell jobs are session-owned. Tower Control stops/removes known
jobs during normal form shutdown. If Windows forcibly terminates the client,
a child PowerShell process may briefly outlive the UI process, but each Tower
read has a 10-second request timeout and a new Tower Control process cannot
reattach to or reuse the old job.


## 2026-08-22 - IR pane render cache v16

After v15 stabilized Home/IR loading, returning to the IR Remotes tab still
felt sluggish even though the device inventory was already loaded.

Root cause: `Load-SelectedTabIfNeeded` called `Show-IrDevice` every time the IR
tab became active. `Show-IrDevice` clears and recreates the complete WinForms
command tree, reloads the remote preview image and recalculates group widths.

v16 adds a render signature for the selected IR device:

- Tracks the rendered device ID and a signature derived from its profile and
  enabled IR commands.
- Returning to IR Remotes reuses the existing command controls when the device
  and profile are unchanged.
- A background `/api/v1/devices` refresh no longer rebuilds the visible remote
  when its data is identical.
- Selecting a different device still renders immediately.
- Changed command/profile data invalidates the signature and rebuilds normally.
- Denon MAIN/ZONE2 still calls `Show-IrDevice` directly, so switching zone mode
  intentionally forces a rebuild.
- Logs the actual `Show-IrDevice` render time in
  `%APPDATA%\\Tower\\tower-control.log` for future performance diagnosis.


## 2026-08-22 - Native smooth sidebar animation v17

The original sidebar animation was implemented as a synchronous PowerShell
`for` loop with `Application.DoEvents()` and `Start-Sleep` between 12 fixed
steps. Under CPU load, scheduler delays made each sleep/frame take a different
amount of time, which produced visible jerking.

v17 replaces that animation path:

- No `Start-Sleep` or `Application.DoEvents()` is used for sidebar animation.
- A WinForms timer drives the animation without blocking the UI message loop.
- A `Stopwatch` supplies real elapsed time; delayed callbacks catch up to the
  correct animation position instead of stretching the animation.
- Native `user32!SetWindowPos` changes only the top-level window position on
  each frame, avoiding managed `Form.SetBounds`/layout work per frame.
- The existing Smoothstep easing curve is retained.
- Tower Control requests `AboveNormal` process priority and `AboveNormal` UI
  thread priority. This is intentionally below High/Realtime to avoid starving
  other applications.
- `timeBeginPeriod(1)` is requested while Tower Control is running to improve
  timer granularity and is paired with `timeEndPeriod(1)` on shutdown.
- Display-topology recovery forcibly stops any in-progress animation timer
  before hiding/rebinding the form.

The goal is scheduler resilience rather than CPU affinity. Pinning Tower Control
to one CPU would not reserve that CPU and could make animation worse if that
logical processor were busy.


## 2026-08-22 - Monitor-clipped sidebar animation v18

v17 made the sidebar animation substantially smoother, but on a dual-monitor
desktop a hidden sidebar could remain visible while physically moving onto the
monitor adjacent to the selected target display. Opacity was only set to zero
after the movement completed.

v18 adds native per-frame monitor clipping:

- `user32!SetWindowRgn` and `gdi32!CreateRectRgn` clip Tower Control to the
  selected monitor's right boundary while it animates.
- Pixels that physically cross into a neighboring monitor are never rendered.
- On slide-out, the visible portion shrinks exactly at the target monitor edge,
  creating the effect of the panel moving behind the edge of that screen.
- On slide-in, the visible portion grows from that same boundary.
- The clip is applied before opacity is raised, preventing a one-frame flash on
  the adjacent monitor.
- Once fully open, the temporary region is removed and the form returns to its
  normal full rectangular shape.
- The hidden state keeps both a zero-width clip and opacity 0.
- Existing v17 native movement, Stopwatch timing, AboveNormal scheduling and
  1 ms timer-resolution behavior are retained.

This works regardless of whether another Windows monitor exists immediately to
the right of the selected display.


## 2026-08-22 - RF inventory cache / pre-warm v19

The RF Power tab still took roughly two seconds on its first visit after each
Tower Control launch even though the RF inventory itself is tiny.

The delay came primarily from the v14+ background-read architecture:
`Start-Job` launches a separate `powershell.exe` process before the
`/api/v1/rf/devices` request can run. IR already masked this process-start cost
with a local inventory cache; RF did not.

v19:

- Adds `%APPDATA%\\Tower\\rf-devices-cache.json`.
- A cached RF inventory is applied immediately when the RF tab is opened.
- The real RF inventory is refreshed quietly in the background afterward.
- A successful RF background read updates the cache.
- When cached RF data is already visible, the header is not changed to
  `Loading RF devices...` for the silent freshness check.
- A one-shot 1.5 second startup timer pre-warms the tiny RF inventory in the
  background. This does not perform network work on the WinForms UI thread.
- Existing v18 monitor-clipped animation and all v15-v17 stability/performance
  fixes remain unchanged.


## 2026-08-22 - IR Remote device manager / custom images v20

The IR Remotes left pane is now a compact device-management surface.

### Device controls

The old text `Delete` button has been replaced by four compact controls:

- `↑` move selected remote up
- `↓` move selected remote down
- `X` delete selected remote
- `+` add remote

Move buttons are disabled automatically at the top/bottom of the list.
Delete remains protected by the existing Yes/No confirmation with No as the
default answer.

The `+` button is intentionally a placeholder for now. The plan is to build the
RF add-device wizard first and then reuse its layout for IR, adding the IR
learning/calibration steps.

IR reordering is now local/instant. It updates `client.json`, the Home tile
order and the local IR cache without making a synchronous `/api/v1/devices`
request.

### Remote images

The remote preview pane is now interactive:

- If no image exists, a centered square button says
  `Click here to add image`.
- Clicking the placeholder opens a Windows image picker.
- Clicking an existing remote image opens the same picker to replace it.
- Chosen images are copied into
  `%APPDATA%\\Tower\\remote-images\\`.
- The image is keyed by Tower device ID, so it survives application-folder
  updates/syncs.
- Custom images override the bundled legacy remote-image mapping.
- The Home page also benefits automatically because its fallback image path
  resolves through the same remote-image resolver.
- Deleting an IR device also removes its local custom remote image.

### Delete behavior

After a confirmed Pi-side delete, the device disappears from the Windows list
and Home page immediately. Tower Control then starts a normal background
inventory refresh to verify authoritative Pi state without blocking the UI.


## 2026-08-22 - IR device manager startup fix v21

v20 introduced a startup-order regression in `Tower-Control.ps1`.

The new IR toolbar and remote-image controls called
`$toolTip.SetToolTip(...)` before `$toolTip` had been instantiated. When Tower
Control was launched through `Start-Tower-Control.vbs`, the PowerShell runtime
error was hidden by the launcher and the application appeared to do nothing.

v21:

- Creates the shared WinForms `ToolTip` object before the first IR toolbar or
  preview control uses it.
- Removes the later duplicate ToolTip construction so existing tooltip
  registrations are not discarded.
- Adds a small startup log breadcrumb after IR device-manager controls are
  initialized.
- No functional changes to the v20 IR ordering, delete, add placeholder, image
  picker, RF cache, sidebar animation, or Pi APIs.


## 2026-08-22 - IR toolbar visibility fix v22

v21 started correctly but the new IR management buttons were invisible.

Root cause:
`$irDeviceListLabel` used `Dock = Fill` inside the same panel as the manually
positioned `+ / ↑ / ↓ / X` buttons. The label's z-order covered the buttons,
so only `IR devices` was visible.

v22 replaces the manual positioning with a dedicated right-docked
`FlowLayoutPanel` toolbar:

- Left: `IR devices`
- Right: `+  ↑  ↓  X`
- Toolbar has explicit z-order and cannot be covered by the fill label.
- Button order matches the requested/mock-up layout.
- Existing move/delete/add-placeholder logic is unchanged.
- Existing custom-image behavior is unchanged.


## 2026-08-22 - RF Power presets / metadata UI v23

The RF Power page has been redesigned around frequent-use device groups and
clearer device identity.

### Persistent presets

Three client-side presets are shown at the top of the RF Power tab.

Each preset displays every known RF power device as a selectable button. The
interaction intentionally mirrors the IR transmitter selector:

- click a device button to include it in that preset;
- click it again to remove it;
- selected devices use the same SteelBlue/white selected state;
- preset memberships are stored in `client.json`;
- selections therefore survive Tower Control restarts.

Each preset has a `POWER ON PRESET` action. Windows sends the selected device
IDs to the Pi through the new `/api/v1/rf/group` endpoint, so the Tower backend
performs the grouped RF transmissions under the existing RF command mutex.

### Device cards

The old RF rows placed the friendly name hundreds of pixels away from the
ON/OFF buttons. They are now compact GroupBox cards:

- friendly name is the card title;
- ON and OFF are directly below the name;
- protocol/address summary is directly beside the action buttons.

### RF technical metadata

`GET /api/v1/rf/devices` now also exposes the stored RF definition fields:

- protocol
- description
- house
- unit
- GPIO
- pulse length
- repeat count
- legacy ON/OFF codes
- modern transmitter ID/address

Hovering a device/preset button shows these details.

Important terminology: current modern KAKU devices do **not** each use a unique
RF carrier frequency. The Tower uses shared 433 MHz RF transmitter hardware.
The unique modern KAKU value is the transmitter ID/address plus unit.

### Add RF Device entry point

A `+ Add RF Device` button has been placed in the RF header. v23 intentionally
does not create device definitions yet; it is the entry point for the RF wizard
to be implemented next. That wizard will generate a unique modern KAKU address,
collect the friendly name, pair/test the receiver, and save the Tower RF
definition. The same wizard shell can then be reused for IR learning.


## 2026-08-22 - RF preset startup parse fix v24

v23 contained a PowerShell parse error in `Refresh-RfPresetControls`.

The preset power-button tooltip passed an `if/else` statement directly as the
second argument to `ToolTip.SetToolTip(...)`. Windows PowerShell does not accept
that statement form as a direct method argument. Because Tower Control normally
starts through the hidden VBS launcher, the parser error resulted in no visible
window, tray icon, or startup indication.

v24 computes the tooltip text in a normal variable first and then passes that
string to `SetToolTip`.

This is Windows-only. The v23 Pi/API changes are unchanged and do not need to
be rebuilt again if v23 was already built/installed.


## 2026-08-22 - RF preset PowerShell interpolation fix v25

Windows PowerShell parser diagnostics exposed one remaining v23/v24 syntax
error:

    "Preset $preset: ..."

Inside a double-quoted PowerShell string, the colon immediately following a
variable name is parsed as part of the variable/scoping syntax. `$preset:` is
therefore invalid.

v25 changes that string to:

    "Preset ${preset}: ..."

The braced variable form explicitly terminates the variable name before the
colon.

This patch is Windows-only. The v23 Pi/API backend was already built and
installed and is intentionally not included in v25.


## 2026-08-22 - Compact RF preset/device layout v26

v25 functionality was correct, but the RF Power layout was too vertically
expensive and the RF device cards stretched unnecessarily across the tab.

v26 changes only the Windows layout:

### Presets

- Preset section reduced from 286 px to 188 px.
- Each preset is now one compact horizontal row:
  `Preset N | selectable devices | POWER ON`
- All three presets fit comfortably in the RF sub-window.
- Persistent selection behavior is unchanged.

### RF device cards

- RF devices are now compact fixed-width tiles rather than full-width rows.
- Friendly device name remains the GroupBox title.
- `ON` and `OFF` sit immediately below the name.
- The protocol label (`Modern KAKU`, `Legacy KAKU`, etc.) sits below the
  buttons.
- The card border ends with the buttons/protocol area instead of extending to
  the right edge of the RF page.
- Full transmitter ID/address, unit, pulse and repeat metadata remains
  available through hover tooltips.
- Cards wrap left-to-right when more RF devices are added.


## 2026-08-22 - RF Cards/List choice + button style prototypes v27

v27 adds two UI experiments requested before choosing a final global visual
language.

### RF Cards / List

The RF Power page now has a persistent `Cards` / `List` selector.

- `Cards`: compact RF tiles that wrap left-to-right.
- `List`: one RF device per row from top to bottom.
- List mode keeps friendly name, protocol and ON/OFF actions physically close
  together; rows intentionally stop around 560 px rather than stretching
  across the whole sidebar.
- The selected view is stored as `rfDeviceViewMode` in `client.json`.

### Preset layout repair

The compact preset TableLayout introduced in v26 still rendered its label and
POWER ON cells poorly on the test machine.

v27 replaces each preset with a simple bordered Panel:

- visible `Preset 1/2/3` label at the left;
- scrollable selectable-device strip in the middle;
- visible `POWER ON` pill at the right;
- manual Resize positioning is limited to those two inner controls and avoids
  the previous TableLayout cell-border artifacts.

### Live button-style comparison

To compare the three supplied shape families without changing the entire app at
once:

- IR Remotes command/transmitter buttons use a soft rounded-rectangle region.
- Settings monitor/resolution buttons use a chamfered top-left/bottom-right
  outline; the active display is filled SteelBlue and inactive displays are
  white/outlined.
- RF Power action/preset buttons use a pill/capsule region.

Existing category/semantic colors are deliberately retained. This pass tests
shape and interaction; after choosing a preferred family it can become the
global default.


## 2026-08-22 - Chamfer Point constructor runtime fix v28

v27 parsed correctly but failed during runtime initialization while constructing
the experimental Settings chamfer button region.

Windows PowerShell interpreted arithmetic expressions inside
`New-Object System.Drawing.Point(...)` constructor arguments as arrays.
Expressions such as `$width - 1` then reached subtraction as `System.Object[]`,
producing the `op_Subtraction` runtime error.

v28 builds the polygon as a typed `System.Drawing.Point[]` and uses direct .NET
constructors (`[System.Drawing.Point]::new(...)`), removing that ambiguity.

No functional changes were made to Cards/List mode, RF presets, IR styling,
Settings styling, caching, or the Pi backend.


## 2026-08-22 - Button border/alignment cleanup v29

v28 made the three requested shape families visible, but Windows Forms' normal
rectangular FlatStyle border was still being clipped by custom Regions. That
produced stray horizontal lines above/below rounded and pill buttons and made
the comparison look misaligned.

v29:

- Removes native rectangular button borders for the experimental styles.
- Draws the Rounded / Chamfer / Pill outline manually in each button's Paint
  event with anti-aliasing.
- Reapplies the correct Region when a control is resized.

Alignment refinements:

- RF Cards/List selector and ALL ON / ALL OFF / Add RF Device share a cleaner
  top baseline.
- Preset labels, selector buttons and POWER ON buttons are vertically centered.
- Extra spacing is added before POWER ON so the selector strip does not visually
  collide with it.
- RF cards use consistent size/margins.
- List-mode ON/OFF buttons are vertically centered.
- IR command and transmitter buttons are slightly shorter to give the rounded
  outline equal top/bottom breathing room.
- Settings monitor buttons are slightly shorter for a more balanced chamfered
  outline.

No behavior/API changes are included.


## 2026-08-22 - Button-style Tag collision fix v30

v29 exposed a major runtime error on the IR Remotes page:

    Cannot validate argument on parameter 'shape'.
    The argument "" does not belong to the set Rounded,Chamfer,Pill.

Root cause:
the experimental button-style layer stored its `Shape` and `BorderColor`
metadata in WinForms `Control.Tag`.

Tower Control already uses `Tag` as functional application state:

- IR transmitter buttons store the transmitter name;
- IR command buttons store BaseColor / PressedColor;
- Settings monitor buttons store the Windows Screen.DeviceName.

Whichever code wrote `Tag` last destroyed the other component's state. The
custom Paint/Resize events could therefore receive an empty shape, while normal
button clicks could also lose transmitter/monitor identity.

v30:

- Styling never reads or writes `Control.Tag`.
- Rounded/Chamfer/Pill shape and border color are captured privately in
  PowerShell event-handler closures using `GetNewClosure()`.
- Existing Tower functional Tag values remain untouched.
- Fixes the IR red-X/error controls.
- Restores IR transmitter button identity.
- Restores IR command pressed-color Tag data.
- Restores Settings monitor button DeviceName identity/click behavior.
- RF styling remains visually unchanged because its buttons did not depend on
  Tag in the same way.

No Pi/API changes.


## 2026-08-22 - Settings chamfer edge repair v31

Visual review of v30 confirmed that the IR Rounded style is rendering correctly
and should remain unchanged.

The inactive Settings monitor buttons, however, were missing portions of their
left/right outline. The one-pixel chamfer border was painted directly on the
control Region boundary. Because a GDI+ pen is centered on its path, half of the
stroke landed outside the clipped Region and disappeared.

v31 changes only Chamfer border painting:

- the button Region remains full-sized;
- the painted Chamfer path is reduced by two pixels;
- that path is translated one pixel inward;
- the entire 1px outline therefore stays inside the visible Region.

Rounded IR and Pill RF regions/painting are unchanged.


## 2026-08-22 - Focused RF visual polish v32

IR Rounded buttons and Settings Chamfer buttons are now considered stable and
are intentionally untouched.

RF still looked like a mixture of custom pill buttons and default WinForms
containers. v32 focuses only on that page.

### Presets

- Removes the heavy rectangular border around each individual preset row.
- Keeps the shared outer `Presets` GroupBox.
- Adds subtle 1px separators between rows.
- Preset label, selectable-device strip and POWER ON remain aligned.
- Unselected preset members now use a clean white fill; selected members remain
  SteelBlue/white and use Semibold text.

### RF device Cards

Default GroupBoxes have been removed.

Each Card is now a flat compact panel containing:

- bold device name;
- protocol immediately below;
- ON / OFF pill buttons below that;
- a light custom 1px card border.

This removes the stock GroupBox caption line and makes the whole tile read as
one designed component.

### RF List

List mode uses the same flat-card visual language:

- name + protocol at the left;
- ON/OFF immediately beside them;
- compact fixed maximum width;
- light custom border.

### Cards / List selector

The Cards/List controls now use the RF Pill prototype too, so the mode selector
no longer looks like a separate stock Windows UI family.


## 2026-08-22 - Pure PowerShell anti-aliased RF pills v35

v32 is retained as the stable base. The embedded-C# owner-drawn experiment from
v33/v34 is abandoned.

The RF pill quality issue came from using a normal WinForms Button clipped by a
pill-shaped Region. Region clipping itself is pixel/integer based and creates
visible stair-stepping on full-height capsule curves.

v35 uses a different approach with no `Add-Type` and no RF Region clipping.

Every RF button is now a plain WinForms Panel whose rectangular background
matches its parent. The visible control is owner-painted in the Panel Paint
event:

- anti-aliased pill GraphicsPath;
- direct fill painting;
- direct 1px border painting;
- TextRenderer centered text with ellipsis;
- hover lightening;
- pressed darkening;
- disabled-state fading.

Because only the drawn pill is visible and the surrounding rectangular Panel
blends into its parent, the capsule edge remains fully anti-aliased.

Migrated controls:

- Cards / List;
- ALL ON / ALL OFF;
- Add RF Device;
- preset membership selectors;
- preset POWER ON;
- per-device ON / OFF.

IR Rounded and Settings Chamfer styling are copied unchanged from stable v32.
No C# is compiled at Tower Control startup.


## 2026-08-22 - RF preset POWER OFF v36

v35 confirmed that the pure-PowerShell anti-aliased RF pill rendering works
well. One functional omission remained: each preset only exposed POWER ON even
though the `/api/v1/rf/group` endpoint already supports both `on` and `off`.

v36 adds a matching POWER OFF pill to every preset row.

Behavior:

- POWER ON sends the selected preset members with `action = on`.
- POWER OFF sends the same persistent preset membership with `action = off`.
- Both controls disable automatically when the preset contains no selected RF
  devices.
- Hover text reports the number of devices affected.
- Layout keeps both actions together at the right side of each preset row.
- RF pill rendering, Cards/List, persistent preset membership, IR and Settings
  styling are otherwise unchanged.


## 2026-08-22 - RF pairing-state indicator v37

RF power definitions already persist pairing metadata in the `.rf` file:

    status=paired

The `/api/v1/rf/devices` endpoint already exposes this as `device.status`, so
the first pairing indicator requires no Pi/backend change.

v37 adds a pairing badge to every RF device:

- `PAIRED` — green
- `NOT PAIRED` — amber
- `UNKNOWN` — gray

Placement:

- Cards view: top-right of each RF card.
- List view: far-right of each RF row.
- The card top-left remains intentionally free for the delete `X` planned next.

The badge is clickable now. Until the pairing wizard is implemented it shows
status information / a pairing-wizard placeholder message.

### Pairing semantics

Tower does not currently receive positive RF feedback from these one-way
433 MHz receivers. The persisted `status=paired` value is therefore metadata,
not an automatically discovered radio state.

The planned RF wizard should create a new modern receiver with an unpaired
status, guide the user through physical receiver learn mode, send/test the
pairing command, and only then update the RF definition to `status=paired`
after confirmation that the receiver actually responded.

The UI accepts several future unpaired spellings (`unpaired`, `not_paired`,
`pending`, etc.) and normalizes them visually to `NOT PAIRED`.


## 2026-08-22 - RF device delete control v38

Each RF power device now has a small red `X` immediately to the right of its
pairing-state badge.

Card header layout:

    Device name                  [PAIRED] [X]

List rows use the same right-side ordering.

Deletion behavior:

- Clicking `X` opens an explicit Yes/No warning.
- The default button is **No**.
- The warning names the RF device and its `.rf` definition.
- Confirmed deletion calls `POST /api/v1/rf/delete`.
- The Pi deletes the matching `data/rf/power/<id>.rf` definition.
- Windows removes the device from Preset 1/2/3.
- The local RF cache and visible Cards/List UI update immediately.
- A background RF inventory refresh then verifies authoritative Pi state.

The delete button uses the same pure-PowerShell anti-aliased RF rendering as the
v35+ controls.

### Backend

`RFDatabase` now exposes `deletePowerDevice(name)` with filename/path validation
before removing a definition. The API verifies that the requested RF definition
exists before deletion and returns a normal JSON response.


## 2026-08-22 - RF view selector rail / circular delete control v39

v39 is a Windows-only visual refinement on top of v38.

### RF view selector

The persistent `Cards / List` selector has moved out of the RF page header and
into a dedicated narrow rail on the right side of the `RF Power devices`
section.

Layout:

    RF Power devices                         View
    [device cards/list ...]                 [Cards]
                                            [List ]

This keeps the top RF header focused on global RF actions (`ALL ON`, `ALL OFF`,
`Add RF Device`) and places the view-mode control next to the content it
actually changes.

### Delete control

The device delete control is now a true 24x24 anti-aliased circle:

- solid red fill;
- white centered `X`;
- dark-red border;
- same confirmation/delete behavior as v38.

The pairing indicator remains immediately to the left of the delete circle.

No Pi/API changes are included in v39; the v38 delete endpoint remains valid.


## 2026-08-22 - RF delete-circle rendering fix v40

v39 still used the generic tiny RF text renderer for the delete control. At
24 px wide the text/ellipsis logic could render a literal `X` as dots/pixels.

v40 gives delete its own owner-painted control:

- 24x24 true circle;
- fill exactly matches RF OFF buttons: RGB(248,226,226);
- same soft RF border family;
- centered `X` is drawn explicitly as two anti-aliased diagonal lines;
- subtle hover/pressed feedback.

Deletion safety is unchanged:
- explicit Yes/No confirmation;
- default button remains **No**;
- no file is deleted until Yes is confirmed.


## 2026-08-22 - RF delete-circle size refinement v41

The v40 delete control rendered correctly but was visually too dominant next to
the pairing badge.

v41 changes only the delete control:

- 24x24 -> 18x18;
- X stroke reduced from 1.6 px to 1.25 px;
- X itself is shortened proportionally;
- same soft OFF-button pink fill and RF border;
- re-centered vertically beside the pairing badge.

Delete confirmation remains unchanged:
- explicit Yes/No prompt;
- default = No.

The right-side View / Cards / List rail is unchanged.


## 2026-08-23 - RF Add/Pair wizard v42

RF provisioning now lives in the Pi and is reused by the Pi CLI and Windows.

Current modern definitions use transmitter IDs `0x123456` through `0x123459`,
so the next suggested value is `0x12345A` (hexadecimal), with the next file
`Tower-RF-Power-M2-005.rf`.

New definitions are written with `status=unpaired`. The Windows and CLI pairing
flow sends ON first, verifies receiver response, sends OFF using the same
transmitter ID + unit, and only writes `status=paired` after the user confirms
that OFF also worked.

API:
- GET `/api/v1/rf/modern/next`
- POST `/api/v1/rf/create`
- POST `/api/v1/rf/pair/start`
- POST `/api/v1/rf/pair/status`

CLI:
- `tower rf next`
- `tower rf add`
- `tower rf pair <record-id>`

An unpaired badge in Windows now opens the pairing wizard directly.

Pairing wizard state is shared between its buttons through one mutable state object, and RF inventory refresh is deferred until pairing/skip completes to avoid caching a transient unpaired state after a successful pairing.


## 2026-08-23 - RF Add wizard two-step UI v43

The initial RF Add wizard has been simplified.

### Step 1 - Create

The initial screen now contains only creation data:

- fixed next RF definition filename;
- device name;
- description;
- editable transmitter ID;
- collapsed `Advanced...` section;
- Create Device / Cancel.

The old explanatory text about pairing has been removed from the top of the
initial form.

`Unit` is now hidden inside `Advanced...` and remains `1` by default. The
advanced section also shows the underlying GPIO/pulse/repeat defaults for
diagnostic use.

### Step 2 - Pair or finish

After `POST /api/v1/rf/create` succeeds, the same window switches to a second
step instead of showing a MessageBox.

It displays:

- device friendly name;
- created `.rf` filename on PI3A;
- current NOT PAIRED state;
- `Skip & Finish`;
- `Pair Now`.

`Pair Now` launches the existing pairing mini-wizard.
`Skip & Finish` closes the wizard and leaves `status=unpaired`.

No Pi/backend changes are required for v43; it uses the v42 provisioning API.


## 2026-08-23 - RF Add wizard rendering/layout refinement v44

The v43 creation screen had two visual defects:

- `Advanced...` still used a standard WinForms button and therefore looked
  noticeably rougher than the anti-aliased RF controls.
- the hexadecimal transmitter-ID helper wrapped to two lines while its label
  was only one line high, clipping the second line.

v44 changes only the Windows wizard presentation:

- `Advanced...` now uses the same pure-PowerShell smooth RF renderer;
- hexadecimal helper label height increased to 42 px;
- Advanced button/detail panel moved down slightly;
- form height increased by 20 px;
- Cancel/Create moved down proportionally;
- all backend/API/provisioning behavior remains unchanged.


## 2026-08-23 - IR Remote wizard foundation v45

The IR `+` button and Home `Add Device` tile now open the first real IR wizard.

### Architecture

IR recording logic now has a reusable Pi-side `IRLearningService`.

The existing `tower learn` direct/interactive command was refactored so its
capture, six-receiver analysis, RAW fallback, duplicate detection, backup, IR
file save, and logical-device command update all go through the same service
used by the HTTP API.

This prevents Windows from becoming a second independent IR-learning
implementation.

### API

- `POST /api/v1/ir/devices/create`
- `POST /api/v1/ir/learn/capture`
- `POST /api/v1/ir/learn/save`

The capture endpoint records all six receivers for eight seconds and analyzes
the result, but does **not** save the learned command. Windows can therefore
show the protocol/address/command/carrier/receiver result first.

The save endpoint re-analyzes the retained capture and persists it only after
the user chooses `Save & Next`. Duplicate signals require explicit confirmation.

### Windows flow

Step 1:
- Manufacturer
- Remote name
- Device name
- Location
- Advanced default transmitter (TX-001 by default)

Step 2:
- Command name
- Description
- READY - RECORD
- six-receiver 8-second capture
- result preview
- Retry
- Save & Next
- Finish

Calibration is intentionally not part of v45 yet. It will be added after this
create + learn-command path is verified.


## 2026-08-23 - IR wizard first-screen layout refinement v46

The first IR wizard screen was visually correct, but the helper under
`Device name` wrapped onto a second line while its label was only one line high.

v46 is Windows-only and changes only layout:

- Device-name helper height increased to 40 px.
- Location row moved down by 18 px.
- Advanced button/panel moved down by the same amount.
- Existing smooth button rendering and all IR wizard/backend behavior remain
  unchanged.


## 2026-08-23 - IR wizard fixed locations v47

The IR Remote wizard Location field is now a fixed DropDownList instead of
free text.

Available Tower locations:

- Living Room
- Bedroom
- Facilities

`Living Room` is selected by default.

The backend remains unchanged; this is a Windows UI constraint to keep device
profile location values consistent.


## 2026-08-23 - Global IR duplicate detection v48

A deliberate test learned the already-existing Logitech/Z5500 Mute signal
under a new temporary `Homebrew` device.

The new capture decoded as:

- NEC
- address `0x8`
- command `0x16`
- 38 kHz
- GPIO22 / TSOP38238

This exactly matches the stored `Z5500 5.1 Audio / Mute` definition, but v45
did not flag it because duplicate detection only scanned the current device
directory.

v48 changes duplicate detection to scan **all** `data/ir/devices/*/*.ir`
definitions. Returned duplicate labels now include both device and command,
for example:

    Z5500 5.1 Audio / Mute

The currently edited command itself is excluded so replacement does not report
a false self-duplicate.

The Learn IR Commands summary line now also includes `Location`, because room
assignment will later drive IR transmitter-pod routing.


## 2026-08-23 - Provisional IR device cleanup v49

Creating an IR remote requires a logical device profile to exist before the
first capture, because the shared IR learning service validates the target
device and later attaches the saved command to it.

That profile is now treated as **provisional** until the first IR command is
successfully saved.

Wizard behavior:

- After `Create Remote`, the learning screen initially shows `Cancel`, not
  `Finish`.
- `Cancel` before the first successful `Save & Next` asks for confirmation.
- If confirmed, Tower calls `POST /api/v1/devices/delete` and removes the
  provisional device from PI3A before closing.
- If cleanup fails, the wizard remains open and reports the error.
- Closing with the title-bar X follows the same cleanup rule.
- After the first command is successfully saved, the remote is considered
  committed and the button changes from `Cancel` to `Finish`.
- Once committed, closing/Finish never deletes the remote.

This prevents invisible zero-command orphan profiles while preserving the
existing shared Pi learning architecture.


## 2026-08-23 - IR receiver diagnostics + calibration UI v50

v50 focuses on integrating the existing calibration workflow rather than
changing/tuning the calibration algorithm.

Learning capture now displays all six receiver rows with GPIO, model, nominal
kHz, timing/event count, pulse count, frames, valid decodes, and analyzer
result.

New Pi API:
- POST `/api/v1/ir/calibration/prepare`
- POST `/api/v1/ir/calibration/batch`
- POST `/api/v1/ir/calibration/save`

The Windows calibration flow preserves the existing TX-001-only rules:
10 taps per batch, five-second pre-delay, one-second spacing, 8/10 confirmation
threshold, only 10/10 + 10/10 as a clean duty pass, >10 as over-triggering,
33/40/50/60% normal duty search, and center +/-1 kHz carrier checks.

Calibration batches run through a background POST job so the WinForms UI stays
responsive.

After command learning, Finish now shows an IR Remote Created step with
`Skip & Finish` and `Calibrate`. Existing IR devices also receive a `Calibrate`
button beside the transmitter selection controls.


## 2026-08-23 - Visible per-tap calibration progress v51

The calibration algorithm is unchanged, but the batch transport/UI is now
explicitly visible.

Previously Windows sent one blocking API request asking the Pi to perform a
five-second delay followed by all ten transmissions. The user therefore could
not tell when an individual tap had occurred.

v51 uses the existing `/api/v1/ir/calibration/batch` endpoint with `count=1`.
Tower Control now orchestrates the same ten-tap sequence:

1. visible five-second countdown;
2. one immediate Pi transmission;
3. mark that tap complete;
4. wait one second;
5. repeat until ten actual API transmissions have completed.

The Current Test area displays ten boxes. The active transmission briefly shows
a dot and is changed to `X` only after the Pi request completes successfully.
A counter shows `N / 10 sent`.

This is a Windows-only UX/transport refinement. Carrier/duty candidate logic,
confirmation thresholds, and calibration profile persistence are unchanged.


## 2026-08-23 - Calibration completion flow v52

A successful calibration launched from the `IR Remote Created` step previously
returned to that same step, leaving the user with another `Skip & Finish` /
`Calibrate` choice even though the complete workflow had already succeeded.

v52 makes `Show-IrCalibrationWizard` return a success boolean.

Behavior now differs by launch context:

- **New remote wizard**
  - successful calibration saves the IR profile;
  - closes the calibration dialog;
  - closes the parent IR creation wizard;
  - returns directly to Tower Control.

- **Existing IR device**
  - successful calibration closes only the calibration dialog;
  - Tower Control remains open on the selected device.

Closing calibration without a successful save returns `false`, so the parent
creation wizard remains open and still offers `Skip & Finish` / `Calibrate`.


## 2026-08-23 - Quiet startup RF refresh v53

Tower Control previously started an automatic RF inventory pre-warm about
1.5 seconds after `Form.Shown`.

If that one background request failed transiently, `Complete-RfDeviceRead`
unconditionally changed the global header status to:

    RF device refresh failed

This could happen even when a valid RF cache was already loaded and the app was
otherwise connected normally.

v53 changes only startup RF refresh behavior:

- startup RF pre-warm is delayed slightly to 2.5 seconds;
- it runs in `quiet` mode;
- cached RF inventory remains active if that startup request fails;
- the global status remains Connected instead of showing a false red failure;
- the failure is retained in `tower-control.log` as a WARN;
- one quiet retry is attempted three seconds later;
- manual Refresh and normal RF-tab refreshes remain non-quiet and still expose
  real RF API failures to the user.

No Pi/backend changes are required.


## 2026-08-23 - PI3A header clock v54

Tower Control now has a compact clock box in the top header between `Refresh`
and `EXIT`.

The displayed time is sourced from PI3A, not from the Windows workstation.

Pi API:

- `GET /api/v1/system/time`

Response includes PI3A's local:

- time (`HH:MM:SS`);
- date;
- timezone abbreviation.

Tower Control starts a background Pi-time sync when the form is shown. The
display advances from the Pi-provided clock anchor and re-syncs every 30
seconds, avoiding one HTTP request per second and avoiding use of the Windows
PC timezone.

Before the first successful Pi sync the box displays `--:--:--`.
The tooltip identifies the value as the Raspberry Pi system clock and shows the
timezone reported by the Pi.


## 2026-08-23 - Home/header/image polish v55

- PI clock box moved to the left of `Refresh`.
- `Refresh` and `EXIT` use matching header borders.
- `Home` is now the first/start tab.
- Home tiles use a rounded IR-style device-name button.
- Remote images with near-white outer background are cleaned on load to blend with the app background.


## 2026-08-23 - v56 startup repair

v55 contained two startup defects:

1. a text replacement produced the invalid static property
   `System.Drawing.SystemColors::ControlSmoke`, causing the app to terminate
   while constructing the IR preview;
2. `SelectedTab = $homeTab` was executed before `$homeTab` existed.

v56 replaces new v55 background colors with explicit WinForms-style
`Color.FromArgb(240,240,240)`, moves Home selection until after Home is
created, and makes the image-cleanup visited-array allocation explicit for
Windows PowerShell.


## 2026-08-23 - UI regression repair v57

v57 repairs regressions introduced by the v55 visual polish.

- Removed the runtime remote-image pixel processor. It caused PowerShell
  execution errors while opening IR remotes. The known-good v54 image loader
  is restored.
- `Home` is now physically added before `Sensors` rather than attempting to
  reorder the TabPage collection with `Insert()`.
- `Home` is explicitly selected as the startup page after it is constructed.
- `Refresh` and `EXIT` use the same 1 px white header border.
- Both header buttons are removed from tab focus; Refresh returns focus to the
  main tabs after clicking so WinForms does not paint an extra thick focus
  outline.

Remote JPG cleanup should be performed once on the actual image assets in a
separate asset-cleanup pass rather than during UI rendering.


## 2026-08-23 - IR preview / Home preload / rename v58

v58 repairs the remaining v57 IR regression and adds IR display-name rename.

### IR preview repair

`Update-RemotePreviewHeading` and its resize callback are restored. Their
accidental removal caused an unhandled `CommandNotFoundException` whenever the
IR remote pane attempted to render.

### Home startup

Home is still the first tab. On `Form.Shown`, Tower Control now loads the local
IR-device cache immediately before starting the normal background inventory
refresh. A one-shot 350 ms timer starts `/api/v1/devices` even when Home was
already selected before the tab-change event handlers were attached.

This prevents Home remaining visually empty until another tab is visited.

### Rename

Toolbar order:

`+  ↑  ↓  ✎  X`

`✎` changes only the user-facing `device.name`. The immutable device ID and
all IR recording paths remain unchanged, avoiding any rename/move of learned
IR files.

Backend:

- `POST /api/v1/devices/rename`


## 2026-08-23 - Quiet IR startup + rename return fix v59

### Startup IR inventory

The first Home-page inventory refresh now follows the same cache-aware pattern
as RF:

- cached IR devices are shown immediately;
- startup refresh is delayed to 1.2 seconds;
- when cache is available, startup refresh is quiet;
- a transient failure keeps cached devices active and leaves the global status
  as Connected;
- one quiet retry is attempted three seconds later;
- manual Refresh remains non-quiet and still reports genuine failures.

### Rename dialog

The rename dialog previously assigned its return value to a normal PowerShell
variable inside a WinForms click event. That event executes in a child scope,
so the caller often received `$null` and therefore never called the rename API.

v59 stores the accepted name in `Form.Tag`, reads it after `ShowDialog`, and
then performs the existing `POST /api/v1/devices/rename`.


## 2026-08-23 - Pi clock readability v60

The PI3A header clock keeps the same compact 92x38 box but increases the
display font from Consolas 10 Bold to Consolas 12 Bold for better readability.


## 2026-08-23 - Persistent Home/RF views v61

v61 removes tab-selection-driven inventory refreshes.

Previously, selecting `RF Power` always launched `/api/v1/rf/devices` even
when cached RF data was already rendered. Every successful response called
`Render-RfDevices`, which cleared/recreated the RF cards and preset pills,
causing a visible white flash. A transient failure on that unnecessary read
also produced a brief red `RF device refresh failed` header.

Behavior now:

- switching Home / IR Remotes / RF Power uses existing controls;
- tab selection does not initiate a network read when inventory is loaded;
- startup timers remain responsible for initial background synchronization;
- the header Refresh button remains the explicit user-requested refresh;
- if no local cache exists, the first tab visit still performs one real load.

Both IR and RF responses now have full inventory signatures. An identical
background response updates no controls, so cards, preset pills, Home tiles,
IR list and command pane remain visually stable.

Local rename/delete mutations update their signature before the normal
authoritative verification read, avoiding a redundant second redraw.


## 2026-08-23 - Aquarium sensor image v62

v62 adds a dedicated sensor asset slot for the `Aquarium` sensor card.
The current implementation loads `windows/assets/sensors/aquarium.png` and
renders it inside the existing Aquarium card without changing the card size.
The image is shown in a `PictureBox` with `SizeMode=Zoom`, keeping aspect
ratio while fitting the available empty space on the right side of the card.


## 2026-08-23 - Persistent sensor cards + aquarium image polish v63

Sensor refreshes no longer clear and rebuild the complete Sensors page.
Cards are created once and subsequent refreshes update only measurement and
age labels. Static card imagery therefore stays mounted and no longer flickers.

The Aquarium image is centered inside the existing card without resizing the
card. Its near-white source background is preprocessed once to RGB 240/240/240,
matching Tower Control's main light background while retaining original image
dimensions and detail.


## 2026-08-23 - Sensor failure-handler repair v64

v63's persistent sensor-card refactor accidentally removed the existing
`Register-SensorRefreshFailure` function while leaving its callers intact.
Therefore a transient `/api/v1/sensors` failure produced an unhandled
`CommandNotFoundException` even though the previous sensor values remained
visible.

v64 restores the original failure counter/logging behavior:

- individual transient sensor refresh failures are logged;
- the current sensor cards remain intact;
- the global status escalates only after three consecutive failures;
- a later successful refresh resets the counter through `Apply-SensorResponse`.


## 2026-08-23 - Vertical sensor layout v65

The Sensors tab now stacks sensor cards vertically rather than wrapping them
left-to-right.

`FlowLayoutPanel` configuration:

- `FlowDirection = TopDown`
- `WrapContents = false`
- existing card dimensions are unchanged

This better suits the adjustable Tower Control sidebar width while preserving
the persistent-card refresh behavior introduced in v63/v64.


## 2026-08-23 - Sensor Cards/List selector v66

The Sensors tab now has a right-side `View` selector with `Cards` and `List`.

The selector deliberately uses the existing **Settings button style**:
white/SteelBlue chamfered buttons with the selected view filled SteelBlue.

- Cards: existing persistent vertical sensor cards.
- List: compact ListView with sensor, measurements and update age.
- `sensorViewMode` persists in `client.json`.
- switching Cards/List performs no sensor HTTP request and no control rebuild.


## 2026-08-23 - Sensor three-view selector v67

The Sensors `View` rail now exposes three persistent modes using the existing
Settings-style chamfered buttons:

- **Cards** — full sensor blocks stacked vertically (`TopDown`, no wrapping)
- **List** — the same full sensor blocks arranged horizontally
  (`LeftToRight`, wrapping enabled)
- **Details** — the compact text/table overview introduced in v66

All modes reuse existing controls. Changing view does not initiate a sensor API
refresh and does not recreate or reload static sensor images.


## 2026-08-23 - RF startup preload + display rename v68

### RF startup rendering

RF cache loading previously waited for the 2.5-second prewarm timer. If the
user opened RF Power before that timer fired, the first cache render occurred
while the tab was visible and individual controls could visibly populate.

v68 loads and renders the local RF cache during `Form.Shown` after the sidebar
has been positioned and made fully transparent. No network request is made in
that startup handler. The existing delayed authoritative RF API refresh remains
quiet and signature-aware.

The RF FlowLayoutPanel is also double-buffered through the protected WinForms
`DoubleBuffered` property to reduce intermediate painting on explicit redraws.

### RF display-name rename

RF cards/list rows now include a small blue pencil control immediately left of
the delete X.

New Pi API:

`POST /api/v1/rf/rename`

Body:

```json
{"device":"<immutable RF record id>","name":"<new display name>"}
```

The endpoint changes only `RFDevice.deviceName`; `RFDevice.name`, the `.rf`
filename, protocol/address and pairing information remain unchanged.


## 2026-08-23 - RF list right padding v69

RF list-mode rows are widened from 560 to 574 pixels. Control positions remain
unchanged, providing roughly 16 pixels of right-side breathing room after the
delete control instead of ending the row almost directly on the X.


## 2026-08-23 - RF list visible right padding v70

v69's 14 px increase was too subtle to make a meaningful visual difference.

RF list rows are now 610 px wide while keeping the rename and delete controls
at their existing positions. This leaves roughly 50 px of clear space after
the delete X, making the action cluster feel less cramped.


## 2026-08-23 - RF list width cap fix v71

v69/v70 changed the initial RF list row width, but `Resize-RfDeviceCards`
still capped list rows at 560 pixels. Any panel resize therefore immediately
overwrote the new width, making those patches visually ineffective.

v71 fixes both locations:

- initial list row width: 590 px
- responsive list-mode maximum in `Resize-RfDeviceCards`: 590 px

The ON/OFF/PAIRED/rename/delete control positions are unchanged, leaving
approximately 32 px of clean space after the delete control at full width.


## 2026-08-30 - PC thermal/fan monitor v72

A new `PC` tab integrates the Dell Precision workstation into Tower Control.

The first implementation is intentionally read-only:

- persistent `System.Management.ManagementScope` to
  `\\.\root\DCIM\SYSMAN`;
- one-second `DCIM_NumericSensor` polling while the PC tab is selected;
- temperature sensors (`SensorType=2`);
- fan RPM sensors (`SensorType=5`);
- Dell warning/critical metadata where exposed;
- dynamic discovery of `DCIM_ThermalInformation`, `DCIM_BIOSEnumeration`, and
  `DCIM_BIOSInteger`;
- six verified Precision 7820 `Fan Speed Auto Level ... Zone` settings rendered
  as **Dell Cooling Levels**, never as PWM percentages;
- separate `HDD0 Fan Enable` state;
- attributes reported writable by Dell are marked `Writable / locked`, because
  this phase deliberately does not perform BIOS writes.

The PC page maintains persistent list rows so the 1-second poll updates values
in place rather than clearing/rebuilding the UI.

Detailed safety/design notes are maintained in
[`PC-Thermal-Control.md`](PC-Thermal-Control.md).


## 2026-08-30 - isolated PC monitor helper v74

Dell Command | Monitor polling now runs in one hidden persistent
`Tower-PC-Monitor.ps1` helper. The helper publishes an atomic JSON snapshot;
Tower Control performs no Dell CIM queries itself. Provider failures therefore
cannot freeze or terminate the sidebar process.


## 2026-08-30 - PC hardware discovery v75

The PC tab now contains `Overview` and `Discovery` sub-pages.

The new read-only discovery table combines common fields from Dell DCM,
NVIDIA, Windows storage reliability, PERC CLI, NIC and audio inventory. PERC
JSON is deliberately flattened rather than prematurely assuming a controller
or physical-drive schema.

Also fixed Dell temperature scaling and stopped treating the PERC/DCM fan
245/255 numeric threshold fields as literal RPM limits.


## 2026-08-30 - PC manual Main Cooling Bank v78

Precision 7820 testing established that Dell's zone levels are effective only
when BIOS Thermal/Climate mode is set to **Auto**. Performance mode accepted and
stored the same `0-100` values but produced no live fan-RPM change.

The useful live actuator is:

```text
Fan Speed Auto Level on CPU Memory Zone
```

At level 100 it reliably raises CPU0, CPU1, SYS1, SYS2, REAR0 and REAR1. SYS0
remains under Dell automatic control. `Fan Speed Auto Level on PSU Zone` also
raises the same six-fan bank, so Tower intentionally leaves that overlapping
control at 0 instead of exposing competing sliders.

The old read-only six-zone panel is therefore replaced by one truthful **Main
Cooling Bank** control with a 0-100 target slider, explicit Apply button, Dell
Auto button (level 0), live mapped RPMs, and verified Dell readback.

Writes remain isolated from the WinForms process. Tower writes an atomic local
command file and the existing hidden `Tower-PC-Monitor.ps1` helper performs the
Dell BIOS operation in a sixth runspace. Normal Dell/GPU/storage/PERC collectors
continue while Dell's slow BIOS provider is applying the command.

The helper also watches the Tower parent process. When Tower owns a non-zero
cooling floor and the UI exits/disappears, the helper attempts to return the
CPU/Memory Zone level to 0 before shutting down.

Adaptive green/orange/red climate automation is deliberately deferred to the
next phase; v78 establishes the proven manual actuator and fail-safe first.


## 2026-09-02 - Windows monitor numbering and stable selection v83

Settings previously labelled monitors by their temporary spatial position in
the current `Screen.AllScreens` collection. On the tested three-monitor layout,
Tower displayed Monitor 1 / 2 / 3 while Windows identified the same physical
screens as 3 / 1 / 2. Enabling the third display could therefore change the
visible Tower button numbers and make selection confusing.

The Settings buttons now extract their number from the Windows
`Screen.DeviceName` (`DISPLAY1`, `DISPLAY2`, `DISPLAY3`) and are ordered by that
number. Selection continues to persist the full DeviceName rather than an array
index, so display enumeration changes do not retarget the sidebar.


## 2026-09-02 - stable PC telemetry table v84

The hardware temperature/RPM list previously cleared and recreated every row
whenever any collector published a snapshot. That produced a visible flash even
though most hardware rows had not changed.

The table now assigns each hardware source a stable row key and updates only
changed cell text. Existing rows stay attached to the WinForms list between
refreshes, and double buffering prevents background repaint flashes. The list is
rebuilt only when hardware rows are genuinely added, removed or reordered.

The PC tab layout and displayed fields are unchanged.


## 2026-09-02 - retain last good telemetry rows v85

Frame-by-frame capture of v84 showed that the remaining flash was a structural
update rather than simple drawing flicker. During asynchronous collector
publishes, Tower briefly considered some established rows absent and rebuilt a
shorter list before the full set returned.

Established hardware rows are no longer removed or reordered during runtime.
Each source updates its existing cells while rows from other sources retain
their last good text and position. Newly discovered rows are inserted once at
their intended location. Tower merges the snapshot first and then performs one
table update. Restarting Tower performs a fresh hardware discovery.


## 2026-09-02 - cell-only repaint and PC preloading v86

A second animated capture proved that suspending and resuming the native
ListView itself could still expose a partial redraw even after row deletion was
removed. The hardware table no longer uses a list-wide BeginUpdate/EndUpdate
cycle. Only cells whose useful value changed are assigned new text.

An established valid cell is retained when a collector temporarily reports
`--`, `Loading` or `Unknown`. Empty storage objects are ignored, preventing the
brief orange `-- / Unknown` disk row. Source state remains visible in the
Sources line.

The PC helper and snapshot reader now start in the background immediately after
Tower launches. Opening the PC tab only reveals the already-loading or loaded
view; it no longer initiates collection.


## 2026-09-04 - Tower-owned RF presets and voice sharing

RF Presets 1-3 are no longer intended to exist only in the Windows
`%APPDATA%\Tower\client.json`. The main Tower service persists their device
membership in `data/rf/presets.json` and returns it with
`GET /api/v1/rf/devices`.

On the first connection after upgrading, if the Pi has no preset file yet,
Tower Control uploads all three existing local preset selections. This is a
one-time migration: the current Windows configuration is preserved and becomes
the Pi's starting configuration. On later starts, the Pi is authoritative and
Tower Control refreshes its local copy from the Pi.

Clicking a preset member saves that preset through
`POST /api/v1/rf/presets`. POWER ON/OFF executes the centrally stored preset
through `POST /api/v1/rf/preset`; the Windows app no longer needs to send the
membership list with every action.

This lets the independent voice service execute the same current presets when
the Windows machine is offline. Editing a preset requires no Python edit,
voice-service restart, or rebuild.
