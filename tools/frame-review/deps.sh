#!/usr/bin/env bash
# deps.sh — install or upgrade ffmpeg, which frame-review needs.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/deps-common.sh"
brewfile_upgrade "$HERE/Brewfile"
