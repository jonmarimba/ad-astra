#!/usr/bin/env bash
# test-template-partial-rollback.sh — a partial install rolls back successfully-installed
# members so they are not orphaned on disk with no template claiming them.
#
# The bug (GhOST-OpenClaw peer review of 362b4ba4): if member A installs and member B
# fails, the template is (correctly) not recorded. But member A's files stay on disk,
# and `template.py uninstall` refuses because the template is not recorded — so the user
# has no path to remove those files through the template interface. The fix is transactional
# rollback: on install failure, uninstall the members that succeeded.
#
# Exercised against the REAL template.py with TWO STUB TOOLS created in the sandbox:
# stub-ok (installs a marker file, has uninstall.sh) and stub-fail (install.sh exits 1).
# The stubs are symlinked into the real tools/ dir for the test and removed on exit.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

need python3 "xcode-select --install"
need git "system-present"
TPL="$HERE/../lib/template.py"
TOOLS_DIR="$HERE/../tools"  # NOT used — template.py resolves tools/ from its own location
ASTRA_TOOLS="$(cd "$HERE/../../tools" && pwd)"

# --- create stub tools in the sandbox, then symlink into astra/tools/ ---
STUB_OK="$SB/stub-ok"
STUB_FAIL="$SB/stub-fail"
mkdir -p "$STUB_OK" "$STUB_FAIL"

