#!/usr/bin/env bash
# test-install-contract.sh — every repo-level astra tool installs, updates and
# uninstalls the SAME way (Jonathan, 2026-10-04: "Why not be consistent?").
#
# What is pinned here, each as a requirement he stated:
#   1. Every installer marked `# astra-scope: repo` records every file it
#      places in .astra/manifest.json, and wires the updater hooks.
#   2. "I may change my mind and uninstall something. It shouldn't come back on
#      an automatic update." Uninstall removes the files and the manifest
#      entry, and a later --pull does not restore them.
#   3. "I don't want to manually manage anything": the hooks exist after any
#      install, merge into a hook the repo already has, and go away with the
#      last tool, leaving the repo's own hook content intact.
#   4. "Having Astra shouldn't be a prerequisite for pulling any of my stuff":
#      with no astra checkout reachable, the hook's --pull is silent and exits 0.
# Red-capable: each check fails against the pre-2026-10-04 installers.
set -u
A="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ASTRA="$A/tools/astra"
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"; git -C "$A" checkout -q -- tools/check-prose/rules.json 2>/dev/null' EXIT

new_repo() {
  R="$SCRATCH/r$RANDOM$RANDOM"; mkdir -p "$R"; git -C "$R" init -q
  git -C "$R" commit -q --allow-empty -m init
}
manifest_has() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if sys.argv[2] in d.get('tools',{}) else 1)" "$1/.astra/manifest.json" "$2" 2>/dev/null; }
recorded_dests() { python3 - "$1/.astra/manifest.json" "$2" <<'PY'
import json, sys
e = json.load(open(sys.argv[1]))["tools"][sys.argv[2]]
p = e.get("paths", {})
for f in e.get("files", {}):
    print(p.get(f, {}).get("dest") or f".astra/{sys.argv[2]}/{f}")
PY
}
hooked() { grep -qF ">>> astra-update (managed by astra" "$1/.git/hooks/$2" 2>/dev/null; }

REPO_TOOLS=$(grep -l '^# astra-scope: repo$' "$A"/tools/*/install.sh | sed -E 's#.*/tools/([^/]+)/install.sh#\1#')

echo "== 1+2. Every repo-level tool: recorded, hooked, and removable for good =="
for t in $REPO_TOOLS; do
  new_repo
  out="$("$ASTRA" add "$t" --into "$R" 2>&1)"; rc=$?
  [ $rc -eq 0 ] || { bad "$t: install failed (rc=$rc): $(echo "$out" | tail -2 | tr '\n' ' ')"; continue; }
  # convocation and writing-doctrine record as doctrine-<slug>
  entry="$t"; case "$t" in convocation) entry=doctrine-convocation ;; writing-doctrine) entry=doctrine-writing ;; esac
  if ! manifest_has "$R" "$entry"; then bad "$t: no manifest entry '$entry'"; continue; fi
  missing=0; n=0
  while IFS= read -r d; do n=$((n+1)); [ -e "$R/$d" ] || missing=$((missing+1)); done < <(recorded_dests "$R" "$entry")
  [ $n -gt 0 ] && [ $missing -eq 0 ] && ok "$t: $n file(s) placed and recorded" || bad "$t: $missing of $n recorded file(s) missing"
  manifest_has "$R" astra-update && hooked "$R" post-commit && hooked "$R" post-merge \
    && ok "$t: updater vendored and both hooks wired" || bad "$t: updater or hooks not wired"
  dests="$(recorded_dests "$R" "$entry")"
  "$ASTRA" remove "$t" --into "$R" >/dev/null 2>&1 || bad "$t: uninstall failed"
  left=0; while IFS= read -r d; do [ -e "$R/$d" ] && left=$((left+1)); done <<< "$dests"
  manifest_has "$R" "$entry" && bad "$t: manifest entry survived uninstall" || true
  [ $left -eq 0 ] && ok "$t: uninstall removed every file" || bad "$t: $left file(s) survived uninstall"
  { [ ! -e "$R/.astra" ] && ! hooked "$R" post-commit; } && ok "$t: last tool gone, astra gone with it" \
    || bad "$t: .astra or the hook block survived removing the only tool"
done

echo "== 2. An uninstalled tool does not come back on an automatic update =="
new_repo
"$ASTRA" add check-prose asd-ste100 --into "$R" >/dev/null 2>&1
"$ASTRA" remove asd-ste100 --into "$R" >/dev/null 2>&1
printf '\n{"zzz":"upstream moved"}\n' >> "$A/tools/check-prose/rules.json"
"$R/.astra/astra-update" --pull >/dev/null 2>&1
[ ! -e "$R/.claude/skills/asd-ste100/SKILL.md" ] && ok "removed skill stayed removed through a pull" || bad "removed skill came back"
grep -q "upstream moved" "$R/.astra/check-prose/rules.json" && ok "the tool still installed did update" || bad "the remaining tool did not update"
git -C "$A" checkout -q -- tools/check-prose/rules.json

echo "== 3. Hooks merge into what the repo already has, and leave it on removal =="
new_repo
printf '#!/bin/bash\necho "repo-own-guard"\n' > "$R/.git/hooks/post-commit"
# the block every hook carried before 2026-10-04
cat "$A/tools/lib/astra-post-commit.hook" >/dev/null
cat >> "$R/.git/hooks/post-commit" <<'EOF'
# astra: keep this repo's vendored tools current.
#
# Runs in the background so a commit never waits on it.
if [ -x "$(git rev-parse --show-toplevel)/.astra/astra-update" ]; then
  ( "$(git rev-parse --show-toplevel)/.astra/astra-update" --pull \
      >> "$(git rev-parse --show-toplevel)/.astra/update.log" 2>&1 & ) >/dev/null 2>&1
