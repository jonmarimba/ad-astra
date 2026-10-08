#!/usr/bin/env bash
# test-portable-install.sh — install from an astra checkout that is NOT at
# ~/svnCheckouts/js-db-ad-astra, on a machine whose $HOME has no svnCheckouts at all
# (Jonathan, 2026-10-07: "I'd like this to, you know, actually be portable").
#
# test-self-contained.sh greps tracked code for foreign paths. This test runs the thing:
# it copies the toolbox to an oddly named directory, points $HOME at an empty sandbox,
# installs the base template into a fresh repo, and checks what a stranger's machine would
# actually see. It exists because the static grep exempts docs and tilde-paths, and the
# installed doctrine told every other repo's bots to run ~/svnCheckouts/js-db-ad-astra/...
# which fails with "No such file or directory" anywhere else.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need git "install git"; need tar "install tar"; need python3 "install python3"

WS="$SB/workspace"                 # the stranger's checkouts directory
TOOLBOX="$WS/odd-name-toolbox"     # astra, under a name nothing may assume
REPO="$WS/alpha"                   # a consumer repo beside it
FAKEHOME="$SB/home"                # no svnCheckouts, no .claude, nothing
mkdir -p "$TOOLBOX" "$REPO" "$FAKEHOME"

# Copy the working tree (modified files included), submodule contents and all.
( cd "$ASTRA_ROOT" && git ls-files -z --recurse-submodules | tar --null -T - -cf - ) | tar -xf - -C "$TOOLBOX"
git -C "$REPO" init -q && git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
assert_dir "$TOOLBOX/vendor/authsec-bridge/src/session_bridge" "toolbox copy carries the convoq engine"

run_home() { env -u ASTRA_SOURCE -u ASTRA_WORKSPACE -u CONVOQ_BRIDGE HOME="$FAKEHOME" "$@"; }

echo "== install base from the renamed toolbox into a fresh repo"
assert_rc 0 "template.py install base" run_home python3 "$TOOLBOX/tools/lib/template.py" install base --into "$REPO"

