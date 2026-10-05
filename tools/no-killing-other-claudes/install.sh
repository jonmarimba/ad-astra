#!/usr/bin/env bash
# astra-scope: repo
# install.sh — the kill guard on its own: refuses Bash commands that could kill a
# live claude process. It fails CLOSED, so it also refuses any command it cannot
# read without evaluating it: a variable used as a command name ("$TOOL" args),
# and text inside heredocs that looks like one. That blocks a lot of ordinary
# work, so it is opt-in and not part of the base set.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/astra-install.sh"
astra_target "$@"
D=.astra/no-killing-other-claudes
# Move off the pre-2026-10-04 install (.claude/hooks + settings.local.json), keeping the watchlist.
python3 "$ASTRA_MANIFEST_PY" migrate-safety-hooks "$TARGET" "" no-killing-other-claudes.sh
astra_place_at no-killing-other-claudes \
  "tools/claude-safety-hooks/no-killing-other-claudes.sh:$D/no-killing-other-claudes.sh" \
  "tools/claude-safety-hooks/shell_word_literal.py:$D/shell_word_literal.py" \
  "--hook=PreToolUse|Bash|$D/no-killing-other-claudes.sh"
