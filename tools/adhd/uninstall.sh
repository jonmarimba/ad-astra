#!/usr/bin/env bash
# astra-scope: repo
# uninstall.sh — the adhd skill, removed from <repo> along with its manifest entry.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/astra-install.sh"
astra_target "$@"
astra_remove adhd
