#!/usr/bin/env bash
# astra-scope: repo
# install.sh — the idle nag for ONE session at a time. Places the same scripts
# as idle-nag but registers no repo hooks; opt a session in with:
#   claude --settings .astra/idle-nag-session/session-settings.json
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/astra-install.sh"
astra_target "$@"
astra_place_at idle-nag-session \
  "tools/idle-nag/arm.sh:.astra/idle-nag-session/arm.sh" \
  "tools/idle-nag/wait.sh:.astra/idle-nag-session/wait.sh" \
  "tools/idle-nag/cancel.sh:.astra/idle-nag-session/cancel.sh" \
  "tools/idle-nag-session/session-settings.json:.astra/idle-nag-session/session-settings.json"
