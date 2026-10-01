#!/usr/bin/env bash
# TIER: slow — bootstraps a real launchd job (system mutation, multi-second waits)
# test-mcp-front-launchd.sh — the per-repo daemon under REAL launchd.
#
# Exists because the plist had been linted and key-read but never once LOADED —
# "you think shit works you've never tried" (Jonathan, 2026-08-31, correctly). Every
# assertion here is an effect launchd produces: the job starts on bootstrap, the daemon
# serves over real HTTP, a kill -9 is answered by a KeepAlive respawn that serves
# again, and bootout genuinely ends it. The label and repo are scratch; the trap boots
# the job out no matter how this exits.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

need uv "brew install uv"
need jq "brew install jq"
need python3 "xcode-select --install"
need launchctl "system-present"

INSTALLER="$HERE/../xcode-mcp-front/repo-daemon-install.sh"
STUB="$HERE/stub_mcp_server.py"
UID_NUM="$(id -u)"

REPO="$SB/launchdrepo"
mkdir -p "$REPO"
git -C "$REPO" init -q
bash "$INSTALLER" --into "$REPO" >/dev/null 2>&1 || { fail "installer failed"; finish; exit 1; }
PLIST="$REPO/.astra/mcp-front/launchd.plist"
LABEL="$(/usr/libexec/PlistBuddy -c "Print :Label" "$PLIST")"
assert_nonempty "$LABEL" "the plist carries a label"

cat > "$REPO/.astra/mcp-front/_mcp_info.json" <<EOF
{"mcpServers": {"alpha": {"command": "python3", "args": ["$STUB", "--name", "alpha", "--tool", "ping=launchd-pong"]}}}
EOF

trap 'launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null; rm -rf "$SB"' EXIT

# --- RED control: booting out a job that was never bootstrapped is a real failure ---
red "bootout of a never-bootstrapped label fails" 3 "No such process" \
  launchctl bootout "gui/$UID_NUM/$LABEL"

# --- bootstrap: launchd starts the job and the daemon serves ---
launchctl bootstrap "gui/$UID_NUM" "$PLIST" \
  && pass "launchctl bootstrap accepts the generated plist" \
  || { fail "launchctl bootstrap REJECTED the generated plist"; finish; exit 1; }

mcp_probe() { # <port> -> tools/list body
  local port="$1" init_resp session
  init_resp="$(curl -s --max-time 10 -D - -X POST "http://127.0.0.1:$port/mcp" \
    -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
    -H "MCP-Protocol-Version: 2025-06-18" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"launchd-test","version":"0"}}}')"
  session="$(printf '%s' "$init_resp" | grep -i "mcp-session-id" | tr -d '\r' | awk '{print $2}')"
  [ -n "$session" ] || return 1
  curl -s --max-time 10 -X POST "http://127.0.0.1:$port/mcp" \
    -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
    -H "MCP-Protocol-Version: 2025-06-18" -H "Mcp-Session-Id: $session" \
    -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
}

waited=0; body=""
until [ "$waited" -ge 30 ]; do
  PORT="$(cat "$REPO/.astra/mcp-front/port" 2>/dev/null || true)"
  if [ -n "$PORT" ]; then
    body="$(mcp_probe "$PORT" 2>/dev/null || true)"
    case "$body" in *alpha__ping*) break ;; esac
  fi
  sleep 2; waited=$((waited+2))
done
printf '%s' "$body" > "$SB/launchd-list.out"
assert_contains "$SB/launchd-list.out" "alpha__ping" \
  "launchd started the job and the daemon serves its surface (RunAtLoad, for real)"

# --- KeepAlive, by effect: kill -9 the daemon; launchd must bring it back serving ---
DPID="$(cat "$REPO/.astra/mcp-front/pid" 2>/dev/null)"
assert_nonempty "$DPID" "the launchd-started run recorded its pid"
kill -9 "$DPID" 2>/dev/null
waited=0; body=""
until [ "$waited" -ge 40 ]; do
  NEWPID="$(cat "$REPO/.astra/mcp-front/pid" 2>/dev/null || true)"
  PORT="$(cat "$REPO/.astra/mcp-front/port" 2>/dev/null || true)"
  if [ -n "$NEWPID" ] && [ "$NEWPID" != "$DPID" ] && [ -n "$PORT" ]; then
    body="$(mcp_probe "$PORT" 2>/dev/null || true)"
    case "$body" in *alpha__ping*) break ;; esac
  fi
  sleep 2; waited=$((waited+2))
done
printf '%s' "$body" > "$SB/respawn-list.out"
assert_contains "$SB/respawn-list.out" "alpha__ping" \
  "KeepAlive respawned a killed daemon and it serves again — asserted by effect, not by reading the plist"
[ "$(cat "$REPO/.astra/mcp-front/pid")" != "$DPID" ] \
  && pass "the respawn is a genuinely new process" \
  || fail "the pid never changed — no respawn happened"

# --- bootout ends it: the port closes and stays closed ---
PORT="$(cat "$REPO/.astra/mcp-front/port")"
launchctl bootout "gui/$UID_NUM/$LABEL" \
  && pass "bootout succeeds for the running job" \
  || fail "bootout failed for a job launchd claims to manage"
waited=0
while lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 && [ "$waited" -lt 15 ]; do
  sleep 1; waited=$((waited+1))
done
lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 \
  && fail "the daemon is still listening after bootout — launchd did not end it" \
  || pass "after bootout the port is closed and stays closed (no zombie respawn)"

finish
