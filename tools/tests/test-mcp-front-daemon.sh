#!/usr/bin/env bash
# test-mcp-front-daemon.sh — the aggregator daemon itself, by effect over its real HTTP
# endpoint, with STUB upstreams (stub_mcp_server.py) instead of live Xcode.
#
# This is the fast-tier counterpart of the slow test-xcode-mcp-front.sh: same daemon.py,
# same transport, but the upstreams are dependency-free stubs, so it asserts the
# aggregation contract (config file honoured, prefixes served, calls routed, unknown
# names rejected) without launching Xcode or waiting on an approval dialog. Increment 1.2:
# the _mcp_info.json file replaces the corrupting colon/comma env format.
#
# XCODE_MCP_FRONT_AUTO_ALLOW=0 always: the clicker path runs osascript against System
# Events, and a test must never send Apple Events from an unstable shell identity
# (test-xcode-mcp-front.sh documents the tmux-grant disease).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

need uv "brew install uv"
need curl "system-present"
need python3 "xcode-select --install"

DAEMON="$HERE/../xcode-mcp-front/daemon.py"
STUB="$HERE/stub_mcp_server.py"
PORT=8899

cat > "$SB/_mcp_info.json" <<EOF
{
  "mcpServers": {
    "alpha": {"command": "python3", "args": ["$STUB", "--name", "alpha", "--tool", "ping=alpha-pong", "--tool", "build=alpha-built", "--tool", "secret=env:ASTRA_STUB_SECRET", "--tool", "bad=error:kaboom-from-alpha"], "env": {"ASTRA_STUB_SECRET": "sekrit-env-value"}},
    "beta":  {"command": "python3", "args": ["$STUB", "--name", "beta", "--tool", "ping=beta-pong"]},
    "pager": {"command": "python3", "args": ["$STUB", "--name", "pager", "--page-size", "1", "--tool", "first=page-one", "--tool", "second=page-two"]}
  }
}
EOF

env -u XCODE_MCP_FRONT_UPSTREAMS \
  XCODE_MCP_FRONT_MCP_INFO="$SB/_mcp_info.json" \
  XCODE_MCP_FRONT_PORT="$PORT" \
  XCODE_MCP_FRONT_HOME="$SB/home" \
  XCODE_MCP_FRONT_AUTO_ALLOW=0 \
  XCODE_MCP_FRONT_SERVER_NAME="astra-test-front" \
  uv run --script "$DAEMON" >"$SB/daemon.log" 2>&1 &
DPID=$!
trap 'kill "$DPID" 2>/dev/null; wait "$DPID" 2>/dev/null; rm -rf "$SB"' EXIT

mcp_call() { # usage: mcp_call <method> <params-json> -> raw SSE body on stdout
  local method="$1" params="$2" init_resp session
  init_resp="$(curl -s --max-time 10 -D - -X POST "http://127.0.0.1:$PORT/mcp" \
    -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
    -H "MCP-Protocol-Version: 2025-06-18" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}')"
  session="$(printf '%s' "$init_resp" | grep -i "mcp-session-id" | tr -d '\r' | awk '{print $2}')"
  [ -n "$session" ] || { echo "NO_SESSION"; return 1; }
  curl -s --max-time 10 -X POST "http://127.0.0.1:$PORT/mcp" \
    -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
    -H "MCP-Protocol-Version: 2025-06-18" -H "Mcp-Session-Id: $session" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"$method\",\"params\":$params}"
}

# Wait for the daemon to be up AND for both stub upstreams to be connected (the connection
# managers connect asynchronously after uvicorn starts answering).
waited=0
until [ "$waited" -ge 30 ]; do
  if ! kill -0 "$DPID" 2>/dev/null; then
    fail "daemon exited during startup — its log:"; sed 's/^/        /' "$SB/daemon.log" >&2
    finish; exit 1
  fi
  list="$(mcp_call tools/list '{}' 2>/dev/null || true)"
  case "$list" in *alpha__*) break ;; esac
  sleep 1; waited=$((waited+1))
