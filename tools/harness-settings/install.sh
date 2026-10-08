#!/usr/bin/env bash
# astra-scope: machine
# install.sh — deps for harness-settings (jq + python tomlkit).
set -euo pipefail
export PATH="${ASTRA_PATH:-/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:$PATH}"
command -v brew >/dev/null && brew bundle --file="$(dirname "$0")/Brewfile" || echo "no brew; ensure jq + python3 present"
python3 -m pip install --user tomlkit || python3 -m pip install tomlkit
echo "harness-settings deps ready."
