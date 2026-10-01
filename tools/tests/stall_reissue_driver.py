#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["mcp>=2.0.0", "uvicorn"]
# ///
"""stall_reissue_driver — drives ONE daemon.py Upstream through its real
connection_manager against a stalling stdio upstream, then reports the upstream's
tools/list fire count by effect.

Not a client of its own: it imports daemon.py and runs Upstream.connection_manager,
so the exact shipped approval-wait loop is what gets exercised. The upstream is
stub_mcp_server.py --stall-tools --stall-log FILE, which answers initialize normally
and then, on EVERY tools/list, appends one line to FILE and never replies. The line
count in FILE is therefore the number of times the daemon (re)issued tools/list.

Usage:
  stall_reissue_driver.py --stub PATH --count-file FILE --window SECONDS --expect N

_xcode_is_running is forced True so the Upstream takes the require_xcode first-approval
path without a live Xcode. Every timing knob comes from the environment the caller sets
(XCODE_MCP_FRONT_RECONNECT_POLL_S, _APPROVAL_WAIT_S, _CONNECT_TIMEOUT_S, _AUTO_ALLOW=0),
read by daemon.py at import — so this driver sets none of them itself.

Exit codes: 0 = fire count == --expect; 3 = FIRE COUNT MISMATCH (the by-effect
assertion failed); other = a real error (bad args, import failure).
"""
import argparse
import os
import sys

import anyio

HERE = os.path.dirname(os.path.abspath(__file__))
DAEMON_DIR = os.path.join(HERE, "..", "xcode-mcp-front")
sys.path.insert(0, os.path.abspath(DAEMON_DIR))

import daemon  # noqa: E402  (path is set above)


async def _run(up, window):
    # connection_manager loops forever by design; bound it to the observation window,
    # then cancel. Cancellation tears the child down cleanly — it does not, on its own,
    # cause another tools/list.
    with anyio.move_on_after(window):
        await up.connection_manager()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stub", required=True)
    ap.add_argument("--count-file", required=True)
    ap.add_argument("--window", type=float, required=True)
    ap.add_argument("--expect", type=int, required=True)
    a = ap.parse_args()

    # Fresh count file so a previous run cannot bleed in.
    open(a.count_file, "w").close()

    # Force the running-Xcode gate open: no live Xcode in a test, but the first-approval
    # path is exactly what must be exercised.
    daemon._xcode_is_running = lambda: True

    up = daemon.Upstream(
        name="stall",
        command="python3",
        args=[a.stub, "--name", "stall", "--stall-tools", "--stall-log", a.count_file],
        require_xcode_running=True,
    )

    anyio.run(_run, up, a.window)

    with open(a.count_file) as f:
        fires = sum(1 for line in f if line.strip())
    print("APPROVAL_WAIT_SECONDS=%s RECONNECT_POLL_SECONDS=%s CONNECT_TIMEOUT_SECONDS=%s"
          % (daemon.APPROVAL_WAIT_SECONDS, daemon.RECONNECT_POLL_SECONDS,
             daemon.CONNECT_TIMEOUT_SECONDS))
    print("tools/list fire count over %.1fs window: %d (expected %d)"
          % (a.window, fires, a.expect))
    if fires != a.expect:
        print("FIRE COUNT MISMATCH: expected %d, got %d" % (a.expect, fires))
        sys.exit(3)
    print("FIRE COUNT OK")


if __name__ == "__main__":
    main()
