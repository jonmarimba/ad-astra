#!/usr/bin/env bash
# run-slow.sh — the SLOW tier: every tools/tests/test-*.sh marked '# TIER: slow', plus the
# template-system tests that live beside their subject in tools/lib and were never picked
# up by run-all.sh's glob at all (found by the 2026-08-31 colloquium; all three brands
# missed different things, this one Claude caught).
#
# "Slow" means it needs a live application (Xcode, an approval dialog), the network, or
# tens of seconds — not "optional". A ship gate runs BOTH tiers. Nonzero exit on ANY
# failure, same as the fast tier.
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
overall=0; ran=0
for t in "$HERE"/test-*.sh; do
  [ -f "$t" ] || { echo "no tests found in $HERE"; exit 1; }
  head -3 "$t" | grep -q '^# TIER: slow' || continue   # first three lines only — a file that merely MENTIONS the marker is not slow
  echo "── $(basename "$t")"
  if bash "$t"; then :; else overall=1; fi
  ran=$((ran+1))
done
for t in "$HERE/../lib/test-templates.sh" "$HERE/../lib/test-astra-update.sh"; do
  [ -f "$t" ] || { echo "MISSING: $t — the template tests moved without this runner following"; overall=1; continue; }
  echo "── lib/$(basename "$t")"
  if bash "$t"; then :; else overall=1; fi
  ran=$((ran+1))
done
if [ "$ran" -eq 0 ]; then
  echo "slow tier ran ZERO test files — nothing is marked '# TIER: slow' and the lib tests are gone" >&2
  exit 1
fi
echo ""
if [ "$overall" -eq 0 ]; then echo "ALL GREEN ($ran slow test files)"; else echo "FAILURES PRESENT ($ran slow test files) — fix before shipping"; fi
exit "$overall"
