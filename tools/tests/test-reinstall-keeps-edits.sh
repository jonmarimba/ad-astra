#!/usr/bin/env bash
# test-reinstall-keeps-edits.sh — a file the user edited after astra placed it is the user's.
# QUICKSTART calls a re-run of the install the update path, and uninstall is the removal path.
# Neither may throw a hand edit away without a word. ASTRA_FORCE=1 is the explicit override.
#
# Real astra, real check-prose installer, real git repo.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
need git "xcode-select --install"
need python3 "xcode-select --install"
need jq "brew install jq"
ASTRA="$ASTRA_ROOT/tools/astra"
export HOME="$SB/home"; mkdir -p "$HOME"
R="$SB/repo"; mkdir -p "$R"; git -C "$R" init -q
F="$R/.astra/check-prose/check-prose.js"

"$ASTRA" add check-prose --into "$R" > /dev/null 2>&1
assert_file "$F" "(setup) installed"
cp "$F" "$SB/original.js"
recorded="$(jq -r '.tools["check-prose"].files | to_entries[0].value' "$R/.astra/manifest.json")"

echo "== re-running the install after a hand edit"
echo "// my local change" >> "$F"
"$ASTRA" add check-prose --into "$R" > "$SB/re1.out" 2> "$SB/re1.err"
assert_eq 0 "$?" "the re-run succeeds"
assert_contains "$F" "// my local change" "RED: the hand edit is still there"
assert_contains "$SB/re1.err" "kept your edited" "RED: and the run says it kept the file"
assert_eq "$recorded" "$(jq -r '.tools["check-prose"].files | to_entries[0].value' "$R/.astra/manifest.json")" "the manifest still records the hash astra placed, so the updater keeps flagging the edit"
"$R/.astra/astra-update" > "$SB/upd.out" 2>&1; rc=$?
assert_eq 1 "$rc" "astra-update still reports the edit as needing a human"
assert_contains "$SB/upd.out" "LOCAL EDITS" "and names it"

echo "== ASTRA_FORCE=1 overwrites"
ASTRA_FORCE=1 "$ASTRA" add check-prose --into "$R" > /dev/null 2>&1
if cmp -s "$F" "$SB/original.js"; then pass "the forced re-run restores the shipped file"; else fail "ASTRA_FORCE=1 did not restore the shipped file"; fi

echo "== an untouched file is still refreshed normally"
"$ASTRA" add check-prose --into "$R" > "$SB/re2.out" 2> "$SB/re2.err"
assert_eq 0 "$?" "a re-run over an untouched file succeeds"
if grep -q "kept your edited" "$SB/re2.err"; then fail "an untouched file was reported as edited"; else pass "and says nothing about edits"; fi

echo "== uninstall"
echo "// edited again" >> "$F"
"$ASTRA" remove check-prose --into "$R" > "$SB/un1.out" 2> "$SB/un1.err"
assert_eq 0 "$?" "uninstall succeeds"
assert_file "$F" "RED: the edited file is kept, not deleted"
assert_contains "$SB/un1.err" "kept your edited" "RED: and uninstall says so"
rm -rf "$R"; mkdir -p "$R"; git -C "$R" init -q
"$ASTRA" add check-prose --into "$R" > /dev/null 2>&1
"$ASTRA" remove check-prose --into "$R" > /dev/null 2>&1
assert_no_file "$F" "an untouched file is removed as before"
finish
