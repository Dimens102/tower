#!/usr/bin/env bash
set -euo pipefail

installer_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$installer_dir/../.." && pwd)"
output_dir="$installer_dir/output"

command -v python3 >/dev/null || {
    echo "ERROR: python3 is required." >&2
    exit 1
}
command -v wixl >/dev/null || {
    echo "ERROR: wixl is required. On Debian/Ubuntu: sudo apt install wixl" >&2
    exit 1
}

python3 "$installer_dir/generate_wxs.py"
mkdir -p "$output_dir"
wixl \
    -a x64 \
    -D "WindowsSource=$project_root/windows" \
    -o "$output_dir/Tower-Control-0.11.05-x64.msi" \
    "$installer_dir/generated/Tower-Control.wxs"

echo "Built: $output_dir/Tower-Control-0.11.05-x64.msi"
