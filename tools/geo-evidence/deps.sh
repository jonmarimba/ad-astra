#!/usr/bin/env bash
# deps.sh — install or upgrade exiftool and osxphotos.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/deps-common.sh"
brewfile_upgrade "$HERE/Brewfile"
command -v uv >/dev/null || { echo "geo-evidence: FAIL: uv missing (brew install uv)" >&2; exit 69; }
if command -v osxphotos >/dev/null; then uv tool upgrade osxphotos || true; else uv tool install osxphotos --python 3.12; fi
