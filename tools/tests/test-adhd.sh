#!/usr/bin/env bash
# test-adhd.sh — adhd installs into a repo, lands where it should, and uninstalls cleanly.
# Replace or extend these checks with ones for what the tool does.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
need git "xcode-select --install"
export HOME="$SB/home"; mkdir -p "$HOME"
R="$SB/repo"; mkdir -p "$R"; git -C "$R" init -q

bash "$ASTRA_ROOT/tools/adhd/install.sh" --into "$R" > "$SB/install.out" 2>&1
assert_eq 0 "$?" "install succeeds"
assert_file "$R/.claude/skills/adhd/SKILL.md" "the payload landed in the repo"
bash "$ASTRA_ROOT/tools/adhd/uninstall.sh" --into "$R" > "$SB/uninstall.out" 2>&1
assert_eq 0 "$?" "uninstall succeeds"
if [ -e "$R/.claude/skills/adhd/SKILL.md" ]; then fail "the payload is still in the repo after uninstall"; else pass "the payload is gone after uninstall"; fi
bash "$ASTRA_ROOT/tools/adhd/install.sh" > "$SB/red.out" 2>&1
assert_eq 64 "$?" "RED: install without --into exits 64"
finish
