#!/usr/bin/env bash
# Kept so old instructions still work. The installer is tools/humanizer/install.sh.
set -euo pipefail
exec "$(cd "$(dirname "$0")/../../../tools/humanizer" && pwd)/install.sh" --into "${1:?usage: install.sh <repo>}"
