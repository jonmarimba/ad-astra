# xcode-mcp-front

Fronts a single, persistent `xcrun mcpbridge` connection behind a Streamable HTTP MCP server, so every client (kicker nodes, Claude Code, Codex, anything MCP-over-HTTP) shares ONE upstream connection instead of each spawning its own `mcpbridge` and re-triggering Xcode's per-PID "Allow" approval popup.

## Why

Xcode's MCP connection approval is keyed per connecting PID (confirmed by Jonathan, 2026-08-03). kicker runs many concurrent nodes, each configured to spawn `xcrun mcpbridge` itself — that's many concurrent PIDs, so many concurrent approval popups for what is functionally the same tool. Two off-the-shelf MCP aggregators were evaluated and rejected: `mcp-aggregator` (domdomegg) requires a full OIDC identity provider and can only front remote Streamable-HTTP upstreams, not local stdio subprocesses like `mcpbridge` — architecturally can't do this job at all, regardless of its stronger maintenance reputation. `combine-mcp` (nazar256) has the right shape (spawns local stdio children directly, no auth layer) but is a stdio server itself, spawned fresh per client — it would collapse 3 processes to 1 per session, but wouldn't fix the N-concurrent-nodes-N-popups problem, since each session still gets its own instance. Neither does the actual multiplexing job needed (many clients sharing one persistent upstream connection), so this is a small hand-rolled daemon instead.

## Status: NOT YET VALIDATED

`spike.py` — the one assumption this whole design rests on — has not been run against a live Xcode yet (Xcode wasn't running when this was built; launching a GUI app needs Jonathan's go-ahead per standing policy). Run it first:

```sh
./xcode-mcp-front spike        # 5 sequential list_tools round-trips, default
./xcode-mcp-front spike 20     # more round-trips
```

PASS means one `xcrun mcpbridge` connection tolerates staying open across many sequential calls (and ideally a project switch) without needing a reconnect. That's the green light to trust `daemon.py`'s core assumption. If it fails, the design needs to change (reconnect-on-error, respawn on project switch) before it's worth pointing real kicker traffic at it.

## Usage

```sh
./install.sh              # deps: just uv (daemon/spike run as PEP 723 scripts, deps inline)
./xcode-mcp-front spike    # validate the assumption first — see above
./xcode-mcp-front start    # background daemon, http://127.0.0.1:8765/mcp
./xcode-mcp-front status
./xcode-mcp-front logs     # tail the daemon log
./xcode-mcp-front stop
```

Then point client MCP configs at the daemon instead of spawning `mcpbridge` directly — an HTTP-transport server entry (`"type": "http", "url": "http://127.0.0.1:8765/mcp"`) in place of the stdio `xcrun mcpbridge` entry. Not yet done in `js-llmKicker/.mcp.json` — that's the next step once the spike passes and Jonathan wants it wired in for real.

## Design

- `daemon.py` — the whole thing. `Server.lifespan` (from the `mcp` SDK's low-level `Server`) opens ONE `xcrun mcpbridge` stdio connection and holds it for the daemon's entire process life — confirmed by reading the SDK source (`StreamableHTTPSessionManager.run` enters the app's lifespan exactly once, not per HTTP session). `on_list_tools`/`on_call_tool` forward to that one shared `ClientSession`, serialized through a lock (mcpbridge's tolerance for concurrent overlapping calls hasn't been tested, so this starts correctness-first — tool calls are already human-paced, so serialization shouldn't be felt).
- No auth layer. Binds to `127.0.0.1` only — single machine, single user, the SDK auto-enables DNS-rebinding protection for localhost binds. This is exactly what made `mcp-aggregator`'s OIDC requirement pure overkill for this use case.
- Dumb passthrough, not a real aggregator — forwards whatever `mcpbridge` advertises rather than pre-declaring tool signatures. Only fronts one upstream today; multi-upstream (also wrapping `xcode-mcp-server` and `XcodeBuildMCP` behind the same daemon) is a natural next step once this is proven, not built yet.
- `xcode-mcp-front` — start/stop/status/logs wrapper, pidfile-based, foreground `spike` passthrough.

## Known gaps

- Not yet a launchd-managed persistent service — `start`/`stop` are manual today. If this proves out, wiring it to launch automatically (survive reboots/logouts) is a follow-up.
- Single upstream (`mcpbridge` only). `xcode-mcp-server` and `XcodeBuildMCP` aren't fronted yet.
- No reconnect-on-crash. If the daemon's `mcpbridge` child dies (Xcode quits, project closes), the daemon needs a manual restart — no supervisor loop yet.
