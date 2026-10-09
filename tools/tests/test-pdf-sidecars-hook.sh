#!/usr/bin/env bash
# test-pdf-sidecars-hook.sh — what `pdf-sidecars/install.sh --into` does to a repo's pre-commit hook.
# Three promises: it keeps every line of the repo's own hook that is not the old hand-rolled sidecar
# call (a repo guard living in the same hook must survive); it takes a backup only when it adopts a
# hook it has not managed before, not on every re-run; and uninstall removes only its own block.
#
# The real installer and uninstaller against real git repos. Machine dependencies are not touched:
# --into places repo files only.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
need git "xcode-select --install"
need python3 "xcode-select --install"
INST="$ASTRA_ROOT/tools/pdf-sidecars/install.sh"
UNINST="$ASTRA_ROOT/tools/pdf-sidecars/uninstall.sh"
export HOME="$SB/home"; mkdir -p "$HOME"
MARK="# >>> pdf-sidecars (managed by astra) >>>"

mkrepo() { mkdir -p "$SB/$1"; git -C "$SB/$1" init -q; echo "$SB/$1"; }
backups() { ls "$1/.git/hooks/" 2>/dev/null | grep -c '^pre-commit\.bak\.' | tr -d ' '; }

echo "== a repo with no hook"
R1="$(mkrepo fresh)"
bash "$INST" --into "$R1" > "$SB/i1.out" 2>&1
assert_eq 0 "$?" "install succeeds"
assert_contains "$R1/.git/hooks/pre-commit" "$MARK" "the managed block is in the hook"
assert_eq 0 "$(backups "$R1")" "no backup, because there was nothing to back up"
bash "$INST" --into "$R1" > "$SB/i1b.out" 2>&1
assert_eq 1 "$(grep -cF "$MARK" "$R1/.git/hooks/pre-commit" | tr -d ' ')" "a second install leaves exactly one managed block"
assert_eq 0 "$(backups "$R1")" "and still no backup"

echo "== a repo hook that holds its own guard and the old sidecar call"
R2="$(mkrepo guarded)"
printf '#!/bin/bash\n# repo guard: never commit deletions of scraped evidence\necho GUARD-RAN\n./scripts/generate_pdf_sidecars.sh\n' > "$R2/.git/hooks/pre-commit"; chmod +x "$R2/.git/hooks/pre-commit"
bash "$INST" --into "$R2" > "$SB/i2.out" 2>&1
assert_eq 0 "$?" "install succeeds over it"
assert_contains "$R2/.git/hooks/pre-commit" "echo GUARD-RAN" "the repo's own guard survives"
assert_contains "$R2/.git/hooks/pre-commit" "$MARK" "the managed block is added"
if grep -v '^[[:space:]]*:' "$R2/.git/hooks/pre-commit" | grep -v '^[[:space:]]*#' | grep -q 'generate_pdf_sidecars'; then fail "the old sidecar call still runs as a command"; else pass "the old sidecar call no longer runs, so sidecars are not generated twice"; fi
assert_eq 1 "$(backups "$R2")" "one backup of the original hook"
bash "$INST" --into "$R2" > "$SB/i2b.out" 2>&1
bash "$INST" --into "$R2" > "$SB/i2c.out" 2>&1
assert_eq 1 "$(backups "$R2")" "RED: re-running the installer does not pile up more backups"
assert_eq 1 "$(grep -cF "$MARK" "$R2/.git/hooks/pre-commit" | tr -d ' ')" "RED: and does not duplicate the block"
assert_contains "$R2/.git/hooks/pre-commit" "echo GUARD-RAN" "the guard is still there after three installs"

echo "== uninstall"
bash "$UNINST" --into "$R2" > "$SB/u2.out" 2>&1
assert_eq 0 "$?" "uninstall succeeds"
if grep -qF "$MARK" "$R2/.git/hooks/pre-commit"; then fail "the managed block is still in the hook"; else pass "the managed block is gone"; fi
assert_contains "$R2/.git/hooks/pre-commit" "echo GUARD-RAN" "the repo's own guard survives uninstall"
assert_contains "$SB/u2.out" "pre-commit.bak" "uninstall tells the user the backup of their original hook is still there"
finish
