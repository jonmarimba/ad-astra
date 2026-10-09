#!/usr/bin/env bash
# test-agent-sync-uninstall.sh — agent-sync's uninstaller removes its schedule and cache, keeps the
# shared software on a plain run, and removes rsync and uv only with --deps (QUICKSTART promises
# that for every machine tool; this one used to ignore the flag).
#
# The real uninstaller runs from a COPY of the tool and the shared lib in a sandbox, with HOME
# redirected and a stub launchctl first on PATH, so the real launchd job, the real built app and
# the real cache of this machine are never touched.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

mkdir -p "$SB/astra/tools" "$SB/bin" "$SB/home/Library/LaunchAgents" "$SB/home/.cache/agent-sync"
cp -R "$ASTRA_ROOT/tools/lib" "$SB/astra/tools/lib"
mkdir -p "$SB/astra/tools/agent-sync"
cp "$ASTRA_ROOT/tools/agent-sync/uninstall.sh" "$SB/astra/tools/agent-sync/uninstall.sh"
mkdir -p "$SB/astra/tools/agent-sync/AgentSync.app/Contents"
printf 'x\n' > "$SB/astra/tools/agent-sync/agentsync_launch.sh"
printf 'x\n' > "$SB/home/Library/LaunchAgents/astra.agent-sync.plist"
printf 'x\n' > "$SB/home/.cache/agent-sync/mirror"

LOG="$SB/calls.log"
for c in launchctl brew uv; do printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$c" "$LOG" > "$SB/bin/$c"; chmod +x "$SB/bin/$c"; done
unset XDG_CACHE_HOME
export HOME="$SB/home" ASTRA_PATH="$SB/bin:/usr/bin:/bin" BREW_BIN="$SB/bin/brew" UV_BIN="$SB/bin/uv"
UN="$SB/astra/tools/agent-sync/uninstall.sh"

echo "== a plain run"
: > "$LOG"
bash "$UN" > "$SB/plain.out" 2>&1
assert_eq 0 "$?" "uninstall succeeds"
assert_no_file "$HOME/Library/LaunchAgents/astra.agent-sync.plist" "the launchd plist is gone"
assert_no_file "$HOME/.cache/agent-sync" "the cache is gone"
assert_no_file "$SB/astra/tools/agent-sync/AgentSync.app" "the built app is gone"
assert_contains "$LOG" "launchctl bootout" "the job was unloaded (through the stub)"
if grep -q "uninstall" "$LOG"; then fail "a plain run removed shared software"; else pass "a plain run leaves rsync and uv alone"; fi
assert_contains "$SB/plain.out" "KEEPING shared dep 'rsync'" "and says how to remove them"

echo "== --deps"
: > "$LOG"
bash "$UN" --deps > "$SB/deps.out" 2>&1
assert_eq 0 "$?" "uninstall --deps succeeds"
assert_contains "$LOG" "brew uninstall rsync" "RED: --deps removes rsync"
assert_contains "$LOG" "brew uninstall uv" "RED: --deps removes uv"

echo "== an unknown flag"
bash "$UN" --nonsense > "$SB/bad.out" 2>&1
assert_eq 64 "$?" "RED: an unknown flag exits 64 instead of being ignored"
finish
