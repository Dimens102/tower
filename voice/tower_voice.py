#!/usr/bin/env python3
"""Tower local voice-input process.

Speech recognition stays separate from Tower's command execution engine.
This process uses unrestricted speech recognition while waiting for an exact
wake phrase, then switches to a constrained command vocabulary before submitting
logical device/command actions to Tower's authenticated HTTP API.
"""

from __future__ import annotations

import argparse
import array
from contextlib import contextmanager
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.error
import urllib.request

import pyaudio
from vosk import KaldiRecognizer, Model, SetLogLevel


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = PROJECT_ROOT / "data" / "voice" / "voice_commands.json"


def load_config(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        config = json.load(handle)

    required = ["wake_phrase", "microphone_name_contains", "model_path", "commands"]
    missing = [name for name in required if name not in config]
    if missing:
        raise ValueError("Missing voice config field(s): " + ", ".join(missing))
    if not isinstance(config["commands"], dict) or not config["commands"]:
        raise ValueError("Voice config must contain at least one command phrase")
    return config


def resolve_project_path(value: str) -> Path:
    expanded = os.path.expandvars(os.path.expanduser(value))
    path = Path(expanded)
    if not path.is_absolute():
        path = PROJECT_ROOT / path
    return path.resolve()


@contextmanager
def suppress_native_stderr():
    """Temporarily silence native-library stderr output.

    PortAudio/ALSA probes optional PCM/JACK backends while PyAudio starts. On
    Raspberry Pi this can print harmless warnings for devices/services that are
    not configured. Limit suppression to PyAudio initialization so real runtime
    audio errors remain visible.
    """
    sys.stderr.flush()
    saved_stderr = os.dup(2)
    try:
        with open(os.devnull, "w", encoding="utf-8") as devnull:
            os.dup2(devnull.fileno(), 2)
            yield
    finally:
        os.dup2(saved_stderr, 2)
        os.close(saved_stderr)
        sys.stderr.flush()


def set_capture_gain(config: dict) -> None:
    audio = config.get("audio", {})
    alsa_card = str(audio.get("alsa_card", "")).strip()
    control = str(audio.get("capture_control", "Mic")).strip()
    gain = audio.get("capture_gain")
    if not alsa_card or gain is None:
        return

    command = ["amixer", "-q", "-c", alsa_card, "sset", control, str(gain)]
    try:
        subprocess.run(command, check=True)
        print(f"Voice audio: {control} capture gain set to {gain} on ALSA card {alsa_card}")
    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
        print(f"Voice audio warning: could not apply capture gain ({exc})", file=sys.stderr)


def find_pyaudio_device(audio: pyaudio.PyAudio, name_contains: str, *, input_device: bool) -> int:
    needle = name_contains.casefold()
    matches: list[tuple[int, str]] = []

    for index in range(audio.get_device_count()):
        info = audio.get_device_info_by_index(index)
        channels = int(info.get("maxInputChannels" if input_device else "maxOutputChannels", 0))
        name = str(info.get("name", ""))
        if channels > 0 and needle in name.casefold():
            matches.append((index, name))

    if not matches:
        direction = "input" if input_device else "output"
        available: list[str] = []
        for index in range(audio.get_device_count()):
            info = audio.get_device_info_by_index(index)
            channels = int(info.get("maxInputChannels" if input_device else "maxOutputChannels", 0))
            if channels > 0:
                available.append(str(info.get("name", "")))
        raise RuntimeError(
            f"No {direction} audio device contains '{name_contains}'. "
            f"Available: {', '.join(available) if available else 'none'}"
        )

    # Prefer the most specific hardware-style name when ALSA exposes duplicates.
    matches.sort(key=lambda item: ("hw:" not in item[1].casefold(), item[0]))
    return matches[0][0]


def make_open_recognizer(model: Model, sample_rate: int) -> KaldiRecognizer:
    """Create an unrestricted recognizer for wake-phrase listening.

    The wake stage deliberately uses the full language model instead of forcing
    ordinary room speech into a tiny grammar containing only the wake phrase.
    Only an exact final transcription of the configured wake phrase is accepted.
    """
    recognizer = KaldiRecognizer(model, sample_rate)
    recognizer.SetWords(True)
    return recognizer


def make_recognizer(model: Model, sample_rate: int, phrases: list[str], include_unknown: bool = True) -> KaldiRecognizer:
    grammar = list(dict.fromkeys(phrase.strip().lower() for phrase in phrases if phrase.strip()))
    if include_unknown and "[unk]" not in grammar:
        grammar.append("[unk]")
    recognizer = KaldiRecognizer(model, sample_rate, json.dumps(grammar))
    recognizer.SetWords(True)
    return recognizer


def recognition_result(recognizer: KaldiRecognizer) -> tuple[str, float]:
    payload = json.loads(recognizer.Result())
    text = str(payload.get("text", "")).strip().lower()
    words = payload.get("result", [])
    confidences = [float(word.get("conf", 0.0)) for word in words if word.get("word") != "[unk]"]
    confidence = sum(confidences) / len(confidences) if confidences else 0.0
    return text, confidence


def play_beep(audio: pyaudio.PyAudio, output_index: int | None, config: dict) -> None:
    beep = config.get("beep", {})
    if not beep.get("enabled", True):
        return

    rate = int(beep.get("sample_rate", 16000))
    frequency = float(beep.get("frequency_hz", 880.0))
    duration_ms = float(beep.get("duration_ms", 90.0))
    volume = max(0.0, min(1.0, float(beep.get("volume", 0.18))))
    frame_count = max(1, int(rate * duration_ms / 1000.0))

    mono_samples = [
        int(32767 * volume * math.sin(2.0 * math.pi * frequency * frame / rate))
        for frame in range(frame_count)
    ]
    # The Raspberry Pi analogue output is stereo. Duplicate the tone to both
    # channels rather than relying on the hardware device to accept mono.
    samples = array.array("h", (sample for value in mono_samples for sample in (value, value)))

    stream = audio.open(
        format=pyaudio.paInt16,
        channels=2,
        rate=rate,
        output=True,
        output_device_index=output_index,
    )
    try:
        stream.write(samples.tobytes())
    finally:
        stream.stop_stream()
        stream.close()


def post_tower_action(config: dict, action: dict, token: str) -> tuple[bool, str]:
    api = config.get("api", {})
    url = str(api.get("execute_url", "http://127.0.0.1:8080/api/v1/execute"))
    payload = {
        "device": str(action["device"]),
        "command": str(action["command"]),
    }
    if action.get("transmitter"):
        payload["transmitter"] = str(action["transmitter"])
    if action.get("transmitters"):
        payload["transmitters"] = list(action["transmitters"])

    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=float(api.get("timeout_seconds", 4.0))) as response:
            body = json.loads(response.read().decode("utf-8"))
            return bool(body.get("ok", False)), str(body.get("message", "Tower API completed"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        return False, f"HTTP {exc.code}: {body}"
    except (urllib.error.URLError, TimeoutError) as exc:
        return False, f"Tower API connection failed: {exc}"


def execute_phrase(config: dict, phrase: str, token: str, dry_run: bool) -> bool:
    actions = config["commands"].get(phrase)
    if actions is None:
        return False
    if not isinstance(actions, list):
        raise ValueError(f"Voice command '{phrase}' must contain an action list")

    print(f"Voice command: {phrase}")
    if not actions:
        print("  No actions configured")
        return True

    for number, action in enumerate(actions, start=1):
        if not isinstance(action, dict) or "device" not in action or "command" not in action:
            raise ValueError(f"Invalid action #{number} for voice command '{phrase}'")
        repeat = max(1, int(action.get("repeat", 1)))
        delay_ms = max(0, int(action.get("delay_ms", 0)))

        for repetition in range(repeat):
            device = str(action["device"])
            command = str(action["command"])
            if dry_run:
                suffix = f" ({repetition + 1}/{repeat})" if repeat > 1 else ""
                print(f"  DRY RUN -> {device} :: {command}{suffix}")
            else:
                ok, message = post_tower_action(config, action, token)
                status = "OK" if ok else "FAILED"
                print(f"  {status} -> {device} :: {command} -- {message}")
                if not ok:
                    return False
            if delay_ms and (repetition + 1 < repeat or number < len(actions)):
                time.sleep(delay_ms / 1000.0)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Tower offline Vosk voice command listener")
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--dry-run", action="store_true", help="recognize commands but never call Tower API")
    parser.add_argument("--live", action="store_true", help="override config dry_run and allow Tower API execution")
    parser.add_argument("--list-devices", action="store_true", help="list PyAudio devices and exit")
    args = parser.parse_args()

    if args.dry_run and args.live:
        parser.error("--dry-run and --live cannot be used together")

    config = load_config(args.config.resolve())
    SetLogLevel(int(config.get("vosk_log_level", -1)))
    set_capture_gain(config)

    # PortAudio probes several optional ALSA/JACK endpoints during startup.
    # Silence only that native probe chatter; actual device/open errors below
    # are intentionally left visible.
    with suppress_native_stderr():
        audio = pyaudio.PyAudio()
    try:
        if args.list_devices:
            for index in range(audio.get_device_count()):
                info = audio.get_device_info_by_index(index)
                print(
                    f"{index:2d}: in={int(info.get('maxInputChannels', 0))} "
                    f"out={int(info.get('maxOutputChannels', 0))} "
                    f"{info.get('name', '')}"
                )
            return 0

        microphone_name = str(config["microphone_name_contains"])
        input_index = find_pyaudio_device(audio, microphone_name, input_device=True)
        input_info = audio.get_device_info_by_index(input_index)

        output_index: int | None = None
        output_match = str(config.get("speaker_name_contains", "")).strip()
        if output_match:
            try:
                output_index = find_pyaudio_device(audio, output_match, input_device=False)
            except RuntimeError as exc:
                print(f"Voice audio warning: {exc}; using default playback device", file=sys.stderr)

        model_path = resolve_project_path(str(config["model_path"]))
        if not model_path.is_dir():
            print(
                f"Voice model not found: {model_path}\n"
                "Run ./voice/setup-vosk.sh first.",
                file=sys.stderr,
            )
            return 2

        print(f"Voice microphone: {input_info.get('name', microphone_name)}")
        print(f"Voice model: {model_path}")

        sample_rate = int(config.get("sample_rate", 16000))
        chunk_size = int(config.get("chunk_size", 4000))
        wake_phrase = str(config["wake_phrase"]).strip().lower()
        cancel_phrases = [str(value).strip().lower() for value in config.get("cancel_phrases", ["never mind", "cancel"])]
        command_phrases = [str(phrase).strip().lower() for phrase in config["commands"].keys()]
        min_confidence = float(config.get("minimum_command_confidence", 0.0))
        command_timeout = float(config.get("command_timeout_seconds", 5.0))

        model = Model(str(model_path))
        wake_recognizer = make_open_recognizer(model, sample_rate)

        stream = audio.open(
            format=pyaudio.paInt16,
            channels=1,
            rate=sample_rate,
            input=True,
            input_device_index=input_index,
            frames_per_buffer=chunk_size,
        )

        config_dry_run = bool(config.get("dry_run", True))
        dry_run = True if args.dry_run else False if args.live else config_dry_run
        api = config.get("api", {})
        token_env = str(api.get("token_env", "TOWER_API_TOKEN"))
        token = os.environ.get(token_env, "")
        if not dry_run and not token:
            print(
                f"Voice listener is LIVE but {token_env} is not set. "
                "Use --dry-run or export the Tower API token.",
                file=sys.stderr,
            )
            stream.close()
            return 2

        print(f"Voice mode: {'DRY RUN' if dry_run else 'LIVE'}")
        print(f"Listening for wake phrase: {wake_phrase!r}")

        try:
            while True:
                data = stream.read(chunk_size, exception_on_overflow=False)
                if not wake_recognizer.AcceptWaveform(data):
                    continue

                text, confidence = recognition_result(wake_recognizer)
                if text != wake_phrase:
                    continue

                print(f"Wake detected: {wake_phrase} (confidence {confidence:.2f})")

                # Pause capture while the acknowledgement tone plays so the tone
                # cannot become part of the command recognizer's input.
                stream.stop_stream()
                play_beep(audio, output_index, config)
                stream.start_stream()

                command_recognizer = make_recognizer(
                    model,
                    sample_rate,
                    command_phrases + cancel_phrases,
                )
                deadline = time.monotonic() + command_timeout
                handled = False

                while time.monotonic() < deadline:
                    command_data = stream.read(chunk_size, exception_on_overflow=False)
                    if not command_recognizer.AcceptWaveform(command_data):
                        continue

                    command_text, command_confidence = recognition_result(command_recognizer)
                    if not command_text or command_text == "[unk]":
                        continue

                    print(f"Heard: {command_text!r} (confidence {command_confidence:.2f})")
                    if command_text in cancel_phrases:
                        print("Voice command cancelled")
                        handled = True
                        break
                    if command_text not in config["commands"]:
                        continue
                    if command_confidence < min_confidence:
                        print(
                            f"Ignored low-confidence command ({command_confidence:.2f} < {min_confidence:.2f})"
                        )
                        handled = True
                        break

                    execute_phrase(config, command_text, token, dry_run)
                    handled = True
                    break

                if not handled:
                    print("Voice command timed out")

                # Use a fresh recognizer so command-state audio never leaks back
                # into wake-word recognition.
                wake_recognizer = make_open_recognizer(model, sample_rate)
                print(f"Listening for wake phrase: {wake_phrase!r}")

        except KeyboardInterrupt:
            print("\nVoice listener stopped")
        finally:
            stream.stop_stream()
            stream.close()

    finally:
        audio.terminate()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
