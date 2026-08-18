#!/bin/bash
# test-registry.sh — RED-capable tests for the thing that overwrites files in
# other people's repositories.
#
# registry.py sync is the highest-blast-radius code in astra: a post-commit
# hook fires it automatically and it rewrites tools across six checkouts,
# including two legal repos. It shipped on 2026-08-18 with no test at all,
# under a commit message claiming its fork protection was verified. A Codex
# review found the protection was unreachable; this file is that finding turned
# into something that stays found.
#
# Every test drives the REAL hook sequence (scan then sync), because that
# ordering is what defeated the original guard. A test that called sync alone
# would have passed against the broken version.

set -u
ASTRA="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTRY="$ASTRA/tools/lib/registry.py"
CANON="$ASTRA/tools/check-prose/check-prose.js"
PASS=0
FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "MISSING DEPENDENCY: $1 — install it, do not skip"; exit 1; }
}
need python3

# The registry writes installed.json in the REAL astra tree. These tests must
# not disturb it, so snapshot and restore. Losing the real registry would be
# the test destroying production state — the same class of bug as the health
# check texting a real phone.
REAL_REG="$ASTRA/tools/lib/installed.json"
REG_BACKUP="$(mktemp)"
[ -f "$REAL_REG" ] && cp "$REAL_REG" "$REG_BACKUP"
restore() {
  if [ -s "$REG_BACKUP" ]; then cp "$REG_BACKUP" "$REAL_REG"; fi
  rm -f "$REG_BACKUP"
  [ -n "${WS:-}" ] && rm -rf "$WS"
}
trap restore EXIT

# Fresh scratch workspace with one installed copy of a real canonical tool.
new_workspace() {
  WS="$(mktemp -d)"
  export ASTRA_WORKSPACE="$WS"
  mkdir -p "$WS/fakerepo/tools"
  cp "$CANON" "$WS/fakerepo/tools/check-prose.js"
  TARGET="$WS/fakerepo/tools/check-prose.js"
  rm -f "$REAL_REG"
}

# What the post-commit hook actually does, in its actual order.
hook_run() {
  python3 "$REGISTRY" scan >/dev/null 2>&1
  python3 "$REGISTRY" sync 2>&1
}

echo "== 1. A local edit must survive the hook =="
new_workspace
python3 "$REGISTRY" scan >/dev/null 2>&1          # registry learns the install, in sync
printf '\n// LOCAL EDIT — must never be clobbered\n' >> "$TARGET"
out="$(hook_run)"
if grep -q "LOCAL EDIT" "$TARGET"; then
  ok "local edit survived a full scan+sync cycle"
else
  bad "LOCAL EDIT WAS DESTROYED — sync said: $(echo "$out" | tr '\n' ' ')"
fi
if echo "$out" | grep -q "LOCAL EDITS, skipping"; then
  ok "sync named the fork instead of silently skipping"
else
  bad "sync did not report a fork (out=$(echo "$out" | tr '\n' ' '))"
fi

echo "== 2. A stale copy nobody touched MUST still be updated =="
# The opposite error. Refusing everything would 'protect' local edits by
# breaking the tool's entire purpose — bringing month-old copies current.
new_workspace
printf '\n// pretend this copy is from July\n' >> "$TARGET"
python3 "$REGISTRY" scan >/dev/null 2>&1          # first sighting: adopted as-is
out="$(python3 "$REGISTRY" sync 2>&1)"
if ! grep -q "pretend this copy is from July" "$TARGET"; then
  ok "adopted stale copy was brought current"
else
  bad "stale copy was NOT updated — the registry cannot do its job (out=$(echo "$out" | tr '\n' ' '))"
fi

echo "== 3. An edit made AFTER a successful sync must also survive =="
new_workspace
printf '\n// old vintage\n' >> "$TARGET"
python3 "$REGISTRY" scan >/dev/null 2>&1
python3 "$REGISTRY" sync >/dev/null 2>&1          # now synced_sha is stamped
printf '\n// EDIT AFTER SYNC\n' >> "$TARGET"
hook_run >/dev/null 2>&1
if grep -q "EDIT AFTER SYNC" "$TARGET"; then
  ok "post-sync edit survived"
else
  bad "post-sync edit was destroyed"
fi

echo "== 4. A symlinked destination must be refused, not followed =="
new_workspace
OUTSIDE="$(mktemp -d)"
echo "PRECIOUS CONTENT OUTSIDE THE WORKSPACE" > "$OUTSIDE/real.js"
rm "$TARGET"
ln -s "$OUTSIDE/real.js" "$TARGET"
out="$(hook_run)"
if grep -q "PRECIOUS CONTENT OUTSIDE THE WORKSPACE" "$OUTSIDE/real.js"; then
  ok "did not write through the symlink"
else
  bad "WROTE THROUGH A SYMLINK to $OUTSIDE — escaped the workspace"
fi
rm -rf "$OUTSIDE"

echo "== 5. The update must be atomic, not an in-place truncate =="
# copy2 opens the destination 'wb' — it truncates the live tool to zero bytes
# and then streams into it, so an interruption leaves a fragment or an empty
# file where a working tool used to be.
#
# Asserting that by interrupting a copy is unreliable, and a test that cannot
# reliably go red is a paragraph. The observable property is the mechanism
# itself: a write-in-place keeps the destination's inode, while a
# write-beside-and-rename necessarily produces a NEW one. Verified red — this
# assertion fails against the copy2 version.
new_workspace
printf '\n// old vintage\n' >> "$TARGET"
python3 "$REGISTRY" scan >/dev/null 2>&1
before_inode="$(ls -i "$TARGET" | awk '{print $1}')"
python3 "$REGISTRY" sync >/dev/null 2>&1
after_inode="$(ls -i "$TARGET" | awk '{print $1}')"
if [ "$before_inode" != "$after_inode" ]; then
  ok "destination was replaced atomically (inode $before_inode -> $after_inode)"
else
  bad "destination was written IN PLACE (inode unchanged: $before_inode) — an interrupted sync leaves a truncated tool"
fi
if ls "$WS/fakerepo/tools/"*.astra-sync.tmp >/dev/null 2>&1; then
  bad "left a .astra-sync.tmp turd behind"
else
  ok "no temp file left behind"
fi

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
