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
# Xcode itself is a dependency of half this file, not an optional extra: every assertion that
# reaches mcpbridge fails identically whether the daemon is broken or Xcode is simply closed.
# On 2026-08-26 that cost a ship-gate run four failures that read like a regression and were
# an unopened application.
#
# So the test opens it. Jonathan, 2026-08-26: "I don't mind that test starting with open
# /Applications/Xcode or whatever xcselect says is current Xcode." The path comes from
# `xcode-select -p` rather than a literal, because the current Xcode is whatever he has
# selected and a hardcoded path would quietly test the wrong one after a beta swap.
XCODE_APP="$(xcode-select -p 2>/dev/null | sed 's|/Contents/Developer.*||')"
if ! pgrep -x Xcode >/dev/null 2>&1; then
  [ -d "$XCODE_APP" ] || { fail "xcode-select points at '$XCODE_APP', which is not an app bundle. Run xcode-select --switch."; finish; exit 1; }
  echo "  ..  opening $XCODE_APP (not running)"
  open -g "$XCODE_APP" 2>/dev/null
  # Xcode is slow and mcpbridge only answers once it is up. Wait, but bounded: a hang here
  # would be indistinguishable from the failure this whole block exists to prevent.
  waited=0
  until pgrep -x Xcode >/dev/null 2>&1 || [ "$waited" -ge 90 ]; do sleep 3; waited=$((waited+3)); done
  if ! pgrep -x Xcode >/dev/null 2>&1; then
    fail "Xcode did not start within 90s of 'open $XCODE_APP' — the mcpbridge assertions below cannot mean anything."
    finish
    exit 1
  fi
  # Launching the app is not the same as the bridge being ready: it needs its MCP approval.
  sleep 10
fi

# A RUNNING XCODE WITH NO PROJECT OPEN IS NOT ENOUGH, and this is the part that made the
# first fix look like it worked. mcpbridge reports a workspacePath, so with zero windows the
# assertions below fail exactly as they did with Xcode closed. Verified live 2026-08-26:
# Xcode up, window count 0, same four failures.
#
# ASK XCODE, NOT SYSTEM EVENTS. `tell application "System Events" to tell process "Xcode" to
# count windows` returns 0 for a Xcode showing two windows — it reads the Accessibility view of
# the process, which is empty without that permission in this context. `tell application
# "Xcode" to count windows` returns 2. Measured side by side on 2026-08-26, after the wrong one
# had already produced a confident hard failure. The instrument was the bug, not Xcode.
#
# The test opens its OWN throwaway Swift package rather than one of Jonathan's workspaces.
# A test that opens the Kicker project would make the ship gate depend on the state of real
# work, and would put a test's fingerprints on a repo he is using.
# COUNT WORKSPACE DOCUMENTS, NOT WINDOWS. "Welcome to Xcode" is a window, so on a machine
# where Xcode is open with no project this guard was satisfied by the launcher panel and the
# scaffold below never ran — the suite then failed all four mcpbridge assertions while
# believing it had a workspace. Found live 2026-08-30, twice, before the real cause was
# reached. mcpbridge rejects with "no workspace windows are open"; a workspace DOCUMENT is
# the thing it means.
if [ "$(osascript -e 'tell application "Xcode" to count workspace documents' 2>/dev/null || echo 0)" -lt 1 ]; then
  need swift "install Xcode command line tools"
  SCRATCH="$SB/xcode-scratch"; mkdir -p "$SCRATCH"
  ( cd "$SCRATCH" && swift package init --name AstraProbe >/dev/null 2>&1 )
  [ -f "$SCRATCH/Package.swift" ] || { fail "could not scaffold a Swift package to open — swift package init failed in $SCRATCH"; finish; exit 1; }
  echo "  ..  opening a throwaway package so mcpbridge has a workspace"
  open -g -a "$XCODE_APP" "$SCRATCH/Package.swift" 2>/dev/null
  waited=0
  until [ "$(osascript -e 'tell application "Xcode" to count workspace documents' 2>/dev/null || echo 0)" -ge 1 ] || [ "$waited" -ge 90 ]; do
    sleep 3; waited=$((waited+3))
  done
  if [ "$(osascript -e 'tell application "Xcode" to count workspace documents' 2>/dev/null || echo 0)" -lt 1 ]; then
    fail "Xcode is running but never opened a window for $SCRATCH/Package.swift — mcpbridge has no workspace to report and the assertions below cannot mean anything."
    finish
    exit 1
  fi
  sleep 15   # indexing settles; mcpbridge answers once the workspace is loaded
