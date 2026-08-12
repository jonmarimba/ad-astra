#!/usr/bin/env bash
# install.sh — deps for graphify-repo: uv + the graphify CLI (uv tool 'graphifyy').
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
command -v brew >/dev/null && brew bundle --file="$HERE/Brewfile" || echo "no brew; ensure uv present"
command -v graphify >/dev/null || uv tool install graphifyy
graphify --help >/dev/null 2>&1 && echo "graphify-repo ready. Usage: $HERE/graphify-repo <repo-path> [--label-backend ollama --label-model <m>]"
