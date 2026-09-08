#!/bin/bash
# no-silent-truncation.sh — PreToolUse guard on Bash.
#
# Blocks piping a search over PROTECTED DATA through head, tail, or a sed line range.
#
# WHY THIS IS A HOOK AND NOT A NOTE. The underlying rule is easy to write down and easy to
# keep breaking anyway: no unjustified limits, windows, or truncation in anything that
# watches or searches YOUR data, because every one of them silently drops real data with no
# error. Written down in one deployment's CLAUDE.md since 2026-08-05, after eight separate
# silent-data-loss bugs surfaced in one 48-hour window. It did not hold. On 2026-08-31 a diary
# check-in there piped a multi-device activity search through `sed -n '3,9p'` for hours, which
# dropped whichever device fell past the last line — a real device vanished from a check on a
# day it carried real activity, and the human had to point it out: "How many times do I have
# to tell you to stop doing shit with LIMIT and tail and stuff that makes you miss stuff for
# the sake of saving tokens?"
#
# A rule the agent keeps agreeing with and keeps breaking needs a mechanism, not another
# paragraph. This is that mechanism.
#
# CONFIGURATION. This hook is generic on purpose — it does not know which tools in YOUR repo
# search protected data, so it reads that from a config file installed alongside it:
#   .claude/hooks/no-silent-truncation.watchlist
# One substring per line, matched against the raw command text (plain string containment, no
# regex — nobody reads regex easily). A command is treated as "a search over protected data"
# if it contains ANY watchlist line as a substring. install.sh seeds this file with a starter
# list and comments explaining the format; edit it per-repo to name YOUR search tools (a mail
# indexer, a notes search, a transcript search, `grep` over specific data directories, etc.)
# — this hook's own code has no repo-specific tool names baked in.
#
# WHAT IT DOES NOT BLOCK, deliberately, because a guard that cries wolf gets disabled:
#   * head/tail on LOGS and state files — following a log tail is what tails are for
#   * `head -1` reading a watermark or a single value
#   * git log, ls, ps, and other listings that are not a search over protected data
#   * git commit/tag/merge/notes — a commit message DESCRIBING this hook's own behavior
#     (naming head/tail/a grep while explaining a fix) would otherwise trip its own pattern
#     match and block its own repair commit. Found live, twice in a row, fixing this file.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCHLIST="$HOOK_DIR/no-silent-truncation.watchlist"

payload="$(cat)"
cmd="$(printf '%s' "$payload" | python3 -c "
import json,sys
try: print((json.load(sys.stdin).get('tool_input') or {}).get('command',''))
except Exception: print('')
" 2>/dev/null)"

[ -z "$cmd" ] && exit 0

# PROSE IS NOT A SEARCH, AND THIS GUARD CAN BLOCK ITS OWN FIX. It matches the raw command
# string, so a `git commit -m` whose message DESCRIBES the problem — naming a tool, a grep,
# a pipe into head while explaining the repair — trips every test and refuses the commit.
case "$cmd" in
  *"git commit"*|*"git tag"*|*"git merge"*|*"git notes"*) exit 0 ;;
esac

# Is this a search over protected data? Plain substring tests against the configured
# watchlist, no regex.
searches_protected_data=0
if [ -f "$WATCHLIST" ]; then
  while IFS= read -r pattern; do
    pattern="$(printf '%s' "$pattern" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -z "$pattern" ] && continue
    case "$pattern" in \#*) continue ;; esac
    case "$cmd" in *"$pattern"*) searches_protected_data=1 ;; esac
  done < "$WATCHLIST"
fi
[ "$searches_protected_data" -eq 0 ] && exit 0

# Reading a log or a watermark is not a search. Let those through.
case "$cmd" in
  *".log"*|*watermark*|*"fire.log"*) exit 0 ;;
esac

# Normalise whitespace first (a multiline pipeline should not smuggle a truncation past this
# check just because the `| head` landed on its own line), then test.
flat="$(printf '%s' "$cmd" | tr '\n\t' '  ' | tr -s ' ')"

found=""
case "$flat" in
  *"| head"*|*"|head"*)   found="head" ;;
esac
case "$flat" in
  *"| tail"*|*"|tail"*)   found="${found:+$found and }tail" ;;
esac
case "$flat" in
  *"sed -n"*)             found="${found:+$found and }a sed line range" ;;
esac
case "$flat" in
  *"LIMIT "*|*"--limit"*) found="${found:+$found and }an explicit limit" ;;
esac

[ -z "$found" ] && exit 0

cat >&2 <<EOF
BLOCKED: this pipes a search over protected data through $found.

  $cmd

That is a known failure mode: an arbitrary limit or truncation on a search silently drops
real data with no error, so a missing result is indistinguishable from a result that does
not exist.

Run it complete. If the output is genuinely enormous, say out loud why a bound is needed
and choose the bound deliberately — and read the whole thing first to know that it is
enormous, rather than assuming.

(Matched against $WATCHLIST — edit that file if this command shouldn't have been flagged,
or if a real search tool is missing from it.)
EOF
exit 2