echo "== the committed manifest records the source relative to the repo, not an absolute path"
assert_eq "../odd-name-toolbox" "$(jq -r '.tools["check-prose"].source' "$REPO/.astra/manifest.json")" "a sibling toolbox is recorded as ../<name>"
FAR="$SB/elsewhere-entirely/far-repo"; mkdir -p "$FAR"; git -C "$FAR" init -q && git -C "$FAR" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
run_home python3 "$TOOLBOX/tools/lib/template.py" install writing --into "$FAR" >/dev/null 2>&1
case "$(jq -r '.tools["check-prose"].source' "$FAR/.astra/manifest.json")" in
  /*) pass "a toolbox that is not beside the repo has no portable form, so it stays absolute (ASTRA_SOURCE covers it)" ;;
  *) fail "a non-sibling toolbox was recorded as a relative path that cannot resolve" ;;
esac
assert_rc 0 "astra-update resolves the relative source" run_home "$REPO/.astra/astra-update"

echo "== nothing installed names this machine's layout"
# Every installed file, the manifest included, must be free of a machine's paths.
leaks="$(cd "$REPO" && grep -rIn 'svnCheckouts\|/Users/' . --exclude-dir=.git 2>/dev/null)"
assert_empty "$leaks" "no svnCheckouts or /Users/ path in any installed file"
[ -z "$leaks" ] || echo "$leaks" | cut -c1-170 | sed 's/^/        /'
# RED control: the scan itself must be able to see a leak.
printf 'run ~/svnCheckouts/x\n' > "$REPO/planted-leak.md"
planted="$(cd "$REPO" && grep -rIn 'svnCheckouts\|/Users/' . --exclude-dir=.git 2>/dev/null)"
assert_nonempty "$planted" "RED control: the leak scan fails when a path is planted"
rm -f "$REPO/planted-leak.md"

echo "== the dispatcher the doctrine names exists in the repo"
assert_file "$REPO/.astra/convocation/panel" "panel installed beside the repo's other astra tools"
[ -x "$REPO/.astra/convocation/panel" ] && pass "panel is executable" || fail "panel is not executable"
assert_contains "$REPO/.doctrine/convocation.md" ".astra/convocation/panel" "doctrine names the installed panel"
assert_contains "$REPO/.claude/skills/convocation/SKILL.md" ".astra/convocation/panel" "skill names the installed panel"

echo "== convoq finds its engine without ~/svnCheckouts"
assert_rc 0 "convoq runs from the installed repo (source recorded in manifest)" \
  run_home "$REPO/.astra/convoq/convoq" search zzz-no-such-term-zzz
mv "$TOOLBOX" "$WS/moved-toolbox"
red "convoq with the source gone fails loudly" 3 "ASTRA_SOURCE" run_home "$REPO/.astra/convoq/convoq" search zzz
run_home "$REPO/.astra/convoq/convoq" search zzz >"$SB/convoq.out" 2>&1
assert_not_contains "$SB/convoq.out" "svnCheckouts" "the error does not send a stranger to a path that is not theirs"
assert_rc 0 "convoq runs when ASTRA_SOURCE names the moved toolbox" \
  env ASTRA_SOURCE="$WS/moved-toolbox" HOME="$FAKEHOME" "$REPO/.astra/convoq/convoq" search zzz-no-such-term-zzz
mv "$WS/moved-toolbox" "$TOOLBOX"

echo "== convoq picks a 3.10+ interpreter wherever Python lives, and says so when none qualifies"
printf '#!/bin/sh\nexit 1\n' > "$SB/old-python"; chmod +x "$SB/old-python"
red "convoq refuses an interpreter that is too old" 3 "needs 3.10" \
  env CONVOQ_PYTHON="$SB/old-python" HOME="$FAKEHOME" "$REPO/.astra/convoq/convoq" search zzz
assert_not_contains "$TOOLBOX/tools/convoq/convoq" "PY=\"\${CONVOQ_PYTHON:-/opt/homebrew" "convoq no longer defaults to a Homebrew-only interpreter"

echo "== legal-pdf wires a repo from the renamed toolbox, keeping the repo's own hook content"
LEGAL="$WS/legal"; mkdir -p "$LEGAL"
git -C "$LEGAL" init -q && git -C "$LEGAL" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
printf '#!/bin/bash\n# repo-owned guard\necho "guard ran" >&2\n' > "$LEGAL/.git/hooks/pre-commit"; chmod +x "$LEGAL/.git/hooks/pre-commit"
assert_rc 0 "template.py install legal-pdf (machine deps skipped)" \
  run_home env ASTRA_SKIP_MACHINE_DEPS=1 python3 "$TOOLBOX/tools/lib/template.py" install legal-pdf --into "$LEGAL"
assert_file "$LEGAL/.astra/pdf-sidecars/hook_pre_commit.sh" "the sidecar kit landed in the repo"
assert_contains "$LEGAL/.git/hooks/pre-commit" "repo-owned guard" "the repo's own hook content survived"
assert_contains "$LEGAL/.git/hooks/pre-commit" ".astra/pdf-sidecars/hook_pre_commit.sh" "the sidecar block was spliced in beside it"
assert_not_contains "$LEGAL/.git/hooks/pre-commit" "js-db-ad-astra" "the hook's reinstall hint does not assume the checkout's name"
bash -n "$LEGAL/.git/hooks/pre-commit" && pass "the spliced hook parses" || fail "the spliced hook has a syntax error"
leaks="$(cd "$LEGAL" && grep -rIn 'svnCheckouts\|/Users/' .astra .doctrine .claude .git/hooks --exclude='*.bak*' --exclude='*.sample' 2>/dev/null)"
assert_empty "$leaks" "no foreign path anywhere legal-pdf installed"

echo "== the workspace is the toolbox's parent, not ~/svnCheckouts"
got="$(run_home python3 -c "
import importlib.util, sys
spec = importlib.util.spec_from_file_location('registry', sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.WORKSPACE)" "$TOOLBOX/tools/lib/registry.py")"
assert_eq "$(cd "$WS" && pwd -P)" "$got" "registry.py defaults its workspace to the toolbox's parent"
out="$(run_home "$TOOLBOX/tools/astra" sync 2>&1)"
case "$out" in *"synced $(cd "$REPO" && pwd -P)"*) pass "astra sync with no roots finds the repo beside the toolbox" ;;
  *) fail "astra sync with no roots missed the sibling repo (got: $out)" ;; esac

finish
