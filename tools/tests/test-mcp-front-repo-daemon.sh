#!/usr/bin/env bash
# test-mcp-front-repo-daemon.sh — Phase 5: per-repo autonomous daemons.
#
# Jonathan's design, overriding the panel's shared-broker answer: "I'd strongly prefer
# each install in a given repo to be autonomous. That way, one thing failing doesn't
# fuck all my projects at once." A repo gets its own APFS-cloned copy of the wrapper
# under .astra/mcp-front, its own launchd-able run script, a DETERMINISTIC port derived
# from the repo path, and collision resolution at launch. The chosen port lands in the
# repo's .mcp.json, which is how clients find the daemon.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

need uv "brew install uv"
need jq "brew install jq"
need python3 "xcode-select --install"

INSTALLER="$HERE/../xcode-mcp-front/repo-daemon-install.sh"
STUB="$HERE/stub_mcp_server.py"

RPID=""; RPID2=""; OCCUPY=""   # referenced by the EXIT trap; under set -u an unset
                               # variable would fail the trap itself and leak daemons

REPO="$SB/fakerepo"
mkdir -p "$REPO"
git -C "$REPO" init -q

# --- the installer places an autonomous copy under .astra/mcp-front ---
assert_rc 0 "installer succeeds into a scratch repo" bash "$INSTALLER" --into "$REPO"
assert_file "$REPO/.astra/mcp-front/daemon.py" "daemon.py is cloned into the repo"
assert_file "$REPO/.astra/mcp-front/mcp_config.py" "mcp_config.py travels with it"
assert_file "$REPO/.astra/mcp-front/run.sh" "the per-repo run script is installed"
assert_file "$REPO/.astra/mcp-front/launchd.plist" "a launchd plist is generated"
plutil -lint "$REPO/.astra/mcp-front/launchd.plist" >/dev/null 2>&1 \
  && pass "the generated plist parses" || fail "the generated plist does not parse"
# Read the KEY, not the file text: RunAtLoad's <true/> satisfied a substring check even
# with KeepAlive absent (phase-5 panel, codex leg — a genuinely tautological assertion).
ka="$(/usr/libexec/PlistBuddy -c "Print :KeepAlive" "$REPO/.astra/mcp-front/launchd.plist" 2>/dev/null)"
assert_eq "true" "$ka" "KeepAlive is bare true (the SuccessfulExit variant silently stays dead on EADDRINUSE)"

# --- the unservable placeholder dies BEFORE any side effect ---
red "launching on the placeholder config refuses with the reason" 78 "would not load" \
  bash "$REPO/.astra/mcp-front/run.sh"
assert_no_file "$REPO/.astra/mcp-front/port" "no port file was written by the refused launch"
assert_no_file "$REPO/.mcp.json" "and .mcp.json was not pointed at a dead endpoint"

red "the installer refuses a target under HOME itself" 64 "refusing" \
  bash "$INSTALLER" --into "$HOME"

mkdir -p "$REPO/some/subdir"
red "the installer refuses a directory INSIDE a repo that is not its top level" 65 "not its top level" \
  bash "$INSTALLER" --into "$REPO/some/subdir"

# --- launch: deterministic port, recorded in .mcp.json, real daemon serving ---
cat > "$REPO/.astra/mcp-front/_mcp_info.json" <<EOF
{"mcpServers": {"alpha": {"command": "python3", "args": ["$STUB", "--name", "alpha", "--tool", "ping=repo-pong"]}}}
EOF
bash "$REPO/.astra/mcp-front/run.sh" >"$SB/run1.log" 2>&1 &
RPID=$!
trap 'kill "$RPID" "$RPID2" 2>/dev/null; wait "$RPID" "$RPID2" 2>/dev/null; kill "$OCCUPY" 2>/dev/null; rm -rf "$SB"' EXIT
waited=0
until [ -f "$REPO/.astra/mcp-front/port" ] || [ "$waited" -ge 10 ]; do sleep 1; waited=$((waited+1)); done
assert_file "$REPO/.astra/mcp-front/port" "the launcher records its chosen port"
PORT="$(cat "$REPO/.astra/mcp-front/port" 2>/dev/null)"
assert_contains "$REPO/.mcp.json" "127.0.0.1:$PORT/mcp" \
  ".mcp.json points at the chosen port — clients find the daemon through it"

