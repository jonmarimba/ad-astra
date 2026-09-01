# Xcode 27 beta MCP — findings 2026-08-31 (Claude/Fable), by effect

The aggregator is BUILT and was RUN LIVE tonight: Xcode27CombinedFront.app ->
xcode27-combined-front-run.sh, port 8768, fronts the beta's mcpbridge + Drew, same
daemon.py that serves 50 tools with 26.6. It serves Drew's 29 tools; the xcode27 upstream
is the only thing not flowing. The daemon side is now clean (see the storm fix below); the
remaining failure is entirely inside Xcode 27's own tool service.

## The daemon self-DOS ("throwing up MCP requests all night") — FIXED

The old heartbeat wrapped every list_tools in a short fail_after and, on timeout, tore the
connection down and reconnected. Against Xcode 27 that became a dialog storm two ways:
killing the child withdrew the approval dialog and the next connect re-raised it; and
cancelling the list_tools request is NOT local — the pinned mcp>=2.0.0 SDK sends
notifications/cancelled over the wire and the re-issue fires a fresh handler (proven by
effect: fake-server handler count 1->2). The daemon now holds ONE list_tools in flight for
the first approval and never cancels it (bounded by APPROVAL_WAIT_SECONDS, sidecar keeps
last_progress fresh so the stall watchdog stays quiet), backs off reconnects, and asserts
CONNECT_TIMEOUT < STALL_EXIT at startup. Red-first test: test-mcp-front-approval-hold.sh.

## Xcode 27 mcpbridge (beta 27A5252f) — the tools/list close

- serverInfo: name "xcode-tools", version "25295.11" (26.6 was "24952").
- Answers initialize cleanly — but mcpbridge answers initialize LOCALLY, so init proves
  nothing about Xcode connectivity (it answered init even with 26.6 quit). tools/list is
  the first call that needs the real service.
- On tools/list the connection CLOSES at EXACTLY 5.0s (MCPError: Connection closed),
  deterministic across every cycle. No tools/list response, empty stderr.

## Ruled out as the blocker tonight — all confirmed good, by measurement

- Storm / daemon cancellation: fixed and tested (above); the close is not our teardown.
- MCP_XCODE_PID: pinned to the LIVE Xcode-beta pid (verified alive, correct process path).
- External-agents toggle: `IDEAllowUnauthenticatedAgents = 1` in com.apple.dt.Xcode
  (Xcode-beta shares that domain). Unauthenticated agents are ALLOWED, which also explains
  why NO approval dialog is presented now — approval is not the gate.
- .app identity: approved in Xcode's MCP allowlist; Automation TCC grant held, so the
  clicker (AUTO_ALLOW=1) is armed — but there is no dialog to click.
- MCP_XCODE_SESSION_ID: setting a fresh random UUID does NOT make tools/list complete.
  A valid session evidently must come from Xcode's own handshake, not an arbitrary value.
- DEVELOPER_DIR alone (bare `xcrun mcpbridge`, DEVELOPER_DIR=beta, NO MCP_XCODE_PID):
  gets the beta's bridge (25295.11) but STILL closes tools/list at 5s. Proves DEVELOPER_DIR
  overrides the bridge BINARY but not the tool-service endpoint, which follows the SYSTEM
  xcode-select link (26.6, quit). No per-process override reaches the service; only
  `sudo xcode-select --switch` does. This was the last non-sudo permutation and it failed.
- Workspace state: project (BuildCmp) freshly reopened, Xcode-beta activated, 12s to load
  — still closes at 5s.

## UPDATE 2026-09-01: the xcode-select switch was RUN and did NOT fix it

Jonathan ran `sudo xcode-select --switch` to the beta. With the beta selected, running,
and BuildCmp fully loaded (full Xcode UI present), tools/list STILL closes at exactly 5s
(MCPError: Connection closed) — both the bare `xcrun mcpbridge` probe and the approved
`.app` daemon. So xcode-select was necessary-maybe but NOT sufficient; the earlier
"confirmed" call was wrong.

Approval is also NOT the gate: `IDEAllowUnauthenticatedAgents = True` in com.apple.dt.Xcode
means Xcode is set to serve agents with no approval prompt (which is why no dialog ever
appears), and there is no per-client approval/deny entry in the prefs. So the client
identity theory is dead too.

Net after eliminating xcode-select, approval/identity, all per-process overrides
(DEVELOPER_DIR, MCP_XCODE_PID, MCP_XCODE_SESSION_ID), project state, and session id: the
documented bare `xcrun mcpbridge` external-agent path (which works for others) does NOT
work on THIS build (27A5252f) on this machine. Most likely a bug in this beta's mcpbridge
/ tool service. Nothing on our side remains to change. Re-test on the next Xcode 27 beta.

## (earlier) reference setup (2026-08-31, web)

The working Xcode-27 external-agent setup (Quentin Zervaas, crunchybagel.com,
"Enabling the Xcode 27 MCP Server in Claude Code") registers the server as BARE
`xcrun mcpbridge` — no full path, no DEVELOPER_DIR, no MCP_XCODE_PID. `xcrun` resolves
mcpbridge (and, evidently, the tool-service endpoint) through the SELECTED toolchain, so
that setup only works because Xcode 27 is the selected Xcode. Our aggregator fronts the
beta by full path + DEVELOPER_DIR + MCP_XCODE_PID precisely BECAUSE the beta is not
selected — and that substitution reaches the beta's mcpbridge binary but NOT a live tool
service, which is bound to the selected toolchain (26.6, currently Xcode.app and quit).
That is why init answers (local) and tools/list closes at 5s. The fix is to select the
beta; the workaround cannot replace selection.

## The remaining lever (needs Jonathan's password)

Everything client-side is eliminated. mcpbridge answers init locally, then cannot get
tools/list served by Xcode 27's tool service inside the running beta. The unified log
(log show --info --debug during a probe) shows ZERO mcpbridge or Xcode MCP/tool-service
messages — no service-side activity at all — consistent with mcpbridge reaching an
endpoint that never answers and timing out at 5s. The most likely cause left: Xcode 27's
MCP tool service (an XPC endpoint) is bound to the xcode-select'd toolchain, which is
still 26.6 — so mcpbridge, even pinned to the beta's PID via MCP_XCODE_PID, reaches no
live service. DEVELOPER_DIR selects the beta's mcpbridge BINARY,
not the system-selected service endpoint. Test (reversible, one command, needs sudo):

    sudo xcode-select --switch /Applications/Xcode-beta.app/Contents/Developer

If that makes tools/list return, the aggregator picks up Xcode 27's tools on the next
retry with no further change. If it does NOT, the 5s tools/list close is a beta bug in
Xcode 27's mcpbridge/tool service and there is nothing on our side left to fix.
