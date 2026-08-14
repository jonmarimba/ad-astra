# xcode-mcp-front

Fronts a single, persistent `xcrun mcpbridge` connection behind a Streamable HTTP MCP server, so every client (kicker nodes, Claude Code, Codex, anything MCP-over-HTTP) shares ONE upstream connection instead of each spawning its own `mcpbridge` and re-triggering Xcode's per-PID "Allow" approval popup.

## Why

Xcode's MCP connection approval is keyed per connecting PID (confirmed by Jonathan, 2026-08-03). kicker runs many concurrent nodes, each configured to spawn `xcrun mcpbridge` itself — that's many concurrent PIDs, so many concurrent approval popups for what is functionally the same tool. Two off-the-shelf MCP aggregators were evaluated and rejected: `mcp-aggregator` (domdomegg) requires a full OIDC identity provider and can only front remote Streamable-HTTP upstreams, not local stdio subprocesses like `mcpbridge` — architecturally can't do this job at all, regardless of its stronger maintenance reputation. `combine-mcp` (nazar256) has the right shape (spawns local stdio children directly, no auth layer) but is a stdio server itself, spawned fresh per client — it would collapse 3 processes to 1 per session, but wouldn't fix the N-concurrent-nodes-N-popups problem, since each session still gets its own instance. Neither does the actual multiplexing job needed (many clients sharing one persistent upstream connection), so this is a small hand-rolled daemon instead.

## Status: validated and running

Everything below is confirmed live against a real Xcode, not assumed:

- One `mcpbridge` connection tolerates many sequential calls of different shapes, no reconnect needed.
- The approval prompt is requested lazily, on the first `list_tools` call — not at the initial connect. The daemon polls for it continuously, including once it's already "connected," not just while reconnecting.
- Xcode's approval dialogs do NOT stack — only one shows at a time, and an unanswered one blocks the next (including this daemon's own) from appearing. The daemon reads each dialog's own PID and clicks Allow for its own live PID, clicks Don't Allow for a dead PID (nobody's waiting on it), and leaves any other live PID's dialog strictly alone.
- Quitting Xcode doesn't crash the daemon — every call after that fails clean ("not connected to Xcode right now"), and it reconnects on its own once Xcode is back, no manual restart needed.
- Runs as a real launchd daemon (`com.jonathansaggau.xcode-mcp-front`, matching the convention already used by kickerd on this machine) — `RunAtLoad`, survives logins, `KeepAlive` recovers from an actual crash.

## Usage

```sh
./install.sh                # deps, wraps the app for TCC, installs + loads the launchd job
./xcode-mcp-front load       # (re)install + load the launchd job — same as install.sh's last step
./xcode-mcp-front unload     # stop and remove the launchd job
./xcode-mcp-front launchd-status
./xcode-mcp-front launchd-restart
./xcode-mcp-front logs       # tail the daemon log
```

Manual/dev mode (no launchd, no auto-recovery — for quick local testing only):

```sh
./xcode-mcp-front start   # background daemon, http://127.0.0.1:8765/mcp
./xcode-mcp-front status
./xcode-mcp-front stop
./xcode-mcp-front spike [N]   # standalone validation: N sequential list_tools round-trips against a live Xcode
```

Point client MCP configs at the daemon instead of spawning `mcpbridge` directly — an HTTP-transport server entry (`"type": "http", "url": "http://127.0.0.1:8765/mcp"`) in place of the stdio `xcrun mcpbridge` entry. Already wired into this session's own config (`js-project-GhOST/.mcp.json`); not yet wired into `js-llmKicker/.mcp.json` for real kicker node traffic.

## Design

- `daemon.py` — the whole thing. `Server.lifespan` (from the `mcp` SDK's low-level `Server`) runs a `connection_manager()` loop that owns the upstream connection for the daemon's entire process life: while not connected, check Xcode is running, best-effort click its approval prompt if showing, attempt a fresh connect; once connected, keep polling (and clicking) on the same timer until a call proves the connection's broken, then go back to reconnecting. In-process reconnect, not exit-and-let-the-supervisor-restart — cheaper, and doesn't burn a fresh PID/fresh approval each cycle. `on_list_tools`/`on_call_tool` forward to the one shared `ClientSession`, serialized through a lock (mcpbridge's tolerance for concurrent overlapping calls hasn't been tested, so this starts correctness-first — tool calls are already human-paced, so serialization shouldn't be felt).
- No auth layer. Binds to `127.0.0.1` only — single machine, single user, the SDK auto-enables DNS-rebinding protection for localhost binds. This is exactly what made `mcp-aggregator`'s OIDC requirement pure overkill for this use case.
- Dumb passthrough, not a real aggregator — forwards whatever the upstream advertises rather than pre-declaring tool signatures.
- Mostly generic despite the name: which upstream command/args, port, state dir, whether to require Xcode running first, and the server's self-reported name are all env-var-driven (`XCODE_MCP_FRONT_UPSTREAM_CMD`/`_ARGS`, `_PORT`, `_HOME`, `_REQUIRE_XCODE`, `_SERVER_NAME`) — see `daemon.py`'s own header for the full list. This was built out to evaluate also fronting Drew's `xcode-mcp` (`drews-xcode-mcp`) as a second instance; that instance was built, verified end to end, and then torn back down (see "Evaluated and rejected" below) — the hooks stayed because they're harmless and cost nothing to keep, but only one instance actually runs today.
- `xcode-mcp-front` — the CLI. `start`/`stop`/`status`/`logs`/`spike` for manual/dev mode; `load`/`unload`/`launchd-status`/`launchd-restart` for the real launchd-managed mode (the one to actually leave running).
- `xcode-mcp-front-run.sh` — the actual process launchd supervises. Sources `self-preempt.sh` (kills any stale instance already bound to the same port before starting — `launchctl kickstart -k` doesn't reliably cascade-kill the whole descendant process tree, confirmed live) then execs `daemon.py`.
- `XcodeMCPFront.app` (built via `../wrap-in-app/wrap-in-app`) — gives TCC a stable identity to grant Accessibility/Automation permission to (needed for the click-Allow behavior's `osascript`/System-Events UI-scripting). launchd points directly at this app's own executable, not through `open -a` — that was a real dead end, see below. Edit `xcode-mcp-front-run.sh` freely; the grant survives since the app only references it by absolute path. Never edit the `.app` itself — that silently kills the grant.
- `check-allow-window.sh` — read-only diagnostic for the approval-dialog situation, safe to run anytime. Lists every pending dialog, or checks whether a specific PID has one.

### Evaluated and rejected: fronting Drew's xcode-mcp too

Built a second daemon instance (`drews-xcode-mcp`, folder-allowlist auth instead of a live per-PID popup) and verified it end to end — real tool calls, real results, no permission prompt needed at all. Then tore it down: the entire justification for this daemon is "one persistent connection avoids N popups," and Drew's tool has no popup to avoid in the first place. A client can just spawn `uvx drews-xcode-mcp` directly, same as it always could, with zero friction either way — fronting it would have been infrastructure solving a problem that doesn't exist for that upstream. Caught this only after fully building and testing it, not before — worth remembering to check the actual justification applies before building the next "front upstream X too" instance.

### The `open -a` dead end (why launchd points at the app's binary directly)

`wrap-in-app`'s launch shim (`open -a App.app -W`, plus a schd-facing poke-on-stdout wrapper) is built for finite, schd-style scripts that run once and exit. It does not work for a persistent daemon: the app's embedded script never exits, so a second `open -a` on an already-running instance either no-ops or blocks forever on the SAME old instance — `launchctl kickstart -k` was killing the launchd-tracked shim/`open` process, which isn't even in the same process tree as the actual `daemon.py` (`open` hands off to LaunchServices, decoupling it from whatever called it), so the real work was never actually restarted. Fixed by pointing `ProgramArguments` directly at `XcodeMCPFront.app/Contents/MacOS/Automator Application Stub` — launchd then owns that process as its own direct child, so `kickstart`/`KeepAlive` genuinely control its lifecycle. The TCC grant still applies either way; it's pinned to the `.app`'s identity, not to how it's launched.

## Known gaps

- `js-llmKicker/.mcp.json` (and kicker nodes' MCP config generally) still spawn `mcpbridge` directly — this daemon isn't wired into real kicker traffic yet, only into this session's own config.
- No multi-upstream fronting behind one daemon (e.g. also wrapping `XcodeBuildMCP`) — evaluated for Drew's tool specifically and rejected as unnecessary; a genuinely popup-prone upstream might justify revisiting this.