mcp_probe() { # <port> -> tools/list body
  local port="$1" init_resp session
  init_resp="$(curl -s --max-time 10 -D - -X POST "http://127.0.0.1:$port/mcp" \
    -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
    -H "MCP-Protocol-Version: 2025-06-18" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"repo-test","version":"0"}}}')"
  session="$(printf '%s' "$init_resp" | grep -i "mcp-session-id" | tr -d '\r' | awk '{print $2}')"
  [ -n "$session" ] || return 1
  curl -s --max-time 10 -X POST "http://127.0.0.1:$port/mcp" \
    -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
    -H "MCP-Protocol-Version: 2025-06-18" -H "Mcp-Session-Id: $session" \
    -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
}
waited=0; body=""
until [ "$waited" -ge 15 ]; do
  body="$(mcp_probe "$PORT" 2>/dev/null || true)"
  case "$body" in *alpha__ping*) break ;; esac
  sleep 1; waited=$((waited+1))
done
printf '%s' "$body" > "$SB/repo-list.out"
assert_contains "$SB/repo-list.out" "alpha__ping" "the per-repo daemon serves its own configured surface"

# --- a SECOND repo resolves the port collision at launch and both serve ---
# Same repo path cloned elsewhere would hash differently; to force a collision we
# occupy this repo's NEXT deterministic launch: keep daemon 1 running, install into a
# second repo, and pin the second repo's base port to the first one's by occupying
# nothing — instead, occupy is proven the direct way: a foreign listener squats the
# second repo's deterministic base port, and the launcher must step past it without
# killing it.
REPO2="$SB/fakerepo2"
mkdir -p "$REPO2"; git -C "$REPO2" init -q
bash "$INSTALLER" --into "$REPO2" >/dev/null 2>&1
cat > "$REPO2/.astra/mcp-front/_mcp_info.json" <<EOF
{"mcpServers": {"beta": {"command": "python3", "args": ["$STUB", "--name", "beta", "--tool", "ping=repo2-pong"]}}}
EOF
BASE2="$(bash "$REPO2/.astra/mcp-front/run.sh" --print-port)"
assert_nonempty "$BASE2" "--print-port reports the deterministic base port without launching"
python3 -c "
import socket, time, sys
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', int(sys.argv[1]))); s.listen(1)
time.sleep(60)
" "$BASE2" &
OCCUPY=$!
sleep 1
bash "$REPO2/.astra/mcp-front/run.sh" >"$SB/run2.log" 2>&1 &
RPID2=$!
waited=0
until [ -f "$REPO2/.astra/mcp-front/port" ] || [ "$waited" -ge 10 ]; do sleep 1; waited=$((waited+1)); done
PORT2="$(cat "$REPO2/.astra/mcp-front/port" 2>/dev/null)"
assert_nonempty "$PORT2" "the second launcher chose a port"
[ "$PORT2" != "$BASE2" ] && pass "the squatted base port was stepped past ($BASE2 -> $PORT2)" \
  || fail "the launcher took the squatted port $BASE2"
kill -0 "$OCCUPY" 2>/dev/null && pass "the foreign listener was left alone, not preempted" \
  || fail "the foreign listener on $BASE2 was killed — only OUR stale daemons may be preempted"
assert_contains "$REPO2/.mcp.json" "127.0.0.1:$PORT2/mcp" ".mcp.json records the RESOLVED port"
waited=0; body2=""
until [ "$waited" -ge 15 ]; do
  body2="$(mcp_probe "$PORT2" 2>/dev/null || true)"
  case "$body2" in *beta__ping*) break ;; esac
  sleep 1; waited=$((waited+1))
