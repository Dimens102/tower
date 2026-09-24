# Passive device estimates and scripts — v0.11.13

## Devices

Tower stores passive estimated configuration in `data/control/device_states.json`.
The Devices tab combines the properties observed or inferred for each device in
one Estimated configuration column, followed by the last update and its source.
Properties are dynamic: a Denon can show Power, Source, Volume, Mute or Sound
mode while a KPN box may show Power and Channel.

These values are informational only. Tower never skips a command, selects a
different command, or decides ON/OFF from an estimate. Every explicit ON or OFF
request runs its complete configured sequence from schedules, voice, programmable
remotes, presets, and manual controls—even if the estimate already matches.

- **Send ON sequence / Send OFF sequence** always transmit the configured action.
- Configure IR power commands, shutdown press count/delay, and IR outputs in the
  lower panel. Save to Tower stores this device's power behavior without sending.
- Select “Separate ON and OFF signals” only for genuinely separate codes. A
  command merely labelled “Power On” may still be a toggle.

An acknowledged transmission is not feedback from the appliance. A blocked IR
beam, another handset, mains switch, or device timer can make the estimate wrong.
For that reason, bookkeeping happens only after a successful transmission and
bookkeeping errors cannot turn a successful device command into a failed one.
Automatic SMART/toggle power requests are rejected; choose explicit ON or OFF.

## Disabled devices and physical remotes

Disable / Enable acts immediately and preserves the last known state. Disabled
devices are skipped by the common IR/RF command paths, managed power, presets,
voice, schedules, remote buttons, tests using those paths, and calibration sends.
Raw CLI send/replay commands and user-written scripts bypass this layer.

The Tower service observes all available IR receivers. Every 30 seconds it
refreshes its learned-command catalogue and receiver discovery. It matches
supported decoded protocols, or closely matching raw pulse frames. Unsupported
or ambiguous signals are ignored; it cannot identify arbitrary unlearned codes.
Holding a remote button or receiving its frame on several receivers counts once.
Tower transmissions and teaching are suppressed; observations during a locked
power operation can be ignored. Reception continues between actions and during
ordinary action delays. This is estimated state, not device
feedback. Misheard, blocked, or unrecognized presses require manual correction.

The retained observation engine can infer common effects from learned command
names. Its editor is hidden in v0.11.13 because these mappings are groundwork for
future sensor-backed detection, not a reliable source for operational decisions:
- Source: for example `CBL-SAT` for Denon's CBL-SAT command.
- Channel: `1` for a complete channel selection; `digit:1` for keypad 1.
  Consecutive keypad digits within two seconds are combined into a channel.
- Channel up/down: `+1` / `-1`; these require a known numeric channel and cannot
  account for skipped/unavailable channels or provider-specific wraparound.
- Volume: `+1` or `-1` records relative button steps because IR has no feedback
  for the absolute dB value. `toggle` records a toggle whose initial state may
  remain unknown.
- Blank leaves the configuration unchanged.

Use Refresh in Devices to see new observations. Its Last command and Observed via
columns distinguish physical remote presses from commands sent by Tower.

## RF mains links

The retained RF-to-IR link model can associate one RF outlet with one IR
appliance and record a passive estimate after mains power changes. Its editor is
hidden in v0.11.13.

After a successful RF OFF, Tower records the linked IR appliance as OFF because
it has no mains power. After RF ON, Tower applies the selected startup state.
This is a state relationship only: it deliberately sends no additional IR
command, preventing an automatic startup from being toggled straight back off.
This relationship never skips or changes a later action. Schedules that require
an IR action should keep RF power first and then use an explicit ON or OFF action.

## Windows scripts

Choose Windows - PowerShell in Scripts and enter the target as `computer|domain\user`
(the app supplies the current PC/user for new scripts). Installing or repairing
Tower Control automatically registers and starts its highest-privilege per-user
worker. It runs separately from Tower Control, using that user's existing
AppData/Tower/client.json connection settings. Windows must be on and that user
logged in; the desktop can be locked. Removing Windows startup integration also
removes all script-worker tasks.

Windows actions are queued asynchronously: later actions in a Tower sequence do
not wait for Windows completion. Run status shows queued/running/completed/failed,
expired, or unknown. An unclaimed job expires after 60 seconds. Claimed jobs are
never automatically executed again; if the worker dies the result becomes Unknown.
Changing/deleting a saved script does not change a job already queued with its body.
The worker records an explicit child-script exit result, so a successfully executed
PowerShell job is not incorrectly reported as `failed (exit )`.

