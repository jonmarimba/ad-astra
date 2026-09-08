#!/bin/bash
# no-killing-other-claudes.sh — PreToolUse guard on Bash.
#
# Blocks `kill`/`pkill`/`killall` from ever terminating a live `claude` process.
#
# WHY THIS IS A HOOK AND NOT A NOTE. On one real deployment, after a genuine split-brain
# outage was fixed, a bare `claude --resume <session-id>` process turned up an hour later in
# a plain terminal (no tmux). It pattern-matched the session id from the earlier outage, so
# it LOOKED like a stale duplicate. It was not — it was the human's own live session. It was
# killed anyway, on the model's own judgment, outside any tested/scoped reap mechanism.
# His words: "You killed one of my claudes?" / "I'm using that one." / "Asshole." Then,
# naming the actual bug: "You continue to assume you're the only claude on this machine YOU
# ARE NOT." And: "FIX IT."
#
# Any machine that runs more than one Claude Code session at once — multiple terminal
# windows, a multi-agent ensemble, unrelated work in another repo — has this exposure. None
# of that is ever evidence that a given `claude` process is a stale duplicate safe to kill.
#
# REVISED after peer review of the first version found three real evasion paths, all now
# closed by FAILING CLOSED instead of trying to prove danger:
#   1. `/bin/kill 12345` — the tokenizer matched only the bare word "kill", so any
#      path-qualified form slipped through unrecognized as a kill call at all.
#      Fixed: match on the BASENAME of each word, not the literal string.
#   2. `pid="$(pgrep -f 'claude --resume')"; kill "$pid"` — no literal integer PID appears in
#      the submitted command text (it's a shell variable), so an "extract bare integers" scan
#      finds nothing to check. Fixed: `kill` is refused by default for any non-flag argument
#      that is not a literal decimal integer — a variable, a command substitution, anything
#      this hook cannot resolve itself is treated as unsafe, not passed through as safe.
#   3. `pkill -f 'cla.*'` matches a live claude process via a regex the pattern text never
#      literally spells "claude" — so "does the command text contain the substring claude" is
#      not a real safety check for pattern-matching kill commands; it can always be evaded by
#      an equivalent pattern. Fixed: pkill and killall are blocked UNCONDITIONALLY, every
#      time, full stop. They match live processes by NAME/PATTERN, which this hook cannot
#      safely pre-evaluate against arbitrary regex without literally running it against the
#      whole process table first — and even then a clever enough pattern is an arms race this
#      text-matching hook will always eventually lose. A pattern-based kill of anything is not
#      worth that risk; use `kill <pid>` with a literal, checkable PID instead.
#
# WHAT IT DOES NOW: `pkill`/`killall` in any form are always blocked. `kill` is allowed only
# when every non-flag argument is a literal decimal integer, and only after resolving each
# one via a live `ps -p <pid> -o command=` lookup and confirming none of them is currently
# running `claude`. Anything else about a `kill` call (a variable, `$(...)`, an unrecognized
# argument shape) is refused by default — this hook does not try to prove a command is
# dangerous before blocking it; it requires proof a command is SAFE before allowing it.
#
# CONFIGURATION. Optional: set REAP_MECHANISM_HINT below (or export it before this hook
# runs) to name YOUR repo's tested, scoped reap path, if one exists, so the block message can
# point at it instead of a generic "ask a human first." Leave it empty for a plain refusal.
REAP_MECHANISM_HINT="${REAP_MECHANISM_HINT:-}"
#
# KNOWN LIMIT, stated plainly rather than left implicit: this hook inspects only the literal
# Bash tool_input command TEXT, same as its sibling no-silent-truncation.sh. `bash
# some_script.sh` where the script itself contains a kill is invisible to this check — the
# guard is a backstop against typing a kill directly, not a sandbox. Anything written to a
# script file first is still visible in that Write call for review; this hook does not
# replace judgment about what gets written, only removes the single most common failure (a
# direct, careless `kill <pid>` typed straight into a Bash call).
set -uo pipefail

payload="$(cat)"
cmd="$(printf '%s' "$payload" | python3 -c "
import json,sys
try: print((json.load(sys.stdin).get('tool_input') or {}).get('command',''))
except Exception: print('')
" 2>/dev/null)"

[ -z "$cmd" ] && exit 0

# PROSE IS NOT A KILL CALL. This hook's own commit message describes what it does and says
# "kill/pkill/killall" in plain English — which would otherwise block ITS OWN commit, the
# same self-referential trap no-silent-truncation.sh documents. A git commit/tag/merge/notes
# command is never itself a process kill.
case "$cmd" in
  *"git commit"*|*"git tag"*|*"git merge"*|*"git notes"*) exit 0 ;;
