#!/usr/bin/env bash
# TIER: slow
# test-clone-portability.sh — the whole fast tier must pass from a copy of this checkout that
# lives somewhere else, under another name, on a machine whose $HOME is empty.
#
# APFS clones are free (cp -c is a copy-on-write clonefile), so this copies the CURRENT working
# tree, uncommitted edits included, into a throwaway workspace, empties $HOME, drops every
# ASTRA_* override, and runs run-all.sh there. Anything that assumes ~/svnCheckouts, the
# checkout's own name, a file under the real $HOME, or a path into another project fails here
# instead of on the next person's machine. It is deliberately the dumb, total version of the
# portability check: no list of things to look for.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
[ "$(uname)" = Darwin ] || { fail "clone check needs macOS cp -c (APFS clonefile)"; finish; exit 1; }

WS="$SB/elsewhere"; CLONE="$WS/not-the-usual-name"; HOME2="$SB/empty-home"
mkdir -p "$WS" "$HOME2"
cp -Rc "$ASTRA_ROOT" "$CLONE" && pass "cloned the working tree (copy-on-write)" || { fail "clone failed"; finish; exit 1; }
assert_file "$CLONE/tools/tests/run-all.sh" "the clone carries the test runner"

# The clone must not be able to reach the original by path: if a test passes only because it
# falls back to the real checkout, this would hide it. Run with the original's path unreadable
# to the tests by pointing everything at the clone, and check nothing wrote back to the original.
before="$(cd "$ASTRA_ROOT" && git status --porcelain | shasum)"

# Skip THIS file in the clone (it would recurse); everything else in the fast tier runs.
rm "$CLONE/tools/tests/test-clone-portability.sh"
env -u ASTRA_SOURCE -u ASTRA_WORKSPACE -u ASTRA_CONFIG_FILE -u CONVOQ_BRIDGE -u WORKLOG_BIN \
    HOME="$HOME2" XDG_CONFIG_HOME="$HOME2/.config" XDG_CACHE_HOME="$HOME2/.cache" \
    ASTRA_FAST_BUDGET_S=120 bash "$CLONE/tools/tests/run-all.sh" >"$SB/clone-run.out" 2>&1
rc=$?
assert_eq 0 "$rc" "run-all.sh passes from the clone with an empty HOME"
if [ "$rc" -ne 0 ]; then
  grep -E '^== .*failed|FAIL' "$SB/clone-run.out" | grep -v ' 0 failed' | cut -c1-220 | sed 's/^/        /'
  echo "        --- tail of the clone's run:"; tail -n 12 "$SB/clone-run.out" | cut -c1-220 | sed 's/^/        /'
fi
# The slow tier too (it carries the lib/ and per-tool tests). '# TIER: live' tests are the only
# ones that may need this machine's services, and neither runner touches them.
env -u ASTRA_SOURCE -u ASTRA_WORKSPACE -u ASTRA_CONFIG_FILE -u CONVOQ_BRIDGE -u WORKLOG_BIN \
    HOME="$HOME2" XDG_CONFIG_HOME="$HOME2/.config" XDG_CACHE_HOME="$HOME2/.cache" \
    bash "$CLONE/tools/tests/run-slow.sh" >"$SB/clone-slow.out" 2>&1
rc=$?
assert_eq 0 "$rc" "run-slow.sh passes from the clone with an empty HOME"
if [ "$rc" -ne 0 ]; then
  grep -E '^== .*failed|FAIL' "$SB/clone-slow.out" | grep -v ' 0 failed' | cut -c1-220 | sed 's/^/        /'
fi
after="$(cd "$ASTRA_ROOT" && git status --porcelain | shasum)"
assert_eq "$before" "$after" "the run left the original checkout untouched"

# RED control: a planted assumption must be caught, or this test proves nothing.
printf '#!/usr/bin/env bash\n. "$(dirname "$0")/lib.sh"\n[ -d "$HOME/svnCheckouts/js-db-ad-astra" ] && pass "found it" || fail "assumed a path under HOME"\nfinish\n' > "$CLONE/tools/tests/test-zz-planted.sh"
env HOME="$HOME2" bash "$CLONE/tools/tests/test-zz-planted.sh" >"$SB/planted.out" 2>&1
assert_nonempty "$(grep 'assumed a path under HOME' "$SB/planted.out")" "RED control: a test that assumes ~/svnCheckouts fails in the clone"
finish
