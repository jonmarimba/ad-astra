#!/usr/bin/env bash
# deps.sh — the machine half of graphify-repo: its Brewfile, then the graphify CLI (installed if
# missing, upgraded if present).
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v brew >/dev/null && brew bundle --file="$HERE/Brewfile" || echo "no brew; ensure uv is present"
command -v uv >/dev/null || { echo "graphify-repo: FAIL: uv missing" >&2; exit 69; }
if command -v graphify >/dev/null; then uv tool upgrade graphifyy || true; else uv tool install graphifyy; fi
