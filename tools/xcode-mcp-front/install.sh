#!/usr/bin/env bash
# install.sh — deps for xcode-mcp-front: uv (runs daemon.py/spike.py as PEP 723
# scripts, deps declared inline, no separate venv to manage).
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
command -v uv >/dev/null || { echo "uv not found — install via 'brew install uv'" >&2; exit 1; }
mkdir -p "$HOME/.xcode-mcp-front"
echo "xcode-mcp-front ready. NOT YET VALIDATED — run '$HERE/xcode-mcp-front spike' against a live Xcode first."
echo "Then: $HERE/xcode-mcp-front start"
