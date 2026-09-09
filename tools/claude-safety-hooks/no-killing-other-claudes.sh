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
# CONFIGURATION. Optional: install.sh can write a one-line hint naming YOUR repo's tested,
# scoped reap path (if one exists) to no-killing-other-claudes.reap-hint next to this script,
# so the block message points at it instead of a generic "ask a human first." Read as DATA
# from a file, not embedded in this script's source: an earlier version had install.sh
# sed-substitute the hint text directly into a shell variable assignment in the installed
# copy, escaping only '/' and '&' -- a hint containing a '"' or a newline could break the
# installed script's syntax or inject shell code that runs on every invocation. Found by peer
# review, 2026-09-08. A plain file read has no such injection surface: whatever the file
# contains is used as inert text in an error message, never re-parsed as shell.
#
# KNOWN LIMIT, stated plainly rather than left implicit: this hook inspects only the literal
# Bash tool_input command TEXT, same as its sibling no-silent-truncation.sh. `bash
# some_script.sh` where the script itself contains a kill is invisible to this check — the
# guard is a backstop against typing a kill directly, not a sandbox. Anything written to a
# script file first is still visible in that Write call for review; this hook does not
# replace judgment about what gets written, only removes the single most common failure (a
# direct, careless `kill <pid>` typed straight into a Bash call).
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORD_LITERAL="$HOOK_DIR/shell_word_literal.py"
REAP_HINT_FILE="$HOOK_DIR/no-killing-other-claudes.reap-hint"
REAP_MECHANISM_HINT=""
[ -f "$REAP_HINT_FILE" ] && REAP_MECHANISM_HINT="$(cat "$REAP_HINT_FILE")"

payload="$(cat)"
cmd="$(printf '%s' "$payload" | python3 -c "
import json,sys
try: print((json.load(sys.stdin).get('tool_input') or {}).get('command',''))
except Exception: print('')
" 2>/dev/null)"

[ -z "$cmd" ] && exit 0

# Bash removes a backslash followed by a physical newline before it recognizes
# words. Do the same before segmenting; otherwise `k\\` followed by `ill` is
# inspected as two harmless lines even though Bash executes `kill`.
cmd="$(printf '%s' "$cmd" | python3 -c 'import sys; sys.stdout.write(sys.stdin.read().replace(chr(92) + chr(10), ""))')"

# PROSE IS NOT A KILL CALL, BUT THIS EXEMPTION MUST NOT BE GLOBAL. This hook's own commit
# message describes what it does and says "kill/pkill/killall" in plain English — which
# would otherwise block ITS OWN commit, the same self-referential trap
# no-silent-truncation.sh documents. A git commit/tag/merge/notes command is never itself a
# process kill.
#
# BUT a command-text SUBSTRING check for "git commit" here, applied to the WHOLE command
# before any segmentation, is a real hole: `kill <live-claude-pid>; git commit --allow-empty
# -m x` contains the substring "git commit" and would exit 0 here, skipping analysis of the
# kill call entirely. Found by peer review, 2026-09-08. Fixed: this check now runs PER
# SEGMENT, after splitting on `;|&` (same segmentation the kill scan already uses), and only
# exempts a segment that ITSELF begins with git commit/tag/merge/notes -- never a whole
# command merely because one of its chained segments happens to be a git operation.

