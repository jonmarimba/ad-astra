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
interpret tool semantics, and does not (yet) multiplex more than one upstream. Calls
are serialized through a lock: mcpbridge's tolerance for concurrent overlapping calls
hasn't been tested, so this starts correctness-first. Tool calls are human-paced
anyway; serialization shouldn't be felt in practice.

VALIDATED 2026-08-14 (all live, against a real Xcode):
- One connection tolerates many sequential calls of different shapes, no reconnect
  needed (spike.py, then a real multi-call session through this daemon).
- Quitting Xcode does NOT crash this process — it keeps serving HTTP, but the
  mcpbridge child dies and every call after that fails clean with "Connection
  closed".
- The approval prompt's PID (confirmed from the actual dialog, not assumed) is
  THIS daemon's own PID, not the ephemeral mcpbridge child's — so as long as this
  process keeps running, reconnecting mcpbridge in a loop should NOT need a fresh
  approval each time, only the very first connection (or after a genuine
  permission reset) does.

Recovery design (Jonathan, 2026-08-14, after watching a stuck approval sit
unclicked because the click-attempt and the reconnect-attempt weren't on the
same timer): "any time the connection is lost... poll for xcode, then poll for
the allow window... because you may not know if it's broken because it lost
auth somehow or if xcode isn't running." One loop, in-process (no more
exit-and-let-the-supervisor-respawn — reconnecting in place is simpler and
doesn't burn a fresh PID / fresh approval each time): while not connected,
every poll tick — check Xcode is running, best-effort click "Allow" if it's
showing, then attempt a fresh connect. Gentle (a few seconds between tries),
indefinite, and it's the SAME check whether the break was "Xcode quit" or
"connection died some other way" — no need to know which, the recovery is
identical either way.

Env overrides:
  XCODE_MCP_FRONT_UPSTREAM_CMD    default "xcrun"
  XCODE_MCP_FRONT_UPSTREAM_ARGS   default "mcpbridge" (space-separated)
  XCODE_MCP_FRONT_HOST            default "127.0.0.1" (do not bind wider — no auth layer)
  XCODE_MCP_FRONT_PORT            default "8765"
  XCODE_MCP_FRONT_XCODE_APP_PATH  default "/Applications/Xcode.app" — the reconnect
                                   loop matches THIS exact binary path, not a bare
                                   process name (Xcode.app and Xcode-beta.app share
                                   both their process name and bundle ID, so only
                                   the full path tells them apart — confirmed live)
  XCODE_MCP_FRONT_RECONNECT_POLL_S default "5" (seconds between reconnect attempts)
  XCODE_MCP_FRONT_CONNECT_TIMEOUT_S default "15" (per-attempt connect timeout, so a
                                   stuck approval dialog can't hang a whole attempt
                                   forever — it just times out and the next tick
                                   tries the click again)
