#!/usr/bin/env bash
# run-all.sh — run every tools/tests/test-*.sh, report per-file and overall. Nonzero exit on
# ANY failure. No skips: a test that can't run its subject fails loudly (lib.sh `need`).
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
overall=0; ran=0
for t in "$HERE"/test-*.sh; do
  [ -f "$t" ] || { echo "no tests found in $HERE"; exit 1; }
  echo "── $(basename "$t")"
  if bash "$t"; then :; else overall=1; fi
  ran=$((ran+1))
done
echo ""
if [ "$overall" -eq 0 ]; then echo "ALL GREEN ($ran test files)"; else echo "FAILURES PRESENT ($ran test files) — fix before shipping"; fi
exit "$overall"
