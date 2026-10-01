#!/usr/bin/env bash
# TIER: slow
# test-mcp-front-approval-hold.sh — the daemon's first-approval wait holds ONE list_tools
# in flight and never re-issues it, proven by the upstream's tools/list fire count.
#
# Xcode raises its "Allow X to access Xcode?" dialog LAZILY on the first tools/list and
# blocks that call until a human answers. Cancelling the call is NOT local: the pinned
# mcp>=2.0.0 SDK sends notifications/cancelled over the wire, the child cancels its
# handler, and any re-issue fires a FRESH handler — so a bounded-then-reissue heartbeat
# re-asks Xcode on a timer (the 2026-08-31 "throwing up MCP requests all night" storm).
# That wire mechanic was established by effect first: a fake server's handler count went
# 1->2 across one cancelled + one re-issued list_tools. This test guards the daemon side
# of it: the shipped connection_manager must keep exactly ONE list_tools outstanding for
# the whole approval wait, so the upstream sees tools/list exactly ONCE.
#
# By effect: stub_mcp_server.py --stall-tools --stall-log FILE appends one line to FILE on
# every tools/list and never answers; the line count is the number of times the daemon
# issued tools/list. stall_reissue_driver.py imports daemon.py and runs the REAL
# Upstream.connection_manager (not a hand-rolled client) against that stub, with
# _xcode_is_running forced True so the require_xcode first-approval path is exercised
# without a live Xcode. Timing knobs come from the environment this test sets.
#
# XCODE_MCP_FRONT_AUTO_ALLOW=0 always: the clicker path runs osascript against System
# Events, and a test must never send Apple Events from an unstable shell identity.
#
# RED-CAPABLE, two independent ways, both watched go red on 2026-08-31 before commit:
#   1. Automated RED control below: with APPROVAL_WAIT_S set BELOW the observation window,
#      the shipped code's own approval wait times out, tears down, reconnects and RE-ISSUES
#      — fire count climbs to 3 over the window, so the "== 1" assertion fails (rc 3,
#      "FIRE COUNT MISMATCH"). This proves the metric can see >1 and the green assert is
#      not a tautology.
#   2. Code-revert mutation (not automatable without editing the shipped file): change the
#      approval-wait bound at daemon.py's first-approval branch from
#      `anyio.fail_after(APPROVAL_WAIT_SECONDS)` to `anyio.fail_after(CONNECT_TIMEOUT_SECONDS)`.
#      Under THIS test's GREEN config (APPROVAL_WAIT_S=600 but CONNECT_TIMEOUT_S=1) the
#      reverted code cancels the held request after 1s and re-issues — fire count went to 3
#      and the GREEN assertion failed. Restore the line to APPROVAL_WAIT_SECONDS to go green.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

need uv "brew install uv"
need python3 "xcode-select --install"

DRIVER="$HERE/stall_reissue_driver.py"
STUB="$HERE/stub_mcp_server.py"
assert_file "$DRIVER" "the connection_manager driver is present"
assert_file "$STUB" "the stalling stub upstream is present"

# GREEN: shipped code holds one list_tools for the whole approval wait.
#   APPROVAL_WAIT_S=600  — far longer than the window, so the held request never cancels.
#   CONNECT_TIMEOUT_S=1  — deliberately SHORT: the shipped approval branch must NOT use it
#                          (a code revert to it is exactly mutation #2 above), so a green
#                          run here also fails the moment someone reintroduces that bound.
#   RECONNECT_POLL_S=0.5 — a fast poll so one window covers several would-be re-issues.
green_env=(
  XCODE_MCP_FRONT_AUTO_ALLOW=0
  XCODE_MCP_FRONT_RECONNECT_POLL_S=0.5
  XCODE_MCP_FRONT_APPROVAL_WAIT_S=600
  XCODE_MCP_FRONT_CONNECT_TIMEOUT_S=1
  XCODE_MCP_FRONT_HOME="$SB/home"
)
assert_rc 0 "shipped first-approval wait issues tools/list EXACTLY ONCE over a 6s window" \
  env "${green_env[@]}" \
    "$DRIVER" --stub "$STUB" --count-file "$SB/green_count" --window 6 --expect 1

# RED control: same driver, same by-effect assertion, but APPROVAL_WAIT_S=1 sits BELOW the
# 6s window. The approval wait times out, the connection tears down and reconnects, and the
# reconnect re-issues tools/list — the fire count climbs past 1, so "--expect 1" fails with
# rc 3 and the driver's own diagnostic. If this control ever PASSES (count stays 1 under a
# sub-window approval budget), the green assertion above is a tautology and the run fails.
red "a sub-window approval budget re-issues tools/list, so the fire count leaves 1" 3 "FIRE COUNT MISMATCH" \
  env XCODE_MCP_FRONT_AUTO_ALLOW=0 XCODE_MCP_FRONT_RECONNECT_POLL_S=0.5 \
      XCODE_MCP_FRONT_APPROVAL_WAIT_S=1 XCODE_MCP_FRONT_CONNECT_TIMEOUT_S=1 \
      XCODE_MCP_FRONT_HOME="$SB/home_red" \
      "$DRIVER" --stub "$STUB" --count-file "$SB/red_count" --window 6 --expect 1

finish
