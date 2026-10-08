#!/usr/bin/env bash
# deps.sh — install or upgrade rsync and uv, and check out the session-bridge submodule. It does not touch the hourly schedule or AgentSync.app.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/deps-common.sh"
brewfile_upgrade "$HERE/Brewfile"
git -C "$HERE/../.." submodule update --init vendor/authsec-bridge
