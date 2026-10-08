#!/usr/bin/env bash
# deps.sh — install or upgrade rsync and uv, and check out the session-bridge submodule. It does not touch the hourly schedule or AgentSync.app.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/deps-common.sh"
brewfile_upgrade "$HERE/Brewfile"
# Only when the engine is missing, and only in a git checkout: a toolbox unpacked from a tarball or copied
# without .git has no submodule to update, and one that already carries the engine needs nothing.
if [ ! -d "$HERE/../../vendor/authsec-bridge/src" ]; then
  git -C "$HERE/../.." submodule update --init vendor/authsec-bridge
fi