done

printf '%s' "$list" > "$SB/list.out"
assert_contains "$SB/list.out" "alpha__ping" "tools/list serves alpha's tools under the alpha__ prefix"
assert_contains "$SB/list.out" "alpha__build" "tools/list serves alpha's second tool"
assert_contains "$SB/list.out" "beta__ping" "tools/list serves beta's tools under the beta__ prefix"

# Same tool name on both upstreams routes by prefix, not by luck.
mcp_call tools/call '{"name":"alpha__ping","arguments":{}}' > "$SB/alpha.out"
assert_contains "$SB/alpha.out" "alpha-pong" "alpha__ping routes to the alpha stub"
mcp_call tools/call '{"name":"beta__ping","arguments":{}}' > "$SB/beta.out"
assert_contains "$SB/beta.out" "beta-pong" "beta__ping routes to the beta stub, same bare name"

# --- increment 1.5: a paginating upstream is drained into a full snapshot ---
# Cursors are per-server opaque tokens, so the one downstream cursor used to be handed
# to EVERY upstream verbatim; the pager stub serves one tool per page, and only draining
# its pages produces both tools.
assert_contains "$SB/list.out" "pager__first" "page one of a paginating upstream is served"
assert_contains "$SB/list.out" "pager__second" "page two is served as well — the upstream was drained, not truncated"
mcp_call tools/call '{"name":"pager__second","arguments":{}}' > "$SB/pager.out"
assert_contains "$SB/pager.out" "page-two" "a tool from a drained later page is callable"

# A downstream cursor this daemon never issued is refused, not forwarded to upstreams
# whose cursor spaces it cannot belong to — with the spec's INVALID_PARAMS code and the
# daemon's own diagnostic, so a generic 500 cannot satisfy this (panel: the bare "error"
# substring passed for any failure at all).
mcp_call tools/list '{"cursor":"bogus-cursor"}' > "$SB/cursor.out"
assert_contains "$SB/cursor.out" "-32602" \
  "an unissued cursor is refused with the spec's INVALID_PARAMS code"
assert_contains "$SB/cursor.out" "unexpected cursor" \
  "and the refusal carries the daemon's own diagnostic, not a generic internal error"

# An unrecognised exposed name is a real error, not a silent success or a misroute.
mcp_call tools/call '{"name":"NotARealTool","arguments":{}}' > "$SB/unknown.out"
assert_contains "$SB/unknown.out" "doesn't match any known upstream prefix" \
  "an unknown exposed name returns the routing error"
assert_contains "$SB/unknown.out" '"isError":true' "and it is marked as an error result"

# --- Phase 1 hardening: env pass-through, application errors, no blind forwarding ---
# The config's env map must reach the child by EFFECT: the SDK's default child
# environment is a six-variable allowlist, so this value arrives only if the daemon
# passes it deliberately.
mcp_call tools/call '{"name":"alpha__secret","arguments":{}}' > "$SB/secret.out"
assert_contains "$SB/secret.out" "sekrit-env-value" \
  "the config env map reaches the upstream child process"

# An upstream's application-level JSON-RPC error is the CALLER'S error, not a dead
# transport (codex leg: the old path marked the connection broken and reported 'not
# connected right now', tearing down a healthy session).
mcp_call tools/call '{"name":"alpha__bad","arguments":{}}' > "$SB/bad.out"
assert_contains "$SB/bad.out" "kaboom-from-alpha" \
  "an upstream JSON-RPC error is forwarded with its own message"
assert_not_contains "$SB/bad.out" "not connected right now" \
  "and is not misreported as a disconnection"
mcp_call tools/call '{"name":"alpha__ping","arguments":{}}' > "$SB/after-bad.out"
assert_contains "$SB/after-bad.out" "alpha-pong" \
  "the session survives the upstream error — no teardown, no reconnect gap"

