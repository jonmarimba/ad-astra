# xcode-mcp-front

Three ways to reach Xcode-adjacent MCP tools, pick whichever fits:

1. **`xcode-mcp-front` alone** — just Apple's `xcrun mcpbridge`, fronted so you can drive Xcode without the per-PID "Allow" popup firing on every new connecting process. Port 8765, tools unprefixed (`BuildProject`, `XcodeListWindows`, ...).
2. **`xcode-combined-front`** — BOTH `mcpbridge` and Drew's `xcode-mcp` (`drews-xcode-mcp`) behind one endpoint, tools prefixed per-upstream (`xcode__BuildProject`, `drews__run_project_unmonitored`, ...) so a same-named tool from either side can never collide or shadow the other. Port 8767.
3. **Drew's `drews-xcode-mcp` directly, no wrapper at all** — it has no popup friction of its own (folder-allowlist auth, not a live per-PID prompt), so if you only need Drew's tools, just spawn `uvx drews-xcode-mcp` as a normal stdio MCP server, same as you always could. Nothing in this directory is required for that case.

All three share the exact same `daemon.py` — no duplicated logic between (1) and (2); (3) needs no daemon at all.

## Why

Xcode's MCP connection approval is keyed per connecting PID (confirmed by Jonathan, 2026-08-03). kicker runs many concurrent nodes, each configured to spawn `xcrun mcpbridge` itself — that's many concurrent PIDs, so many concurrent approval popups for what is functionally the same tool. Two off-the-shelf MCP aggregators were evaluated and rejected: `mcp-aggregator` (domdomegg) requires a full OIDC identity provider and can only front remote Streamable-HTTP upstreams, not local stdio subprocesses like `mcpbridge` — architecturally can't do this job at all, regardless of its stronger maintenance reputation. `combine-mcp` (nazar256) has the right shape (spawns local stdio children directly, no auth layer) but is a stdio server itself, spawned fresh per client — it would collapse 3 processes to 1 per session, but wouldn't fix the N-concurrent-nodes-N-popups problem, since each session still gets its own instance. Neither does the actual multiplexing job needed (many clients sharing one persistent upstream connection), so this is a small hand-rolled daemon instead.

Drew's tool never got a standalone daemon of its own for the same reason config (3) above exists: it was built, verified end to end (real tool calls, real results, no permission prompt at all), then torn back down — the entire justification for this daemon is "one persistent connection avoids N popups," and Drew's tool has no popup to avoid in the first place. It only shows up here as one half of the *combined* daemon (2), where the value isn't popup-avoidance but having both toolsets behind one endpoint.

## Status: validated and running

Everything below is confirmed live, not assumed — see `tools/tests/test-xcode-mcp-front.sh` (real HTTP calls against both running daemons, no mocks):

