#!/usr/bin/env bash
# test-handlebars-notes-append.sh — `handlebars.sh notes-append` finds the checkout that holds
# notes_html_append.sh from $GHOST_REPO or the astra config file, and refuses when neither names one.
# It used to default to $HOME/svnCheckouts/js-project-GhOST, which exists on one machine.
#
# The real handlebars.sh; the delegate script is a stub that prints what it received.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
HB="$ASTRA_ROOT/tools/handlebars/handlebars.sh"

export HOME="$SB/home"; mkdir -p "$HOME"
unset GHOST_REPO XDG_CONFIG_HOME ASTRA_CONFIG_FILE
printf '<p>x</p>\n' > "$SB/content.html"
mkdir -p "$SB/ghost/tools"
printf '#!/bin/bash\necho "delegate received: $1 | $2"\n' > "$SB/ghost/tools/notes_html_append.sh"

echo "== no checkout named anywhere"
bash "$HB" notes-append "Title" "$SB/content.html" > "$SB/none.out" 2>&1; rc=$?
assert_eq 64 "$rc" "RED: with nothing set, notes-append exits 64"
assert_contains "$SB/none.out" "GHOST_REPO is not set" "RED: and names the setting"
if grep -q "svnCheckouts" "$SB/none.out"; then fail "the message points at a fixed ~/svnCheckouts path"; else pass "the message does not assume ~/svnCheckouts"; fi

echo "== the environment names it"
GHOST_REPO="$SB/ghost" bash "$HB" notes-append "Title" "$SB/content.html" > "$SB/env.out" 2>&1; rc=$?
assert_eq 0 "$rc" "GHOST_REPO in the environment is used"
assert_contains "$SB/env.out" "delegate received: Title | $SB/content.html" "and the delegate got the title and file"

echo "== the config file names it"
mkdir -p "$HOME/.config/astra"; printf 'GHOST_REPO="%s"\n' "$SB/ghost" > "$HOME/.config/astra/config"
bash "$HB" notes-append "Title" "$SB/content.html" > "$SB/cfg.out" 2>&1; rc=$?
assert_eq 0 "$rc" "GHOST_REPO in ~/.config/astra/config is used"

echo "== a path that does not hold the script"
GHOST_REPO="$SB/not-there" bash "$HB" notes-append "Title" "$SB/content.html" > "$SB/bad.out" 2>&1; rc=$?
assert_eq 66 "$rc" "RED: a GHOST_REPO without the script exits 66"
assert_contains "$SB/bad.out" "does not exist" "RED: and says which path"
finish