# A prefixed name the upstream does not offer is refused after a refresh, never
# forwarded blind (the prefix fallback would bypass Phase 2's sieve).
mcp_call tools/call '{"name":"alpha__enoexist","arguments":{}}' > "$SB/enoexist.out"
assert_contains "$SB/enoexist.out" "does not currently offer" \
  "a prefixed-but-unknown tool is refused by the daemon, not forwarded on faith"

# --- increment 1.4: a dead upstream must not blank the others, and connected-but-empty
# --- is not the same thing as disconnected ---
# All three colloquium brands found this independently: on_list_tools served ZERO tools
# for every upstream when any one was missing, so during an Xcode reconnect Drew's tools
# — which need no Xcode — vanished too. gamma's command dies instantly (never connects);
# delta connects fine and genuinely has zero tools. alpha must keep serving through both.
cat > "$SB/_mcp_degraded.json" <<EOF
{
  "mcpServers": {
    "alpha": {"command": "python3", "args": ["$STUB", "--name", "alpha", "--tool", "ping=alpha-pong"]},
    "gamma": {"command": "python3", "args": ["-c", "import sys; sys.exit(1)"]},
    "delta": {"command": "python3", "args": ["$STUB", "--name", "delta"]},
    "looper": {"command": "python3", "args": ["$STUB", "--name", "looper", "--page-loop", "--tool", "trap=x"]}
  }
}
EOF
PORT=8901
env -u XCODE_MCP_FRONT_UPSTREAMS \
  XCODE_MCP_FRONT_MCP_INFO="$SB/_mcp_degraded.json" \
  XCODE_MCP_FRONT_PORT="$PORT" \
  XCODE_MCP_FRONT_HOME="$SB/home2" \
  XCODE_MCP_FRONT_AUTO_ALLOW=0 \
  XCODE_MCP_FRONT_SERVER_NAME="astra-test-degraded" \
  uv run --script "$DAEMON" >"$SB/daemon2.log" 2>&1 &
DPID2=$!
trap 'kill "$DPID" "$DPID2" 2>/dev/null; wait "$DPID" "$DPID2" 2>/dev/null; rm -rf "$SB"' EXIT

# Wait only for the daemon's HTTP to answer at all — waiting for alpha__ would make the
# assertion its own precondition and turn the old blank-everything defect into a timeout.
waited=0
until [ "$waited" -ge 20 ]; do
  if ! kill -0 "$DPID2" 2>/dev/null; then
    fail "degraded daemon exited during startup — its log:"; sed 's/^/        /' "$SB/daemon2.log" >&2
    finish; exit 1
  fi
  dlist="$(mcp_call tools/list '{}' 2>/dev/null || true)"
  case "$dlist" in *'"tools"'*) break ;; esac
  sleep 1; waited=$((waited+1))
done
# Give the connection managers a few extra ticks: alpha needs to be connected AND listed.
for _ in 1 2 3 4 5 6 7 8; do
  case "$dlist" in *alpha__ping*) break ;; esac
  sleep 1
  dlist="$(mcp_call tools/list '{}' 2>/dev/null || true)"
done
printf '%s' "$dlist" > "$SB/dlist.out"
assert_contains "$SB/dlist.out" "alpha__ping" \
  "a dead upstream (gamma) does not blank the healthy one's tools"
assert_not_contains "$SB/dlist.out" "gamma__" "the dead upstream contributes nothing"
assert_not_contains "$SB/dlist.out" "delta__" \
  "a connected upstream with zero tools contributes zero tools, and is not treated as missing"

mcp_call tools/call '{"name":"alpha__ping","arguments":{}}' > "$SB/alpha2.out"
assert_contains "$SB/alpha2.out" "alpha-pong" "calls to the healthy upstream still route while gamma is down"

mcp_call tools/call '{"name":"gamma__anything","arguments":{}}' > "$SB/gamma.out"
assert_contains "$SB/gamma.out" "[gamma] not connected right now" \
  "a call to the dead upstream names IT as the unavailable one"