done
printf '%s' "$body2" > "$SB/repo2-list.out"
assert_contains "$SB/repo2-list.out" "beta__ping" "the second repo's daemon serves beside the first"
body1_again="$(mcp_probe "$PORT" 2>/dev/null || true)"
printf '%s' "$body1_again" > "$SB/repo1-again.out"
assert_contains "$SB/repo1-again.out" "alpha__ping" "the first repo's daemon is untouched — autonomy holds"

# --- a shape-valid config the LOADER rejects must not touch a healthy deployment ---
# The adversarial round's second break: the old jq gate passed {"command":..., "url":...}
# (shape-valid, loader-fatal), so the relaunch preempted the running daemon and
# rewrote .mcp.json before dying — a working deployment torn down by a bad template
# push. The gate is now the daemon's own loader.
cp "$REPO/.astra/mcp-front/_mcp_info.json" "$SB/good-config-backup.json"
cat > "$REPO/.astra/mcp-front/_mcp_info.json" <<'EOF'
{"mcpServers": {"alpha": {"command": "python3", "url": "http://nope"}}}
EOF
MCPJSON_BEFORE="$(cat "$REPO/.mcp.json")"
red "a loader-fatal config is refused before any side effect" 78 "would not load" \
  bash "$REPO/.astra/mcp-front/run.sh"
LIVEPID="$(cat "$REPO/.astra/mcp-front/pid")"
kill -0 "$LIVEPID" 2>/dev/null && pass "the healthy daemon survived the bad-config relaunch" \
  || fail "the bad-config relaunch preempted the healthy daemon (pid $LIVEPID gone)"
[ "$(cat "$REPO/.mcp.json")" = "$MCPJSON_BEFORE" ] \
  && pass ".mcp.json was left exactly as it was" \
  || fail ".mcp.json was rewritten by a launch that then died"
cp "$SB/good-config-backup.json" "$REPO/.astra/mcp-front/_mcp_info.json"

# --- relaunching THIS repo's daemon preempts the stale copy and keeps the port ---
# The port file is REMOVED first and the old pid captured, so these assertions cannot
# be satisfied by run 1's leftovers (phase-5 panel, claude leg: the whole relaunch
# section passed against a run.sh that did nothing). A bystander process that merely
# carries the daemon path in its argv must survive the preempt — pgrep -f matched a
# tail -f on the installed file (verified live by the panel).
OLDPID="$(cat "$REPO/.astra/mcp-front/pid")"
rm -f "$REPO/.astra/mcp-front/port"
tail -f "$REPO/.astra/mcp-front/daemon.py" >/dev/null 2>&1 &
BYSTANDER=$!
bash "$REPO/.astra/mcp-front/run.sh" >"$SB/run1b.log" 2>&1 &
RPID=$!
sleep 3
kill -0 "$BYSTANDER" 2>/dev/null && pass "a bystander holding the daemon path in argv survives the preempt" \
  || fail "the preempt killed an innocent tail -f on the installed daemon.py"
kill "$BYSTANDER" 2>/dev/null; wait "$BYSTANDER" 2>/dev/null
kill -0 "$OLDPID" 2>/dev/null && fail "the stale daemon (pid $OLDPID) survived the relaunch" \
  || pass "the stale daemon was really preempted (pid $OLDPID is gone)"
PORT1B="$(cat "$REPO/.astra/mcp-front/port" 2>/dev/null)"
assert_eq "$PORT" "$PORT1B" "a relaunch self-preempts and keeps the deterministic port stable"
waited=0; body3=""
until [ "$waited" -ge 15 ]; do
  body3="$(mcp_probe "$PORT1B" 2>/dev/null || true)"
  case "$body3" in *alpha__ping*) break ;; esac
  sleep 1; waited=$((waited+1))
done
printf '%s' "$body3" > "$SB/repo1b.out"
assert_contains "$SB/repo1b.out" "alpha__ping" "and the relaunched daemon serves"

finish
