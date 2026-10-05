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
astra_place_at no-killing-other-claudes \
  "tools/claude-safety-hooks/no-killing-other-claudes.sh:$D/no-killing-other-claudes.sh" \
  "tools/claude-safety-hooks/shell_word_literal.py:$D/shell_word_literal.py" \
  "--hook=PreToolUse|Bash|$D/no-killing-other-claudes.sh"