fi

# KNOWN STATE, 2026-08-27 09:50 — the four mcpbridge assertions below fail, and the daemon is
# not the reason. Traced with Xcode running and two windows open:
#
#   * The daemon answers on /mcp, initializes, and returns its own instructions. Healthy.
#   * Its log shows the real shape: "connected — serving until this breaks", then five seconds
#     later "heartbeat list_tools failed, marking broken: Connection closed", forever. It
#     reconnects every 5s and the upstream drops each time.
#   * `xcrun mcpbridge` run DIRECTLY, with an initialize on stdin, prints NOTHING and exits 0.
#     So the bridge closes immediately on its own, with the daemon out of the picture.
#
# What is NOT established: why. Xcode's approval never being granted fits, and so does the
# throwaway Swift package this file opens not being the kind of workspace mcpbridge wants.
# Both fit the same evidence and neither has been tested, so neither is written into a guard.
# The next person here should start by opening a real .xcodeproj and watching for an approval
# prompt, rather than re-deriving the above.

mcp_call() { # usage: mcp_call <port> <method> <params-json>  -> prints the raw SSE response body
  local port="$1" method="$2" params="$3"
  local init_resp session
  init_resp="$(curl -s --max-time 30 -D - -X POST "http://127.0.0.1:$port/mcp" \
    -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
    -H "MCP-Protocol-Version: 2025-06-18" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}')"
  session="$(printf '%s' "$init_resp" | grep -i "mcp-session-id" | tr -d '\r' | awk '{print $2}')"
  [ -n "$session" ] || { echo "NO_SESSION"; return 1; }
  curl -s --max-time 30 -X POST "http://127.0.0.1:$port/mcp" \
    -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
    -H "MCP-Protocol-Version: 2025-06-18" -H "Mcp-Session-Id: $session" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"$method\",\"params\":$params}"
}

# --- the clicker's sibling rule, tested directly -----------------------------
# THE CLICKER IS THE ONLY WAY THESE DAEMONS EVER CONNECT. Xcode keys approval to the
# connecting PID and a restart always mints a new one, so nothing survives a bounce and an
# unattended daemon must answer its own prompt. That makes a wrong branch here fatal and
# silent: for sixteen days each daemon declined to touch the other's dialog, because the
# other was a live PID it did not recognise, while Xcode's dialogs do not stack so neither
# ever saw its own. 21,388 broken connections, and every log line said "connected".
#
# The two daemons happen to clear their own prompts when they start a second apart, so the
# sibling branch can pass a whole suite run without ever executing. It is asserted directly
# instead, against the REAL running daemon PIDs, with the discriminating negatives included —
# an unrelated Python must NOT be treated as family.
sib_a="$(pgrep -f "xcode-mcp-front/daemon.py" | head -1)"
sib_b="$(pgrep -f "xcode-mcp-front/daemon.py" | tail -1)"
if [ -z "$sib_a" ] || [ -z "$sib_b" ] || [ "$sib_a" = "$sib_b" ]; then
  fail "expected two front daemons running to test the sibling rule against; found: ${sib_a:-none} ${sib_b:-none}"
else
  sib_out="$(python3 - "$sib_a" "$sib_b" <<'SIBPY'
import importlib.util, os, sys, subprocess

path = os.path.expanduser("~/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py")
src = open(path, encoding="utf-8").read()
# Pull the function out rather than importing the module, which would start a server.
start = src.index("def _pid_is_sibling_front")
end = src.index("\nasync def", start)
ns = {"__file__": path, "os": os, "subprocess": subprocess}
exec(compile(src[start:end], "<sibling>", "exec"), ns)
f = ns["_pid_is_sibling_front"]

a, b = sys.argv[1], sys.argv[2]
checks = [
    ("daemon A is family", f(a), True),
    ("daemon B is family", f(b), True),
    ("this test process is not", f(str(os.getpid())), False),
    ("launchd is not", f("1"), False),
    ("a dead pid is not", f("999999"), False),
]
bad = [name for name, got, want in checks if got != want]
print("FAILED:" + ",".join(bad) if bad else "ALLOK")
SIBPY
)"
  if [ "$sib_out" = "ALLOK" ]; then
    pass "clicker sibling rule: both live front daemons are family, unrelated/dead pids are not"
  else
    fail "clicker sibling rule wrong — $sib_out"
  fi
fi

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
