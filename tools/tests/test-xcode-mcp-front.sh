#!/usr/bin/env bash
# TIER: slow — needs a live Xcode with a workspace and its approval dialogs; minutes, and GUI by definition
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
# first fix look like it worked. mcpbridge reports a workspacePath, so with zero workspace
# documents the assertions below fail exactly as they did with Xcode closed. Verified live
# 2026-08-26: Xcode up, no workspace, same four failures.
#
# NO osascript. THIS FILE USED TO SEND FOUR APPLE EVENTS TO XCODE AND THAT WAS THE BUG BEHIND
# THE BUG. macOS attributes an Apple Event to the process that sent it, which here is the
# shell, which is tmux — not a stable grantable identity — so every run asked Jonathan to
# grant *tmux* control of Xcode, and answering it grants a shell rather than a task. That is
# the same disease as the daemon connecting as a bare interpreter with no identity to grant.
# Jonathan, 2026-08-30: "NOBODY should be firing one-off python or osascript shit without
# wrapping it in something I don't have to re-approve."
#
# What replaces it: `open` is LaunchServices, not scripting, and needs no Automation grant —
# the same reason launching Mail for the mail sweep is not GUI automation. Readiness is then
# read from the daemon itself over HTTP. Nothing here talks to Xcode directly.
#
# THE PROBE PACKAGE LIVES OUTSIDE THE SANDBOX, ON PURPOSE. It used to be scaffolded inside $SB,
# which lib.sh wipes on exit — so Xcode was left holding a workspace whose file had vanished
# and threw a modal "The workspace file ... has disappeared" that a human had to dismiss. Since
# Xcode's dialogs do not stack, that one modal also blocked every approval prompt behind it.
# Every run produced one; Jonathan closed twenty-one by hand in an evening and then killed
# Xcode. The previous fix was to close the document before the delete, which needed yet another
# Apple Event and still lost the race when the suite was killed rather than exited.
#
# Not deleting it is the fix that has no race in it. The package is created once, reused by
# every run, and never removed, so there is nothing for Xcode to lose and no cleanup that has
# to survive a SIGKILL. Reuse also skips re-scaffolding and re-indexing on every run.
PROBE_DIR="$HOME/.xcode-mcp-front-probe/AstraProbe"
if [ ! -f "$PROBE_DIR/Package.swift" ]; then
  need swift "install Xcode command line tools"
  mkdir -p "$PROBE_DIR"
  ( cd "$PROBE_DIR" && swift package init --name AstraProbe >/dev/null 2>&1 )
  [ -f "$PROBE_DIR/Package.swift" ] || { fail "could not scaffold the probe package in $PROBE_DIR — swift package init failed"; finish; exit 1; }
  echo "  ..  created the persistent probe package at $PROBE_DIR (kept between runs by design)"
fi
# A PENDING APPROVAL DIALOG INVALIDATES THE RUN, AND THIS TEST REFUSES RATHER THAN KILLS.
# Xcode's approval dialogs do not stack, so one already-showing prompt blocks every prompt the
# daemons raise behind it, and every mcpbridge assertion below then fails for a reason that has
# nothing to do with the daemons. That is a run whose result means nothing, so it should not
# produce a verdict.
#
# IT WOULD BE EASY TO SIGTERM XCODE HERE AND EASY IS THE PROBLEM. Jonathan, 2026-08-31: "You need
# to be careful putting SIGTERM in test code. I don't mind you doing that manually or even
# automatically during this testing to make it work. But I'd prefer you didn't rely on it for
# tests after we get this stable." A suite that terminates his IDE to tidy its own preconditions
# will one day terminate it in the middle of real work, and the test will have been the thing
# that lost it. Detect, report what a human should do, and stop. Killing Xcode during this
# stabilisation is a hand operation, deliberately, not a step this file performs.
if [ -x "$HERE/../xcode-mcp-front/check-allow-window.sh" ]; then
  pending="$("$HERE/../xcode-mcp-front/check-allow-window.sh" 2>/dev/null || true)"
  case "$pending" in
    *"access Xcode"*)
      fail "Xcode already has an approval dialog showing. Its dialogs do not stack, so this one
        blocks every prompt the daemons raise and all four mcpbridge assertions would fail for a
        reason unrelated to them. Answer or dismiss it and re-run. Not doing it for you: a test
        that terminates or clicks through your IDE's dialogs is a test that will eventually do
        that to real work."
      finish
      exit 1 ;;
  esac
