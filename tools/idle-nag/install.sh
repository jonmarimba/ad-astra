#!/usr/bin/env bash
# astra-scope: repo
# install.sh — the spoken idle nag ("Dude. Look over here." 25s after Claude
# goes quiet), as hooks in <repo>/.claude/settings.json, so it applies to
# sessions in this repo only. For one session at a time, use idle-nag-session.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/astra-install.sh"
astra_target "$@"
astra_place_at idle-nag \
  "tools/idle-nag/arm.sh:.astra/idle-nag/arm.sh" \
  "tools/idle-nag/wait.sh:.astra/idle-nag/wait.sh" \
  "tools/idle-nag/cancel.sh:.astra/idle-nag/cancel.sh" \
  "--hook=Stop||.astra/idle-nag/arm.sh" \
  "--hook=UserPromptSubmit||.astra/idle-nag/cancel.sh"