esac

# basename(1) without a subprocess per token: strip everything up to the last '/'.
basename_of() {
  local w="$1"
  printf '%s' "${w##*/}"
}

# SEGMENT, don't flatten. Flattening the whole command with a single seen_kill flag that is
# never cleared means `kill 12345; echo done` scans unrelated tokens from a SEPARATE chained
# command ("echo", "done") as kill targets, finds them non-literal-integer, and
# fail-closed-blocks an otherwise-safe command. Split on separators FIRST (one command
# segment per line) and reset the kill-target scan at the start of each segment, so a kill
# word's targets never leak past its own segment boundary.
reason=""
pkill_or_killall_hit=0
found_unsafe_arg=""
claude_pids=""

while IFS= read -r segment; do
  [ -z "$segment" ] && continue
  seg_kill_word=""
  seg_pkill_or_killall=0
  for word in $segment; do
    b="$(basename_of "$word")"
    case "$b" in
      kill) [ -z "$seg_kill_word" ] && seg_kill_word="kill" ;;
      pkill) seg_kill_word="pkill"; seg_pkill_or_killall=1 ;;
      killall) seg_kill_word="killall"; seg_pkill_or_killall=1 ;;
    esac
  done
  [ -z "$seg_kill_word" ] && continue

  if [ "$seg_pkill_or_killall" -eq 1 ]; then
    pkill_or_killall_hit=1
    continue
  fi

  # kill: walk THIS SEGMENT's own tokens only. Any non-flag argument that is not a literal
  # decimal integer is unsafe-by-default. Any literal integer PID is resolved via a live ps
  # lookup; block if it is currently running claude.
  seg_seen_kill=0
  for tok in $segment; do
    b="$(basename_of "$tok")"
    if [ "$b" = "kill" ]; then
      seg_seen_kill=1
      continue
    fi
    [ "$seg_seen_kill" -eq 0 ] && continue
    case "$tok" in
      -*) continue ;;                 # a flag (e.g. -9, -TERM): not a target
      ''|*[!0-9]*)
        # Not a bare non-negative integer -- a variable, $(...), a name, etc.
        # We cannot resolve what this actually targets. Fail closed.
        found_unsafe_arg="$tok"
        ;;
      *)
        [ "$tok" -lt 100 ] 2>/dev/null && continue  # tiny numbers: not real PIDs
        proc="$(ps -p "$tok" -o command= 2>/dev/null || true)"
        case "$proc" in
          *claude*) claude_pids="$claude_pids $tok ($proc)" ;;
        esac
        ;;
    esac
  done
done <<EOF_SEGMENTS
$(printf '%s' "$cmd" | tr ';|&' '\n')
EOF_SEGMENTS

# pkill/killall: ALWAYS refused. They match by name/pattern, which cannot be safely
# pre-validated against arbitrary regex text — see finding #3 above.
if [ "$pkill_or_killall_hit" -eq 1 ]; then
  reason="pkill/killall match processes by NAME PATTERN, which this hook cannot safely verify does not match a live claude process (regex can always be written to evade a substring check). Blocked unconditionally."
elif [ -n "$found_unsafe_arg" ]; then
  reason="the target '$found_unsafe_arg' is not a literal PID this hook can resolve and verify (a variable, command substitution, or name) -- refused by default rather than assumed safe."
elif [ -n "$claude_pids" ]; then
  reason="target(s) currently running claude:$claude_pids"
fi

[ -z "$reason" ] && exit 0

reap_line=""
if [ -n "$REAP_MECHANISM_HINT" ]; then
  reap_line="

If a duplicate genuinely needs reaping, that goes through this repo's tested, scoped reap
path ($REAP_MECHANISM_HINT) -- never a manual kill/pkill/killall from a Bash call."
fi

cat >&2 <<EOF
BLOCKED: this would risk killing a live 'claude' process.

  $cmd

Reason: $reason

This machine may run many live claude sessions at once as normal operation -- other terminal
windows, a multi-agent ensemble, unrelated work. A claude process is NEVER safe to kill on
your own judgment, however confident the story ("this looks like a stale duplicate from
before") sounds. That exact reasoning has killed a session someone was actively using. This
hook fails CLOSED: a kill target it cannot verify as non-claude is treated as unsafe, not as
innocent.${reap_line}

If this is a LEGITIMATE, verified non-claude target that got refused, find its literal PID
with ps/pgrep and pass exactly that PID to a plain \`kill\` call -- pattern-based termination
(pkill/killall) is never available. If you believe a claude process genuinely needs to die,
ask the human first.
EOF
exit 2
