#!/usr/bin/env bash
# test-xcode-mcp-front.sh — asserts BY EFFECT against the real, running daemons
# (both the single-upstream and combined instances) over their actual HTTP
# endpoints — no mocks, no fakes. Requires both launchd jobs already running:
#   com.jonathansaggau.xcode-mcp-front       (port 8765, single-upstream)
#   com.jonathansaggau.xcode-combined-front  (port 8767, xcode__ + drews__)
# and a live Xcode with the Kicker project open (xcode-mcp-front/README.md's
# own spike.py has the same live-Xcode requirement).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

need curl "brew install curl (should already be system-present)"
need python3 "brew install python3"

mcp_call() { # usage: mcp_call <port> <method> <params-json>  -> prints the raw SSE response body
  local port="$1" method="$2" params="$3"
  local init_resp session
  init_resp="$(curl -s -D - -X POST "http://127.0.0.1:$port/mcp" \
    -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
    -H "MCP-Protocol-Version: 2025-06-18" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}')"
  session="$(printf '%s' "$init_resp" | grep -i "mcp-session-id" | tr -d '\r' | awk '{print $2}')"
  [ -n "$session" ] || { echo "NO_SESSION"; return 1; }
  curl -s -X POST "http://127.0.0.1:$port/mcp" \
    -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
    -H "MCP-Protocol-Version: 2025-06-18" -H "Mcp-Session-Id: $session" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"$method\",\"params\":$params}"
}

# --- single-upstream daemon (port 8765): unprefixed passthrough still works ---
resp="$(mcp_call 8765 tools/call '{"name":"XcodeListWindows","arguments":{}}')"
echo "$resp" > "$SB/single.out"
assert_contains "$SB/single.out" "workspacePath" "single-upstream daemon: XcodeListWindows (unprefixed) returns a real workspace path"

# --- combined daemon (port 8767): tool list carries BOTH prefixes ---
list_resp="$(mcp_call 8767 tools/list '{}')"
echo "$list_resp" > "$SB/list.out"
xcode_count="$(python3 -c "
import sys,json
for line in open('$SB/list.out'):
    if line.startswith('data:'):
        d=json.loads(line[5:])
        names=[t['name'] for t in d['result']['tools']]
        print(sum(1 for n in names if n.startswith('xcode__')))
")"
drews_count="$(python3 -c "
import sys,json
for line in open('$SB/list.out'):
    if line.startswith('data:'):
        d=json.loads(line[5:])
        names=[t['name'] for t in d['result']['tools']]
        print(sum(1 for n in names if n.startswith('drews__')))
")"
[ "${xcode_count:-0}" -ge 1 ] && pass "combined daemon: tools/list has xcode__-prefixed tools ($xcode_count)" || fail "combined daemon: no xcode__-prefixed tools found"
[ "${drews_count:-0}" -ge 1 ] && pass "combined daemon: tools/list has drews__-prefixed tools ($drews_count)" || fail "combined daemon: no drews__-prefixed tools found"

# --- combined daemon: a real xcode__ call routes to mcpbridge and returns real content ---
resp="$(mcp_call 8767 tools/call '{"name":"xcode__XcodeListWindows","arguments":{}}')"
echo "$resp" > "$SB/xcode_call.out"
assert_contains "$SB/xcode_call.out" "workspacePath" "combined daemon: xcode__XcodeListWindows routes to mcpbridge, real workspace path back"

# --- combined daemon: a real drews__ call routes to drews-xcode-mcp and returns real content ---
resp="$(mcp_call 8767 tools/call '{"name":"drews__version","arguments":{}}')"
echo "$resp" > "$SB/drews_call.out"
assert_contains "$SB/drews_call.out" "drews-xcode-mcp" "combined daemon: drews__version routes to Drew's server, real version string back"

# --- RED control: an unprefixed/unknown tool name on the combined daemon must fail, not silently succeed ---
resp="$(mcp_call 8767 tools/call '{"name":"NotARealPrefixedTool","arguments":{}}')"
echo "$resp" > "$SB/red.out"
assert_contains "$SB/red.out" "doesn't match any known upstream prefix" "RED: an unprefixed/unrecognized tool name on the combined daemon returns a real error, not a silent success"

# --- both launchd plists: KeepAlive must be bare true, not {SuccessfulExit:false} ---
# (found live 2026-08-14: {SuccessfulExit:false} reads a clean-exit-on-EADDRINUSE as
# "finished on purpose" and never respawns — the daemon silently stayed dead)
for label in com.jonathansaggau.xcode-mcp-front com.jonathansaggau.xcode-combined-front; do
  plist="$HOME/Library/LaunchAgents/$label.plist"
  assert_file "$plist" "$label: plist exists"
  ka="$(/usr/libexec/PlistBuddy -c "Print :KeepAlive" "$plist" 2>/dev/null)"
  assert_eq "true" "$ka" "$label: KeepAlive is bare true (not {SuccessfulExit:false})"
done

finish
