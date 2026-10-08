#!/usr/bin/env bash
# deps.sh — make sure the three agent CLIs a convocation runs (claude, codex, qwen) are present.
# install.sh with no --into does exactly this. It installs a missing CLI by the method this machine
# already uses and never upgrades or removes one that is there: those are the owner's primary tools.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$HERE/install.sh"
