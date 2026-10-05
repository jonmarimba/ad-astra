#!/usr/bin/env bash
# astra-scope: repo
# uninstall.sh — the banned-phrases checker with its own copy of the list, in <repo>/.astra/check-banned-phrases/.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/astra-install.sh"
astra_target "$@"
astra_remove check-banned-phrases
