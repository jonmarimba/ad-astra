#!/bin/bash
# test-astra-update.sh — RED-capable tests for tool distribution.
#
# These properties used to belong to `registry.py sync`, which pushed files from
# astra into other repos. That mechanism is retired: it had to guess which files
# were its own, and the guess let it overwrite work in a legal repo. Each repo
# now pulls with .astra/astra-update, so the tests live where the behaviour does.
#
# Two things must both hold, and it is easy to get one by sacrificing the other:
#   - a copy nobody touched gets updated (or the whole tool is pointless)
#   - a copy somebody edited is never silently overwritten
# Test 2 is the control for that trade. It passes against both the old and new
# implementations, which is how a fix that merely refuses everything gets caught.

set -u
ASTRA="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "MISSING DEPENDENCY: $1 — install it, do not skip"; exit 1; }
}
need python3
need git

# Astra's own check-prose files are the fixture. They must be restored no matter
# how this exits — a test that leaves the canonical tree modified has broken the
# thing it was checking.
RULES="$ASTRA/tools/check-prose/rules.json"
JS="$ASTRA/tools/check-prose/check-prose.js"
SAVE="$(mktemp -d)"
cp "$RULES" "$SAVE/rules.json"
cp "$JS" "$SAVE/check-prose.js"
cleanup() {
  cp "$SAVE/rules.json" "$RULES"
  cp "$SAVE/check-prose.js" "$JS"
  rm -rf "$SAVE" ${WORK:-}
}
trap cleanup EXIT

new_repo() {
  WORK="$(mktemp -d)"
  R="$WORK/repo"
  mkdir -p "$R"
  git -C "$R" init -q .
  "$ASTRA/tools/check-prose/install.sh" --into "$R" >/dev/null
  TARGET="$R/.astra/check-prose/rules.json"
}

echo "== 1. Install must land in .astra and record where it came from =="
new_repo
if [ -f "$R/.astra/check-prose/check-prose.js" ] && [ -f "$R/.astra/manifest.json" ]; then
  ok "tool and manifest present under .astra"
else
  bad "install did not produce .astra/<tool> plus a manifest"
fi
if grep -q "js-db-ad-astra" "$R/.astra/manifest.json"; then
  ok "manifest records the source it was installed from"
else
  bad "manifest does not record a source — the repo cannot pull updates"
fi
# The whole point of .astra is that nothing lands where the repo keeps its own
# work. A stray copy outside it would reintroduce the collision hazard.
stray="$(find "$R" -name 'check-prose.js' -not -path '*/.astra/*' | wc -l | tr -d ' ')"
if [ "$stray" = "0" ]; then
  ok "nothing installed outside .astra"
else
  bad "$stray copy(ies) landed outside .astra"
fi

echo "== 2. A copy nobody touched MUST be updated =="
# The control. A fix that protects local edits by refusing every update would
# pass test 3 and fail here.
new_repo
printf '\n{"zzz":"upstream moved"}\n' >> "$RULES"
"$R/.astra/astra-update" --pull >/dev/null 2>&1
if grep -q "upstream moved" "$TARGET"; then
  ok "untouched copy picked up the upstream change"
else
  bad "untouched copy was NOT updated — distribution does not work"
fi
cp "$SAVE/rules.json" "$RULES"

echo "== 3. A locally edited copy must never be overwritten =="
new_repo
printf '\n// LOCAL EDIT\n' >> "$R/.astra/check-prose/check-prose.js"
printf '\n// upstream also moved\n' >> "$JS"
out="$("$R/.astra/astra-update" --pull 2>&1)"
if grep -q "LOCAL EDIT" "$R/.astra/check-prose/check-prose.js"; then
  ok "local edit survived a pull"
else
  bad "LOCAL EDIT DESTROYED by pull"
fi
if echo "$out" | grep -q "LOCAL EDITS"; then
  ok "pull reported the divergence instead of hiding it"
else
  bad "pull was silent about a locally modified file (out=$(echo "$out" | tr '\n' ' '))"
fi
cp "$SAVE/check-prose.js" "$JS"

echo "== 4. The update must be atomic, not an in-place truncate =="
# A write-in-place keeps the destination inode; write-beside-and-rename cannot.
# Asserting the mechanism is reliable where interrupting a copy is not.
new_repo
printf '\n{"zzz":"moved again"}\n' >> "$RULES"
before="$(ls -i "$TARGET" | awk '{print $1}')"
"$R/.astra/astra-update" --pull >/dev/null 2>&1
after="$(ls -i "$TARGET" | awk '{print $1}')"
if [ "$before" != "$after" ]; then
  ok "replaced atomically (inode $before -> $after)"
else
  bad "written IN PLACE — an interrupted update leaves a truncated tool"
fi
cp "$SAVE/rules.json" "$RULES"

echo "== 5. A missing file must be reported, not silently passed =="
new_repo
rm -f "$TARGET"
out="$("$R/.astra/astra-update" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "MISSING"; then
  ok "missing file reported and exit is nonzero"
else
  bad "a missing tool file passed quietly (rc=$rc, out=$(echo "$out" | tr '\n' ' '))"
fi

echo "== 6. A corrupt manifest must refuse, not read as 'nothing installed' =="
new_repo
echo 'this is not json' > "$R/.astra/manifest.json"
out="$("$R/.astra/astra-update" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -qi "unreadable"; then
  ok "corrupt manifest refused loudly"
else
  bad "corrupt manifest treated as empty — a broken repo looks like a clean one (rc=$rc)"
fi

echo "== 7. Astra must no longer be able to push into other repos =="
out="$(python3 "$ASTRA/tools/lib/registry.py" sync 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "RETIRED"; then
  ok "registry sync refuses"
else
  bad "registry sync still writes into other repos (rc=$rc)"
fi

echo "== 8. Scan must not adopt a same-named file it was never told about =="
# The collision bug: any repo's own rules.json or lib.sh was claimed as an astra
# install and overwritten. Ownership is recorded now, so an unknown look-alike
# is reported and left alone.
WS="$(mktemp -d)"
mkdir -p "$WS/somebodyelse"
echo '{"this":"is not ours"}' > "$WS/somebodyelse/rules.json"
out="$(ASTRA_WORKSPACE="$WS" python3 "$ASTRA/tools/lib/registry.py" scan 2>&1)"
if echo "$out" | grep -q "NOT in the ledger"; then
  ok "unregistered look-alike reported as a candidate"
else
  bad "scan did not flag an unknown same-named file (out=$(echo "$out" | tr '\n' ' '))"
fi
if grep -q "is not ours" "$WS/somebodyelse/rules.json"; then
  ok "and it was left completely untouched"
else
  bad "SOMEBODY ELSE'S FILE WAS MODIFIED"
fi
rm -rf "$WS"

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
