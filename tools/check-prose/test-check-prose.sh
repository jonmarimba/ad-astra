#!/bin/bash
# test-check-prose.sh — RED-capable tests for the prose checker's rule loading.
#
# The checker gates writing that goes to clients and attorneys, so the failure
# that costs most is not a missed word. It is the checker reporting success
# while nothing is being checked. A Codex review found several one-line files a
# repo could drop in to achieve exactly that, and every one of them left the
# exit code at 0.
#
# These tests attack the loader, not the prose rules. Adding a banned word does
# not need a test; being unable to silently remove one does.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CP="$HERE/check-prose.js"
PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "MISSING DEPENDENCY: $1 — install it, do not skip"; exit 1; }
}
need node

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
# The checker reads .check-prose.json from the CURRENT directory, so each test
# writes its own and runs from here.
printf 'This matters a great deal and the approach is robust.\n' > dirty.md
printf 'The team shipped the release on Tuesday.\n' > clean.md

echo "== 1. Controls: dirty prose fails, clean prose passes =="
# Without these the rest proves nothing — every later test could pass because
# the checker flags everything, or nothing.
node "$CP" dirty.md >/dev/null 2>&1
[ $? -ne 0 ] && ok "banned vocabulary is flagged and exit is nonzero" \
             || bad "dirty prose passed — the checker is not checking"
node "$CP" clean.md >/dev/null 2>&1
[ $? -eq 0 ] && ok "clean prose exits 0" \
             || bad "clean prose was flagged — false positives make it ignorable"

echo "== 2. An empty pattern list must NOT disable a category =="
echo '{"self_referential":{"patterns":[]}}' > .check-prose.json
out="$(node "$CP" dirty.md 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "may add rules, not remove"; then
  ok "empty override kept the defaults and said so"
else
  bad "a one-line file switched off a rule category (rc=$rc)"
fi

echo "== 3. An invalid pattern must name itself, not stack-trace =="
echo '{"self_referential":{"patterns":["^(unclosed"]}}' > .check-prose.json
out="$(node "$CP" clean.md 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q "invalid pattern"; then
  ok "bad pattern reported by name, exit 2"
else
  bad "invalid pattern did not produce a clean error (rc=$rc)"
fi
if echo "$out" | grep -q "at Object\|node:internal"; then
  bad "leaked a stack trace"
else
  ok "no stack trace"
fi

echo "== 4. A wholesale replacement must announce itself =="
echo '{"label_fragment":{"verbish":".*"}}' > .check-prose.json
out="$(node "$CP" clean.md 2>&1)"
if echo "$out" | grep -q "REPLACES"; then
  ok "narrowing override announced"
else
  bad "a category was replaced silently"
fi

echo "== 5. Additive override must still work — it is the documented purpose =="
# The control for tests 2 and 4. A loader that refused every override would
# pass those and fail here.
echo '{"banned_words":["zebrafish"]}' > .check-prose.json
printf 'The zebrafish swims.\n' > extra.md
out="$(node "$CP" extra.md 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "zebrafish"; then
  ok "repo-specific word was added and flagged"
else
  bad "additive override no longer works (rc=$rc)"
fi
# and the defaults must survive alongside it
out="$(node "$CP" dirty.md 2>&1)"
if echo "$out" | grep -q "matters"; then
  ok "defaults survived the addition"
else
  bad "adding a word dropped the built-in list"
fi

echo "== 6. A rules entry containing regex characters is a literal =="
echo '{"banned_words":["c++"]}' > .check-prose.json
printf 'We wrote it in c++ last year.\n' > lit.md
out="$(node "$CP" lit.md 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
  ok "literal with regex characters matched as written"
else
  bad "a word containing regex syntax silently changed meaning (rc=$rc)"
fi

echo "== 7. Unreadable local file must refuse, not run on partial rules =="
echo 'not json at all' > .check-prose.json
out="$(node "$CP" clean.md 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -qi "unreadable"; then
  ok "malformed override refused loudly"
else
  bad "malformed override did not stop the run (rc=$rc)"
fi

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
