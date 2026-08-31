#!/usr/bin/env bash
# run-all.sh — the FAST tier: every tools/tests/test-*.sh NOT marked '# TIER: slow' in its
# first three lines (first three only, so a test that merely MENTIONS the marker — in a
# heredoc, a comment, an assertion — is not silently reclassified). Nonzero exit on ANY
# failure. No skips: a test that can't run its subject fails loudly (lib.sh `need`).
#
# Files run in PARALLEL, output buffered per file and printed in order. Every test file
# already builds its own mktemp sandbox (lib.sh), which is what makes this safe; a test
# that needs an exclusive global resource (a live Xcode, a launchd job) belongs in the
# slow tier, where files still run one at a time.
#
# THE TIME BUDGET IS AN ASSERTION, NOT A HOPE. Jonathan will not watch more than fifteen
# seconds of basic tests, so this tier fails itself when it runs over — a suite that
# quietly grows past the budget stops being run, which is worse than any single failure.
# When it trips: make the culprit faster or mark it '# TIER: slow' (run-slow.sh picks it
# up). ASTRA_FAST_BUDGET_S overrides the budget; its only legitimate uses are the RED
# control in test-run-tiers.sh and a deliberately slower CI box.
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
BUDGET="${ASTRA_FAST_BUDGET_S:-15}"
JOBS="${ASTRA_FAST_JOBS:-8}"
start=$(date +%s)

TMPOUT="$(mktemp -d -t astra-fast-tier)"
trap 'rm -rf "$TMPOUT"' EXIT

fast=(); slow=0
for t in "$HERE"/test-*.sh; do
  [ -f "$t" ] || { echo "no tests found in $HERE"; exit 1; }
  if head -3 "$t" | grep -q '^# TIER: slow'; then slow=$((slow+1)); continue; fi
  fast+=("$t")
done
if [ "${#fast[@]}" -eq 0 ]; then
  echo "fast tier ran ZERO test files — every file is marked slow or the glob is broken" >&2
  exit 1
fi

printf '%s\n' "${fast[@]}" | TMPOUT="$TMPOUT" xargs -P "$JOBS" -I{} bash -c '
  f="{}"; b="$(basename "$f")"
  bash "$f" >"$TMPOUT/$b.out" 2>&1
  echo $? >"$TMPOUT/$b.rc"
' || true   # per-file verdicts come from the rc files, not xargs's own exit

overall=0; ran=0
for t in "${fast[@]}"; do
  b="$(basename "$t")"
  echo "── $b"
  cat "$TMPOUT/$b.out"
  rc="$(cat "$TMPOUT/$b.rc" 2>/dev/null || echo missing)"
  if [ "$rc" != "0" ]; then
    [ "$rc" = "missing" ] && echo "  FAIL: $b never reported an exit code — killed mid-run?" >&2
    overall=1
  fi
  ran=$((ran+1))
done

elapsed=$(( $(date +%s) - start ))
echo ""
[ "$slow" -gt 0 ] && echo "(skipped $slow slow-tier file(s) — run-slow.sh runs them)"
if [ "$elapsed" -gt "$BUDGET" ]; then
  echo "FAST TIER OVER BUDGET: took ${elapsed}s, budget is ${BUDGET}s. Make the culprit faster" >&2
  echo "or move it to the slow tier ('# TIER: slow' in the file's first three lines)." >&2
  overall=1
fi
if [ "$overall" -eq 0 ]; then echo "ALL GREEN ($ran fast test files, ${elapsed}s)"; else echo "FAILURES PRESENT ($ran fast test files, ${elapsed}s) — fix before shipping"; fi
exit "$overall"
