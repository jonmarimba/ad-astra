#!/usr/bin/env bash
# astra-scope: repo
# uninstall.sh — remove the per-session idle nag scripts.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/astra-install.sh"
astra_target "$@"
astra_remove idle-nag-session
