#!/usr/bin/env bash
# test-pdf-sidecars-setup.sh — the hook add/refresh/coexist/subtract lifecycle against real git
# repos (the fixture paths that caught the mystery-bot edit on 2026-08-12, made permanent).
# setup.sh wires the repo ENCLOSING the kit, so each fixture repo gets the kit copied in.
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
KIT_SRC="$HERE/../pdf-sidecars"
need git "xcode-select --install"
need zsh "macOS"

mkrepo(){ # mkrepo <dir> -> a real git repo with the kit copied in; echoes kit path
  mkdir -p "$1/tools"; git -C "$1" init -q
  cp -R "$KIT_SRC" "$1/tools/pdf-sidecars"
  echo "$1/tools/pdf-sidecars"
}

# ---- A: fresh repo, no hook ----
A="$SB/repoA"; KA="$(mkrepo "$A")"
assert_rc 0 "fresh repo: setup succeeds" "$KA/setup.sh"
HOOK_A="$A/.git/hooks/pre-commit"
assert_file "$HOOK_A" "hook created"
assert_contains "$HOOK_A" ">>> pdf-sidecars pre-commit" "managed block present"
[ -x "$HOOK_A" ] && pass "hook is executable" || fail "hook not executable"
assert_eq "$(cd "$KA" && pwd -P)" "$(git -C "$A" config jsutils.path)" "jsutils.path recorded (canonicalized — zsh :A resolves /var -> /private/var)"
"$KA/setup.sh" >/dev/null
n="$(grep -cF '>>> pdf-sidecars pre-commit' "$HOOK_A")"
assert_eq "1" "$n" "re-run refreshed, did not duplicate the block"

# ---- B: foreign PDF hook with a trailing exit — guarded refusal, then coexist ----
B="$SB/repoB"; KB="$(mkrepo "$B")"
mkdir -p "$B/.git/hooks"
cat > "$B/.git/hooks/pre-commit" <<'EOF'
#!/bin/bash
./scripts/generate_pdf_sidecars.sh
exit 0
EOF
chmod +x "$B/.git/hooks/pre-commit"
cp "$B/.git/hooks/pre-commit" "$SB/B.orig"
red "foreign PDF hook + no mode: setup must REFUSE" 2 "Not touching it" "$KB/setup.sh"
cmp -s "$SB/B.orig" "$B/.git/hooks/pre-commit" && pass "refusal left the foreign hook byte-identical" || fail "guarded refusal MODIFIED the foreign hook"
assert_rc 0 "coexist mode succeeds" "$KB/setup.sh" --coexist
HOOK_B="$B/.git/hooks/pre-commit"
assert_contains "$HOOK_B" ">>> pdf-sidecars pre-commit" "kit block added in coexist"
assert_contains "$HOOK_B" "generate_pdf_sidecars.sh" "foreign hook content preserved"
kit_line="$(grep -nF '>>> pdf-sidecars pre-commit' "$HOOK_B" | cut -d: -f1)"
exit_line="$(grep -nE '^exit' "$HOOK_B" | tail -1 | cut -d: -f1)"
[ "$kit_line" -lt "$exit_line" ] && pass "kit block inserted BEFORE the trailing exit (not dead code)" || fail "kit block landed after the trailing exit — dead code"
ls "$HOOK_B".bak.* >/dev/null 2>&1 && pass "foreign hook backed up before coexist" || fail "no backup taken before coexist"

# ---- C: replace mode takes over ----
C="$SB/repoC"; KC="$(mkrepo "$C")"
mkdir -p "$C/.git/hooks"
printf '#!/bin/bash\n./scripts/generate_pdf_sidecars.sh\n' > "$C/.git/hooks/pre-commit"
chmod +x "$C/.git/hooks/pre-commit"
assert_rc 0 "replace mode succeeds" "$KC/setup.sh" --replace
assert_not_contains "$C/.git/hooks/pre-commit" "generate_pdf_sidecars.sh" "replace removed the foreign hook body"
assert_contains "$C/.git/hooks/pre-commit" ">>> pdf-sidecars pre-commit" "replace installed the managed block"
ls "$C/.git/hooks/pre-commit".bak.* >/dev/null 2>&1 && pass "replace backed up the old hook first" || fail "replace took over without a backup"

# ---- subtract: exact inverse, preserves foreign content ----
assert_rc 0 "subtract succeeds on the coexist repo" "$KB/hook-subtract.sh"
assert_not_contains "$HOOK_B" "pdf-sidecars pre-commit" "managed block removed"
assert_contains "$HOOK_B" "generate_pdf_sidecars.sh" "foreign content survived subtract"
git -C "$B" config jsutils.path >/dev/null 2>&1 && fail "jsutils.path not unset by subtract" || pass "jsutils.path unset by subtract"

# ---- RED control ----
red "unknown option must fail" 64 "unknown option" "$KA/setup.sh" --frobnicate

finish