assert_contains "$SB/gamma.out" '"isError":true' "and is an error result, not a silent success"

# --- an upstream whose cursor loops is bounded and reported, not followed forever ---
# The looper answers instantly with the same nextCursor every page; an unbounded drain
# accumulates pages until timeout or memory death, and every upstream listed after it
# waits the whole time (panel, all three brands; the claude leg measured 48k pages in
# 10 seconds).
assert_not_contains "$SB/dlist.out" "looper__" \
  "a cursor-cycling upstream contributes nothing rather than wedging the list"

# --- the log tells the degraded story precisely (panel: the list alone cannot
# --- distinguish connected-but-empty from disconnected, so the test must read it) ---
grep "WITHOUT unavailable" "$SB/daemon2.log" > "$SB/unavail-lines" || : > "$SB/unavail-lines"
assert_contains "$SB/unavail-lines" "gamma" "the unavailable warning names the dead upstream"
assert_not_contains "$SB/unavail-lines" "delta" \
  "the connected-but-empty upstream is NOT reported unavailable"
assert_contains "$SB/daemon2.log" "[gamma] attempting connect" \
  "gamma was genuinely attempted, not silently dropped from the config"
assert_contains "$SB/daemon2.log" "[delta] connected" \
  "delta genuinely connected — its absence from the list means empty, not missing"

# --- a single-upstream FILE config honours its declared prefix ---
# The validator prints prefix=solo__ and the daemon used to serve the tool bare; the
# two disagreed about the same file, and adding a second server silently renamed every
# tool the first offered (the roadmap's own defect 2, measured live by the claude leg).
cat > "$SB/_mcp_solo.json" <<EOF
{"mcpServers": {"solo": {"command": "python3", "args": ["$STUB", "--name", "solo", "--tool", "ping=solo-pong"]}}}
EOF
PORT=8905
env -u XCODE_MCP_FRONT_UPSTREAMS \
  XCODE_MCP_FRONT_MCP_INFO="$SB/_mcp_solo.json" \
  XCODE_MCP_FRONT_PORT="$PORT" \
  XCODE_MCP_FRONT_HOME="$SB/home3" \
  XCODE_MCP_FRONT_AUTO_ALLOW=0 \
  XCODE_MCP_FRONT_SERVER_NAME="astra-test-solo" \
  uv run --script "$DAEMON" >"$SB/daemon3.log" 2>&1 &
DPID3=$!
trap 'kill "$DPID" "$DPID2" "$DPID3" 2>/dev/null; wait "$DPID" "$DPID2" "$DPID3" 2>/dev/null; rm -rf "$SB"' EXIT
waited=0
until [ "$waited" -ge 20 ]; do
  slist="$(mcp_call tools/list '{}' 2>/dev/null || true)"
  case "$slist" in *solo__ping*|*'"ping"'*) break ;; esac
  sleep 1; waited=$((waited+1))
done
printf '%s' "$slist" > "$SB/solo.out"
assert_contains "$SB/solo.out" "solo__ping" \
  "a one-upstream file config serves the prefix its validator printed"
mcp_call tools/call '{"name":"solo__ping","arguments":{}}' > "$SB/solo-call.out"
assert_contains "$SB/solo-call.out" "solo-pong" "and the prefixed name routes"

# --- RED control: the replaced env format is a startup death, not a fallback ---
red "a set XCODE_MCP_FRONT_UPSTREAMS kills the daemon at startup naming the replacement" 1 "replaced by _mcp_info.json" \
  env XCODE_MCP_FRONT_UPSTREAMS="xcode:1:xcrun:mcpbridge" XCODE_MCP_FRONT_PORT=8907 \
      XCODE_MCP_FRONT_HOME="$SB/home4" XCODE_MCP_FRONT_AUTO_ALLOW=0 \
      uv run --script "$DAEMON"

finish
