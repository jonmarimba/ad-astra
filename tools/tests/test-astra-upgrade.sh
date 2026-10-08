#!/usr/bin/env bash
# test-astra-upgrade.sh — `astra upgrade` refreshes the machine's dependencies without touching any repo.
#
# Re-running a repo install already upgrades a tool's dependencies, but it also rewrites the repo, and
# the software on the machine (a brew formula, a CLI, a downloaded app) belongs to no repo. So there is
# a second verb that does only the machine half: it runs each tool's deps.sh and NOTHING else.
# It never runs an install.sh, because several of those also reload launchd jobs (restarting the Xcode
# daemons re-raises approval dialogs), rewrite a schedule, or rebuild a signed app wrapper (which
# destroys its permission grants). A tool with no deps.sh has nothing to refresh and is skipped.
# This runs the real verb against a fake toolbox of stub tools, so no brew or network is involved.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FAKE="$SB/astra"; mkdir -p "$FAKE/tools/lib"
cp "$ASTRA_ROOT/tools/astra" "$FAKE/tools/astra"
cp -R "$ASTRA_ROOT/tools/lib/." "$FAKE/tools/lib/"
mkdir -p "$SB/ran"
stub() {  # stub <name> <scope> <installer-body> [deps-body]
  mkdir -p "$FAKE/tools/$1"
  printf '#!/usr/bin/env bash\n# astra-scope: %s\n%s\n' "$2" "$3" > "$FAKE/tools/$1/install.sh"
  [ -n "${4:-}" ] && printf '#!/usr/bin/env bash\n%s\n' "$4" > "$FAKE/tools/$1/deps.sh"
  chmod +x "$FAKE/tools/$1"/*.sh
  printf 'x\n' > "$FAKE/tools/$1/uninstall.sh"
}
stub brewlike machine "touch '$SB/ran/brewlike-install-WRONG'; exit 1" "touch '$SB/ran/brewlike-deps'; echo 'brewlike upgraded'"
stub daemonlike machine "touch '$SB/ran/daemonlike-install-WRONG'; exit 1"
stub failing machine "touch '$SB/ran/failing-install-WRONG'; exit 1" "echo 'cannot reach the network' >&2; exit 69"
stub needsapp repo-config "touch '$SB/ran/needsapp-install-WRONG'; exit 1" "touch '$SB/ran/needsapp-deps'; echo 'app refreshed'"
stub files repo "touch '$SB/ran/files-install-WRONG'; exit 1"
stub withdeps repo "touch '$SB/ran/withdeps-install-WRONG'; exit 1" "touch '$SB/ran/withdeps-deps'"
ASTRA="$FAKE/tools/astra"

echo "== list: shows the plan and runs nothing"
out="$("$ASTRA" upgrade --list 2>&1)"; rc=$?
assert_eq 0 "$rc" "upgrade --list exits 0"
case "$out" in *brewlike*) pass "lists the machine tool" ;; *) fail "machine tool missing from the plan: $out" ;; esac
case "$out" in *needsapp*) pass "lists the repo-config tool that has a deps.sh" ;; *) fail "deps.sh tool missing from the plan: $out" ;; esac
case "$out" in *files*) fail "a repo tool with no deps.sh was planned: $out" ;; *) pass "a repo tool with nothing to refresh is not in the plan" ;; esac
assert_no_file "$SB/ran/brewlike-deps" "--list ran nothing"
case "$out" in *daemonlike*) fail "a machine tool with no deps.sh was planned: $out" ;; *) pass "a machine tool with no deps.sh (a daemon, say) is not in the plan" ;; esac

echo "== a full upgrade runs the machine half only"
rm -f "$SB/ran"/*
out="$("$ASTRA" upgrade 2>&1)"; rc=$?
assert_eq 1 "$rc" "it exits 1 because one tool failed"
assert_file "$SB/ran/brewlike-deps" "the machine tool's deps.sh ran"
assert_no_file "$SB/ran/brewlike-install-WRONG" "its install.sh did NOT run (an installer may reload daemons or rebuild apps)"
assert_no_file "$SB/ran/daemonlike-install-WRONG" "a machine tool with no deps.sh was left alone, not installed"
assert_no_file "$SB/ran/failing-install-WRONG" "the failing tool's install.sh did not run either"
assert_file "$SB/ran/needsapp-deps" "the repo-config tool's deps.sh ran"
assert_file "$SB/ran/withdeps-deps" "the repo tool's deps.sh ran"
assert_no_file "$SB/ran/needsapp-install-WRONG" "a repo-config tool's install.sh did NOT run (it would write into a repo)"
assert_no_file "$SB/ran/files-install-WRONG" "a repo tool's install.sh did NOT run"
assert_no_file "$SB/ran/withdeps-install-WRONG" "even a repo tool that has a deps.sh runs only the deps.sh"
case "$out" in *failing*"cannot reach the network"*|*"cannot reach the network"*failing*) pass "the failing tool is named with its reason" ;; *) fail "the failure was not reported by name: $out" ;; esac
case "$out" in *brewlike*upgraded*) pass "a tool's own output is shown" ;; *) fail "tool output missing: $out" ;; esac
case "$out" in *"1 failed"*) pass "the summary counts the failure" ;; *) fail "no failure count in: $out" ;; esac

echo "== a failure does not stop the rest"
assert_file "$SB/ran/withdeps-deps" "tools after the failing one still ran"

echo "== named tools only"
rm -f "$SB/ran"/*
"$ASTRA" upgrade brewlike >/dev/null 2>&1; rc=$?
assert_eq 0 "$rc" "upgrading one named tool exits 0 when it succeeds"
assert_file "$SB/ran/brewlike-deps" "the named tool ran"
assert_no_file "$SB/ran/needsapp-deps" "tools not named did not run"
red "an unknown tool name is refused" 64 "no such tool" "$ASTRA" upgrade nosuchtool
red "a tool with nothing to refresh is refused by name, not silently skipped" 64 "nothing to upgrade" "$ASTRA" upgrade files
red "a machine tool with no deps.sh is refused the same way" 64 "nothing to upgrade" "$ASTRA" upgrade daemonlike

finish
