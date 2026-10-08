#!/usr/bin/env bash
# deps.sh — install or upgrade ffmpeg for the mic and camera probes. It never rebuilds Handlebars.app: a rebuild changes its hash and destroys every permission grant it holds.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/deps-common.sh"
brewfile_upgrade "$HERE/Brewfile"
