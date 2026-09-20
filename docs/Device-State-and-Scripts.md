# Device state and scripts — v0.11.08

## Devices

Tower stores estimated ON/OFF/Unknown state in `data/control/device_states.json`.
The Devices tab lists IR and RF devices, the last update, and its source.

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

Normal IR Remote commands still transmit on every press. Configured power
commands update the shared estimate; other commands leave it unchanged. Dell's
raw confirmation-style Power presses leave its state Unknown: use the managed
Turn On/Turn Off actions or converted voice routines for tracked Dell power.
Low-level CLI raw sends and shell scripts are not automatically interpreted as
device-state changes.

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

`bash tests/run-state-tests.sh` runs hardware-free state and script tests.
Covered cases: repeated and simultaneous shutdown, partial device state,
interrupted Dell shutdown, raw toggle tracking, shared voice-path execution,
script success/failure/timeout, and a Wake-on-LAN packet captured on loopback.
The Windows modules receive syntax checks; visual and physical testing must be
done on Windows/the Pi.