- One `mcpbridge` connection tolerates many sequential calls of different shapes, no reconnect needed.
- The approval prompt is requested lazily, on the first `list_tools` call — not at the initial connect. Each upstream's connection loop polls for it continuously, including once already "connected," not just while reconnecting.
- Xcode's approval dialogs do NOT stack — only one shows at a time, and an unanswered one blocks the next (including this daemon's own) from appearing. The click logic reads each dialog's own PID and clicks Allow for its own live PID, clicks Don't Allow for a dead PID (nobody's waiting on it), and leaves any other live PID's dialog strictly alone.
- Quitting Xcode doesn't crash the daemon — every call after that fails clean, and it reconnects on its own once Xcode is back, no manual restart needed.
- The combined daemon's `tools/list` returns correctly prefixed names for both upstreams (`xcode__` × 21, `drews__` × 29), and a prefixed call routes to the right one — `xcode__XcodeListWindows` returns a real workspace path from mcpbridge, `drews__version` returns Drew's real version string, verified independently. The unprefixed single-upstream daemon's own `XcodeListWindows` call is verified the same way. Full suite: `tools/tests/test-xcode-mcp-front.sh` — 10/10. The `xcode__`/mcpbridge side needs the screen unlocked AND Xcode's workspace window frontmost — see the third gotcha below; `drews__` has no such dependency.
- Both run as real launchd daemons (`com.jonathansaggau.xcode-mcp-front`, `com.jonathansaggau.xcode-combined-front` — label convention matching kickerd's on this machine) — `RunAtLoad`, survive logins, `KeepAlive` (bare `true`, see the gotcha below) recovers from an actual crash.

## Usage

### Config 1 — xcode-mcp-front alone (port 8765, unprefixed)

```sh
./install.sh                # deps, wraps the app for TCC, installs + loads the launchd job
./xcode-mcp-front load       # (re)install + load — same as install.sh's last step
./xcode-mcp-front unload
./xcode-mcp-front launchd-status
./xcode-mcp-front launchd-restart
./xcode-mcp-front logs
```

MCP client config: `"type": "http", "url": "http://127.0.0.1:8765/mcp"` in place of a stdio `xcrun mcpbridge` entry. Already wired into this session's own config (`js-project-GhOST/.mcp.json`); not yet wired into `js-llmKicker/.mcp.json` for real kicker node traffic.

### Config 2 — xcode-combined-front (port 8767, xcode__ / drews__ prefixed)

Same daemon.py, different env config. Set up like this:

```sh
# xcode-combined-front-run.sh sets:
#   XCODE_MCP_FRONT_UPSTREAMS="xcode:1:xcrun:mcpbridge;drews:0:uvx:drews-xcode-mcp"
#   XCODE_MCP_FRONT_PORT=8767
#   XCODE_MCP_FRONT_HOME=~/.xcode-combined-front
../wrap-in-app/wrap-in-app xcode-combined-front-run.sh --log ~/.xcode-combined-front/daemon.log --name XcodeCombinedFront --outdir .
# then a launchd plist for com.jonathansaggau.xcode-combined-front pointing at
# XcodeCombinedFront.app/Contents/MacOS/Automator Application Stub, same shape
# as xcode-mcp-front's own (see xcode-mcp-front's cmd_launchd_install for the
# template) — KeepAlive MUST be bare true, see the gotcha below.
```

MCP client config: `"type": "http", "url": "http://127.0.0.1:8767/mcp"`. Tool names are prefixed — use `xcode__BuildProject`, `drews__run_project_unmonitored`, etc., never the bare upstream name.

### Config 3 — Drew's tool directly, no wrapper

```json
{"mcpServers": {"drews-xcode-mcp": {"command": "uvx", "args": ["drews-xcode-mcp"]}}}
```

That's it. No daemon, no `.app`, no launchd job — nothing in this directory applies.

### Manual/dev mode (either daemon, no launchd, no auto-recovery — quick local testing only)

```sh
./xcode-mcp-front start   # background daemon, http://127.0.0.1:8765/mcp
./xcode-mcp-front status
./xcode-mcp-front stop
./xcode-mcp-front spike [N]   # standalone validation: N sequential list_tools round-trips against a live Xcode
```

## Design

- `daemon.py` — the whole thing, shared by config (1) and (2). Two pieces:
  - `Upstream` — owns ONE upstream's persistent connection. Its `connection_manager()` loops forever: while not connected, check Xcode is running (if this upstream needs it — Drew's doesn't), best-effort click its approval prompt if showing, attempt a fresh connect; once connected, keep polling (and clicking) on the same timer until a call proves the connection's broken, then go back to reconnecting. In-process reconnect, not exit-and-let-the-supervisor-restart — cheaper, and doesn't burn a fresh PID/fresh approval each cycle.
  - `build_server(upstreams)` — single-upstream mode (one `Upstream`, tools forwarded unprefixed, unchanged from before multi-upstream support existed) or multi-upstream mode (several `Upstream`s, `tools/list` aggregates and prefixes each one's tools `<name>__`, `tools/call` strips the prefix and routes to the matching `Upstream`). Which mode depends on whether `XCODE_MCP_FRONT_UPSTREAMS` is set — see `daemon.py`'s own header for the full env-var reference for both modes.
  - Calls to a given upstream are serialized through that upstream's own lock (concurrent-call tolerance hasn't been tested, so this starts correctness-first); different upstreams are fully independent of each other.
- No auth layer. Binds to `127.0.0.1` only — single machine, single user, the SDK auto-enables DNS-rebinding protection for localhost binds. This is exactly what made `mcp-aggregator`'s OIDC requirement pure overkill for this use case.
- Dumb passthrough, not a real aggregator — forwards whatever each upstream advertises rather than pre-declaring tool signatures.
- `xcode-mcp-front` — the CLI, config (1)'s own. `start`/`stop`/`status`/`logs`/`spike` for manual/dev mode; `load`/`unload`/`launchd-status`/`launchd-restart` for the real launchd-managed mode (the one to actually leave running). Config (2) doesn't have its own CLI yet — see "Known gaps".
- `xcode-mcp-front-run.sh` / `xcode-combined-front-run.sh` — the actual per-config env-var setup, thin on purpose (a handful of `export`s + exec `daemon.py`). Both source `self-preempt.sh` (kills any stale instance already bound to THAT config's own port before starting — port-scoped specifically because both configs' processes match the same `daemon.py` path, so a blind kill would take out the other config too; `launchctl kickstart -k` doesn't reliably cascade-kill the whole descendant process tree, confirmed live).
- `XcodeMCPFront.app` / `XcodeCombinedFront.app` (built via `../wrap-in-app/wrap-in-app`) — each gives TCC a stable identity to grant Accessibility/Automation permission to (needed for the click-Allow behavior's `osascript`/System-Events UI-scripting; Drew's-only calls never need it, but the combined daemon's `xcode` half does). launchd points directly at each app's own executable, not through `open -a` — see the gotcha below. Edit the `-run.sh` scripts freely; the grant survives since each app only references its script by absolute path. Never edit a `.app` itself — that silently kills its grant.
- `check-allow-window.sh` — read-only diagnostic for the approval-dialog situation, safe to run anytime. Lists every pending dialog, or checks whether a specific PID has one.
- `tools/tests/test-xcode-mcp-front.sh` (repo `tools/tests/`) — asserts by effect against both real running daemons over HTTP: unprefixed passthrough still works, both prefixes appear in `tools/list`, both a real `xcode__` and a real `drews__` call route correctly, an unrecognized tool name on the combined daemon fails loud (the RED control — proves the prefix-routing logic is actually being exercised, not just assumed), both plists have the correct `KeepAlive` shape.

### Two gotchas found the hard way

**`open -a` doesn't work for a persistent daemon.** `wrap-in-app`'s launch shim (`open -a App.app -W`, plus a schd-facing poke-on-stdout wrapper) is built for finite, schd-style scripts that run once and exit. The app's embedded script never exits here, so a second `open -a` on an already-running instance either no-ops or blocks forever on the SAME old instance — `launchctl kickstart -k` was killing the launchd-tracked shim/`open` process, which isn't even in the same process tree as the actual `daemon.py` (`open` hands off to LaunchServices, decoupling it from whatever called it), so the real work was never actually restarted. Fixed by pointing `ProgramArguments` directly at each app's own `Contents/MacOS/Automator Application Stub` binary — launchd then owns that process as its own direct child, so `kickstart`/`KeepAlive` genuinely control its lifecycle. The TCC grant still applies either way; it's pinned to the `.app`'s identity, not to how it's launched.

**`KeepAlive` must be bare `true`, not `{SuccessfulExit: false}`.** The latter matches kickerd's own convention on this machine, and was copied here at first — wrong fit. This daemon's most likely failure mode, the port already being in use, makes uvicorn shut down gracefully with exit code 0. `{SuccessfulExit: false}` reads that as "finished on purpose, don't respawn," so the daemon silently stayed dead after an `EADDRINUSE` until this was caught live. Plain `true` respawns regardless of exit code, which is what a persistent service that should never intentionally "finish" actually needs.

**mcpbridge needs the screen unlocked AND Xcode's workspace window frontmost — two separate external requirements, neither one a bug in this daemon.** Both confirmed live, 2026-08-14, and both produce the exact same downstream symptom (`xcode__` calls fail instantly with `Connection closed`), which is what made them look like one cause at first — they aren't:

1. *Screen must be unlocked.* With the console locked (`CGSSessionScreenIsLocked=Yes`), Xcode can't render or process its own Allow prompt at all — a brand-new, never-approved connecting PID hangs indefinitely on its very first real request with no dialog ever appearing anywhere in the Accessibility tree, and `check-allow-window.sh` correctly reports no pending dialog because there genuinely isn't one to click. `_click_allow_if_present()` has nothing to act on here; that isn't the fix. Check with `ioreg -n Root -d1 | grep -i "CGSSessionScreenIsLocked\|IOConsoleLocked"`.
2. *Xcode's own workspace window must be open AND frontmost, not just present.* Unlocking the screen alone does NOT fix a `Connection closed` failure — confirmed by testing with the screen genuinely unlocked and the failure persisting identically. The actual cause, found in Apple's own unified log (`log show`, not guessed): `Xcode: (IDEIntelligenceChat) [com.apple.IDEIntelligenceChat:MCP Server] Rejecting connection - no workspace windows are open`, immediately followed by mcpbridge's XPC connection being invalidated ("the client process (pid <Xcode's pid>) either cancelled the connection or exited") — that XPC teardown is what surfaces on our side as `Connection closed`, milliseconds after a clean connect. AppleScript's own `tell application "Xcode" to get name of every window` can report the workspace window present even while this rejection fires, because Xcode's own frontmost/key-window state is a different check than "does the window exist." Fix: bring Xcode to the front before a real call — `activate_app`/equivalent, or just click its window — not merely confirm it's running or has a window in the list. One concrete way this happens live: an unrelated tool's own connection-approval dialog (e.g. a different agent's "Allow X to access Xcode?" prompt) can sit unanswered as Xcode's frontmost window, silently stealing key-window status from the real workspace window and reproducing this exact failure until that dialog is dismissed.

**`_click_allow_if_present()`'s "Don't Allow" branch used a straight apostrophe and had silently never worked.** Found live, 2026-08-14, while chasing a stray "Allow 'Codex' to access Xcode?" dialog (left over from a codex convocation run) that was blocking Xcode's real workspace window from being frontmost — see gotcha 2 above. Xcode's actual button title uses the typographic U+2019 apostrophe (`Don’t Allow`), not the ASCII `'` the code was checking for (`Don't Allow`). `exists (button "Don't Allow" of w)` against the real Accessibility tree is always false, so `_run_osascript` returns cleanly with `clicked=False` — no exception, nothing loud, just a dead-PID's stale dialog sitting there forever, blocking every connection attempt behind it, which is exactly the failure mode this branch exists to prevent. Fixed to use the real character.

Together, this traced through a chain of separate-looking symptoms that turned out to be TWO causes, not one: `_run_osascript` timeouts against a wedged System Events and orphaned `osascript` processes (cause 1, screen lock) and the immediate `Connection closed` on every real mcpbridge call regardless of lock state (cause 2, Xcode not frontmost). Check both before chasing anything else in this daemon when `xcode__` calls start failing. `drews__` calls are unaffected by either — Drew's tool never touches the GUI.

## Known gaps

- `js-llmKicker/.mcp.json` (and kicker nodes' MCP config generally) still spawn `mcpbridge` directly — neither daemon is wired into real kicker traffic yet, only into this session's own config.
- Config (2)'s launchd install/uninstall is still hand-rolled (see the "Usage" section above) rather than a `cmd_launchd_install`-style CLI command like config (1) has. A natural follow-up if config (2) proves out.
