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

Runs in one of two modes, chosen by which env vars are set (see below):
  - SINGLE-upstream (default, what's been running since 2026-08-14): fronts just
    one upstream (normally mcpbridge). Dumb passthrough — tool names forwarded
    unprefixed, exactly as the upstream advertises them. This is the deployed
    xcode-mcp-front daemon; nothing about its behavior changes in this mode.
  - MULTI-upstream (XCODE_MCP_FRONT_UPSTREAMS set): fronts several upstreams
    behind the SAME endpoint, tool names prefixed per-upstream
    (`<name>__<tool>`, e.g. `xcode__BuildProject`, `drews__run_project_unmonitored`)
    so two upstreams that happen to share a tool name can't collide or shadow
    each other. Built for exactly one reason: Drew's xcode-mcp
    (`drews-xcode-mcp`) has no approval-dialog friction on its own — a client can
    already spawn `uvx drews-xcode-mcp` directly with zero setup, no wrapper
    needed — so it never got its own standalone daemon (built, verified, then
    torn back down, 2026-08-14 — see git history). But "one endpoint with BOTH
    Xcode tools available, prefixed so there's no confusion" is a real,
    different thing worth having alongside the single-upstream daemon, not
    instead of it. Both modes share every line of connection/click/reconnect
    logic below via the Upstream class — no duplicated logic between them.

This is a dumb passthrough, not a real aggregator: it forwards list_tools/call_tool
to the relevant upstream ClientSession(s) and returns whatever comes back. It does
not interpret tool semantics. Calls to a given upstream are serialized through
that upstream's own lock (tolerance for concurrent overlapping calls hasn't been
tested, so this starts correctness-first — tool calls are already human-paced, so
serialization shouldn't be felt in practice); different upstreams' calls are
fully independent of each other.

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
- The approval prompt is requested LAZILY, on the first list_tools call, not at
  the initial connect — the per-upstream reconnect loop polls for it (and
  clicks it) continuously in the connected steady-state too, not just while
  reconnecting.
- Xcode's approval dialogs do NOT stack — only one shows at a time, and a stale
  unanswered one blocks the next (including this daemon's own) from appearing.
  The click logic reads each dialog's own PID: clicks Allow for our own live
  pid, clicks Don't Allow for a dead pid (nobody's waiting on it — a plain
  os.kill(pid,0) liveness check, no PID-history file needed), leaves any other
  live pid's dialog strictly alone.
- Drew's xcode-mcp (drews-xcode-mcp) has NO approval-dialog behavior at all —
  folder-allowlist auth (XCODEMCP_ALLOWED_FOLDERS / --allowed) instead of a
  live per-PID popup. Its Upstream instance just never finds a dialog to click;
  harmless no-op, no special-casing needed.

Env overrides — SINGLE-upstream mode (default):
  XCODE_MCP_FRONT_UPSTREAM_CMD    default "xcrun"
  XCODE_MCP_FRONT_UPSTREAM_ARGS   default "mcpbridge" (space-separated)
  XCODE_MCP_FRONT_REQUIRE_XCODE   default "1" — wait for Xcode.app before connecting.
                                   Set "0" for an upstream (like drews-xcode-mcp)
                                   that doesn't need a live Xcode process at all.
  XCODE_MCP_FRONT_AUTO_ALLOW      default "1" — click-Allow-automatically. Off
                                   switch for anyone who'd rather approve by hand.
  XCODE_MCP_FRONT_SERVER_NAME     default "xcode-mcp-front"

Env overrides — MULTI-upstream mode (mutually exclusive with the single-upstream
UPSTREAM_CMD/ARGS/REQUIRE_XCODE vars above — set THIS instead):
  XCODE_MCP_FRONT_UPSTREAMS       semicolon-separated upstream specs, each
                                   "name:require_xcode:command:arg1,arg2,...".
                                   Example:
                                   "xcode:1:xcrun:mcpbridge;drews:0:uvx:drews-xcode-mcp"
                                   Tool names are prefixed "<name>__" in the
                                   merged tool list and un-prefixed again when
                                   routing a call back to that upstream.

Env overrides — both modes:
  XCODE_MCP_FRONT_HOST             default "127.0.0.1" (do not bind wider — no auth layer)
  XCODE_MCP_FRONT_PORT             default "8765"
  XCODE_MCP_FRONT_XCODE_APP_PATH   default "/Applications/Xcode.app" — the reconnect
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
    """Reached via a wrapped .app under launchd in real deployment, which does
    NOT reliably forward a launchd plist's EnvironmentVariables into the
    launched app's process (a LaunchServices quirk, separate from the TCC one
    this tool is already built around). A config file sidesteps that entirely:
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

HOST = os.environ.get("XCODE_MCP_FRONT_HOST", "127.0.0.1")
PORT = int(os.environ.get("XCODE_MCP_FRONT_PORT", "8765"))
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
# Generous on purpose - a real Xcode build_project call can legitimately run
# for minutes. The point isn't to bound normal work, it's to make sure NO call
# can wedge the daemon forever (found live, 2026-08-14: with no timeout at all,
# one genuinely hung upstream call held the connection lock for 2+ minutes and
# counting, wedging every future call to that upstream, single-upstream or
# combined, until manually restarted). Raise this if a real workload needs
# longer than the default.
#
# Default corrected to 600s (was 120s) by convocation review, 2026-08-14: 120s
# contradicted this comment's own "can legitimately run for minutes" — a real
# clean/first build commonly runs past 2 minutes, so the old default silently
# killed and dropped exactly the workload it claimed to tolerate, then
# reconnected and reported "not connected right now, retry shortly" — which is
# actively misleading once this fires, since the build was killed mid-flight,
# not merely delayed; a retry starts it over, it doesn't resume it.
CALL_TIMEOUT_SECONDS = float(os.environ.get("XCODE_MCP_FRONT_CALL_TIMEOUT_S", "600"))
SERVER_NAME = os.environ.get("XCODE_MCP_FRONT_SERVER_NAME", "xcode-mcp-front")

logging.basicConfig(level=logging.INFO, format=f"%(asctime)s {SERVER_NAME} %(message)s")
log = logging.getLogger(SERVER_NAME)


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
    """Raises on a nonzero exit instead of returning empty bytes. Found by
    convocation review, 2026-08-14: with stderr sent to DEVNULL and no
    returncode check, a TCC grant getting revoked or dying (the documented
    failure mode after any edit to the ad-hoc-signed wrapper .app — new hash,
    dead grant) made osascript exit nonzero with an error, which this
    previously returned as plain b"" — indistinguishable from "no dialog
    showing". The click loop would then silently stop working with nothing in
    the log naming the actual cause. Now surfaces it: caller's except-block
    already logs at warning level, so a dead grant shows up as a real,
    diagnosable log line instead of a silent no-op.

    Also found LIVE the same day, the hard way: a real System Events hang
    (osascript stuck talking to it, unrelated to the return-code fix above —
    System Events itself was wedged) piled up one leaked orphan osascript
    process EVERY poll tick, forever, because `asyncio.wait_for` timing out
    only abandons Python's own wait — it does NOT kill the underlying
    subprocess. Confirmed live: 30+ orphaned osascript processes accumulated
    in under 10 minutes before this was caught, and System Events itself
    became unresponsive to even a basic query as a result. Now explicitly
    kills the process on timeout instead of leaving it to run forever."""
    proc = await asyncio.create_subprocess_exec(
        "osascript",
        "-e",
        script,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        out, err = await asyncio.wait_for(proc.communicate(), timeout=5)
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()  # reap it — don't leave a zombie behind either
        raise RuntimeError("osascript timed out after 5s (System Events may be unresponsive)")
    if proc.returncode != 0:
        raise RuntimeError(f"osascript exited {proc.returncode}: {err.decode(errors='replace').strip()}")
    return out


def _pid_is_sibling_front(pid: str) -> bool:
    """True when this PID is ANOTHER instance of this same daemon family.

    TWO FRONT DAEMONS DEADLOCKED EACH OTHER AND THIS IS THE FIX. Xcode's approval dialogs do
    not stack — one showing hides the next — and the click policy above deliberately leaves a
    live, unfamiliar PID's dialog alone, which is right when the stranger is somebody else's
    agent. With both `xcode-mcp-front` (8765) and `xcode-combined-front` (8767) running, each
    one saw the other's dialog, read a live PID that was not its own, and politely declined.
    Its own dialog sat queued behind that one and it never saw it either. Both then looped
    connect → "Connection closed" → retry forever: 21,422 cycles between 2026-08-14 and
    2026-08-30, a dialog pile the user had to clear by hand, and a suite that failed every
    mcpbridge assertion while both daemons reported themselves healthy.

    A sibling is not a stranger. Approving a dialog raised by another instance of this same
    program, running from this same directory as this same user, is approving our own family
    — and it is the only way either of them ever gets through. Identified by matching the
    process's command line against this file's own path, so an unrelated Python that happens
    to be running is still treated as a stranger.
    """
    try:
        out = subprocess.run(["ps", "-p", str(pid), "-o", "command="],
                             capture_output=True, timeout=5)
    except Exception:
        return False
    if out.returncode != 0:
        return False
    cmd = out.stdout.decode("utf-8", "replace")
    return os.path.basename(__file__) in cmd and os.path.dirname(os.path.abspath(__file__)) in cmd


async def _click_allow_if_present() -> bool:
    """Best-effort, narrowly scoped: only ever touches a button whose title is
    the exact literal string "Allow" or "Don't Allow", only in Xcode's own
    process. This is the one dialog this tool exists to eat, not a general
    click-any-prompt macro. Harmless no-op for an upstream (like
    drews-xcode-mcp) that never triggers this dialog at all — it just never
    finds anything to click.

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
    # Iterate every window, not just window 1 — found by convocation review,
    # 2026-08-14: the approval dialog isn't guaranteed to be window 1 (e.g. a
    # project window frontmost, or the dialog opening as window 2). Window 1
    # only would silently never find the dialog and leave it unclicked
    # forever. check-allow-window.sh already iterated all windows correctly;
    # this production path didn't match it.
    read_script = """
tell application "System Events" to tell process "Xcode"
  repeat with w in windows
    if exists (button "Allow" of w) then
      set winText to ""
      try
        set winText to (value of every static text of w) as string
      end try
      return winText
    end if
  end repeat
  return ""
end tell
"""
    try:
        out = await _run_osascript(read_script)
    except Exception as e:
        log.warning("checking for an approval dialog failed (will retry, but if this repeats, check "
                     "whether the wrapper .app's Accessibility/Automation grant is still valid): %s", e)
        return False

    text = out.decode(errors="replace")
    if "PID: " not in text:
        return False  # no dialog showing — the normal case most ticks

    dialog_pid = text.split("PID: ", 1)[1].split()[0].strip()

    if dialog_pid == my_pid or _pid_is_sibling_front(dialog_pid):
        action = "Allow"
    elif not _pid_is_alive(dialog_pid):
        # Real button title uses U+2019 (’), not a straight apostrophe — found
        # live, 2026-08-14, chasing a stray "Allow 'Codex' to access Xcode?"
        # dialog left over from a convocation run. A straight-quote "Don't
        # Allow" never matches Xcode's actual button, so this branch has
        # silently never clicked anything: `exists (button "Don't Allow" ...)`
        # is always false against the real AX tree, `_run_osascript` returns
        # "not found" cleanly (no exception), and the caller just logs
        # clicked=False with nothing louder. A dead-PID's stale dialog would
        # sit there forever, blocking every future connection attempt behind
        # it — exactly what this branch exists to prevent.
        action = "Don’t Allow"
    else:
        log.debug("a pending approval dialog belongs to a live pid (%s) that is neither us nor a "
                  "sibling front daemon — leaving it alone", dialog_pid)
        return False

    click_script = f"""
tell application "System Events" to tell process "Xcode"
  repeat with w in windows
    if exists (button "{action}" of w) then
      click (button "{action}" of w)
      return "clicked"
    end if
  end repeat
  return "gone"
end tell
"""
    try:
        out2 = await _run_osascript(click_script)
    except Exception as e:
        log.warning("clicking the approval dialog failed (will retry, but if this repeats, check "
                     "whether the wrapper .app's Accessibility/Automation grant is still valid): %s", e)
        return False

    clicked = b"clicked" in out2
    if clicked and action == "Allow":
        log.info("clicked Allow for our own connection-approval prompt (pid %s)", my_pid)
    elif clicked:
        log.info("dismissed a stale approval dialog for dead pid %s, clearing the queue", dialog_pid)
    return clicked and action == "Allow"


class Upstream:
    """One upstream MCP server this daemon fronts, and everything needed to
    keep a persistent connection to it alive. In single-upstream mode there's
    exactly one of these and its tools are forwarded unprefixed (unchanged
    behavior from before multi-upstream support existed). In multi-upstream
    mode there are several, and the aggregator (see build_server) prefixes
    each one's tools with `self.name + "__"` so two upstreams that happen to
    share a tool name can't collide."""

    def __init__(self, name: str, command: str, args: list[str], require_xcode_running: bool):
        self.name = name
        self.command = command
        self.args = args
        self.require_xcode_running = require_xcode_running
        self.lock = anyio.Lock()
        self.session: ClientSession | None = None
        self.known_broken = False

    async def list_tools(self, params: types.PaginatedRequestParams | None) -> types.ListToolsResult:
        async with self.lock:
            if self.session is None:
                return types.ListToolsResult(tools=[])
            try:
                with anyio.fail_after(CALL_TIMEOUT_SECONDS):
                    return await self.session.list_tools(params=params)
            except Exception as e:
                # Found live, 2026-08-14: this call had NO timeout at all before
                # this fix — a genuinely hung upstream call (confirmed: a real
                # tool call sat for 2+ minutes with nothing in the log, no
                # timeout, no recovery) held self.lock forever, permanently
                # wedging this upstream for every future call, single-upstream
                # or combined. A timeout here means a hang gets treated the
                # same as any other failure: marked broken, reconnected fresh.
                self.known_broken = True
                log.warning("[%s] list_tools failed, marking connection broken: %s", self.name, e)
                return types.ListToolsResult(tools=[])

    async def call_tool(self, tool_name: str, arguments: dict) -> types.CallToolResult | None:
        """Returns None if not connected — caller decides how to report that,
        since the aggregator needs a slightly different message than the
        single-upstream case (naming which upstream is down)."""
        async with self.lock:
            if self.session is None:
                return None
            log.info("[%s] call_tool %s", self.name, tool_name)
            try:
                with anyio.fail_after(CALL_TIMEOUT_SECONDS):
                    result = await self.session.call_tool(tool_name, arguments)
            except Exception as e:
                # See list_tools' comment — same missing-timeout bug, same fix.
                self.known_broken = True
                log.warning("[%s] call_tool %s failed, marking connection broken: %s", self.name, tool_name, e)
                return None
            if not isinstance(result, types.CallToolResult):
                # upstream returned something this dumb proxy doesn't forward
                # (e.g. InputRequiredResult) — surface as an error, don't crash.
                return types.CallToolResult(
                    content=[
                        types.TextContent(
                            type="text",
                            text=f"xcode-mcp-front: [{self.name}] unsupported upstream result type "
                            f"{type(result).__name__}",
                        )
                    ],
                    is_error=True,
                )
            return result

    async def connection_manager(self) -> None:
        """Owns this upstream's connection for the daemon's whole life. Loops
        forever: while not connected, check Xcode is running (if this upstream
        needs it), best-effort click its approval prompt if showing, attempt a
        fresh connect. Once connected, holds the session open — polling (and
        clicking) on the same timer — until a call proves it's broken, then
        goes back to reconnecting. In-process, never exits on its own; a
        genuine crash is what the process supervisor (launchd) is for."""
        params = StdioServerParameters(command=self.command, args=self.args)
        while True:
            if self.require_xcode_running and not _xcode_is_running():
                log.info("[%s] Xcode not running, waiting", self.name)
                await anyio.sleep(RECONNECT_POLL_SECONDS)
                continue

            if AUTO_ALLOW:
                await _click_allow_if_present()

            log.info("[%s] attempting connect: %s %s", self.name, self.command, self.args)
            try:
                async with stdio_client(params) as (read, write):
                    async with ClientSession(read, write) as session:
                        with anyio.fail_after(CONNECT_TIMEOUT_SECONDS):
                            await session.initialize()
                        async with self.lock:
                            self.session = session
                            self.known_broken = False
                        log.info("[%s] connected — serving until this breaks", self.name)
                        while not self.known_broken:
                            await anyio.sleep(RECONNECT_POLL_SECONDS)
                            # Health-check: a silent list_tools call catches a
                            # dead upstream before any client discovers it.
                            # Without this, a killed Xcode leaves the daemon
                            # sitting "connected" until a real client call
                            # fails — minutes of silently serving zero tools.
                            try:
                                with anyio.fail_after(CONNECT_TIMEOUT_SECONDS):
                                    await session.list_tools()
                            except Exception as e:
                                log.warning("[%s] heartbeat list_tools failed, marking broken: %s", self.name, e)
                                async with self.lock:
                                    self.known_broken = True
                                break
                            # The approval prompt has been observed appearing
                            # AFTER a successful initialize() — requested
                            # lazily, apparently on the first real list_tools
                            # call rather than at the handshake. So keep
                            # checking even once connected, not just while
                            # reconnecting — safe every tick regardless, since
                            # it only ever acts on our own pid or a dead one.
                            if AUTO_ALLOW:
                                await _click_allow_if_present()
            except Exception as e:
                log.warning("[%s] connect attempt failed (will retry): %s", self.name, e)

            async with self.lock:
                self.session = None
            log.info("[%s] not connected, retrying in %ss", self.name, RECONNECT_POLL_SECONDS)
            await anyio.sleep(RECONNECT_POLL_SECONDS)


def _parse_multi_upstreams(spec: str) -> list[Upstream]:
    """"name:require_xcode:command:arg1,arg2,...;name2:..." -> [Upstream, ...]"""
    upstreams = []
    for chunk in spec.split(";"):
        chunk = chunk.strip()
        if not chunk:
            continue
        name, require_xcode, command, argstr = chunk.split(":", 3)
        args = [a for a in argstr.split(",") if a]
        upstreams.append(Upstream(name.strip(), command.strip(), args, require_xcode.strip() == "1"))
    if not upstreams:
        raise ValueError(f"XCODE_MCP_FRONT_UPSTREAMS set but parsed to zero upstreams: {spec!r}")
    return upstreams


def _build_upstreams() -> list[Upstream]:
    multi_spec = os.environ.get("XCODE_MCP_FRONT_UPSTREAMS")
    if multi_spec:
        return _parse_multi_upstreams(multi_spec)
    return [
        Upstream(
            name="default",
            command=os.environ.get("XCODE_MCP_FRONT_UPSTREAM_CMD", "xcrun"),
            args=os.environ.get("XCODE_MCP_FRONT_UPSTREAM_ARGS", "mcpbridge").split(),
            require_xcode_running=os.environ.get("XCODE_MCP_FRONT_REQUIRE_XCODE", "1") == "1",
        )
    ]


def _not_connected_result(detail: str) -> types.CallToolResult:
    return types.CallToolResult(
        content=[
            types.TextContent(
                type="text",
                text=(
                    f"xcode-mcp-front: {detail} This daemon retries on its own every few "
                    "seconds (checking Xcode is running and clicking its approval prompt if "
                    "one is showing) — a retry shortly should work without any manual action."
                ),
            )
        ],
        is_error=True,
    )


def build_server(upstreams: list[Upstream]) -> Server:
    single = len(upstreams) == 1
    prefix_of = {u: (f"{u.name}__" if not single else "") for u in upstreams}
    upstream_by_prefix = {prefix_of[u]: u for u in upstreams}

    async def on_list_tools(
        ctx: ServerRequestContext, params: types.PaginatedRequestParams | None
    ) -> types.ListToolsResult:
        all_tools: list[types.Tool] = []
        results_by_upstream: dict[str, list[types.Tool]] = {}
        for u in upstreams:
            result = await u.list_tools(params)
            prefix = prefix_of[u]
            upstream_tools = []
            for t in result.tools:
                if prefix:
                    t = t.model_copy(update={"name": f"{prefix}{t.name}"})
                upstream_tools.append(t)
            results_by_upstream[u.name] = upstream_tools
            all_tools.extend(upstream_tools)
        # In multi-upstream mode, ALL upstreams must be connected.  Serving a
        # partial tool list silently hides the missing upstream from the client
        # — it gets half the tools and has no idea.  Return zero tools and a
        # loud message instead so the client retries once the daemon reconnects
        # the dead upstream (which it does on its own, every few seconds).
        if not single:
            missing = [u.name for u in upstreams if not results_by_upstream.get(u.name)]
            if missing:
                log.warning("list_tools: refusing to serve partial tool list — missing upstreams: %s", missing)
                return types.ListToolsResult(tools=[])
        return types.ListToolsResult(tools=all_tools)

    async def on_call_tool(ctx: ServerRequestContext, params: types.CallToolRequestParams) -> types.CallToolResult:
        name = params.name
        target = None
        tool_name = name
        for prefix, u in upstream_by_prefix.items():
            if prefix and name.startswith(prefix):
                target = u
                tool_name = name[len(prefix) :]
                break
        if target is None:
            # single-upstream mode (no prefixes at all), or a multi-upstream
            # call that somehow arrived unprefixed — route to the sole
            # upstream if there's only one, otherwise this is a real error.
            if single:
                target = upstreams[0]
            else:
                return types.CallToolResult(
                    content=[
                        types.TextContent(
                            type="text",
                            text=f"xcode-mcp-front: tool name '{name}' doesn't match any known upstream prefix "
                            f"({', '.join(p for p in upstream_by_prefix if p)})",
                        )
                    ],
                    is_error=True,
                )

        result = await target.call_tool(tool_name, params.arguments)
        if result is None:
            return _not_connected_result(f"[{target.name}] not connected right now.")
        return result

    names = ", ".join(u.name for u in upstreams)
    if single:
        instructions = (
            "This is a persistent proxy in front of Apple's own Xcode MCP bridge "
            "(`xcrun mcpbridge`) — same tools it exposes, reached over HTTP instead of "
            "each client spawning its own copy (that used to mean a separate Xcode "
            "approval popup per client; this way it's approved once and stays up).\n\n"
            "If a call says 'not connected right now', this daemon is already retrying "
            "on its own every few seconds — checking Xcode is running and clicking its "
            "approval prompt if one is showing — so a short retry should work without "
            "any manual action.\n\n"
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
        )
    else:
        instructions = (
            f"This is a persistent proxy fronting MULTIPLE Xcode-adjacent MCP servers "
            f"behind one endpoint: {names}. Every tool is prefixed with its upstream's "
            f"name (e.g. `{upstreams[0].name}__SomeTool`) so two upstreams that happen to "
            "expose a same-named tool can't collide or shadow each other — always use "
            "the prefixed name shown in the tool list, never the bare upstream name.\n\n"
            "If a call says 'not connected right now', that specific upstream is "
            "reconnecting on its own — the others are unaffected, since each upstream "
            "has its own independent connection. A short retry should work."
        )

    return Server(
        SERVER_NAME,
        version="0.4.0",
        instructions=instructions,
        on_list_tools=on_list_tools,
        on_call_tool=on_call_tool,
        lifespan=lambda app: _lifespan(app, upstreams),
    )


@contextlib.asynccontextmanager
async def _lifespan(app: Server, upstreams: list[Upstream]):
    async with anyio.create_task_group() as tg:
        for u in upstreams:
            tg.start_soon(u.connection_manager)
        try:
            yield {}
        finally:
            tg.cancel_scope.cancel()


def main() -> None:
    upstreams = _build_upstreams()
    server = build_server(upstreams)
    app = server.streamable_http_app(host=HOST)
    log.info("listening on http://%s:%s/mcp (upstreams: %s)", HOST, PORT, ", ".join(u.name for u in upstreams))
    uvicorn.run(app, host=HOST, port=PORT, log_level="info")


if __name__ == "__main__":
    main()
