# Tower Voice Control

Tower voice recognition runs as a separate optional systemd service. It owns
microphone capture and offline Vosk recognition, but it does not implement RF
or IR protocols. Recognized leaves call the authenticated Tower HTTP API.

## Runtime layout

- `voice/tower_voice.py` - constrained wake and recursive command recognition.
- `voice/run-voice.sh` - starts the project-local Python environment and reuses
  the API token from the running `rf-tower.service` process.
- `voice/setup-vosk.sh` - creates the venv and installs/copies the Vosk model.
- `data/voice/voice_commands.json` - audio, API and command-tree configuration.
- `systemd/rf-tower-voice.service` - independent, restartable voice service.
- `runtime/voice/` - generated venv/model storage; not committed to Git.

The tested PI3A hardware is a Logitech C930e USB microphone with ALSA capture
gain 50 and `vosk-model-small-en-us-0.15`. The short acknowledgement tone uses
the Raspberry Pi analogue output.

## Recognition flow

The idle recognizer is restricted to the wake phrase `tower`. After a match,
each command level gets a fresh Vosk grammar containing only the valid next
phrases. This makes the tree extensible without asking the small Pi to
transcribe unrestricted speech.

The wake phrase stays silent, so harmless false wakes caused by television or
music are unobtrusive. Every accepted command level beeps before continuing or
executing:

```text
Tower        -> silent wake
Power        -> beep
Preset three -> beep -> execute Preset 3 ON
```

Each level has its own timeout. `cancel` or `never mind`, an invalid phrase, or
a timeout executes nothing and returns safely to wake listening. Only final
Vosk results execute actions; partial results never do.

The JSON tree may be extended to deeper paths later, for example:

```text
Tower -> Remote -> Television -> Volume -> Up
Tower -> Climate -> Office -> Temperature -> 22
```

Tree nodes contain `children`, while leaves contain `actions`. Optional
`aliases` allow English-model alternatives for Dutch device names.

## RF presets are Tower-owned

RF Presets 1-3 are stored centrally by the main Tower service in:

```text
data/rf/presets.json
```

The voice configuration contains only the preset number and requested state.
It never contains a copied device list. A voice leaf calls:

```text
POST /api/v1/rf/preset
{"preset": 1, "action": "on"}
```

The main service resolves the current membership and transmits it. Therefore a
preset edited in Tower Control is immediately used by voice, even when the
Windows PC is later switched off. The voice service does not need restarting
after a preset edit.

Individual named RF targets still use `/api/v1/rf/group` with one device. This
keeps the current API behavior while the future Programs/Automation subsystem
is still being designed.

## Install and test

From the project root:

```bash
bash voice/setup-vosk.sh
bash voice/run-voice.sh --dry-run
```

Dry-run performs recognition and prints actions without transmitting. Live
mode is configured in `voice_commands.json`; the systemd launcher obtains the
same `TOWER_API_TOKEN` already used by `rf-tower.service`.

Install or update the persistent listener:

```bash
sudo install -m 0644 systemd/rf-tower-voice.service /etc/systemd/system/rf-tower-voice.service
sudo systemctl daemon-reload
sudo systemctl enable --now rf-tower-voice.service
```

Useful diagnostics:

```bash
sudo systemctl --no-pager --full status rf-tower-voice.service
sudo journalctl --no-pager -u rf-tower-voice.service -n 100
```

The voice service is intentionally separate from `rf-tower.service`: audio or
Vosk can restart independently without interrupting RF, IR, sensors, or the
main API.

## Windows Voice editor and Tower API

Tower Control includes a `Voice` tab backed by the authenticated endpoints:

- `GET/POST /api/v1/voice/config` loads and atomically saves the authoritative
  `data/voice/voice_commands.json` file. The previous file is retained as
  `voice_commands.json.bak`.
- `GET /api/v1/voice/catalog` returns the current RF devices, RF Presets 1-3,
  IR devices and only the commands belonging to each selected IR device.
- `GET /api/v1/voice/status` reads the listener's small runtime status file.
- `POST /api/v1/voice/notification` queues a five-second LCD confirmation.

The editor presents the recursive command tree from the wake phrase downward.
Every level can be a branch, RF preset leaf, individual RF-device leaf, or IR
command leaf. Phrase aliases are edited independently from the action target.
Each leaf contains an ordered action list and may combine RF presets,
individual RF devices, and IR commands. The `Test action` button executes the
complete list without requiring speech. Every action can have a `Delay before`
value from 0 to 300 seconds. The sequence pauses before that specific action;
zero means immediate execution. Existing actions without this value remain
instant. These Pi-owned action lists are also
intended as the reusable command sets for the future scheduler/control tab.
IR command leaves also store one or more Tower IR outputs. The editor initially
uses the active output selection from the IR Remotes tab, then saves that
selection with the Pi-owned voice action so spoken execution uses the same
physical transmitter path when the Windows application is offline.

Saving validates the entire tree on the Pi and replaces the JSON atomically.
The voice process watches the file modification time while listening and
reloads valid command-tree and wake-phrase changes without a systemd restart.
Changes to microphone, sample rate, or Vosk model still require a service
restart because they change open audio/model resources.

After a spoken leaf executes, the voice process reports the canonical command
path, resolved targets, commands, and success state to Tower. The LCD backlight
activates for five seconds. It shows the voice path plus the actual remote or
RF target and command; multi-action leaves rotate through their actions once
per second. The normal environmental display then resumes.

## Current command branches

- `Tower -> Power -> Preset one/two/three`
- `Tower -> Shutdown -> Preset one/two/three`
- `Tower -> Power/Shutdown -> zoutlamp, cat, links, rechts, logitech, buro`
- Existing one-stage AVR commands remain compatible (`volume up`,
  `volume down`, and `receiver power`).

The English Vosk model may recognize `salt lamp`, `left`, `right`, or `desk`
more reliably than their Dutch aliases. Both forms are configured so field
testing can determine which phrases should remain.
