#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["mcp>=2.0.0"]
# ///
"""spike.py — validates the one assumption daemon.py is built on: that a single
`xcrun mcpbridge` connection tolerates staying open across MANY sequential tool
calls, rather than being built assuming a fresh spawn per client session.

Requires Xcode.app running with a project open (mcpbridge bridges to a live Xcode
via XPC — it has nothing to talk to otherwise).

Run: uv run spike.py [N]   (N = number of list_tools round-trips, default 5)

PASS means: same PID, N successful round-trips, no reconnect. That's the green
light to trust daemon.py's core assumption. A failure here means the daemon
design needs to change (e.g. reconnect-on-error, or per-project-switch respawn)
before it's worth relying on for real kicker traffic.
"""

import sys

import anyio
from mcp.client.session import ClientSession
from mcp.client.stdio import StdioServerParameters, stdio_client


async def main(n: int) -> None:
    params = StdioServerParameters(command="xcrun", args=["mcpbridge"])
    print(f"spawning: xcrun mcpbridge (held open for {n} round-trips)")
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            init = await session.initialize()
            print(f"initialize OK — server: {init.server_info}")
            for i in range(1, n + 1):
                result = await session.list_tools()
                print(f"  round-trip {i}/{n}: {len(result.tools)} tools listed")
            print(f"PASS — {n} sequential calls over ONE connection, no reconnect needed")


if __name__ == "__main__":
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 5
    anyio.run(main, n)