PowerShell scripts run elevated, default to terminating errors, and use the saved
timeout (1-120 seconds). Each definition selects a visible or hidden PowerShell
window; existing definitions default to visible. Timeout stops the script process; applications
it already launched may remain open. Output is bounded and truncated for display.
For example, save `Start-Process notepad.exe` to open Notepad in that user's desktop.
Upgrading or using Settings > Install / Repair automatically replaces an older
limited worker. No separate worker button or per-start action is required.
Pi Bash and Wake-on-LAN behavior remains available in the same type selector.

## Existing morning routines

With both services stopped, run `python3 tools/enable-device-state.py` once.
It backs up changed files with `.before-state-<timestamp>` suffixes and converts:

- **Zone → Set Two:** send the complete KPN, Dell 1610HD and Denon ON sequences.
  The KPN channel 1 and Denon CBL-SAT commands retain their order and delays.
- **Zone → Set Three:** send the complete Dell, Denon and KPN OFF sequences.
  Dell uses two Power sends with a two-second pause, as one operation.

The migration preserves schedules, IDs, aliases, other voice commands, and
recorded estimates on repeated runs. Both schedules and programmable remote
buttons reference these voice paths and therefore always run every action.
Your 07:30/08:19 schedule times remain unchanged.

Other voice routines remain custom raw actions until their actions are changed
to **Device power** in the Voice editor. RF commands and presets require an
explicit ON or OFF action. Legacy SMART programmable buttons are shown as
disabled in the Windows editor and should be converted before saving.

## Scripts and Wake-on-LAN

In Scripts, click New, enter a name, and choose:

- **Bash script:** edit shell text executed on the Pi as the Tower service user
  (normally beheerder). The editor uses a 15-second timeout. It shows completion,
  failure or timeout and up to 4 KiB of output. Scripts are finite jobs, not
  background daemons; remaining processes in the job's group are terminated.
- **Wake-on-LAN:** enter the PC's wired MAC address and a broadcast address
  (default `255.255.255.255`, UDP port 9). The PC must already support and have
  Wake-on-LAN enabled. Tower sends the magic packet three times and reports the
  MAC and broadcast destination. Sending packets does not confirm the PC is ON.

Save first, then choose **Saved script** as an action in Voice, Control schedules,
or programmable Remote buttons. Scripts are stored in `data/control/scripts.json`.
The authenticated Tower API protects their editing and execution. Bash scripts
have the service user's permissions and run on the Pi, not on Windows.
Use Tower's normal action types for IR/RF sequences; do not call Tower's HTTP API
from a script while Tower is waiting for that script to finish.

The saved-script selector prefixes entries with `[PI]`, `[WOL]`, or `[WIN]`, so
the same friendly name may be used for different execution types without making
the list ambiguous. A direct **Save to Tower** preserves the saved definition and
immediately prepares a new blank-name draft with the same fields. Enter a new
name to create a similar script; selecting a saved entry explicitly switches back
to editing that entry. While a script draft is dirty, the slide-away application
panel stays open even when the pointer moves away for keyboard input.

The same type prefixes are used in Home, Voice, Control, and programmable Remote
selectors. Those editors store the script's stable ID, so changing a displayed
name does not break an existing action.

Control schedules contain an ordered action list. One schedule may combine Voice
command sets, saved scripts, RF presets/devices, and learned IR commands. Use Add,
Update, Remove, Up, and Down before applying the schedule. **Clone** copies the
complete schedule under a new ID and keeps its trigger and every ordered action.

## Unsaved edits

A small red floppy disk blinks slowly on Save to Tower while editor changes are
pending. Successful saves clear it; failed saves leave it active. The indicators
cover Voice, schedules, remote buttons, device power profiles and scripts.

## Verification

`bash tests/run-state-tests.sh` runs hardware-free state, script and scheduler tests.
Covered cases: repeated and simultaneous requests always transmit, explicit
disabled-device blocking, passive estimate bookkeeping, shared voice execution,
script success/failure/timeout, and a Wake-on-LAN packet captured on loopback.
The Windows modules receive syntax checks; visual and physical testing must be
done on Windows/the Pi.
