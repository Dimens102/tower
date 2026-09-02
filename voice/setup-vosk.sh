#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV="$ROOT/runtime/voice/venv"
MODEL_DEST="$ROOT/runtime/voice/models/vosk-model-small-en-us-0.15"
DEFAULT_MODEL_SOURCE="$HOME/Development/ir-lab/vosk/SpeechRecognition/models/vosk-model-small-en-us-0.15"
MODEL_SOURCE="${1:-$DEFAULT_MODEL_SOURCE}"

mkdir -p "$ROOT/runtime/voice/models"

if ! python3 -c 'import venv' >/dev/null 2>&1; then
    echo "python3-venv is required: sudo apt install python3-venv" >&2
    exit 1
fi
if ! python3 -c 'import pyaudio' >/dev/null 2>&1; then
    echo "python3-pyaudio is required: sudo apt install python3-pyaudio" >&2
    exit 1
fi

if [[ ! -x "$VENV/bin/python" ]]; then
    python3 -m venv --system-site-packages "$VENV"
fi

"$VENV/bin/python" -m pip install --upgrade vosk

if [[ ! -d "$MODEL_DEST" ]]; then
    if [[ ! -d "$MODEL_SOURCE" ]]; then
        echo "Vosk model source not found: $MODEL_SOURCE" >&2
        echo "Pass the model directory as argument 1, or keep the lab model at:" >&2
        echo "  $DEFAULT_MODEL_SOURCE" >&2
        exit 1
    fi
    cp -a "$MODEL_SOURCE" "$MODEL_DEST"
fi

cat <<EOF
Tower Vosk runtime is ready.
Venv:  $VENV
Model: $MODEL_DEST

Test in dry-run mode:
  bash $ROOT/voice/run-voice.sh --dry-run
EOF
