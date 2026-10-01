#!/usr/bin/env bash
# adversarial-run-side-effects.sh — REPRO for finding 2.
#
# Claim under attack (SYNTHESIS_phase5, "Fixed"): "run.sh now validates the config before
# ANY side effect: the unservable placeholder still dies loudly, but without first
# sweeping processes, writing a port file, and pointing .mcp.json at an endpoint that will
# never serve."
#
# run.sh's gate is a jq SHAPE check only (.mcpServers is an object of length>0). It is NOT
# the daemon's real loader (mcp_config). A config that is shape-valid but loader-INVALID —
# e.g. an upstream carrying an unimplemented 'url' field, a typo'd quirk, a block/map
# contradiction, a prefix collision — passes the jq gate, so run.sh proceeds to (1)
# preempt the running healthy daemon, (2) rewrite .mcp.json, THEN the daemon dies at
# startup. Under launchd KeepAlive this is the placeholder crash loop with side effects,
# reached through a shape-valid door — and it tears down a PREVIOUSLY WORKING daemon,
# which is worse than the empty placeholder the fix was scoped to.
#
# Expect: FAIL — the healthy daemon is preempted and .mcp.json points at a dead port.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALLER="$HERE/../repo-daemon-install.sh"
STUB="$HERE/../../tests/stub_mcp_server.py"
SB="$(mktemp -d)"; REPO="$SB/repo"
mkdir -p "$REPO"; git -C "$REPO" init -q
trap 'kill "$RPID" 2>/dev/null; wait "$RPID" 2>/dev/null; rm -rf "$SB"' EXIT

bash "$INSTALLER" --into "$REPO" >/dev/null
MF="$REPO/.astra/mcp-front"

cat > "$MF/_mcp_info.json" <<EOF
{"mcpServers": {"alpha": {"command":"python3","args":["$STUB","--name","alpha","--tool","ping=pong"]}}}
EOF
bash "$MF/run.sh" > "$SB/run1.log" 2>&1 &
RPID=$!
for _ in $(seq 1 15); do [ -f "$MF/port" ] && break; sleep 1; done
PORT="$(cat "$MF/port")"; OLDPID="$(cat "$MF/pid")"
sleep 2
kill -0 "$OLDPID" 2>/dev/null || { echo "SETUP FAIL: healthy daemon never came up"; exit 2; }
echo "healthy daemon pid=$OLDPID serving on $PORT"

# The template pushes a shape-valid but loader-invalid config (unimplemented 'url').
cat > "$MF/_mcp_info.json" <<EOF
{"mcpServers": {"alpha": {"command":"python3","url":"http://nope"}}}
EOF
bash "$MF/run.sh" > "$SB/run2.log" 2>&1
echo "--- run2 (should have refused before touching anything) ---"
grep -qi "preempting stale daemon" "$SB/run2.log" && echo "SIDE EFFECT: it preempted the running daemon"
listening="$(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | grep -c LISTEN || true)"

fail=0
if kill -0 "$OLDPID" 2>/dev/null; then
  echo "old daemon survived"; else echo "FAIL: healthy daemon was preempted by a config it then rejected"; fail=1; fi
if grep -q "127.0.0.1:$PORT/mcp" "$REPO/.mcp.json" && [ "$listening" -eq 0 ]; then
  echo "FAIL: .mcp.json points at $PORT but nothing is listening (dead endpoint)"; fail=1; fi
[ "$fail" -eq 0 ] && echo "PASS: no side effects before the loader rejection"
exit "$fail"
