# Device state and scripts — v0.11.11

## Devices

Tower stores estimated configuration in `data/control/device_states.json`.
The Devices tab combines the properties known for each device into one Current
configuration column, followed by the last update and its source. Properties are
dynamic: a Denon can show Power, Source, Volume, Mute or Sound mode while a KPN
box may show Power and Channel.

- **Mark On / Mark Off / Mark Unknown** correct the record without transmitting.
- **Turn On / Turn Off** request a state and skip a device already in that state.
- Configure IR power commands, shutdown press count/delay, and IR outputs in the
  lower panel. Save to Tower stores this device's power commands, OFF sequence,
  and IR outputs. It sends no signal and preserves the recorded state.
  Mark On/Off/Unknown saves immediately and needs no separate Save click.
- Select “Separate ON and OFF signals” only for genuinely separate codes. A
  command merely labelled “Power On” may still be a toggle.

An acknowledged transmission is not feedback from the appliance. A blocked IR
beam, another handset, mains switch, or device's own timer can change the actual
state without Tower knowing. Correct the estimate when this happens.

Toggle-based requests stop with an explanation if state is Unknown. Separate
ON/OFF codes can establish state from Unknown. Operations write Unknown before
transmission, then the estimated result after success, using atomic, synced
writes. Interrupted/failed operations stay Unknown. Requests in the Tower
service are serialized, including a device's entire power sequence.

Normal IR Remote commands still transmit on every press unless the device is
disabled. Configured power commands update the shared estimate. Learned commands
can update arbitrary named properties. A two-press shutdown profile
using the same Power command tracks OFF-to-ON with one press, and ON-to-OFF after
the second press near the configured delay. Unknown remains Unknown until corrected.
Low-level CLI raw sends and shell scripts are not automatically interpreted as
device-state changes.

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

In Devices > Command effects, Tower pre-fills common effects inferred from the
learned command names. Correct or add a property and resulting value when a
device uses different wording:
- Source: for example `CBL-SAT` for Denon's CBL-SAT command.
- Channel: `1` for a complete channel selection; `digit:1` for keypad 1.
  Consecutive keypad digits within two seconds are combined into a channel.
- Channel up/down: `+1` / `-1`; these require a known numeric channel and cannot
  account for skipped/unavailable channels or provider-specific wraparound.
- Volume: `+1` or `-1` records relative button steps because IR has no feedback
  for the absolute dB value. `toggle` records a toggle whose initial state may
  remain unknown.
- Blank leaves the configuration unchanged. Save stores mappings without sending IR.

Use Refresh in Devices to see new observations. Its Last command and Observed via
columns distinguish physical remote presses from commands sent by Tower.

## RF mains links

Select an RF power device and open **RF to IR link**. One RF outlet can own one
IR appliance. Select the IR device and describe its hardware state after mains
power returns: ON automatically, OFF automatically, or Unknown/varies.

After a successful RF OFF, Tower records the linked IR appliance as OFF because
it has no mains power. After RF ON, Tower applies the selected startup state.
This is a state relationship only: it deliberately sends no additional IR
command, preventing an automatic startup from being toggled straight back off.
Schedules that require an additional IR action should keep RF power first and
then request the desired IR state explicitly.

## Windows scripts

Choose Windows - PowerShell in Scripts and enter the target as `computer|domain\user`
(the app supplies the current PC/user for new scripts). Reinstall the Windows app
before using Enable Windows worker. This registers a limited-privilege per-user
logon task and starts it. It runs separately from Tower Control, using that user's
existing AppData/Tower/client.json connection settings. Windows must be on and
that user logged in; the desktop can be locked. Disable Windows worker removes
the task. Removing Windows startup integration also removes all script-worker tasks.

Windows actions are queued asynchronously: later actions in a Tower sequence do
not wait for Windows completion. Run status shows queued/running/completed/failed,
expired, or unknown. An unclaimed job expires after 60 seconds. Claimed jobs are
never automatically executed again; if the worker dies the result becomes Unknown.
Changing/deleting a saved script does not change a job already queued with its body.

PowerShell scripts run without elevation, default to terminating errors, and use
the saved timeout (1-120 seconds). Timeout stops the script process; applications
it already launched may remain open. Output is bounded and truncated for display.
For example, save `Start-Process notepad.exe` to open Notepad in that user's desktop.
Pi Bash and Wake-on-LAN behavior remains available in the same type selector.

## Existing morning routines

With both services stopped, run `python3 tools/enable-device-state.py` once.
It backs up changed files with `.before-state-<timestamp>` suffixes and converts:

- **Zone → Set Two:** request KPN, Dell 1610HD and Denon ON. The KPN channel 1
  and Denon CBL-SAT commands retain their order and delays. Those non-power
  commands still run when their devices were already ON.
- **Zone → Set Three:** request Dell, Denon and KPN OFF. Dell uses two Power
  sends with a two-second pause, as one operation. Devices already OFF are skipped.

The migration preserves schedules, IDs, aliases, other voice commands, and
recorded states on repeated runs. Both schedules and programmable remote buttons
already reference these voice paths and therefore receive the new behavior.
Your 07:30/08:19 schedule times remain unchanged.

Before first use, mark the actual starting states of those three devices in
Devices. New devices remain Unknown until corrected or controlled using a
configured, separate ON/OFF code. Other voice routines remain custom raw actions
until their actions are changed to **Device power** in the Voice editor.

RF commands share the same persistent state. RF preset SMART chooses OFF when
all members are recorded ON; otherwise it chooses ON. A preset requests that
state per member, allowing individual RF commands and manual corrections to
remain consistent with the preset.

## Scripts and Wake-on-LAN

In Scripts, click New, enter a name, and choose:

- **Bash script:** edit shell text executed on the Pi as the Tower service user
  (normally beheerder). The editor uses a 15-second timeout. It shows completion,
  failure or timeout and up to 4 KiB of output. Scripts are finite jobs, not
  background daemons; remaining processes in the job's group are terminated.
- **Wake-on-LAN:** enter the PC's wired MAC address and a broadcast address
  (default `255.255.255.255`, UDP port 9). The PC must already support and have
  Wake-on-LAN enabled. Sending a packet does not mark the PC as confirmed ON.

Save first, then choose **Saved script** as an action in Voice, Control schedules,
or programmable Remote buttons. Scripts are stored in `data/control/scripts.json`.
The authenticated Tower API protects their editing and execution. Bash scripts
have the service user's permissions and run on the Pi, not on Windows.
Use Tower's normal action types for IR/RF sequences; do not call Tower's HTTP API
from a script while Tower is waiting for that script to finish.

## Unsaved edits

A small red floppy disk blinks slowly on Save to Tower while editor changes are
pending. Successful saves clear it; failed saves leave it active. The indicators
cover Voice, schedules, remote buttons, device power profiles and scripts.

## Verification

`bash tests/run-state-tests.sh` runs hardware-free state, script and scheduler tests.
Covered cases: repeated and simultaneous shutdown, partial device state,
interrupted Dell shutdown, raw toggle tracking, shared voice-path execution,
script success/failure/timeout, and a Wake-on-LAN packet captured on loopback.
The Windows modules receive syntax checks; visual and physical testing must be
done on Windows/the Pi.
