#!/usr/bin/env python3
"""Tower local voice-input process.

Speech recognition stays separate from Tower's command execution engine.
This process uses a constrained wake-word recognizer, then switches to a
constrained command vocabulary before submitting logical device/command actions
to Tower's authenticated HTTP API.
"""

from __future__ import annotations

import argparse
import array
from contextlib import contextmanager
from datetime import datetime, timezone
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
DEFAULT_STATUS = PROJECT_ROOT / "runtime" / "voice" / "status.json"


def load_config(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        config = json.load(handle)

    required = ["wake_phrase", "microphone_name_contains", "model_path"]
    missing = [name for name in required if name not in config]
    if missing:
        raise ValueError("Missing voice config field(s): " + ", ".join(missing))
    commands = config.get("commands", {})
    command_tree = config.get("command_tree", {})
    if not isinstance(commands, dict) or not isinstance(command_tree, dict):
        raise ValueError("Voice commands and command_tree must be objects")
    if not commands and not command_tree:
        raise ValueError("Voice config must contain commands or a command_tree")
    return config


def resolve_project_path(value: str) -> Path:
    expanded = os.path.expandvars(os.path.expanduser(value))
    path = Path(expanded)
    if not path.is_absolute():
        path = PROJECT_ROOT / path
    return path.resolve()


def write_voice_status(
    config: dict,
    state: str,
    message: str,
    *,
    command_path: list[str] | None = None,
    ok: bool | None = None,
) -> None:
    status_value = str(config.get("status_path", DEFAULT_STATUS))
    status_path = resolve_project_path(status_value)
    temporary = status_path.with_suffix(status_path.suffix + ".tmp")
    payload: dict[str, object] = {
        "state": state,
        "message": message,
        "updatedUtc": datetime.now(timezone.utc).isoformat(),
    }
    if command_path is not None:
        payload["path"] = command_path
    if ok is not None:
        payload["ok"] = ok

    try:
        status_path.parent.mkdir(parents=True, exist_ok=True)
        temporary.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        temporary.replace(status_path)
    except OSError as exc:
        print(f"Voice status warning: {exc}", file=sys.stderr)


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


def make_wake_recognizer(model: Model, sample_rate: int, wake_phrase: str) -> KaldiRecognizer:
    """Create a recognizer restricted to the configured wake phrase.

    The command stage already benefits from a constrained grammar. Applying the
    same approach here prevents the full English model from turning a clear
    single-word wake phrase into similar words such as "power" or "our".
    """
    grammar = [wake_phrase.strip().lower(), "[unk]"]
    recognizer = KaldiRecognizer(model, sample_rate, json.dumps(grammar))
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


def post_json_action(config: dict, url: str, payload: dict, token: str) -> tuple[bool, str]:
    api = config.get("api", {})
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
    return post_json_action(config, url, payload, token)


def post_rf_group_action(config: dict, action: dict, token: str) -> tuple[bool, str]:
    api = config.get("api", {})
    url = str(api.get("rf_group_url", "http://127.0.0.1:8080/api/v1/rf/group"))
    payload = {
        "action": str(action["action"]),
        "devices": [str(device) for device in action["devices"]],
    }
    return post_json_action(config, url, payload, token)


def post_rf_preset_action(config: dict, action: dict, token: str) -> tuple[bool, str]:
    api = config.get("api", {})
    url = str(api.get("rf_preset_url", "http://127.0.0.1:8080/api/v1/rf/preset"))
    payload = {
        "preset": int(action["preset"]),
        "action": str(action["action"]),
    }
    return post_json_action(config, url, payload, token)


def post_voice_notification(
    config: dict,
    command_path: list[str],
    actions: list[dict[str, str]],
    ok: bool,
    token: str,
) -> None:
    api = config.get("api", {})
    url = str(
        api.get(
            "voice_notification_url",
            "http://127.0.0.1:8080/api/v1/voice/notification",
        )
    )
    notification_ok, message = post_json_action(
        config,
        url,
        {
            "path": command_path,
            "actions": actions,
            "ok": ok,
            "durationSeconds": 5,
        },
        token,
    )
    if not notification_ok:
        print(f"Voice display warning: {message}", file=sys.stderr)


def execute_actions(
    config: dict,
    command_path: list[str],
    actions: list,
    token: str,
    dry_run: bool,
) -> tuple[bool, list[dict[str, str]]]:
    phrase = " -> ".join(command_path)
    if not isinstance(actions, list):
        raise ValueError(f"Voice path '{phrase}' must contain an action list")

    print(f"Voice command: {phrase}")
    if not actions:
        print("  No actions configured")
        return True, []

    display_actions: list[dict[str, str]] = []

    for number, action in enumerate(actions, start=1):
        if not isinstance(action, dict):
            raise ValueError(f"Invalid action #{number} for voice command '{phrase}'")

        action_type = str(action.get("type", "command"))
        if action_type == "command":
            if "device" not in action or "command" not in action:
                raise ValueError(f"Invalid command action #{number} for voice command '{phrase}'")
            description = f"{action['device']} :: {action['command']}"
            display_actions.append({
                "target": str(action["device"]),
                "command": str(action["command"]),
            })
        elif action_type == "rf_group":
            devices = action.get("devices")
            group_action = str(action.get("action", ""))
            if group_action not in ("on", "off") or not isinstance(devices, list) or not devices:
                raise ValueError(f"Invalid RF group action #{number} for voice command '{phrase}'")
            group_name = str(action.get("name", "RF group"))
            description = f"{group_name} :: {group_action} ({len(devices)} devices)"
            display_actions.append({"target": group_name, "command": group_action})
        elif action_type == "rf_preset":
            preset = int(action.get("preset", 0))
            preset_action = str(action.get("action", ""))
            if preset not in (1, 2, 3) or preset_action not in ("on", "off"):
                raise ValueError(f"Invalid RF preset action #{number} for voice path '{phrase}'")
            description = f"Preset {preset} :: {preset_action} (Tower-managed)"
            display_actions.append({
                "target": f"Preset {preset}",
                "command": preset_action,
            })
        else:
            raise ValueError(f"Unsupported action type '{action_type}' for voice command '{phrase}'")

        delay_before_seconds = min(
            300, max(0, int(action.get("delay_before_seconds", 0)))
        )
        if delay_before_seconds:
            print(f"  Waiting {delay_before_seconds}s before action {number}")
            time.sleep(delay_before_seconds)

        repeat = max(1, int(action.get("repeat", 1)))
        delay_ms = max(0, int(action.get("delay_ms", 0)))

        for repetition in range(repeat):
            if dry_run:
                suffix = f" ({repetition + 1}/{repeat})" if repeat > 1 else ""
                print(f"  DRY RUN -> {description}{suffix}")
            else:
                if action_type == "rf_group":
                    ok, message = post_rf_group_action(config, action, token)
                elif action_type == "rf_preset":
                    ok, message = post_rf_preset_action(config, action, token)
                else:
                    ok, message = post_tower_action(config, action, token)
                status = "OK" if ok else "FAILED"
                print(f"  {status} -> {description} -- {message}")
                if not ok:
                    return False, display_actions
            if delay_ms and (repetition + 1 < repeat or number < len(actions)):
                time.sleep(delay_ms / 1000.0)
    return True, display_actions


def command_children(config: dict) -> dict[str, dict]:
    children: dict[str, dict] = {}
    for phrase, node in config.get("command_tree", {}).items():
        if not isinstance(node, dict):
            raise ValueError(f"Voice tree node '{phrase}' must be an object")
        children[str(phrase).strip().lower()] = node

    # Existing one-stage commands stay compatible. A tree branch with the same
    # phrase wins, allowing 'power' and 'shutdown' to gain another level.
    for phrase, actions in config.get("commands", {}).items():
        key = str(phrase).strip().lower()
        if key not in children:
            children[key] = {"actions": actions}
    return children


def phrase_map(children: dict[str, dict]) -> dict[str, tuple[str, dict]]:
    mapping: dict[str, tuple[str, dict]] = {}
    for phrase, node in children.items():
        spoken = [phrase]
        aliases = node.get("aliases", [])
        if not isinstance(aliases, list):
            raise ValueError(f"Aliases for '{phrase}' must be an array")
        spoken.extend(str(alias).strip().lower() for alias in aliases)
        for alias in spoken:
            if not alias:
                continue
            if alias in mapping:
                raise ValueError(f"Duplicate voice phrase or alias '{alias}'")
            mapping[alias] = (phrase, node)
    return mapping


def node_children(node: dict) -> dict[str, dict]:
    children = node.get("children", {})
    if not isinstance(children, dict):
        raise ValueError("Voice tree children must be an object")
    normalized: dict[str, dict] = {}
    for phrase, child in children.items():
        if not isinstance(child, dict):
            raise ValueError(f"Voice tree node '{phrase}' must be an object")
        normalized[str(phrase).strip().lower()] = child
    return normalized


def main() -> int:
    parser = argparse.ArgumentParser(description="Tower offline Vosk voice command listener")
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--dry-run", action="store_true", help="recognize commands but never call Tower API")
    parser.add_argument("--live", action="store_true", help="override config dry_run and allow Tower API execution")
    parser.add_argument("--list-devices", action="store_true", help="list PyAudio devices and exit")
    args = parser.parse_args()

    if args.dry_run and args.live:
        parser.error("--dry-run and --live cannot be used together")

    config_path = args.config.resolve()
    config = load_config(config_path)
    config_mtime_ns = config_path.stat().st_mtime_ns
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
        root_children = command_children(config)
        min_confidence = float(config.get("minimum_command_confidence", 0.0))
        command_timeout = float(config.get("command_timeout_seconds", 5.0))

        model = Model(str(model_path))
        wake_recognizer = make_wake_recognizer(model, sample_rate, wake_phrase)

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
        last_result_message = ""
        write_voice_status(
            config,
            "listening",
            f"Listening for wake phrase: {wake_phrase}",
        )

        try:
            while True:
                current_mtime_ns = config_path.stat().st_mtime_ns
                if current_mtime_ns != config_mtime_ns:
                    try:
                        updated_config = load_config(config_path)
                        updated_sample_rate = int(updated_config.get("sample_rate", 16000))
                        updated_model_path = resolve_project_path(str(updated_config["model_path"]))
                        updated_microphone = str(updated_config["microphone_name_contains"])
                        if (
                            updated_sample_rate != sample_rate
                            or updated_model_path != model_path
                            or updated_microphone != microphone_name
                        ):
                            raise ValueError(
                                "Audio device, sample rate, and model changes require a voice-service restart"
                            )

                        config = updated_config
                        wake_phrase = str(config["wake_phrase"]).strip().lower()
                        cancel_phrases = [
                            str(value).strip().lower()
                            for value in config.get("cancel_phrases", ["never mind", "cancel"])
                        ]
                        root_children = command_children(config)
                        min_confidence = float(config.get("minimum_command_confidence", 0.0))
                        command_timeout = float(config.get("command_timeout_seconds", 5.0))
                        config_dry_run = bool(config.get("dry_run", True))
                        dry_run = True if args.dry_run else False if args.live else config_dry_run
                        api = config.get("api", {})
                        token_env = str(api.get("token_env", "TOWER_API_TOKEN"))
                        token = os.environ.get(token_env, "")
                        if not dry_run and not token:
                            raise ValueError(f"{token_env} is not set")

                        wake_recognizer = make_wake_recognizer(
                            model,
                            sample_rate,
                            wake_phrase,
                        )
                        config_mtime_ns = current_mtime_ns
                        print("Voice configuration reloaded")
                        print(f"Listening for wake phrase: {wake_phrase!r}")
                        write_voice_status(
                            config,
                            "listening",
                            f"Configuration reloaded; listening for: {wake_phrase}",
                        )
                    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
                        config_mtime_ns = current_mtime_ns
                        print(f"Voice configuration reload failed: {exc}", file=sys.stderr)
                        write_voice_status(
                            config,
                            "error",
                            f"Configuration reload failed: {exc}",
                            ok=False,
                        )

                data = stream.read(chunk_size, exception_on_overflow=False)
                if not wake_recognizer.AcceptWaveform(data):
                    continue

                text, confidence = recognition_result(wake_recognizer)
                if text != wake_phrase:
                    continue
                print(f"Wake detected: {wake_phrase} (confidence {confidence:.2f})")
                write_voice_status(
                    config,
                    "awake",
                    f"Wake phrase detected: {wake_phrase}",
                    command_path=[wake_phrase],
                )

                current_children = root_children
                command_path: list[str] = []
                handled = False
                timeout_reported = False

                while current_children:
                    choices = phrase_map(current_children)
                    command_recognizer = make_recognizer(
                        model,
                        sample_rate,
                        list(choices.keys()) + cancel_phrases,
                    )
                    deadline = time.monotonic() + command_timeout
                    selected: tuple[str, dict] | None = None

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
                        if command_text not in choices:
                            continue
                        if command_confidence < min_confidence:
                            print(
                                f"Ignored low-confidence command ({command_confidence:.2f} < {min_confidence:.2f})"
                            )
                            handled = True
                            break

                        selected = choices[command_text]
                        break

                    if handled:
                        break
                    if selected is None:
                        location = " -> ".join(command_path) if command_path else "root"
                        print(f"Voice command timed out after: {location}")
                        timeout_reported = True
                        break

                    canonical_phrase, node = selected
                    command_path.append(canonical_phrase)
                    write_voice_status(
                        config,
                        "recognized",
                        "Recognized: " + " -> ".join(command_path),
                        command_path=[wake_phrase] + command_path,
                    )

                    # Confirm command levels only: Tower stays silent, then
                    # Power (beep), Preset three (beep), and execute the leaf.
                    stream.stop_stream()
                    play_beep(audio, output_index, config)
                    stream.start_stream()

                    actions = node.get("actions")
                    children = node_children(node)
                    if actions is not None:
                        if children:
                            raise ValueError(
                                f"Voice node '{' -> '.join(command_path)}' cannot have both actions and children"
                            )
                        succeeded, display_actions = execute_actions(
                            config,
                            command_path,
                            actions,
                            token,
                            dry_run,
                        )
                        full_path = [wake_phrase] + command_path
                        write_voice_status(
                            config,
                            "completed" if succeeded else "failed",
                            ("Completed: " if succeeded else "Failed: ") +
                            " -> ".join(full_path),
                            command_path=full_path,
                            ok=succeeded,
                        )
                        if not dry_run:
                            post_voice_notification(
                                config,
                                command_path,
                                display_actions,
                                succeeded,
                                token,
                            )
                        last_result_message = (
                            ("Last command OK: " if succeeded else "Last command failed: ")
                            + " -> ".join(full_path)
                        )
                        handled = True
                        break
                    if not children:
                        raise ValueError(
                            f"Voice node '{' -> '.join(command_path)}' has no actions or children"
                        )
                    current_children = children

                if not handled and not timeout_reported:
                    print("Voice command timed out")

                # Use a fresh recognizer so command-state audio never leaks back
                # into wake-word recognition.
                wake_recognizer = make_wake_recognizer(model, sample_rate, wake_phrase)
                print(f"Listening for wake phrase: {wake_phrase!r}")
                write_voice_status(
                    config,
                    "listening",
                    f"Listening for wake phrase: {wake_phrase}"
                    + (f"; {last_result_message}" if last_result_message else ""),
                )

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
