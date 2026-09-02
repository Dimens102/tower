# Tower Voice Control

Tower voice recognition is intentionally a separate input process. It does not
contain IR or RF protocol logic. Recognized phrases are mapped to logical Tower
device/command IDs and submitted through the authenticated `/api/v1/execute`
endpoint, the same command-execution path used by network clients.

## Current laboratory hardware

The current PI3A test setup uses:

- Logitech C930e USB microphone (`C930e` ALSA/PyAudio device).
- C930e `Mic Capture Volume` set to `50/60`; the test recording peaked near
  `-15.5 dBFS` and was clear at roughly one metre.
- Raspberry Pi analogue headphone output for the short wake acknowledgement
  tone.
- Vosk small English model `vosk-model-small-en-us-0.15`.

A Kinect v1 microphone array was tested first. Linux exposed its four raw
16 kHz channels after loading the Kinect UAC firmware, but all four channels
were approximately `-34 dBFS` peak / `-56 to -58 dBFS` RMS at the same desk
position and did not provide the processed Xbox/Windows voice experience. The
C930e is therefore the current voice input.

## Files

- `voice/tower_voice.py` - unrestricted wake-phrase listening, constrained command
  recognition, beep, and Tower API submission.
- `voice/setup-vosk.sh` - creates the project-local Python venv and copies the
  tested Vosk model from the IR lab into Tower runtime storage.
- `voice/run-voice.sh` - launcher for the project-local venv.
- `data/voice/voice_commands.json` - microphone, wake phrase, confidence,
  audio gain, API, and phrase/action mappings.
- `runtime/voice/models/` and `runtime/voice/venv/` - local generated runtime
  data; intentionally ignored by Git.

## Install the project-local runtime

The earlier lab test is expected at:

```text
~/Development/ir-lab/vosk/SpeechRecognition
```

From the Tower project root:

```bash
bash voice/setup-vosk.sh
```

The setup script creates `runtime/voice/venv`, installs Vosk into it, and copies
`vosk-model-small-en-us-0.15` from the lab into `runtime/voice/models`.

## Dry-run test

The default configuration has `"dry_run": true`. No IR/RF commands are sent.

```bash
bash voice/run-voice.sh --dry-run
```

Expected flow:

```text
Listening for wake phrase: 'radio tower'
        |
        +-- normal room speech is transcribed with the full Vosk language model
        |   and ignored unless the final result is exactly "radio tower"
        |
        +-- user says "Radio Tower"
        |
        +-- short acknowledgement beep
        |
        +-- listener accepts one phrase from the configured command grammar
        |
        +-- DRY RUN prints the mapped logical Tower action(s)
        |
        +-- returns to unrestricted wake-phrase listening
```

While idle, Vosk uses the full English model and accepts only an exact final
transcription of the two-word wake phrase `radio tower`. This avoids forcing
unrelated TV or room speech into a wake-only grammar. After the wake phrase is
accepted, the listener switches to the small constrained command grammar.

Only final Vosk results are eligible for execution. Partial results never
execute a Tower command. `[unk]`, unconfigured phrases, and command timeouts
execute nothing. The listener prints Vosk confidence for each accepted final
phrase; the initial configuration leaves the confidence floor at `0.0` until
the microphone is installed in the Tower's final location and real command
samples can be measured.

## Live execution

Live mode uses the authenticated local Tower API. Export the same token used by
`rf-tower.service`, then override dry-run mode:

```bash
export TOWER_API_TOKEN='your-existing-private-token'
bash voice/run-voice.sh --live
```

The listener POSTs logical `device` and `command` values to:

```text
http://127.0.0.1:8080/api/v1/execute
```

A voice phrase may contain multiple ordered actions. Each action may optionally
specify `repeat` and `delay_ms`, so the voice layer can represent simple chains
without duplicating any IR/RF implementation. Longer-term Tower-owned Programs
should replace voice-local chains when the Programs/Automation subsystem is
implemented.

## Initial mappings

The default file contains working logical mappings for AVR volume up/down and a
receiver power toggle. `watch television` is deliberately present with an empty
action list until its exact desired sequence is defined; Tower must not guess a
home-automation sequence.

The current AVR profile exposes a single `Power` toggle rather than distinct
Power On and Power Off commands, so voice phrases should not pretend that toggle
is deterministic on/off control.

## Audio startup logging

PyAudio/PortAudio probes optional ALSA PCM and JACK backends when it starts. On
the Pi this can otherwise print harmless `Unknown PCM` and `jack server is not
running` messages even when the configured C930e microphone works normally.
Tower suppresses stderr only during that initial backend probe; later audio
device/open errors remain visible.