fi
EOF
chmod +x "$R/.git/hooks/post-commit"
"$ASTRA" add check-prose --into "$R" >/dev/null 2>&1
h="$R/.git/hooks/post-commit"
grep -q "repo-own-guard" "$h" && ok "existing hook content preserved" || bad "existing hook content lost"
[ "$(grep -c '>>> astra-update' "$h")" -eq 1 ] && ! grep -q "keep this repo's vendored tools current" "$h" \
  && ok "legacy block replaced, updater runs once" || bad "legacy block left alongside the new one"
"$ASTRA" add asd-ste100 --into "$R" >/dev/null 2>&1
[ "$(grep -c '>>> astra-update' "$h")" -eq 1 ] && ok "re-install does not duplicate the block" || bad "block duplicated"
"$ASTRA" remove check-prose asd-ste100 --into "$R" >/dev/null 2>&1
grep -q "repo-own-guard" "$h" && ! grep -q "astra-update" "$h" && ok "removal strips only astra's block" || bad "removal damaged the hook"
[ ! -e "$R/.git/hooks/post-merge" ] && ok "a hook astra created alone is deleted with the last tool" || bad "empty post-merge hook left behind"
grep -q "astra" "$R/.gitignore" 2>/dev/null && bad "astra ignore rule left behind" || ok "ignore rule removed with the last tool"

echo "== 3a. The 2026-10-02 --log variant of the old block is replaced too =="
new_repo
cat > "$R/.git/hooks/post-commit" <<'EOF'
#!/bin/bash
# astra: keep this repo's vendored tools current.
#
# Runs in the background so a commit never waits on it.
ROOT="$(git rev-parse --show-toplevel)"
if [ -x "$ROOT/.astra/astra-update" ]; then
  ( "$ROOT/.astra/astra-update" --pull --log "$ROOT/.astra/update.log" \
      >/dev/null 2>&1 & ) >/dev/null 2>&1
fi
EOF
chmod +x "$R/.git/hooks/post-commit"
"$ASTRA" add check-prose --into "$R" >/dev/null 2>&1
h="$R/.git/hooks/post-commit"
! grep -q "keep this repo's vendored tools current" "$h" && ! grep -q '^ROOT=' "$h" && [ "$(grep -c '>>> astra-update' "$h")" -eq 1 ] \
  && ok "--log legacy block replaced by the managed one" || bad "--log legacy block survived"

echo "== 3b. A hook that is not a shell script is refused, not mangled =="
new_repo
printf '#!/usr/bin/env python3\nprint("mine")\n' > "$R/.git/hooks/post-commit"
out="$("$ASTRA" add check-prose --into "$R" 2>&1)"
grep -q 'print("mine")' "$R/.git/hooks/post-commit" && ! grep -q astra-update "$R/.git/hooks/post-commit" \
  && echo "$out" | grep -q "not a shell script" && ok "python hook left alone, refusal explains" || bad "python hook mangled or refusal silent"

echo "== 3c. The update log is never committed =="
new_repo
"$ASTRA" add check-prose --into "$R" >/dev/null 2>&1
echo x > "$R/.astra/update.log"
git -C "$R" add -A >/dev/null 2>&1
git -C "$R" diff --cached --name-only | grep -q "update.log" && bad "update.log would be committed" || ok "update.log ignored"

echo "== 4. No astra on this machine: the hook is silent and harmless =="
new_repo
"$ASTRA" add check-prose --into "$R" >/dev/null 2>&1
python3 - "$R/.astra/manifest.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
for e in d["tools"].values():
    e["source"] = "/nonexistent/js-db-ad-astra"; e.pop("source_remote", None)
open(p, "w").write(json.dumps(d))
PY
out="$("$R/.astra/astra-update" --pull 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && ok "--pull without astra: silent, exit 0" || bad "--pull without astra printed or failed (rc=$rc): $out"
out="$("$R/.astra/astra-update" 2>&1)"
echo "$out" | grep -q "SOURCE GONE" && ok "an explicit status check still reports it" || bad "explicit status hid the missing source"
(cd "$R" && sh .git/hooks/post-commit); [ $? -eq 0 ] && ok "hook exits 0 without astra" || bad "hook failed without astra"

echo "== 3d. Reinstalling a doctrine leaves CLAUDE.md byte-identical =="
new_repo
printf '# Repo\n\nintro\n' > "$R/CLAUDE.md"
"$ASTRA" add writing-doctrine --into "$R" >/dev/null 2>&1
echo "after the block" >> "$R/CLAUDE.md"; cp "$R/CLAUDE.md" "$SCRATCH/before.md"
"$ASTRA" add writing-doctrine --into "$R" >/dev/null 2>&1
cmp -s "$SCRATCH/before.md" "$R/CLAUDE.md" && ok "doctrine block replaced in place, not moved" || bad "reinstall moved or duplicated the doctrine block"

echo "== 5. The humanizer replaces the old untracked npx install =="
new_repo
mkdir -p "$R/.agents/skills/humanizer" "$R/.claude/skills"
echo old > "$R/.agents/skills/humanizer/SKILL.md"
ln -s ../../.agents/skills/humanizer "$R/.claude/skills/humanizer"
printf '{"version":1,"skills":{"humanizer":{"source":"blader/humanizer"}}}\n' > "$R/skills-lock.json"
"$ASTRA" add humanizer --into "$R" >/dev/null 2>&1
{ [ ! -L "$R/.claude/skills/humanizer" ] && [ -f "$R/.claude/skills/humanizer/voice-calibration.md" ] \
  && [ ! -e "$R/.agents/skills/humanizer" ] && [ ! -e "$R/skills-lock.json" ]; } \
  && ok "symlink, .agents copy and lock entry replaced by tracked files" || bad "old humanizer install not retired"

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