"""

import asyncio
import contextlib
import logging
import os
import subprocess

import anyio
import uvicorn
from mcp import types
from mcp.client.session import ClientSession
from mcp.client.stdio import StdioServerParameters, stdio_client
from mcp.server.lowlevel import Server
from mcp.server.lowlevel.server import ServerRequestContext


def _load_config_file() -> None:
    """Reached via `open -a` in launchd mode (see xcodemcpfront_launch.sh), which
    does NOT reliably forward a launchd plist's EnvironmentVariables into the
    launched app's process — a LaunchServices quirk, separate from the TCC one
    this tool is already built around. A config file sidesteps that entirely:
    it's read directly off disk, so it works regardless of how this process was
    launched. Real env vars still win if both are set (checked with setdefault,
    same layering as ollama-watch's config convention elsewhere in this repo)."""
    conf = os.path.join(os.environ.get("XCODE_MCP_FRONT_HOME", os.path.expanduser("~/.xcode-mcp-front")), "config")
    if not os.path.isfile(conf):
        return
    with open(conf) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            os.environ.setdefault(key.strip(), value.strip().strip("'\""))


_load_config_file()

UPSTREAM_COMMAND = os.environ.get("XCODE_MCP_FRONT_UPSTREAM_CMD", "xcrun")
UPSTREAM_ARGS = os.environ.get("XCODE_MCP_FRONT_UPSTREAM_ARGS", "mcpbridge").split()
HOST = os.environ.get("XCODE_MCP_FRONT_HOST", "127.0.0.1")
PORT = int(os.environ.get("XCODE_MCP_FRONT_PORT", "8765"))
# Off switch for the click-Allow-automatically behavior, for anyone who'd rather
# affirmatively approve each connection by hand. Default on — matches what's
# already running today.
AUTO_ALLOW = os.environ.get("XCODE_MCP_FRONT_AUTO_ALLOW", "1") == "1"

# Both /Applications/Xcode.app and /Applications/Xcode-beta.app share the exact
# same CFBundleExecutable ("Xcode") AND the same CFBundleIdentifier
# (com.apple.dt.Xcode) - confirmed live, 2026-08-14. Neither a bare process-name
# match nor a bundle-ID match can tell them apart. Only the executable's full
# path differs, so that's what this matches on - anchored and exact, not a
# substring, so it can't accidentally match the beta path either.
XCODE_APP_PATH = os.environ.get("XCODE_MCP_FRONT_XCODE_APP_PATH", "/Applications/Xcode.app")
XCODE_BINARY_PATH = f"{XCODE_APP_PATH.rstrip('/')}/Contents/MacOS/Xcode"
RECONNECT_POLL_SECONDS = float(os.environ.get("XCODE_MCP_FRONT_RECONNECT_POLL_S", "5"))
CONNECT_TIMEOUT_SECONDS = float(os.environ.get("XCODE_MCP_FRONT_CONNECT_TIMEOUT_S", "15"))
# This daemon fronts more than one upstream now (mcpbridge, drews-xcode-mcp).
# mcpbridge needs a live Xcode.app to bridge to at all; drews-xcode-mcp does
# NOT (confirmed live, 2026-08-14: it connects and lists tools with no Xcode
# process running, no approval dialog either — a folder-allowlist auth model
# instead). So the "wait for Xcode" gate before even attempting a connect is
# only correct for SOME upstreams — make it optional rather than bake in the
# mcpbridge-specific assumption.
REQUIRE_XCODE_RUNNING = os.environ.get("XCODE_MCP_FRONT_REQUIRE_XCODE", "1") == "1"
SERVER_NAME = os.environ.get("XCODE_MCP_FRONT_SERVER_NAME", "xcode-mcp-front")

logging.basicConfig(level=logging.INFO, format=f"%(asctime)s {SERVER_NAME} %(message)s")
log = logging.getLogger(SERVER_NAME)

# Serializes every downstream call through the one shared upstream session.
# Set once a connection is live; None means "not connected right now" (a client
# that calls while disconnected gets a clear error instead of a hang or crash).
upstream_lock = anyio.Lock()
upstream_session: ClientSession | None = None

# Flipped True the first time a call proves the current connection is actually
# dead. The connection loop watches for this to know when to stop holding the
# session open and go back to reconnecting.
upstream_known_broken = False


def _not_connected_result() -> types.CallToolResult:
    return types.CallToolResult(
        content=[
            types.TextContent(
                type="text",
                text=(
                    "xcode-mcp-front: not connected to Xcode right now. This daemon "
                    "retries on its own every few seconds (checking Xcode is running "
                    "and clicking its approval prompt if one is showing) — a retry "
                    "shortly should work without any manual action."
                ),
            )
        ],
        is_error=True,
    )


def _pid_is_alive(pid_str: str) -> bool:
    """No history file needed: a dialog's PID is either us, or it's a live PID
    that belongs to someone else's legitimate in-flight request (leave it
    alone), or it's simply not in the process table anymore (nothing is
    waiting on it — always safe to dismiss, regardless of whose it was).
    Generalizes to every stale dialog, not just ones this exact daemon
    happens to remember spawning itself, so it can never permanently
    deadlock behind one it doesn't recognize."""
    try:
        os.kill(int(pid_str), 0)
        return True
    except ProcessLookupError:
        return False
    except (ValueError, PermissionError):
        # ValueError: not a real pid, treat as "can't tell" -> leave it alone.
        # PermissionError: pid exists but isn't ours to signal -> still alive.
        return True


def _xcode_is_running() -> bool:
    try:
        # -f matches the full command line; anchored so it can only match this
        # exact binary path, not a substring of some other process's args.
        return (
            subprocess.run(["pgrep", "-f", f"^{XCODE_BINARY_PATH}$"], capture_output=True, timeout=5).returncode
            == 0
        )
    except Exception:
        # A broken check must never itself take the daemon down — treat "can't
        # tell" as "not running" and just try again next poll.
        return False


async def _run_osascript(script: str) -> bytes:
    proc = await asyncio.create_subprocess_exec(
        "osascript",
        "-e",
        script,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
    )
    out, _ = await asyncio.wait_for(proc.communicate(), timeout=5)
    return out


async def _click_allow_if_present() -> bool:
    """Best-effort, narrowly scoped: only ever touches a button whose title is
    the exact literal string "Allow" or "Don't Allow", only in Xcode's own
    process. This is the one dialog this tool exists to eat, not a general
    click-any-prompt macro.

    Xcode's approval dialogs do NOT stack (confirmed live, 2026-08-14 — only
    one is ever showing; a new connection attempt's own dialog stays hidden
    behind whatever's currently up until that one is dismissed). So a single
    stale, never-answered dialog can permanently block every future connection
    attempt, including this daemon's own, unless something clears it.

    The decision, once a dialog's own PID is read from its text:
      - matches OUR current pid            -> click Allow
      - doesn't match, and that pid is DEAD -> click Don't Allow (nobody's
        waiting on it — always safe, regardless of whose it originally was;
        no history-tracking needed, this can't deadlock behind a dialog it
        doesn't "remember")
      - doesn't match, and that pid is ALIVE -> leave it alone; it's someone
        else's legitimate in-flight request, not ours to approve OR deny
    """
    my_pid = str(os.getpid())
    read_script = """
tell application "System Events" to tell process "Xcode"
  if exists (button "Allow" of window 1) then
    set winText to ""
    try
      set winText to (value of every static text of window 1) as string
    end try
    return winText
  end if
  return ""
end tell
"""
    try:
        out = await _run_osascript(read_script)
    except Exception as e:
        log.debug("checking for an approval dialog failed (harmless, will retry next tick): %s", e)
        return False

    text = out.decode(errors="replace")
    if "PID: " not in text:
        return False  # no dialog showing — the normal case most ticks

    dialog_pid = text.split("PID: ", 1)[1].split()[0].strip()

    if dialog_pid == my_pid:
        action = "Allow"
    elif not _pid_is_alive(dialog_pid):
        action = "Don't Allow"
    else:
        log.debug("a pending approval dialog belongs to a live pid (%s) that isn't us — leaving it alone", dialog_pid)
        return False

    click_script = f"""
tell application "System Events" to tell process "Xcode"
  if exists (button "{action}" of window 1) then
    click (button "{action}" of window 1)
    return "clicked"
  end if
  return "gone"
end tell
"""
    try:
        out2 = await _run_osascript(click_script)
    except Exception as e:
        log.debug("clicking the approval dialog failed (harmless, will retry next tick): %s", e)
        return False

    clicked = b"clicked" in out2
    if clicked and action == "Allow":
        log.info("clicked Allow for our own connection-approval prompt (pid %s)", my_pid)
    elif clicked:
        log.info("dismissed a stale approval dialog for dead pid %s, clearing the queue", dialog_pid)
    return clicked and action == "Allow"


async def on_list_tools(
    ctx: ServerRequestContext, params: types.PaginatedRequestParams | None
) -> types.ListToolsResult:
    global upstream_known_broken
    async with upstream_lock:
        if upstream_session is None:
            return types.ListToolsResult(tools=[])
        try:
            return await upstream_session.list_tools(params=params)
        except Exception as e:
            upstream_known_broken = True
            log.warning("list_tools failed, marking connection broken: %s", e)
            return types.ListToolsResult(tools=[])


async def on_call_tool(ctx: ServerRequestContext, params: types.CallToolRequestParams) -> types.CallToolResult:
    global upstream_known_broken
    async with upstream_lock:
        if upstream_session is None:
            return _not_connected_result()
        log.info("call_tool %s", params.name)
        try:
            result = await upstream_session.call_tool(params.name, params.arguments)
        except Exception as e:
            upstream_known_broken = True
            log.warning("call_tool %s failed, marking connection broken: %s", params.name, e)
            return _not_connected_result()
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


async def connection_manager() -> None:
    """Owns the upstream connection for the daemon's whole life. Loops forever:
    while not connected, check Xcode is running, best-effort click its approval
    prompt if showing, then attempt a fresh connect — the SAME check whether the
    prior break was "Xcode quit" or "connection died some other way", since
    there's no way to tell which from here and the recovery is identical either
    way. Once connected, holds the session open until a call proves it's broken,
    then goes back to reconnecting. Never exits on its own; a genuine crash is
    what the process supervisor (launchd) is for."""
    global upstream_session, upstream_known_broken
    params = StdioServerParameters(command=UPSTREAM_COMMAND, args=UPSTREAM_ARGS)
    while True:
        if REQUIRE_XCODE_RUNNING and not _xcode_is_running():
            log.info("Xcode not running, waiting")
            await anyio.sleep(RECONNECT_POLL_SECONDS)
            continue

        if AUTO_ALLOW:
            await _click_allow_if_present()

        log.info("attempting connect: %s %s", UPSTREAM_COMMAND, UPSTREAM_ARGS)
        try:
            async with stdio_client(params) as (read, write):
                async with ClientSession(read, write) as session:
                    with anyio.fail_after(CONNECT_TIMEOUT_SECONDS):
                        await session.initialize()
                    async with upstream_lock:
                        upstream_session = session
                        upstream_known_broken = False
                    log.info("connected — serving until this breaks")
                    while not upstream_known_broken:
                        await anyio.sleep(RECONNECT_POLL_SECONDS)
                        # The approval prompt has been observed appearing AFTER a
                        # successful initialize() — apparently requested lazily,
                        # possibly on the first real tool call rather than at the
                        # handshake (confirmed live, 2026-08-14: a dialog for this
                        # exact daemon's own pid showed up well into a session
                        # already marked "connected", and nothing was watching for
                        # it). So keep checking even once connected, not just
                        # while reconnecting — safe to run every tick regardless,
                        # since it only ever acts on our own pid or a dead one.
                        if AUTO_ALLOW:
                            await _click_allow_if_present()
        except Exception as e:
            log.warning("connect attempt failed (will retry): %s", e)

        async with upstream_lock:
            upstream_session = None
        log.info("not connected, retrying in %ss", RECONNECT_POLL_SECONDS)
        await anyio.sleep(RECONNECT_POLL_SECONDS)


@contextlib.asynccontextmanager
async def lifespan(app: Server):
    async with anyio.create_task_group() as tg:
        tg.start_soon(connection_manager)
        try:
            yield {}
        finally:
            tg.cancel_scope.cancel()


def build_server() -> Server:
    return Server(
        SERVER_NAME,
        version="0.3.0",
        instructions=(
            "This is a persistent proxy in front of Apple's own Xcode MCP bridge "
            "(`xcrun mcpbridge`) — same tools it exposes, reached over HTTP instead of "
            "each client spawning its own copy (that used to mean a separate Xcode "
            "approval popup per client; this way it's approved once and stays up).\n\n"
            "If a call says 'not connected to Xcode right now', this daemon is already "
            "retrying on its own every few seconds — checking Xcode is running and "
            "clicking its approval prompt if one is showing — so a short retry should "
            "work without any manual action.\n\n"
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
