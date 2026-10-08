#!/usr/bin/env bash
# deps.sh — install or upgrade jq and the tomlkit Python package.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/deps-common.sh"
brewfile_upgrade "$HERE/Brewfile"
python3 -m pip install --user --upgrade --quiet tomlkit || python3 -m pip install --upgrade --quiet tomlkit