# basename(1) without a subprocess per token: strip everything up to the last '/'. ALSO
# strips a leading command-substitution or subshell opener ($(, a backtick, or a bare open
# paren) first -- `out=$(kill <pid>)` word-splits as the single token "$(kill" (no space
# between the opener and the word), so a plain basename/exact-match on "kill" never fires and
# the whole segment's kill-word detection is skipped entirely, letting every argument through
# unscanned rather than merely one unsafe token. Found by peer review, 2026-09-08 -- the
# earlier per-segment git-commit fix closed one bypass but this word-tokenization gap was
# separate and just as real: it is not about WHERE in the command a kill sits, but about
# spelling "kill" in a way the exact-match never recognizes as the word "kill" at all.
basename_of() {
  local w="$1"
  # Decode literal Bash word syntax with the companion scanner.  It understands
  # ANSI-C quoting ($'\\151') without evaluating command text; dynamic
  # expansions are intentionally left for this hook's existing fail-closed
  # substitution handling.
  if [ -f "$WORD_LITERAL" ]; then
    local literal
    if literal="$(python3 "$WORD_LITERAL" "$w" 2>/dev/null)"; then
      w="$literal"
    fi
  fi
  # QUOTE-AND-BACKSLASH SPLICING. Bash removes matched quote pairs during word expansion
  # AND removes a bare backslash before an ordinary character (a backslash-escape), then
  # CONCATENATES what is left -- k''ill and k\ill are both single words Bash hands the real
  # `kill` command exactly as if typed unquoted, but as raw strings neither ever matches
  # "kill" by exact comparison (nor any of the prefix/opener stripping above and below).
  # Both a quote pair and a backslash-escape can appear ANYWHERE inside a word, not just at
  # its edges, so no amount of edge-stripping closes either class. Round five (2026-09-08)
  # fixed the quote form; round six, same day, added the backslash form after peer review
  # caught that removing quotes alone still let a lone backslash splice a word apart.
  # Strip every ', ", and \ character from the word before anything else runs; this is a
  # blunt normalization (it does not model an escaped backslash meaning a literal backslash,
  # a real but much rarer shape here), but it is the same fail-closed trade this file makes
  # throughout -- better to over-normalize a rare edge case than under-normalize the common
  # evasion.
  #
  # ANSI-C and locale quoting: $'kill' and $"kill" are two more Bash quoting forms that
  # also produce the bare word "kill" once expanded, and a plain `tr -d "'\""` alone leaves
  # the leading $ behind (word becomes "$kill", still not a match) since $ isn't one of the
  # stripped characters and isn't adjacent to a stripped one in the right order to cancel
  # out. Strip the two-character $' and $" sequences globally FIRST, then the general
  # quote/backslash strip below cleans up whatever quote character they left orphaned.
  # Found by GhOST-Claude while investigating a supervisor finding about this file's
  # evasion-fixing pattern, 2026-09-08 -- same day as rounds five and six.
  w="${w//\$\'/}"
  w="${w//\$\"/}"
  w="$(printf '%s' "$w" | tr -d "'\"\\\\")"
  # A bare `var=$(kill ...)` glues the assignment directly onto the substitution with no
  # space -- bash's own inline-assignment-before-command syntax -- so the opener check below
  # would miss it too if the word still starts with "var=". Strip one leading
  # identifier-looking "name=" prefix first, if the remainder looks like a substitution
  # opener (with or without a wrapping double-quote -- `out="$(kill ...)"` is exactly as
  # common as the unquoted form, and peer review 2026-09-08 caught that the opener check
  # only recognized $(/`/( and never a leading quote in front of one of those, so the
  # quoted form -- "$(kill" -- matched none of the three patterns and slipped through
  # untouched); a token that merely CONTAINS "=" without a quote/$(/`/( right after it (an
  # ordinary argument, not an assignment-glued substitution) is left alone.
  case "$w" in
    [A-Za-z_]*=*)
      rest="${w#*=}"
      case "$rest" in
        '"'*|"'"*|'$('*|'`'*|'('*) w="$rest" ;;
      esac
      ;;
  esac
  while :; do
    case "$w" in
      '"'*)  w="${w#\"}" ;;
      "'"*)  w="${w#\'}" ;;
      '$('*) w="${w#\$\(}" ;;
      '`'*)  w="${w#\`}" ;;
      '('*)  w="${w#\(}" ;;
      *) break ;;
    esac
  done
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
substitution_kill_hit=0
dynamic_command_hit=0
found_unsafe_arg=""
claude_pids=""

