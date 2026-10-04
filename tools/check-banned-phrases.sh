#!/usr/bin/env bash
# check-banned-phrases.sh — read text on stdin or from a file, report banned phrases.
#
# The list lives in agents-and-prompts/doctrine/banned-phrases.txt (this repo, js-db-ad-astra)
# and is the ONLY copy — canonical home as of 2026-09-19 (moved from js-project-GhOST/policy so
# any repo, not just GhOST, can reach it). The GhOST path policy/banned-phrases.txt is now a
# symlink to this file. Override with BANNED_PHRASES=/path. Four prose copies with four
# different memberships is what this replaces.
#
#   check-banned-phrases.sh FILE...        check files
#   ... | check-banned-phrases.sh          check stdin
#   check-banned-phrases.sh --list         print the active list
#
# Exit 0 clean, 1 when something matched, 3 when the list itself is missing —
# a checker that cannot find its list must not report "clean".
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="${BANNED_PHRASES:-$HERE/../agents-and-prompts/doctrine/banned-phrases.txt}"

[ -f "$LIST" ] || { echo "check-banned-phrases: list not found at $LIST" >&2; exit 3; }

if [ "${1:-}" = "--list" ]; then
  grep -v '^#' "$LIST" | grep -v '^[[:space:]]*$'
  exit 0
fi

TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
if [ "$#" -gt 0 ]; then cat "$@" > "$TMP"; else cat > "$TMP"; fi

hits=0
while IFS= read -r phrase; do
  case "$phrase" in ''|'#'*) continue ;; esac
  # -F fixed string, -i case-insensitive, -n line numbers. No regex: the list is
  # literal phrases and Jonathan's standing rule is to avoid regex where plain
  # string scanning does the job. Report EVERY matching line — no head/limit: a
  # checker that shows only the first N violations makes you fix N, re-run, and
  # find the rest, and it undercounts the total (GhOST-OpenClaw peer review of
  # 37c9e571). The match count is small by nature, so completeness is free.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    hits=$((hits+1))
    printf '  %s  <- "%s"\n' "$line" "$phrase"
  done < <(grep -Fin -- "$phrase" "$TMP" 2>/dev/null)
done < "$LIST"

if [ "$hits" -gt 0 ]; then
  echo "check-banned-phrases: $hits banned phrase occurrence(s). See $LIST." >&2
  exit 1
fi
exit 0
