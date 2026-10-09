#!/usr/bin/env bash
# test-astra-doctor.sh — `astra doctor` (one report over every astra repo on the machine) and
# `astra sync` telling the truth. sync used to discard every error and print "synced" for a repo
# whose update had failed; the RED half of this file is that case.
#
# Real astra, real template.py and check-prose installer, repos in a sandbox workspace.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

need python3 "xcode-select --install"
need git "xcode-select --install"
need jq "brew install jq"
ASTRA="$ASTRA_ROOT/tools/astra"

WS="$SB/ws"; mkdir -p "$WS/good" "$WS/broken" "$WS/plain"
for r in good broken plain; do git -C "$WS/$r" init -q; done
export HOME="$SB/home"; mkdir -p "$HOME"
"$ASTRA" add check-prose --into "$WS/good" > /dev/null 2>&1
"$ASTRA" add check-prose --into "$WS/broken" > /dev/null 2>&1
assert_file "$WS/good/.astra/manifest.json" "(setup) a repo with an astra tool installed"

echo "== doctor on healthy repos"
"$ASTRA" doctor "$WS" > "$SB/doctor-ok.out" 2>&1; rc=$?
assert_eq 0 "$rc" "doctor exits 0 when every repo is healthy"
assert_contains "$SB/doctor-ok.out" "this machine" "it starts with the machine prerequisites"
assert_contains "$SB/doctor-ok.out" "$(cd "$WS/good" && pwd -P)" "it names each repo that has astra tools"
assert_contains "$SB/doctor-ok.out" "check-prose" "it shows what the repo has installed"
assert_contains "$SB/doctor-ok.out" "2 repo(s), 0 problem(s)" "and counts the repos it found"
if grep -q "$(cd "$WS/plain" && pwd -P)" "$SB/doctor-ok.out"; then fail "doctor listed a repo that has no astra tools"; else pass "a repo with no astra tools is not listed"; fi

echo "== doctor and sync on a broken repo"
rm -f "$WS/broken/.astra/astra-update"
"$ASTRA" doctor "$WS" > "$SB/doctor-bad.out" 2>&1; rc=$?
assert_eq 1 "$rc" "RED: doctor exits 1 when a repo lost its updater"
assert_contains "$SB/doctor-bad.out" "MISSING  .astra/astra-update" "RED: and names what is missing"
# Wiring the hooks fails when an existing post-commit hook is not a shell script: astra refuses to edit it.
printf '#!/usr/bin/perl\nprint "not shell\\n";\n' > "$WS/broken/.git/hooks/post-commit"; chmod +x "$WS/broken/.git/hooks/post-commit"
"$ASTRA" sync "$WS" > "$SB/sync-bad.out" 2> "$SB/sync-bad.err"; rc=$?
assert_eq 1 "$rc" "RED: sync exits 1 when it cannot wire one repo's hooks"
assert_contains "$SB/sync-bad.err" "FAILED" "RED: sync says FAILED for that repo"
assert_contains "$SB/sync-bad.err" "not a shell script" "RED: and shows the reason"
assert_contains "$SB/sync-bad.out" "synced $(cd "$WS/good" && pwd -P)" "a healthy repo is still synced"
if grep -q "synced $(cd "$WS/broken" && pwd -P)" "$SB/sync-bad.out"; then fail "RED: sync printed 'synced' for the repo it could not wire"; else pass "RED: sync does not claim the failed repo synced"; fi

echo "== a hand-edited file is a note, not a failure"
rm -f "$WS/broken/.git/hooks/post-commit"
echo "// local edit" >> "$WS/broken/.astra/check-prose/check-prose.js"
"$ASTRA" sync "$WS" > "$SB/sync-edit.out" 2> "$SB/sync-edit.err"; rc=$?
assert_eq 0 "$rc" "sync exits 0 when a repo only has a hand-edited file"
assert_contains "$SB/sync-edit.out" "LOCAL EDITS" "and shows the updater's note about it"

echo "== the tree verb"
"$ASTRA" tree writing > "$SB/tree.out" 2>&1
assert_eq 0 "$?" "astra tree <set> works"
assert_contains "$SB/tree.out" "writing/" "and prints the set"
finish
