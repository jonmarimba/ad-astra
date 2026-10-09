#!/usr/bin/env bash
# test-astra-new.sh — `astra new <name> --kind <kind>` scaffolds a tool that already keeps every
# promise the suite checks: a declared kind, an uninstaller that undoes the installer, a test with a
# RED control. The proof is to scaffold one tool of each kind into a copy-on-write clone of this
# checkout and run the clone's own kind checker and the new tool's own test.
#
# Real astra, a real clone, real installs into a real git repo.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
need git "xcode-select --install"
need jq "brew install jq"

CLONE="$SB/clone"
cp -Rc "$ASTRA_ROOT" "$CLONE" && pass "(setup) cloned the checkout copy-on-write" || { fail "clone failed"; finish; exit 1; }
export HOME="$SB/home"; mkdir -p "$HOME"
NEW="$CLONE/tools/astra"

echo "== refusals"
"$NEW" new > "$SB/r0.out" 2>&1; assert_eq 64 "$?" "RED: no name exits 64"
"$NEW" new Bad_Name --kind repo > "$SB/r1.out" 2>&1; assert_eq 64 "$?" "RED: a name with capitals or underscores exits 64"
assert_contains "$SB/r1.out" "lowercase" "RED: and says what a name looks like"
"$NEW" new zz-thing > "$SB/r2.out" 2>&1; assert_eq 64 "$?" "RED: a missing --kind exits 64"
assert_contains "$SB/r2.out" "skill, repo, repo-config, machine, run-in-place" "RED: and lists the kinds"
"$NEW" new zz-thing --kind bogus > "$SB/r3.out" 2>&1; assert_eq 64 "$?" "RED: an unknown kind exits 64"
"$NEW" new check-prose --kind repo > "$SB/r4.out" 2>&1; assert_eq 73 "$?" "RED: a name that already exists exits 73"
assert_no_file "$CLONE/tools/zz-thing" "nothing was created by a refused call"

echo "== one tool of each kind"
for spec in "zz-skill:skill" "zz-repo:repo" "zz-config:repo-config" "zz-machine:machine" "zz-inplace:run-in-place"; do
  name="${spec%%:*}"; kind="${spec##*:}"
  "$NEW" new "$name" --kind "$kind" > "$SB/new-$name.out" 2>&1
  assert_eq 0 "$?" "$kind: scaffolded $name"
  assert_dir "$CLONE/tools/$name" "$kind: tools/$name exists"
  assert_file "$CLONE/tools/tests/test-$name.sh" "$kind: it has a test"
done
assert_file "$CLONE/agents-and-prompts/skills/zz-skill/SKILL.md" "skill: the SKILL.md was created"
assert_file "$CLONE/tools/zz-inplace/RUN-IN-PLACE" "run-in-place: the declaration file exists"
assert_file "$CLONE/tools/zz-machine/deps.sh" "machine: it has a deps.sh for astra upgrade"

echo "== the clone's own checks accept all five"
bash "$CLONE/tools/tests/test-tool-kinds.sh" > "$SB/kinds.out" 2>&1
assert_eq 0 "$?" "the kind checker passes with the five new tools in place"
bash "$CLONE/tools/tests/test-no-gnu-only-commands.sh" > "$SB/gnu.out" 2>&1
assert_eq 0 "$?" "and so does the portability check on shell commands"
for name in zz-skill zz-repo zz-config zz-machine zz-inplace; do
  bash "$CLONE/tools/tests/test-$name.sh" > "$SB/t-$name.out" 2>&1
  assert_eq 0 "$?" "the scaffolded test for $name passes on its own"
done

echo "== the repo kinds really install and uninstall"
R="$SB/repo"; mkdir -p "$R"; git -C "$R" init -q
for name in zz-skill zz-repo zz-config; do
  "$CLONE/tools/astra" add "$name" --into "$R" > "$SB/add-$name.out" 2>&1
  assert_eq 0 "$?" "astra add $name"
done
assert_file "$R/.claude/skills/zz-skill/SKILL.md" "the skill landed in .claude/skills"
assert_file "$R/.astra/zz-repo/zz-repo" "the repo tool landed in .astra"
assert_eq "http" "$(jq -r '.mcpServers["zz-config"].type' "$R/.mcp.json")" "the repo-config entry is in .mcp.json"
for name in zz-skill zz-repo zz-config; do
  "$CLONE/tools/astra" remove "$name" --into "$R" > "$SB/rm-$name.out" 2>&1
  assert_eq 0 "$?" "astra remove $name"
done
assert_no_file "$R/.claude/skills/zz-skill" "the skill is gone"
assert_no_file "$R/.astra/zz-repo/zz-repo" "the repo tool is gone"
if [ -f "$R/.mcp.json" ]; then assert_eq "null" "$(jq '.mcpServers["zz-config"]' "$R/.mcp.json")" "the config entry is gone"; else pass "the config entry is gone (with the file it created)"; fi
finish
