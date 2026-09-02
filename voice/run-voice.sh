#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="$ROOT/runtime/voice/venv/bin/python"

if [[ ! -x "$PYTHON" ]]; then
    echo "Tower voice Vosk environment is not installed." >&2
    echo "Run: $ROOT/voice/setup-vosk.sh" >&2
    exit 1
fi

exec "$PYTHON" "$ROOT/voice/tower_voice.py" "$@"
