#!/usr/bin/env bash
# deps.sh — check that uv is present, which the daemon runs under. It does not reload a launchd job or rebuild a wrapper app: restarting the daemon re-raises Xcode approval dialogs.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/deps-common.sh"
command -v uv >/dev/null || { command -v brew >/dev/null && brew install uv; }
command -v uv >/dev/null || { echo "xcode-mcp-front: FAIL: uv missing" >&2; exit 69; }
uv self update >/dev/null 2>&1 || brew upgrade uv >/dev/null 2>&1 || true
