#!/usr/bin/env bash
# test-install-doctrine.sh — the shared doctrine installer: copies a doctrine md into <repo>/.doctrine
# and writes a repo-RELATIVE @-import block into CLAUDE.md/AGENTS.md; refresh is idempotent; uninstall
# removes block + file; QWEN.md only touched if it already exists; bad slugs/paths refused.
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
INS="$HERE/../lib/install-doctrine.sh"
UNI="$HERE/../lib/uninstall-doctrine.sh"

REPO="$SB/repo"; mkdir -p "$REPO"
printf '# Project\nkeep this prose.\n' > "$REPO/CLAUDE.md"
DOC="$SB/mydoctrine.md"; printf '# Doctrine\nrule one.\nrule two.\n' > "$DOC"

# ---- install ----
assert_rc 0 "install succeeds" "$INS" "$REPO" "$DOC" --slug convocation
assert_file "$REPO/.doctrine/convocation.md" "doctrine file copied into repo"
[ -s "$REPO/.doctrine/convocation.md" ] && pass "copied doctrine non-empty" || fail "copied doctrine empty"
assert_contains "$REPO/CLAUDE.md" ">>> doctrine:convocation" "managed block present in CLAUDE.md"
assert_contains "$REPO/CLAUDE.md" "@.doctrine/convocation.md" "import is repo-relative"
assert_not_contains "$REPO/CLAUDE.md" "/Users/" "NO absolute machine path leaked"
assert_contains "$REPO/CLAUDE.md" "keep this prose." "pre-existing prose untouched"
assert_file "$REPO/AGENTS.md" "AGENTS.md created + block written"

# ---- QWEN.md only if it already exists ----
assert_no_file "$REPO/QWEN.md" "QWEN.md NOT invented when absent"
printf '# qwen\n' > "$REPO/QWEN.md"
"$INS" "$REPO" "$DOC" --slug convocation >/dev/null
assert_contains "$REPO/QWEN.md" ">>> doctrine:convocation" "existing QWEN.md gets the block on refresh"

# ---- idempotent refresh: exactly one block ----
"$INS" "$REPO" "$DOC" --slug convocation >/dev/null
n="$(grep -cF '>>> doctrine:convocation' "$REPO/CLAUDE.md")"
assert_eq "1" "$n" "refresh left exactly one block (no duplicate)"

# ---- a second, different doctrine coexists (distinct slug) ----
DOC2="$SB/other.md"; printf '# other\n' > "$DOC2"
"$INS" "$REPO" "$DOC2" --slug geo-evidence >/dev/null
assert_contains "$REPO/CLAUDE.md" ">>> doctrine:geo-evidence" "second slug coexists"
assert_contains "$REPO/CLAUDE.md" ">>> doctrine:convocation" "first slug still present"

# ---- uninstall removes only the named block + its file ----
assert_rc 0 "uninstall convocation" "$UNI" "$REPO" --slug convocation
assert_not_contains "$REPO/CLAUDE.md" "doctrine:convocation" "convocation block gone"
assert_no_file "$REPO/.doctrine/convocation.md" "convocation doctrine file removed"
assert_contains "$REPO/CLAUDE.md" "doctrine:geo-evidence" "OTHER slug survived the targeted uninstall"
assert_contains "$REPO/CLAUDE.md" "keep this prose." "pre-existing prose still intact"

# ---- RED ----
red "missing --slug must fail" 64 "usage: install-doctrine.sh" "$INS" "$REPO" "$DOC"
red "path-shaped slug must fail (../ escape)" 64 "bad --slug '../evil'" "$INS" "$REPO" "$DOC" --slug "../evil"
red "slug with slash must fail" 64 "bad --slug 'a/b'" "$INS" "$REPO" "$DOC" --slug "a/b"
red "missing doctrine file must fail" 1 "no such doctrine file" "$INS" "$REPO" "$SB/nope.md" --slug x
red "missing repo must fail" 1 "no such repo" "$INS" "$SB/norepo" "$DOC" --slug x

finish