# Return success when the executable word itself contains a dynamic expansion.
# Do not evaluate it: an expansion can manufacture `kill` from arbitrary text.
# Leading literal assignments are not executable words, so `x=i; k${x}ll` must
# inspect the second word rather than treating the assignment as the command.
dynamic_executable_word() {
  local word wrapper=0 wrapper_name="" skip_operand=0
  for word in $1; do
    if [ "$skip_operand" -eq 1 ]; then
      # This word is the OPERAND of a flag consumed on the previous
      # iteration (e.g. the "name" in `exec -a name`), not a candidate
      # executable itself -- skip it without re-examining it as one.
      skip_operand=0
      continue
    fi
    case "$word" in
      [A-Za-z_]*=*) continue ;;
    esac
    # These wrappers delegate execution to their next command word.  Keep
    # scanning past the wrapper rather than incorrectly treating `exec` (or
    # `command`) itself as the executable.
    case "$word" in
      exec|command|builtin|nohup|time) wrapper=1; wrapper_name="$word"; continue ;;
    esac
    if [ "$wrapper" -eq 1 ]; then
      # `exec -a name cmd` overrides argv0: `-a` takes its OWN operand
      # ("name") as a separate word, which is not the delegated executable
      # either -- skip both, or the scanner stops on "name" and never
      # reaches the real command word that follows.
      if [ "$wrapper_name" = "exec" ] && [ "$word" = "-a" ]; then
        skip_operand=1
        continue
      fi
      # Command's common flags do not name its delegated executable.
      case "$word" in --|-*) continue ;; esac
    fi
    case "$word" in
      *'$'*|*'`'*|*'<('*|*'>('* ) return 0 ;;
    esac
    return 1
  done
  return 1
}