cat > "$STUB_OK/install.sh" <<'INST'
#!/usr/bin/env bash
# astra-scope: repo
set -euo pipefail
repo=""
while [ $# -gt 0 ]; do case "$1" in --into) repo="$2"; shift 2;; *) shift;; esac; done
[ -n "$repo" ] || { echo "no --into" >&2; exit 1; }
mkdir -p "$repo/.astra/stub-ok"
echo "installed" > "$repo/.astra/stub-ok/marker.txt"
INST
chmod +x "$STUB_OK/install.sh"

cat > "$STUB_OK/uninstall.sh" <<'UNINST'
#!/usr/bin/env bash
set -euo pipefail
repo=""
while [ $# -gt 0 ]; do case "$1" in --into) repo="$2"; shift 2;; *) shift;; esac; done
[ -n "$repo" ] || { echo "no --into" >&2; exit 1; }
rm -rf "$repo/.astra/stub-ok"
UNINST
chmod +x "$STUB_OK/uninstall.sh"

cat > "$STUB_FAIL/install.sh" <<'FAIL'
#!/usr/bin/env bash
# astra-scope: repo
echo "deliberate failure for test" >&2
exit 1
FAIL
chmod +x "$STUB_FAIL/install.sh"

# Symlink the stubs into the real tools dir so template.py finds them.
ln -sfn "$STUB_OK" "$ASTRA_TOOLS/stub-ok"
ln -sfn "$STUB_FAIL" "$ASTRA_TOOLS/stub-fail"
# Clean up the symlinks on exit (the sandbox cleanup handles the stubs themselves).
_cleanup_stubs(){ rm -f "$ASTRA_TOOLS/stub-ok" "$ASTRA_TOOLS/stub-fail"; }
trap '_cleanup_stubs; _lib_cleanup' EXIT

REPO="$SB/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q

CAT="$SB/templates.json"
cat > "$CAT" <<'EOF'
{"templates": {
  "partial-test": {"description": "first member succeeds, second fails",
                   "tools": ["stub-ok", "stub-fail"]}
}}
EOF

# --- partial install: stub-ok succeeds, stub-fail fails -> rollback ---
out="$SB/partial.out"
ASTRA_TEMPLATES_JSON="$CAT" python3 "$TPL" install partial-test --into "$REPO" >"$out" 2>&1
rc=$?
assert_eq "1" "$rc" "partial install exits nonzero"
assert_no_file "$REPO/.astra/stub-ok/marker.txt" \
  "stub-ok was rolled back — its marker file is gone (no orphan)"
assert_contains "$out" "ROLLED BACK" "the output says stub-ok was rolled back"
assert_contains "$out" "FAILED" "the output says stub-fail failed"
# Verify the template is not in the manifest (the NOT-recording stderr message is expected;
# what we care about is the manifest state).
if python3 -c "
import json, sys
p = '$REPO/.astra/manifest.json'
try: d = json.loads(open(p).read())
except: sys.exit(0)
sys.exit(1 if 'partial-test' in d.get('templates_installed',{}) else 0)
"; then
  pass "the template is NOT recorded in the manifest (no orphan claim)"
else
  fail "the template is recorded in the manifest despite partial failure"
fi

# --- verify uninstall is not blocked by phantom state ---
out2="$SB/uninstall-after-partial.out"
ASTRA_TEMPLATES_JSON="$CAT" python3 "$TPL" uninstall partial-test --into "$REPO" >"$out2" 2>&1
# This should say "not recorded as installed" — which is correct, because the rollback
# cleaned up and nothing was recorded.
assert_contains "$out2" "not recorded as installed" \
  "uninstall correctly reports the template was never recorded (rollback was clean)"

# --- RED control: a clean install (no failing member) does NOT roll back ---
CAT_CLEAN="$SB/templates-clean.json"
cat > "$CAT_CLEAN" <<'EOF'
{"templates": {
  "clean-test": {"description": "only the working member", "tools": ["stub-ok"]}
}}
EOF
out3="$SB/clean.out"
ASTRA_TEMPLATES_JSON="$CAT_CLEAN" python3 "$TPL" install clean-test --into "$REPO" >"$out3" 2>&1
rc3=$?
assert_eq "0" "$rc3" "clean install succeeds"
assert_file "$REPO/.astra/stub-ok/marker.txt" \
  "RED control: a clean install keeps the marker file (no spurious rollback)"
assert_not_contains "$out3" "ROLLED BACK" \
  "RED control: no rollback message on a clean install"

# --- RED control: the partial install MUST fail, not silently succeed ---
REPO_RED="$SB/repo-red"; mkdir -p "$REPO_RED"; git -C "$REPO_RED" init -q
red "a partial install is not silently successful" 1 "FAILED" \
  env ASTRA_TEMPLATES_JSON="$CAT" python3 "$TPL" install partial-test --into "$REPO_RED"

# --- rollback respects shared claims: if another template also claims stub-ok, it is kept ---
CAT_SHARED="$SB/templates-shared.json"
cat > "$CAT_SHARED" <<'EOF'
{"templates": {
  "other": {"description": "also claims stub-ok", "tools": ["stub-ok"]},
  "partial-shared": {"description": "shares stub-ok, also has stub-fail",
                     "tools": ["stub-ok", "stub-fail"]}
}}
EOF
REPO2="$SB/repo2"; mkdir -p "$REPO2"; git -C "$REPO2" init -q
# Install the other template first so stub-ok is claimed.
ASTRA_TEMPLATES_JSON="$CAT_SHARED" python3 "$TPL" install other --into "$REPO2" >/dev/null 2>&1
assert_file "$REPO2/.astra/stub-ok/marker.txt" "precondition: stub-ok installed by other template"
out4="$SB/shared-partial.out"
ASTRA_TEMPLATES_JSON="$CAT_SHARED" python3 "$TPL" install partial-shared --into "$REPO2" >"$out4" 2>&1
assert_file "$REPO2/.astra/stub-ok/marker.txt" \
  "stub-ok survives rollback because another template still claims it"
assert_contains "$out4" "KEPT" "rollback reports that stub-ok was kept (shared claim)"

# --- rollback leaves a tool alone that the repo had BEFORE this run ---
# Found reviewing GhOST's rollback (2026-10-05): stub-ok installed by hand, with no
# template claiming it, was deleted when a later template containing it failed.
REPO3="$SB/repo3"; mkdir -p "$REPO3"; git -C "$REPO3" init -q
"$STUB_OK/install.sh" --into "$REPO3"
assert_file "$REPO3/.astra/stub-ok/marker.txt" "precondition: stub-ok installed by hand, no template"
out5="$SB/preexisting-partial.out"
ASTRA_TEMPLATES_JSON="$CAT" python3 "$TPL" install partial-test --into "$REPO3" >"$out5" 2>&1
assert_file "$REPO3/.astra/stub-ok/marker.txt" \
  "a tool installed before the failed run survives its rollback"
assert_contains "$out5" "installed before this run" "rollback says why it kept stub-ok"
assert_not_contains "$out5" "ROLLED BACK  stub-ok" "RED control: stub-ok is not rolled back"

finish
