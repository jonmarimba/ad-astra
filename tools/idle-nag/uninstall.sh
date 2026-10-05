#!/usr/bin/env bash
# astra-scope: repo
# uninstall.sh — remove the idle nag: its scripts and only its own hook entries.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/astra-install.sh"
astra_target "$@"
astra_remove idle-nag