while IFS= read -r segment; do
  [ -z "$segment" ] && continue
  # Per-segment git-commit-prose exemption: only when THIS segment itself starts with the
  # git operation (leading whitespace trimmed), not merely contains the substring anywhere.
  trimmed="${segment#"${segment%%[![:space:]]*}"}"
  case "$trimmed" in
    "git commit"*|"git tag"*|"git merge"*|"git notes"*) continue ;;
  esac

  if dynamic_executable_word "$trimmed"; then
    dynamic_command_hit=1
    continue
  fi

  # A variable-expanded command name cannot be resolved without evaluating
  # command text. Refuse the direct form and common transparent wrappers;
  # literal `kill $pid` is handled below as an unsafe target instead.
  case "$trimmed" in
    '$'*|'"$'*|"'$"*|command[[:space:]]*'$'*|env[[:space:]]*'$'*|nice[[:space:]]*'$'*)
      dynamic_command_hit=1
      continue
      ;;
  esac

  # UNCONDITIONAL FAIL-CLOSED ON SUBSTITUTION + KILL-WORD ANYWHERE IN THE SAME SEGMENT.
  # Prior fixes handled command substitution GLUED directly onto "kill" with an enumerable
  # prefix shape (a bare $(/`/( opener, a wrapping quote, a var= assignment). But bash lets
  # arbitrary text precede $( with no delimiter at all -- `echo prefix$(kill $pid)` -- and no
  # amount of prefix-enumeration can anticipate every such shape. Rather than continue a
  # losing arms race against ever more creative gluing, this segment is refused
  # UNCONDITIONALLY (same treatment as pkill/killall) the moment it contains BOTH a
  # substitution/redirection opener AND a kill-family word anywhere in it -- because this
  # hook cannot safely resolve what such a segment actually targets, full stop. Covers
  # command substitution ($( or a backtick) AND Bash PROCESS substitution (<( or >( -- `cat
  # <(kill $pid)` runs the kill inside the process-substitution subshell exactly like $(...)
  # does, and round 3 of this fix only checked for $( and the backtick, missing this
  # syntactically distinct but equally live form; found by peer review, 2026-09-08, as round
  # four on this exact evasion shape). Traded off deliberately: this can false-positive on a
  # segment that merely mentions "kill" in prose near an unrelated substitution/redirection,
  # which costs an occasional unnecessary block -- the same trade this file already makes
  # everywhere else (fail closed over prove-danger).
  case "$segment" in
    *'$('*|*'`'*|*'<('*|*'>('*)
      case "$segment" in
        *kill*)
          substitution_kill_hit=1
          continue
          ;;
      esac
      ;;
  esac

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

  # kill: walk THIS SEGMENT's own tokens only, WITH LOOKAHEAD -- `kill -9 1234` uses -9 as a
  # signal NUMBER (always followed by at least one more target token), while a bare negative
  # number with NOTHING after it (`kill -1234`) is kill's process-GROUP form, semantically
  # identical to a positive PID target but for the whole group. Positional indexing (not a
  # plain `for tok in $segment`) is required to tell these apart: whether a `-N` token is a
  # signal flag or a process-group target depends on whether another token follows it in the
  # SAME kill invocation, not on its shape alone. Found by peer review, 2026-09-08 (the first
  # fix here treated ALL `-<digits>` as unsafe, which also blocked plain `kill -9 <pid>`).
  seg_seen_kill=0
  # shellcheck disable=SC2086
  set -- $segment
  n=$#
  i=1
  while [ "$i" -le "$n" ]; do
    tok="${!i}"   # bash indirect positional-parameter expansion -- no eval, no re-parsing
    b="$(basename_of "$tok")"
    if [ "$b" = "kill" ]; then
      seg_seen_kill=1
      i=$((i + 1))
      continue
    fi
    if [ "$seg_seen_kill" -eq 0 ]; then
      i=$((i + 1))
      continue
    fi
    has_next=0
    [ "$i" -lt "$n" ] && has_next=1
    case "$tok" in
      0)
        # kill 0 signals EVERY process in the caller's own process group -- which can
        # include a live claude process sharing that group. Not "not a real PID"; the
        # single most dangerous bare target there is. Fail closed.
        found_unsafe_arg="$tok"
        ;;
      -*)
        rest="${tok#-}"
        case "$rest" in
          ''|*[!0-9]*) ;;   # a named signal flag (-TERM, -KILL, -s): not a target, ignore
          *)
            if [ "$has_next" -eq 1 ]; then
              : # a numeric signal flag (-9, -15) followed by a real target -- not itself
                # a target, ignore; the target token is scanned on its own iteration
            else
              # A bare negative number with NOTHING after it is kill's process-GROUP form
              # (kill -1234 signals every process in group 1234), not a signal number.
              # Fail closed, same as kill 0 above.
              found_unsafe_arg="$tok"
            fi
            ;;
        esac
        ;;
      ''|*[!0-9]*)
        # Not a bare non-negative integer -- a variable, $(...), a name, etc.
        # We cannot resolve what this actually targets. Fail closed.
        found_unsafe_arg="$tok"
        ;;
      *)
        # Resolve EVERY literal positive PID via ps, regardless of magnitude -- a ps lookup
        # is cheap and correct at any PID value, so there is no reason to skip verifying any
        # of them (an earlier version skipped small numbers "because they're not real PIDs,"
        # which is exactly what let kill 0 through unexamined).
        proc="$(ps -p "$tok" -o command= 2>/dev/null || true)"
        case "$proc" in
          *claude*) claude_pids="$claude_pids $tok ($proc)" ;;
        esac
        ;;
    esac
    i=$((i + 1))
  done
done <<EOF_SEGMENTS
$(printf '%s' "$cmd" | tr ';|&' '\n')
EOF_SEGMENTS

# pkill/killall: ALWAYS refused. They match by name/pattern, which cannot be safely
# pre-validated against arbitrary regex text — see finding #3 above.
if [ "$pkill_or_killall_hit" -eq 1 ]; then
  reason="pkill/killall match processes by NAME PATTERN, which this hook cannot safely verify does not match a live claude process (regex can always be written to evade a substring check). Blocked unconditionally."
elif [ "$substitution_kill_hit" -eq 1 ]; then
  reason="this segment contains a command/process substitution (\$( or a backtick) alongside a kill-family word, and this hook cannot safely resolve what such a segment actually targets -- text of any shape can precede a substitution opener with no delimiter, so no prefix-stripping can enumerate every case. Blocked unconditionally, the same as pkill/killall."
elif [ "$dynamic_command_hit" -eq 1 ]; then
  reason="this segment uses a variable-expanded command name the hook cannot decode without evaluating command text. Blocked rather than assuming it is safe."
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
