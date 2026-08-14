#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["mcp>=2.0.0", "uvicorn"]
# ///
"""xcode-mcp-front daemon.

Problem: Xcode's MCP-connection "Allow" prompt is keyed per connecting PID. Every
separate process that execs `xcrun mcpbridge` (one per kicker node, one per Claude
Code / Codex session) makes Xcode ask again. kicker runs many concurrent nodes, so
that's many concurrent popups for the same underlying tool.

Fix: hold exactly ONE `xcrun mcpbridge` child process for the whole life of this
daemon, and front it with a Streamable HTTP MCP server. Every downstream client
(kicker nodes, Claude Code, Codex — anything that can speak MCP-over-HTTP) points
at this daemon's URL instead of spawning mcpbridge itself. Xcode approves ONE PID,
once, and stays approved as long as this daemon (and its mcpbridge child) keep running.

This is a dumb passthrough, not a real aggregator: it forwards list_tools/call_tool
to the one shared upstream ClientSession and returns whatever comes back. It does not
interpret tool semantics, and does not (yet) multiplex more than one upstream — see
config.py for the single upstream command. Calls are serialized through a lock:
mcpbridge's tolerance for concurrent overlapping calls hasn't been tested, so this
starts correctness-first. Tool calls are human-paced anyway; serialization shouldn't
be felt in practice.

NOT YET VALIDATED: whether `xcrun mcpbridge` actually tolerates staying open across
many sequential tool calls and Xcode project switches, as opposed to being built
assuming a fresh spawn per client session. Run spike.py first, against a live Xcode,
before trusting this daemon for real work.

Env overrides:
  XCODE_MCP_FRONT_UPSTREAM_CMD   default "xcrun"
  XCODE_MCP_FRONT_UPSTREAM_ARGS  default "mcpbridge" (space-separated)
  XCODE_MCP_FRONT_HOST           default "127.0.0.1" (do not bind wider — no auth layer)
  XCODE_MCP_FRONT_PORT           default "8765"
"""

import contextlib
import logging
import os

import anyio
import uvicorn
from mcp import types
from mcp.client.session import ClientSession
from mcp.client.stdio import StdioServerParameters, stdio_client
from mcp.server.lowlevel import Server
from mcp.server.lowlevel.server import ServerRequestContext

UPSTREAM_COMMAND = os.environ.get("XCODE_MCP_FRONT_UPSTREAM_CMD", "xcrun")
UPSTREAM_ARGS = os.environ.get("XCODE_MCP_FRONT_UPSTREAM_ARGS", "mcpbridge").split()
HOST = os.environ.get("XCODE_MCP_FRONT_HOST", "127.0.0.1")
PORT = int(os.environ.get("XCODE_MCP_FRONT_PORT", "8765"))

logging.basicConfig(level=logging.INFO, format="%(asctime)s xcode-mcp-front %(message)s")
log = logging.getLogger("xcode-mcp-front")

# Serializes every downstream call through the one shared upstream session.
# Set once the upstream connection is live; None means "not ready yet" (a
# client that connects before the upstream handshake finishes gets a clear
# error instead of a hang or a crash).
upstream_lock = anyio.Lock()
upstream_session: ClientSession | None = None


def _not_ready_result() -> types.CallToolResult:
    return types.CallToolResult(
        content=[types.TextContent(type="text", text="xcode-mcp-front: upstream mcpbridge not connected yet")],
        is_error=True,
    )


async def on_list_tools(
    ctx: ServerRequestContext, params: types.PaginatedRequestParams | None
) -> types.ListToolsResult:
    async with upstream_lock:
        if upstream_session is None:
            return types.ListToolsResult(tools=[])
        return await upstream_session.list_tools(params=params)


async def on_call_tool(ctx: ServerRequestContext, params: types.CallToolRequestParams) -> types.CallToolResult:
    async with upstream_lock:
        if upstream_session is None:
            return _not_ready_result()
        log.info("call_tool %s", params.name)
        result = await upstream_session.call_tool(params.name, params.arguments)
        if not isinstance(result, types.CallToolResult):
            # upstream returned something this dumb proxy doesn't forward (e.g.
            # InputRequiredResult) — surface it as an error rather than crash the daemon.
            return types.CallToolResult(
                content=[
                    types.TextContent(
                        type="text",
                        text=f"xcode-mcp-front: unsupported upstream result type {type(result).__name__}",
                    )
                ],
                is_error=True,
            )
        return result


@contextlib.asynccontextmanager
async def lifespan(app: Server):
    global upstream_session
    log.info("spawning upstream (once, held for this daemon's life): %s %s", UPSTREAM_COMMAND, UPSTREAM_ARGS)
    params = StdioServerParameters(command=UPSTREAM_COMMAND, args=UPSTREAM_ARGS)
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            async with upstream_lock:
                upstream_session = session
            log.info("upstream ready — one persistent mcpbridge connection is now live")
            try:
                yield {}
            finally:
                async with upstream_lock:
                    upstream_session = None
                log.info("upstream connection closed")


def build_server() -> Server:
    return Server(
        "xcode-mcp-front",
        version="0.1.0",
        instructions=(
            "This is a persistent proxy in front of Apple's own Xcode MCP bridge "
            "(`xcrun mcpbridge`) — same tools it exposes, reached over HTTP instead of "
            "each client spawning its own copy (that used to mean a separate Xcode "
            "approval popup per client; this way it's approved once and stays up).\n\n"
            "You will likely also see other Xcode-adjacent MCP servers configured "
            "alongside this one — commonly named xcode-mcp-server (a third-party tool, "
            "Drew's) and XcodeBuildMCP. That overlap is INTENTIONAL, not a conflict to "
            "resolve or a sign something's misconfigured. Different tools cover the same "
            "ground with different tradeoffs (this one needs Xcode's own approval once; "
            "XcodeBuildMCP runs headless; xcode-mcp-server has its own run/screenshot "
            "path). If a call here fails or behaves inconsistently, try the equivalent "
            "tool on one of the others instead of giving up.\n\n"
            "If you notice one of these consistently working better (or worse) than the "
            "others for a given task, say so out loud in your response — that's wanted "
            "information, not noise. It may be used later to deprioritize or hide the "
            "less reliable option."
        ),
        on_list_tools=on_list_tools,
        on_call_tool=on_call_tool,
        lifespan=lifespan,
    )


def main() -> None:
    server = build_server()
    app = server.streamable_http_app(host=HOST)
    log.info("listening on http://%s:%s/mcp", HOST, PORT)
    uvicorn.run(app, host=HOST, port=PORT, log_level="info")


if __name__ == "__main__":
    main()
