#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="$ROOT/runtime/voice/venv/bin/python"

if [[ ! -x "$PYTHON" ]]; then
    echo "Tower voice Vosk environment is not installed." >&2
    echo "Run: $ROOT/voice/setup-vosk.sh" >&2
    exit 1
fi

# The Tower API and this listener use the same bearer token. When the listener
# is started manually or by its own service, reuse the token already present in
# the running rf-tower.service process without printing or storing another copy.
if [[ -z "${TOWER_API_TOKEN:-}" ]]; then
    tower_pid="$(systemctl show rf-tower.service --property=MainPID --value 2>/dev/null || true)"
    if [[ "$tower_pid" =~ ^[1-9][0-9]*$ ]] && [[ -r "/proc/$tower_pid/environ" ]]; then
        while IFS= read -r -d '' environment_entry; do
            if [[ "$environment_entry" == TOWER_API_TOKEN=* ]]; then
                export TOWER_API_TOKEN="${environment_entry#TOWER_API_TOKEN=}"
                echo "Voice API token: reused from rf-tower.service"
                break
            fi
        done < "/proc/$tower_pid/environ"
    fi
fi

exec "$PYTHON" "$ROOT/voice/tower_voice.py" "$@"