fi

echo "  ..  opening the probe package so mcpbridge has a workspace to report"
open -g -a "$XCODE_APP" "$PROBE_DIR/Package.swift" 2>/dev/null

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

# XCODE MUST BE FRONTMOST, NOT MERELY OPEN WITH A WORKSPACE. mcpbridge connects cleanly and
# then drops the first real call when Xcode's workspace window is not key — Apple's own log
# says "Rejecting connection - no workspace windows are open" even while AppleScript reports
# the window present. Earlier runs of this suite passed only because something else had
# happened to focus Xcode; that is not a precondition, it is luck. `open -a` activates via
# LaunchServices, which needs no Automation permission and raises no consent prompt — unlike
# telling System Events to do it, which asks macOS to let the CALLING process control Xcode
# and prompts the user for tmux or Terminal.
open -a "$XCODE_APP" 2>/dev/null

# WAIT FOR THE WORKSPACE THE WAY THE TEST WILL LATER READ IT — through the daemon, over HTTP.
# The old wait polled Xcode with an Apple Event; this asks the thing under test whether it can
# see a workspace yet, which needs no permission and is the same channel every assertion below
# uses. A fixed `sleep 3` is not a substitute: Xcode indexes for as long as it indexes, and a
# short sleep turned "not ready yet" into a hard failure that read like a daemon regression.
#
# THIS DOES NOT MAKE THE FIRST ASSERTION UNFALSIFIABLE, which is the obvious hazard of using
# the assertion's own call as its precondition. Timing out here does NOT skip or pass anything:
# it falls through and lets the assertions run and fail on their own terms. The wait exists to
# stop a slow Xcode being reported as a broken daemon, not to decide the verdict.
echo "  ..  waiting for mcpbridge to report a workspace"
ws_waited=0
until [ "$ws_waited" -ge 90 ]; do
  probe_resp="$(mcp_call 8765 tools/call '{"name":"XcodeListWindows","arguments":{}}' 2>/dev/null || true)"
  case "$probe_resp" in
    *workspacePath*) echo "  ..  workspace visible after ${ws_waited}s"; break ;;
  esac
  sleep 5; ws_waited=$((ws_waited+5))
done
if [ "$ws_waited" -ge 90 ]; then
  # SAY WHICH FAILURE THIS IS. mcpbridge answers "no workspace windows are open" when Xcode has
  # nothing loaded, which is a different situation from the daemon being down, and the two used
  # to produce identical unexplained assertion failures. Naming it here does not weaken the
  # assertions; they still run.
  case "$probe_resp" in
    *"no workspace"*|*"No workspace"*)
      echo "  ..  NOTE: mcpbridge says Xcode has no workspace open after 90s. The failures below" ;;
    "")
      echo "  ..  NOTE: the daemon on 8765 returned nothing at all after 90s. The failures below" ;;
    *)
      echo "  ..  NOTE: the daemon answered but never reported a workspacePath in 90s. Below" ;;
  esac
  echo "  ..        are about THAT, not about routing or prefixing."
fi

# The sibling rule this used to assert is GONE, and deliberately. It identified a family
# process by substring-matching `ps` output, which GhOST-OpenClaw showed would match an
# unrelated `python3 helper.py --note /…/daemon.py` and grant it Xcode access. The clicker
# now approves only its OWN pid and clears anything else that has been blocking it past a
# grace period, so there is no identity heuristic left to test.

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
