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
not interpret tool semantics. tools/call requests to a given upstream are
serialized through that upstream's own lock; tools/list requests — client drains
and the heartbeat alike — run WITHOUT the lock on a session snapshot, because the
MCP session multiplexes concurrent requests by id and a list must never wait
behind a long-running build (measured by the phase-1 panel: a client connecting
during one upstream's slow call got no tool list at all until it finished).
Different upstreams are fully independent of each other.

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
  XCODE_MCP_FRONT_MCP_INFO        path to a _mcp_info.json in the Claude Code shape
                                   ({"mcpServers": {"<name>": {"command", "args"}}}),
                                   plus per-server "prefix" (default "<name>__") and
                                   "quirks" (["require_xcode"] for an upstream that
                                   needs a live Xcode). See mcp_config.py, which
                                   validates it and REJECTS fields the daemon does
                                   not pass through (env, cwd, url, ...) by name.
                                   Tool names are prefixed in the merged tool list
                                   and un-prefixed again when routing a call back.
  XCODE_MCP_FRONT_UPSTREAMS       REPLACED by the file above; setting it is a
                                   startup error naming the replacement. The old
                                   colon/comma format corrupted a command path
                                   containing ':' and an argument containing ','.

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
import time

import anyio
import uvicorn

import mcp_config
from mcp import types
from mcp.client.session import ClientSession
from mcp.client.stdio import StdioServerParameters, get_default_environment, stdio_client
from mcp.shared.exceptions import MCPError
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


# NOTE: no longer consulted by the click decision. It used to gate the "Don't Allow" branch
# on the dialog's PID being dead, and that gate is what let a LIVE stranger's dialog block
# the daemon forever. Kept because it is a correct, cheap liveness check and reads clearly
# at a call site; delete it if nothing else picks it up.
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


# THE CLICKER IS LOAD-BEARING AND MUST NOT BE "DESIGNED AWAY". Xcode's approval is keyed to
# the CONNECTING PID, and a daemon restart always mints a new one, so no grant survives a
# bounce — not a signed app bundle, not the "don't ask again for this agent binary" checkbox,
# which only lasts until Xcode itself restarts. An unattended daemon therefore has to answer
# its own prompt or it can never connect after any restart. Jonathan, 2026-08-30, correcting
# a suggestion to remove it: "the daemons HAVE to depend on a clicker."
#
# That is why a defect in this function is not cosmetic. It is the only path to a working
# connection, so a branch that silently declines to click takes the whole daemon down while
# every log line still says "connected".


# How long another process's approval dialog is left alone before we clear it. Only once we
# have been blocked for this long is it fair to assume nobody is coming to answer it.
# HOW LONG A FOREIGN DIALOG MAY BLOCK US BEFORE WE CLEAR IT. This MUST be comfortably less
# than CONNECT_TIMEOUT_SECONDS or two daemons deadlock by arithmetic rather than by bad luck.
#
# It was 45 against a 15-second connect timeout. Xcode's approval dialogs do not stack, so when
# both front daemons are up, each one's clicker finds the other's dialog, correctly classifies it
# as foreign-and-alive, and waits out a grace period three times longer than the connection
# attempt it is holding up. Its own prompt therefore never surfaces, its list_tools times out,
# it tears the child down — which withdraws its request — and both sides repeat forever. That is
# the "do two bridges interfere" question Jonathan asked: they do, and this constant is why.
#
# Clearing a live foreign dialog is not destructive. That process re-prompts on its next attempt,
# which for these daemons is RECONNECT_POLL_SECONDS away, so two of them alternate and both get
# through instead of neither.
FOREIGN_DIALOG_GRACE_SECONDS = float(os.environ.get("XCODE_MCP_FRONT_FOREIGN_GRACE", "6"))

# The relationship above is load-bearing, so it is checked rather than trusted to a comment. A
# grace period at or beyond the connect timeout is a silent, permanent deadlock whenever a second
# client exists, and it presents as "mcpbridge refuses to serve tools" — which is exactly how it
# presented, for a night.
if FOREIGN_DIALOG_GRACE_SECONDS >= CONNECT_TIMEOUT_SECONDS:
    raise SystemExit(
        "xcode-mcp-front: XCODE_MCP_FRONT_FOREIGN_GRACE (%.1fs) must be less than "
        "XCODE_MCP_FRONT_CONNECT_TIMEOUT_S (%.1fs). A foreign approval dialog that outlives the "
        "connection attempt it is blocking can never be cleared in time, so two daemons deadlock "
        "and every symptom looks like Xcode refusing to serve tools."
        % (FOREIGN_DIALOG_GRACE_SECONDS, CONNECT_TIMEOUT_SECONDS))

# How long an upstream may make NO progress before we let launchd restart us. See
# stall_watchdog(). Generous on purpose: a false positive restarts a healthy daemon.
STALL_EXIT_SECONDS = float(os.environ.get("XCODE_MCP_FRONT_STALL_EXIT", "180"))

# Structural ceiling on one tools/list drain, far above any real server's page count.
# See Upstream.list_tools for why a wall-clock bound alone is not enough.
LIST_MAX_PAGES = int(os.environ.get("XCODE_MCP_FRONT_LIST_MAX_PAGES", "200"))

# How often to look for the approval dialog while a call is blocked waiting for it. Short,
# because the window is the length of one blocked list_tools and a missed dialog costs the
# whole connection attempt.
ALLOW_CLICK_POLL_SECONDS = float(os.environ.get("XCODE_MCP_FRONT_CLICK_POLL", "1.5"))

# Set the first time we see a foreign dialog while we are not connected; cleared whenever we
# see no dialog or our own. Module-level rather than per-upstream because Xcode shows one
# dialog at a time for the whole application, so this is genuinely global state.
_foreign_dialog_first_seen: dict = {}


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

    if dialog_pid == my_pid:
        _foreign_dialog_first_seen.pop("pid", None)
        action = "Allow"
    else:
        # A GRACE PERIOD, BECAUSE CLEARING UNCONDITIONALLY MONOPOLISES XCODE. The previous
        # version denied every foreign PID on sight. That unblocks us and starves everyone
        # else: a legitimate agent's dialog gets Don't Allow, it retries, and it lands in the
        # same denial loop forever, so this daemon owns Xcode and nothing else can use it.
        # GhOST-OpenClaw caught it in peer review of the commit that introduced it.
        #
        # The bounded version keeps both properties. Somebody else's prompt is left alone
        # while there is any chance they are about to answer it — which is the normal case,
        # since a live agent's own approval usually resolves in seconds. Only once the SAME
        # foreign dialog has been sitting there long enough to have stopped being anyone's
        # in-flight request do we clear it so ours can surface. Nothing is destroyed either
        # way: a denied agent re-prompts on its next attempt.
        first = _foreign_dialog_first_seen.get("pid")
        now = time.monotonic()
        if first is None or first[0] != dialog_pid:
            _foreign_dialog_first_seen["pid"] = (dialog_pid, now)
            log.debug("a foreign approval dialog (pid %s) is in the way; leaving it for %.0fs "
                      "in case its own agent answers it", dialog_pid, FOREIGN_DIALOG_GRACE_SECONDS)
            return False
        if now - first[1] < FOREIGN_DIALOG_GRACE_SECONDS:
            return False
        log.info("foreign approval dialog for pid %s has blocked us for %.0fs — clearing it so "
                 "our own prompt can surface; that process re-prompts on its next attempt",
                 dialog_pid, now - first[1])
        # ANYTHING ELSE IN FRONT OF OURS GETS CLEARED, live or dead. This used to leave a
        # LIVE unfamiliar PID's dialog strictly alone, out of politeness to another agent's
        # in-flight request. That politeness is unaffordable here: Xcode's dialogs do not
        # stack, so a single stranger's unanswered prompt sits in front of ours forever and
        # the daemon can never connect again — which is exactly what a leftover
        # "Allow 'Codex' to access Xcode?" from a convocation run did on 2026-08-30, and
        # what the two front daemons did to each other for the sixteen days before that.
        #
        # Denying is not destructive and that is what makes this safe. A denied agent is
        # told no for one connection attempt and re-prompts on its next one, by which time
        # ours is out of the way. Jonathan, 2026-08-30: "I don't see why this needs
        # exclusive access. Just run it saying with PID you care about or whatever?"
        #
        # The sibling branch above still matters and is not redundant: two front daemons
        # denying each other would ping-pong, each clearing the other's prompt on every
        # retry. Family gets Allow, everyone else gets out of the way.
        action = "Don’t Allow"
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
        log.info("cleared an approval dialog for pid %s (not ours, not a sibling) so ours can "
                 "surface — it re-prompts on its next attempt", dialog_pid)
    return clicked and action == "Allow"


class Upstream:
    """One upstream MCP server this daemon fronts, and everything needed to
    keep a persistent connection to it alive. In single-upstream mode there's
    exactly one of these and its tools are forwarded unprefixed (unchanged
    behavior from before multi-upstream support existed). In multi-upstream
    mode there are several, and the aggregator (see build_server) prefixes
    each one's tools with `self.name + "__"` so two upstreams that happen to
    share a tool name can't collide."""

    def __init__(self, name: str, command: str, args: list[str], require_xcode_running: bool,
                 prefix: str = "", env: dict | None = None):
        self.name = name
        # Exposed-name prefix, VERBATIM from the spec. The daemon used to force "" for a
        # sole upstream regardless of what the config declared, so the validator printed
        # prefix=solo__ while the daemon served bare names — and adding a second server
        # silently renamed every tool the first one offered (round-one colloquium defect
        # 2; the phase-1 panel measured it still live). The env-var single mode passes ""
        # explicitly, which keeps the deployed passthrough unprefixed.
        self.prefix = prefix
        self.env = dict(env) if env else None
        # Watchdog input: bumped on every connect attempt and every successful heartbeat.
        # Initialised here so the watchdog never reads a missing attribute on a slow start.
        self.last_progress = time.monotonic()
        self.command = command
        self.args = args
        self.require_xcode_running = require_xcode_running
        self.lock = anyio.Lock()
        self.session: ClientSession | None = None
        self.known_broken = False

    async def _mark_broken(self, why: str) -> None:
        """Set known_broken AND drop the public session reference immediately. The codex
        leg of the phase-1 panel caught the gap: known_broken was set but the session
        stayed visible until stdio teardown completed, and a wedged teardown (documented
        below in stall_watchdog) let calls keep entering a session everyone knew was
        dead."""
        async with self.lock:
            self.known_broken = True
            self.session = None
        log.warning("[%s] marking connection broken: %s", self.name, why)

    async def list_tools(self, params: types.PaginatedRequestParams | None) -> types.ListToolsResult | None:
        """Returns None when this upstream is DISCONNECTED or the call failed — which is a
        different fact from a connected upstream answering with zero tools, and the two
        must never be conflated (increment 1.4: conflating them is how one missing
        upstream used to blank the entire aggregate surface).

        CONCURRENCY, stated plainly (the phase-1 panel caught the old file claiming full
        serialization while the heartbeat bypassed the lock): tools/call is serialized
        through self.lock; tools/list runs WITHOUT the lock on a session snapshot. The
        MCP session multiplexes concurrent requests by id, and the heartbeat has listed
        concurrently with real calls in production since 2026-08-14. Holding the lock
        here meant a client connecting during a 10-minute build got no tool list at all
        until the build ended — measured live by the panel's claude leg."""
        async with self.lock:
            session = None if self.known_broken else self.session
        if session is None:
            return None
        try:
            # DRAIN EVERY PAGE (increment 1.5). Cursors are opaque, per-server tokens,
            # so the downstream client's cursor cannot be forwarded here — this daemon
            # aggregates several cursor spaces into one surface and therefore serves a
            # complete snapshot instead. Ignoring nextCursor used to silently truncate
            # any upstream that paginates.
            #
            # The drain is bounded STRUCTURALLY, not just by wall clock (panel, all
            # three brands): a repeated cursor is a definite upstream bug, and the page
            # ceiling catches the fresh-cursor-forever variant — the claude leg measured
            # 48,075 pages accumulated in ten seconds from a cycling stub. Listing is
            # discovery, so it gets the short connect timeout, not the 600-second budget
            # that exists for real builds.
            tools: list[types.Tool] = []
            cursor: str | None = None
            seen_cursors: set[str] = set()
            pages = 0
            with anyio.fail_after(CONNECT_TIMEOUT_SECONDS):
                while True:
                    page = await session.list_tools(
                        params=types.PaginatedRequestParams(cursor=cursor) if cursor else None)
                    tools.extend(page.tools)
                    pages += 1
                    cursor = page.next_cursor
                    if not cursor:
                        return types.ListToolsResult(tools=tools)
                    if cursor in seen_cursors:
                        raise RuntimeError(
                            f"cursor {cursor!r} repeated after {pages} pages — the upstream's "
                            f"pagination cycles and can never finish")
                    if pages >= LIST_MAX_PAGES:
                        raise RuntimeError(
                            f"tools/list still paginating after {LIST_MAX_PAGES} pages — "
                            f"refusing to follow further")
                    seen_cursors.add(cursor)
        except Exception as e:
            # A failed or unbounded listing is treated like any other break: marked
            # broken (which also clears the session reference) and reconnected fresh.
            await self._mark_broken(f"list_tools failed: {e}")
            return None

    async def call_tool(self, tool_name: str, arguments: dict) -> types.CallToolResult | None:
        """Returns None if not connected — caller decides how to report that,
        since the aggregator needs a slightly different message than the
        single-upstream case (naming which upstream is down)."""
        async with self.lock:
            if self.session is None or self.known_broken:
                return None
            log.info("[%s] call_tool %s", self.name, tool_name)
            try:
                with anyio.fail_after(CALL_TIMEOUT_SECONDS):
                    result = await self.session.call_tool(tool_name, arguments)
            except MCPError as e:
                # AN APPLICATION-LEVEL JSON-RPC ERROR IS THE CALLER'S ERROR, NOT A DEAD
                # TRANSPORT. The codex leg of the phase-1 panel caught this: the upstream
                # answering -32602 for an unknown tool proves the connection is HEALTHY,
                # and the old blanket except tore the session down and told the client
                # "not connected right now, retry" — for a call that would fail
                # identically on every retry.
                log.info("[%s] call_tool %s: upstream returned an error (connection kept): %s",
                         self.name, tool_name, e.message)
                return types.CallToolResult(
                    content=[types.TextContent(
                        type="text",
                        text=f"[{self.name}] upstream error for {tool_name!r}: {e.message}")],
                    is_error=True,
                )
            except Exception as e:
                # See list_tools' comment — same missing-timeout bug, same fix.
                self.known_broken = True
                self.session = None
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

    async def stall_watchdog(self) -> None:
        """Exit the process if this upstream stops making progress entirely.

        THE RECONNECT LOOP CAN GET STUCK AND GO PERMANENTLY SILENT. Observed live
        2026-08-30: xcode-mcp-front logged "heartbeat list_tools failed, marking broken"
        at 18:50:55 and then never logged again — no retry, no error, nothing — while its
        HTTP endpoint kept answering and serving zero tools. The cause is the teardown, not
        the loop: leaving `async with stdio_client(...)` waits for the child to exit, and a
        wedged mcpbridge never does, so the task blocks inside __aexit__ where no `except`
        and no retry can reach it. Every health signal this daemon has says "fine" in that
        state, which is the worst possible failure shape.

        There is no clean way to bound a hung context-manager exit from inside it. There IS
        a supervisor: launchd, with KeepAlive true. So when an upstream has made no progress
        for STALL_EXIT_SECONDS — no connect attempt, no successful heartbeat — say so loudly
        and exit non-zero. That is the file's own stated philosophy: "a genuine crash is what
        the process supervisor is for." A restart costs one new Xcode approval prompt, which
        the clicker answers.

        Deliberately generous, because a false positive here restarts a working daemon: the
        default is many multiples of the heartbeat interval, and any progress at all resets it.
        """
        while True:
            await anyio.sleep(RECONNECT_POLL_SECONDS)
            if self.require_xcode_running and not _xcode_is_running():
                # Waiting for Xcode is not a stall; that path logs and sleeps on purpose.
                self.last_progress = time.monotonic()
                continue
            idle = time.monotonic() - getattr(self, "last_progress", time.monotonic())
            if idle > STALL_EXIT_SECONDS:
                log.error("[%s] no connect attempt and no successful heartbeat for %.0fs — the "
                          "reconnect loop made no progress. Two known causes: stdio_client "
                          "teardown waiting on a child that will not exit, or the loop waiting "
                          "on this upstream's own lock behind a wedged call. Exiting so launchd "
                          "restarts us; staying up would serve zero tools while every log line "
                          "claimed we were connected.", self.name, idle)
                os._exit(75)


    async def connection_manager(self) -> None:
        """Owns this upstream's connection for the daemon's whole life. Loops
        forever: while not connected, check Xcode is running (if this upstream
        needs it), best-effort click its approval prompt if showing, attempt a
        fresh connect. Once connected, holds the session open — polling (and
        clicking) on the same timer — until a call proves it's broken, then
        goes back to reconnecting. In-process, never exits on its own; a
        genuine crash is what the process supervisor (launchd) is for."""
        # The config's env map is ADDITIVE over the SDK's safe default set (a six-variable
        # allowlist) — matching Claude Code's semantics for the same file shape. Passing
        # spec env alone would strip PATH and HOME from the child.
        child_env = {**get_default_environment(), **self.env} if self.env else None
        params = StdioServerParameters(command=self.command, args=self.args, env=child_env)
        while True:
            if self.require_xcode_running and not _xcode_is_running():
                log.info("[%s] Xcode not running, waiting", self.name)
                await anyio.sleep(RECONNECT_POLL_SECONDS)
                continue

            if AUTO_ALLOW:
                await _click_allow_if_present()

            log.info("[%s] attempting connect: %s %s", self.name, self.command, self.args)
            self.last_progress = time.monotonic()
            try:
                async with stdio_client(params) as (read, write):
                    async with ClientSession(read, write) as session:
                        with anyio.fail_after(CONNECT_TIMEOUT_SECONDS):
                            await session.initialize()
                        async with self.lock:
                            self.session = session
                            self.known_broken = False
                        log.info("[%s] connected — serving until this breaks", self.name)
                        self.last_progress = time.monotonic()
                        while not self.known_broken:
                            await anyio.sleep(RECONNECT_POLL_SECONDS)
                            # Health-check: a silent list_tools call catches a
                            # dead upstream before any client discovers it.
                            # Without this, a killed Xcode leaves the daemon
                            # sitting "connected" until a real client call
                            # fails — minutes of silently serving zero tools.
                            # CLICK WHILE THE CALL IS BLOCKED, NOT AFTER IT RETURNS. This is
                            # the deadlock that kept the suite at 6/10 and looked for a whole
                            # night like Apple's bridge refusing to serve tools.
                            #
                            # Xcode raises "Allow <x> to access Xcode?" lazily, on the first real
                            # list_tools rather than at the handshake — the comment below has
                            # said so since 2026-08-14. So list_tools BLOCKS until that dialog is
                            # answered. The clicker that answers it was placed after the await.
                            # It therefore ran only once list_tools had already returned, and on
                            # the timeout path the except branch marks the upstream broken and
                            # breaks out before reaching it at all. The one thing that could
                            # unblock the call was scheduled to run only after the call unblocked.
                            #
                            # Worse, the teardown withdraws the prompt: the dialog is bound to the
                            # live connecting process, so killing the child on timeout retracts
                            # the question. With a 5s reconnect loop the daemon spent all night
                            # asking Xcode for permission and cancelling the request before anyone
                            # could say yes — which is why no dialog was ever found on screen, and
                            # why running a single bridge by hand and simply leaving it alive
                            # produced the prompt immediately and 21 tools once it was answered.
                            #
                            # Two daemons made it twice as fast, which is the "do two bridges
                            # interfere" question: they do, but only by doubling the churn. One
                            # daemon alone reproduces it.
                            try:
                                with anyio.fail_after(CONNECT_TIMEOUT_SECONDS):
                                    async with anyio.create_task_group() as _tg:
                                        async def _click_while_blocked():
                                            # Poll rather than click once: the dialog appears a
                                            # moment AFTER the request goes out, so a single
                                            # attempt at the start reliably finds nothing.
                                            while True:
                                                if AUTO_ALLOW:
                                                    await _click_allow_if_present()
                                                await anyio.sleep(ALLOW_CLICK_POLL_SECONDS)
                                        _tg.start_soon(_click_while_blocked)
                                        await session.list_tools()
                                        _tg.cancel_scope.cancel()
                                self.last_progress = time.monotonic()
                            except Exception as e:
                                log.warning("[%s] heartbeat list_tools failed, marking broken: %s", self.name, e)
                                async with self.lock:
                                    self.known_broken = True
                                    # Drop the public reference NOW — stdio teardown can
                                    # wedge (see stall_watchdog), and until it finishes
                                    # the old session must not be callable.
                                    self.session = None
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


def _build_upstreams() -> list[Upstream]:
    """All selection and validation logic lives in mcp_config.resolve_specs (tested fast,
    without this file's mcp/uvicorn dependencies); this is only the Upstream construction.
    A bad config is a loud startup death for launchd to report, never a half-configured
    daemon."""
    try:
        specs = mcp_config.resolve_specs(os.environ)
    except (mcp_config.ConfigError, OSError) as e:
        raise SystemExit(f"{SERVER_NAME}: {e}")
    return [
        Upstream(name=s.name, command=s.command, args=s.args,
                 require_xcode_running=s.require_xcode, prefix=s.prefix, env=s.env)
        for s in specs
    ]


def _not_connected_result(u: "Upstream") -> types.CallToolResult:
    # The retry text is derived from the upstream's own quirks: telling a client that
    # Xcode is being checked and its dialog clicked, for an upstream that has nothing to
    # do with Xcode, is a lie the phase-1 panel reproduced verbatim.
    if u.require_xcode_running:
        how = ("checking Xcode is running and clicking its approval prompt if one is "
               "showing")
    else:
        how = "restarting its child process"
    return types.CallToolResult(
        content=[
            types.TextContent(
                type="text",
                text=(
                    f"{SERVER_NAME}: [{u.name}] not connected right now. This daemon "
                    f"retries on its own every few seconds ({how}) — a retry shortly "
                    "should work without any manual action."
                ),
            )
        ],
        is_error=True,
    )


def build_server(upstreams: list[Upstream]) -> Server:
    single = len(upstreams) == 1
    # Prefixes are honoured VERBATIM — the single-upstream override that forced "" here
    # made the daemon and the validator disagree about the same file, and made adding a
    # second server silently rename the first one's entire surface.
    prefix_of = {u: u.prefix for u in upstreams}
    upstream_by_prefix = {prefix_of[u]: u for u in upstreams}
    # Bare-name passthrough exists ONLY for the deployed env-var single mode, whose spec
    # carries an explicitly empty prefix.
    passthrough = upstreams[0] if single and upstreams[0].prefix == "" else None

    # EXPLICIT DISPATCH TABLE (increment 1.3): exposed name -> (upstream, bare upstream
    # name), rebuilt every time the surface is composed in on_list_tools. Consulted
    # FIRST on tools/call; the startswith() prefix walk below survives only as a
    # fallback for a name that has not been listed yet in this daemon's lifetime.
    # Prefix routing alone cannot survive the tool map (Phase 3): a mapped name that
    # drops the prefix would be advertised and then rejected as unknown. The config
    # loader already rejects the prefix sets that would make this table ambiguous
    # (duplicates, prefixes of each other).
    dispatch: dict[str, tuple[Upstream, str]] = {}

    async def on_list_tools(
        ctx: ServerRequestContext, params: types.PaginatedRequestParams | None
    ) -> types.ListToolsResult:
        # A DISCONNECTED upstream is reported and skipped; it must NOT blank the others
        # (increment 1.4 — the defect all three colloquium brands found independently:
        # this used to serve zero tools for EVERY upstream when any one was missing, so
        # during an Xcode reconnect Drew's tools, which need no Xcode, vanished too).
        # A connected upstream answering with zero tools contributes zero tools; that is
        # an answer, not an absence.
        # This daemon serves its whole surface as ONE page (each upstream is drained in
        # Upstream.list_tools), so it never issues a nextCursor — and a cursor it never
        # issued cannot be honoured. Refusing beats forwarding it into upstream cursor
        # spaces it cannot belong to, which corrupted per-upstream pagination silently.
        if params is not None and params.cursor is not None:
            # MCPError so both transport paths return the spec's INVALID_PARAMS with the
            # message intact — a raised ValueError became code 0 on the 2025 path and a
            # message-less "Internal server error" on the modern one (panel, measured by
            # the claude leg on both protocol versions; empty-string cursor caught by
            # codex — "" is as unissued as any other value).
            raise MCPError(
                types.INVALID_PARAMS,
                f"{SERVER_NAME} serves its full tool list in one page and issued no cursor; "
                f"got unexpected cursor {params.cursor!r}")
        # Upstreams are listed CONCURRENTLY: each drain is independent, and the old
        # sequential walk meant one slow upstream withheld every later upstream's tools
        # for its whole timeout (panel: measured 23 seconds behind a single stalled stub).
        results: dict[Upstream, types.ListToolsResult | None] = {}

        async def _collect(u: Upstream) -> None:
            results[u] = await u.list_tools(None)

        async with anyio.create_task_group() as tg:
            for u in upstreams:
                tg.start_soon(_collect, u)

        all_tools: list[types.Tool] = []
        unavailable: list[str] = []
        new_dispatch: dict[str, tuple[Upstream, str]] = {}
        for u in upstreams:
            result = results.get(u)
            if result is None:
                unavailable.append(u.name)
                continue
            prefix = prefix_of[u]
            for t in result.tools:
                bare = t.name
                if prefix:
                    t = t.model_copy(update={"name": f"{prefix}{bare}"})
                if t.name in new_dispatch:
                    # Reachable since 1.5: an upstream mutating its list between drained
                    # pages can hand back the same tool twice. First one wins; say so.
                    log.warning("list_tools: duplicate exposed name %r from upstream %s — "
                                "keeping the first occurrence", t.name, u.name)
                    continue
                new_dispatch[t.name] = (u, bare)
                all_tools.append(t)
        dispatch.clear()
        dispatch.update(new_dispatch)
        if unavailable:
            log.warning("list_tools: serving %d tools WITHOUT unavailable upstream(s) %s — "
                        "each reconnects on its own; calls to them return a per-upstream error",
                        len(all_tools), ", ".join(unavailable))
        return types.ListToolsResult(tools=all_tools)

    async def _refresh_upstream_dispatch(u: Upstream) -> bool:
        """Re-list ONE upstream and fold its tools into the dispatch table. Returns
        False when the upstream is unavailable."""
        result = await u.list_tools(None)
        if result is None:
            return False
        prefix = prefix_of[u]
        for t in result.tools:
            dispatch[f"{prefix}{t.name}"] = (u, t.name)
        return True

    async def on_call_tool(ctx: ServerRequestContext, params: types.CallToolRequestParams) -> types.CallToolResult:
        # ROUTING IS DISPATCH-FIRST AND NEVER FORWARDS ON FAITH. The old prefix fallback
        # forwarded any dispatch miss to whichever upstream owned the prefix — which
        # would quietly bypass Phase 2's deny list and keep Phase 3's renamed tools
        # callable under their old names (panel, codex leg). A miss now refreshes that
        # one upstream's catalogue once (covering a call that arrives before the first
        # tools/list) and refuses if the name still is not offered.
        name = params.name
        if name not in dispatch:
            candidate = None
            if passthrough is not None:
                candidate = passthrough
            else:
                for prefix, u in upstream_by_prefix.items():
                    if prefix and name.startswith(prefix):
                        candidate = u
                        break
            if candidate is None:
                return types.CallToolResult(
                    content=[
                        types.TextContent(
                            type="text",
                            text=f"{SERVER_NAME}: tool name '{name}' doesn't match any known upstream prefix "
                            f"({', '.join(p for p in upstream_by_prefix if p)})",
                        )
                    ],
                    is_error=True,
                )
            if candidate is passthrough:
                # Env-var single mode serves the upstream's names verbatim, so there is
                # no daemon-side catalogue to enforce; the upstream answers for itself.
                result = await candidate.call_tool(name, params.arguments)
                if result is None:
                    return _not_connected_result(candidate)
                return result
            if not await _refresh_upstream_dispatch(candidate):
                return _not_connected_result(candidate)
            if name not in dispatch:
                bare = name[len(prefix_of[candidate]):]
                return types.CallToolResult(
                    content=[
                        types.TextContent(
                            type="text",
                            text=(
                                f"{SERVER_NAME}: upstream '{candidate.name}' does not currently "
                                f"offer '{bare}' — re-list tools for the current surface."
                            ),
                        )
                    ],
                    is_error=True,
                )

        target, tool_name = dispatch[name]
        result = await target.call_tool(tool_name, params.arguments)
        if result is None:
            return _not_connected_result(target)
        return result

    # THE INSTRUCTIONS ARE DERIVED FROM THE CONFIG, NOT ASSUMED. The old text described
    # every surface as Apple's Xcode bridge — the panel booted a Python stub behind this
    # daemon and read initialize text claiming it was `xcrun mcpbridge`. The mcpbridge
    # guidance survives, but only when an upstream actually IS mcpbridge.
    fronts_mcpbridge = any(
        u.command == "xcrun" and "mcpbridge" in u.args for u in upstreams)
    mcpbridge_para = (
        "\n\nApple's own Xcode MCP bridge (`xcrun mcpbridge`) is one of the upstreams "
        "here. You will likely also see other Xcode-adjacent MCP servers configured "
        "alongside — commonly xcode-mcp-server (a third-party tool, Drew's) and "
        "XcodeBuildMCP. That overlap is INTENTIONAL, not a conflict to resolve. If a "
        "call here fails or behaves inconsistently, try the equivalent tool on one of "
        "the others instead of giving up — and if one consistently works better or "
        "worse for a task, say so out loud in your response; that is wanted "
        "information."
        if fronts_mcpbridge else "")
    if single:
        u0 = upstreams[0]
        shown = f"{u0.prefix}<tool>" if u0.prefix else "the upstream's own tool names, unprefixed"
        instructions = (
            f"This is a persistent HTTP proxy in front of one MCP server: {u0.name} "
            f"(`{u0.command} {' '.join(u0.args)}`), serving {shown}. One approved "
            "daemon stays up instead of each client spawning its own copy.\n\n"
            "If a call says 'not connected right now', this daemon is already retrying "
            "on its own every few seconds, so a short retry should work without any "
            f"manual action.{mcpbridge_para}"
        )
    else:
        roster = "; ".join(
            f"{u.name} (`{u.command} {' '.join(u.args)}`, tools prefixed `{u.prefix}`)"
            for u in upstreams)
        instructions = (
            f"This is a persistent proxy fronting MULTIPLE MCP servers behind one "
            f"endpoint: {roster}. Prefixes keep two upstreams' same-named tools from "
            "colliding — always use the prefixed name shown in the tool list.\n\n"
            "If a call says 'not connected right now', that specific upstream is "
            "reconnecting on its own — the others are unaffected, since each upstream "
            "has its own independent connection. A short retry should work.\n\n"
            "The tool list reflects the upstreams available AT THE MOMENT YOU LIST. If "
            "an upstream named above is missing from the list, it is reconnecting; "
            f"re-run tools/list to pick it up when it returns.{mcpbridge_para}"
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
            tg.start_soon(u.stall_watchdog)
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
