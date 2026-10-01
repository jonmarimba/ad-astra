I have all the information I need. Let me now compile the complete review.

---

# Phase 4 and 5 Convocation Review — Qwen leg

Reviewing commits `782c1de` (notifications and versions) and `efa84ec` (per-repo autonomous deployment) on branch `tool-templates`. Every finding below cites what I read versus what I infer. Findings are numbered, most severe first.

---

## 1. `server/discover` advertises `listChanged: false` for modern-protocol clients — the capability override only covers the handshake path

**Claim.** The `functools.partial` override of `create_initialization_options` at `daemon.py:1275` passes `notification_options=NotificationOptions(tools_changed=True)` to `Server.create_initialization_options`. That method calls `get_capabilities()` with no `protocol_version` argument, so it uses the handshake-era branch (`server.py:582` in the SDK) that reads `notification_options.tools_changed` — and the override works. But the SDK also has a `server/discover` handler (`server.py:657-669` in the SDK), called by modern-protocol (`2026-07-28`) clients, that calls `get_capabilities(protocol_version=ctx.protocol_version)`. When `protocol_version in MODERN_PROTOCOL_VERSIONS`, the SDK ignores `notification_options` entirely and derives `tools_changed` from whether `subscriptions/listen` is served (`server.py:580-583`: `tools_changed = listen_served`). The daemon does not register a `subscriptions/listen` handler, so a modern client that uses `server/discover` instead of the `initialize` handshake sees `listChanged: false` and is told to ignore the very notifications this daemon pushes.

**File:line.** `daemon.py:1275-1277` (the override); SDK `server/lowlevel/server.py:580-583` and `657-669` (the discover path).

**Failure scenario.** A client speaking protocol `2026-07-28` connects, calls `server/discover`, and receives `capabilities.tools.listChanged: false`. The daemon then pushes `notifications/tools/list_changed` on its GET stream. The client's cache is stale, but it was told the list is not a moving target, so it never re-lists.

**Fix.** Override `_handle_discover` the same way `create_initialization_options` is overridden, or register a `subscriptions/listen` handler. Alternatively, test against the modern protocol version to confirm whether any real downstream client (kicker, Claude Code, Codex) actually uses `server/discover` — if none do today, document the gap and defer.

**What I read vs infer.** I read the SDK source directly in the uv cache. The `MODERN_PROTOCOL_VERSIONS = ("2026-07-28",)` tuple is real. The test uses `2025-06-18` (a handshake version), so the test cannot catch this. I infer that `server/discover` is a separate call path; I have not confirmed which real clients exercise it.

---

## 2. `pgrep -f "$HERE/daemon.py"` treats the path as an ERE, so dots are regex wildcards — an editor with the file open in its argv gets killed

**Claim.** `repo-daemon-run.sh:28` uses `pgrep -f "$HERE/daemon.py"` to self-preempt. On macOS, `pgrep -f` treats its pattern as an extended regular expression matched against the full command line. The path `$HERE/daemon.py` contains dots (in `.astra`, in `daemon.py`) that are regex wildcards matching any character. A process whose command line contains a path that differs only in those dot-positions — e.g. an editor with `daemon.py` open, or a `tail -f` on `daemon.log` whose path also contains `.astra` — would match the pattern and be killed.

**File:line.** `repo-daemon-run.sh:28`.

**Failure scenario.** A developer has the daemon file open in `vim /Users/.../repo/.astra/mcp-front/daemon.py` (vim's process name includes the file path in argv). Re-running `run.sh` finds the editor via `pgrep -f` and kills it. More exotic: a process named with `Xastra` in place of `.astra` — unlikely but the regex permits it.

**Fix.** Escape the dots in the pattern (`pgrep -f "$(printf '%s' "$HERE/daemon.py" | sed 's/\./\\./g')"`), or use `pgrep -f "^[0-9]* .*$(printf '%s' "$HERE/daemon.py" | sed 's/[][()|^$.*/?+{}]/\\&/g')"` for a fully anchored literal. macOS `pgrep` has no `-F` (fixed-string) flag, so escaping is the path.

**What I read vs infer.** I read the `pgrep` man page behavior from the macOS documentation: `-f` matches against the full argument list, and the pattern is an ERE. I confirmed the dots-in-path behavior is real. I infer an editor in argv is a plausible match; I have not reproduced it.

---

## 3. The `{"mcpServers": {}}` placeholder under KeepAlive `true` creates an infinite crash-restart loop

**Claim.** `repo-daemon-install.sh:52-53` writes `{"mcpServers": {}}` as the placeholder if `_mcp_info.json` does not exist, calling it "deliberately INVALID-to-serve." The launchd plist has `KeepAlive` set to bare `true` (line 60-61). When the daemon starts with an empty `mcpServers`, `mcp_config.py:256` raises `ConfigError("has no non-empty mcpServers object")`, `daemon.py:829` raises `SystemExit`, and the process exits non-zero. KeepAlive `true` restarts it immediately. This is a tight crash loop — the process starts, exits, and restarts with no backoff, consuming CPU and filling `daemon.log` until a human writes a real config.

**File:line.** `repo-daemon-install.sh:52-53` (placeholder), `repo-daemon-install.sh:60` (KeepAlive true), `mcp_config.py:256` (the rejection), `daemon.py:829` (the SystemExit).

**Failure scenario.** A repo is installed, the launchd plist is loaded before a template writes a real `_mcp_info.json`. The daemon crash-loops forever, filling the log and burning CPU. The comment in `repo-daemon-install.sh` says "die loudly at startup" — but the design conflates "loud" (a log line) with "infinitely recurring" (launchd restarts with no delay). The KeepAlive comment says `{SuccessfulExit:false}` would "silently stay dead" on a clean exit, but `SystemExit` from `raise SystemExit(...)` is a clean exit (exit code 1, not a crash) — so `SuccessfulExit:false` would actually keep it dead. The bare `true` is what causes the loop.

**Fix.** Either (a) use `KeepAlive` with `SuccessfulExit: false` instead of bare `true` — the existing comment rejects this, but `raise SystemExit` is a clean exit (not EADDRINUSE), so `SuccessfulExit: false` would correctly stay dead for the placeholder case while still restarting on a crash; or (b) add `ThrottleInterval` to the plist to slow the loop; or (c) have the daemon sleep before exiting on a config error, so launchd's restart is spaced out.

**What I read vs infer.** I read the plist generation and the config rejection. I verified `SystemExit` produces a non-zero exit code. I infer launchd's KeepAlive `true` restarts immediately on any exit; I have not timed the actual restart interval (launchd may apply its own minimum throttle).

---

## 4. `downstream_sessions` registry keyed by `id(connection)` leaks entries for sessions that never error and never disconnect

**Claim.** `daemon.py:941-956`: `_remember_downstream` adds `id(conn) -> ctx.session` to `downstream_sessions` on every request. `broadcast_list_changed` iterates the registry, and on an exception removes the entry. But a client that connects, makes one request, and then abandons the connection without ever opening a GET stream (the common case for a client that lists tools and caches) stays in the registry forever — `send_tool_list_changed()` is called on its session each broadcast, the `move_on_after(1)` silently times out (no exception is raised by `anyio.move_on_after`), and the entry is never removed. The registry grows monotonically with every distinct client that ever makes a request.

**File:line.** `daemon.py:941` (the dict), `daemon.py:946` (the add), `daemon.py:949-955` (the broadcast), `daemon.py:956` (the only removal path — exception).

**Failure scenario.** Over a daemon's lifetime (days, under launchd), every client that ever lists tools — kicker heartbeat polls, Claude Code sessions, Codex sessions, test probes — accumulates in `downstream_sessions`. Each broadcast iterates all of them, timing out after 1 second each. With 100 stale entries, a single `list_changed` broadcast takes 100 seconds of wall time (serialized, since the loop is sequential `for key, session in list(downstream_sessions.items())`). The debounce plus this serial broadcast means the notification arrives minutes late to the live client at the end of the list.

**Fix.** Track a timestamp per entry and evict entries older than a session TTL, or catch the `move_on_after` timeout and remove the entry (a session that never drains its GET stream after N broadcasts is dead to us). Alternatively, use `move_on_after` + a flag: if the send timed out, remove the entry.

**What I read vs infer.** I read the code path. `anyio.move_on_after` does not raise an exception on timeout — it simply cancels the await and continues. So the `except Exception` branch that removes stale entries is never reached for a timed-out send. I infer the registry grows; I have not measured it on a live daemon.

---

## 5. `id(connection)` reuse after GC: a new connection gets the same key as a dead one, so the broadcast sends to the wrong session

**Claim.** `daemon.py:946`: `downstream_sessions[id(conn)] = ctx.session`. Python's `id()` returns the memory address of an object, and CPython reuses memory addresses after an object is garbage-collected. If a connection is GC'd and a new connection happens to allocate at the same address, `id(conn)` returns the same integer, and the new session overwrites the old entry. This is the real Python hazard the prompt asks about. It is reachable here because the `_connection` attribute is read from the SDK's `ServerSession`, which is a per-request proxy — the underlying `Connection` object's lifetime is managed by the session manager, not by this daemon's code. If a connection closes, its `ServerSession` proxy is GC'd, and a new connection's proxy lands at the same address, the new session replaces the old one in the registry. The old session's entry is gone (overwritten), so no stale send occurs — but a notification meant for the old client is now sent to the new client instead. The new client gets an unexpected `list_changed` notification it did not ask for.

**File:line.** `daemon.py:946`.

**Failure scenario.** Client A connects, lists tools, disconnects (connection GC'd). Client B connects, and its `Connection` object happens to allocate at the same address. `id(conn)` returns the same integer. Client B's session overwrites A's entry. The next `list_changed` broadcast sends to B's session. B receives a spurious notification. Harmless in practice (B just re-lists), but incorrect.

**Fix.** Use a `weakref` to the connection object as the key instead of `id()`, or use `id(ctx.session)` (the session proxy, which is per-request and less likely to be reused), or include a monotonic counter in the key to make it unique.

**What I read vs infer.** I read the `id()` call. CPython's `id()` reuse after GC is documented Python behavior. I infer the connection lifetime is managed by the SDK; I have not traced the SDK's connection GC path to confirm the reuse window is practically reachable. The hazard is real in principle but low-probability — it requires a specific memory allocation pattern.

---

## 6. The `port` file goes stale when launch fails after writing it — a client reading the port connects to nothing or to the wrong service

**Claim.** `repo-daemon-run.sh:38` writes the resolved port to `$HERE/port`, then `repo-daemon-run.sh:50` execs `uv run --script daemon.py`. If the daemon fails to bind (e.g. a TOCTOU race: another process grabs the port between the `lsof` probe at line 33 and the daemon's bind at line 50), the `port` file contains a port the daemon is not listening on. A client reading `.mcp.json` (which was also written with the same port at line 42-44) tries to connect and fails. On the next launchd restart, `run.sh` runs again, but the stale `port` file is overwritten only after the new port is resolved — between the failed bind and the next run, clients have a wrong endpoint.

**File:line.** `repo-daemon-run.sh:38` (write port), `repo-daemon-run.sh:42-44` (write .mcp.json), `repo-daemon-run.sh:50` (exec daemon).

**Failure scenario.** Two repos launch simultaneously. Repo A's `lsof` probe at line 33 sees port 21000 is free. Repo B's `lsof` probe also sees 21000 is free (TOCTOU). Repo A writes `port=21000`, execs the daemon, and binds successfully. Repo B writes `port=21000` to its `.mcp.json`, execs the daemon — the daemon hits EADDRINUSE and exits. Repo B's `.mcp.json` now points at port 21000, which is Repo A's daemon. A client connecting to Repo B's endpoint gets Repo A's tool surface. KeepAlive restarts Repo B's `run.sh`, which re-probes, finds 21000 taken, steps to 21001, and overwrites the port file — but between the failed launch and the restart, a client may have connected to the wrong daemon.

**Fix.** Write the `port` file and `.mcp.json` only after the daemon has successfully bound (e.g. have the daemon write the port file itself after binding, not the run script). Or add a readiness check in `run.sh` that verifies the daemon is listening before writing the port file.

**What I read vs infer.** I read the script's ordering. The TOCTOU window between `lsof` and the daemon's bind is real — `lsof` and `bind` are separate syscalls. I infer the EADDRINUSE exit path; the daemon's `main()` at `daemon.py:1352` calls `uvicorn.run()` which will exit on a bind failure. I have not measured the TOCTOU window in practice.

---

## 7. Version-mismatch persistence file grows unboundedly — every distinct `(name, expected, found)` triple is kept forever

**Claim.** `daemon.py:1306-1312`: `seen_mismatches` is a dict keyed on `f"{name}:{expected}:{found}"`, loaded from `version-mismatches.json` at startup, and appended to on each new mismatch. The file is never pruned. Over a daemon's lifetime, if an upstream cycles through multiple versions (Xcode betas, Drew's server updates), each distinct version pair adds an entry. The file grows monotonically.

**File:line.** `daemon.py:1289` (load), `daemon.py:1306-1312` (append + persist).

**Failure scenario.** Over months of Xcode updates, the file accumulates dozens of entries. Each entry is small (a key + `true`), so the file is not large, but the `json.load` at startup reads the entire file into memory, and the `json.dump` on each new mismatch rewrites the entire file. This is not a memory or disk problem at any realistic scale — but it is the same "unbounded growth" concern the Phase 1 panel raised for other persistence, and the SPEC's "persisted rather than held in memory" design did not specify an eviction policy.

**Fix.** Add a maximum entry count or a time-based eviction (e.g. keep only the last N distinct mismatches, or entries from the last 90 days). The file is human-readable JSON, so pruning is straightforward.

**What I read vs infer.** I read the load/append/persist cycle. I infer the growth is slow in practice (one entry per distinct version pair, not per reconnect). This is a low-severity finding — the file would need thousands of entries to matter, and version pairs are rare.

---

## 8. Mismatch notes in `server.instructions` accumulate across reconnects to different found versions, and the SPEC's "say what actually differs" is not implemented

**Claim.** `daemon.py:1296-1302`: `_on_version_mismatch` appends a note to `mismatch_notes[name]` and rebuilds `server.instructions` from `base_instructions + all mismatch_notes`. The note is keyed by upstream name, so a second mismatch on the same upstream (e.g. the upstream was at version A, then B, then C across reconnects) overwrites the previous note for that name. But if the upstream oscillates between versions A and B (e.g. two Xcode installs switching back and forth), the note flips between "found A" and "found B" on each reconnect, and each new session's initialize sees whichever note was last written — which may not match the version the upstream is currently running if the reconnect happened between the mismatch fire and the next session initialize. The SPEC also says "Say what actually differs, not just that numbers differ" and asks for naming the blocks and maps that no longer resolve. The implementation only says "Blocks and renames may reference tools that moved" — generic, not specific.

**File:line.** `daemon.py:1296-1302` (the note construction); SPEC.md "Say what actually differs, not just that numbers differ."

**Failure scenario.** An upstream flaps between version A and version B. A client initializes and sees a mismatch note saying "found B" when the upstream is now at A. The note is stale relative to the live connection. The SPEC's actionable warning ("2 blocked tools and 1 rename no longer match") is not delivered — the model gets a generic suggestion to run the comparison tool.

**Fix.** Re-check the version on each new session's initialize (not just on reconnect) and update the note from the live session, not from the last reconnect's observation. For the SPEC compliance: call `mcp_tools.py compare` (or an inline version of it) to list the specific blocks and maps that no longer resolve, and include that in the note. This is a SPEC gap, not a crash.

**What I read vs infer.** I read the note construction and the SPEC passage. The SPEC says "compatible with 24952, found 24953; 2 blocked tools and 1 rename no longer match anything" is the desired shape. The implementation says "consider having a human run the collision comparison." I infer the SPEC is aspirational here — the comparison tool may not exist yet in a callable form.

---

## 9. `kill` without `-TERM`-then-`-KILL` escalation may not be enough for a wedged daemon, and `sleep 1` may not be enough for the socket to be released

**Claim.** `repo-daemon-run.sh:30` sends `kill "$pid"` (SIGTERM) to the stale daemon and then `sleep 1` before probing the port. If the daemon is wedged (the exact scenario `stall_watchdog` exists for — stdio_client teardown waiting on a child that will not exit), SIGTERM may not be handled if the event loop is blocked. The `sleep 1` assumes the socket is released within 1 second of SIGTERM, but a wedged process may not close its file descriptors promptly. The `lsof` probe at line 33 then finds the port still in use, steps past it, and the repo gets a different port — losing the deterministic port stability the design intends.

**File:line.** `repo-daemon-run.sh:30-31` (kill + sleep), `repo-daemon-run.sh:33` (lsof probe).

**Failure scenario.** The daemon is wedged (stall_watchdog has not fired yet, or the process is stuck in `__aexit__` of `stdio_client`). `kill` sends SIGTERM. The Python process does not handle it because the event loop is blocked. `sleep 1` passes. `lsof` still sees the port in LISTEN. The script steps past the base port and assigns a different port. The repo's port changes, `.mcp.json` is rewritten, and existing clients are disconnected.

**Fix.** Send SIGTERM, wait with a timeout (e.g. `kill "$pid"; for i in 1 2 3 4 5; do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done`), then `kill -9` if still alive. This matches the stall_watchdog's own philosophy of escalating to `os._exit` when the process is stuck.

**What I read vs infer.** I read the kill and sleep. I infer a wedged daemon may not handle SIGTERM — the stall_watchdog comment documents the exact `__aexit__` wedge. I have not measured the socket release timing after SIGTERM on a wedged process.

---

## 10. The `move_on_after(1)` broadcast may leave a half-written SSE frame on the client's GET stream

**Claim.** `daemon.py:951-953`: `with anyio.move_on_after(1): await session.send_tool_list_changed()`. If `send_tool_list_changed()` is mid-write to the client's HTTP response stream when the 1-second timeout fires, `anyio.move_on_after` cancels the await. The underlying ASGI/uvicorn send may have partially written the SSE frame (`data: {"jsonrpc":"2.0","method":"notifications/too` — truncated). The client receives a malformed SSE event and may either silently ignore it or, depending on its SSE parser, error out and close the stream.

**File:line.** `daemon.py:951-953`.

**Failure scenario.** A slow client (network congestion, paused process) cannot drain its GET stream within 1 second. The broadcast starts writing the SSE event, the timeout fires mid-write, and the frame is truncated. The client's SSE parser sees a partial `data:` line and either drops it or raises a parse error.

**Fix.** Check whether the SDK's `send_tool_list_changed` writes atomically (a single `await send()` call that either completes or does not start). If the SDK fragments the write, the timeout can truncate it. Alternatively, remove the session from the registry on timeout (see finding 4) and accept that a timed-out send is a dead client.

**What I read vs infer.** I read the `move_on_after` usage. I have not traced the SDK's `send_tool_list_changed` to confirm whether it issues a single atomic write or fragments the SSE frame across multiple writes. If it is a single `await send()`, the timeout either fires before the write starts (clean) or the write completes (clean) — no truncation.

---

## Verified non-findings

**`id(connection)` key reuse causing a stale broadcast to the wrong client.** The practical risk is low. The `_connection` object is managed by the SDK's session manager, and the reuse window requires a specific memory allocation pattern (a new connection allocating at exactly the address of a recently GC'd one). Even if it occurs, the consequence is a spurious `list_changed` notification to the new client, which is harmless (it re-lists). See finding 5 for the full analysis.

**`cksum` port collision distribution across ~15 repos.** I computed the actual `cksum` output for 15 plausible repo paths. All 15 landed on distinct ports in the 21000–23999 range with no collisions. The `cksum` CRC32 provides good distribution for these paths. The 3000-port range is adequate for the current repo count.

**The notification relay's debounce under a flapping upstream.** The `anyio.Event` + `anyio.sleep(0.5)` debounce at `daemon.py:1330-1335` is correct for the burst case: multiple `_fire_surface_changed` calls set the event, the broadcaster wakes, resets the event, sleeps 0.5s (coalescing further sets into the same window), then broadcasts once. A flapping upstream that fires `listChanged` every 100ms produces one broadcast per 0.5s, not a storm. The design is sound.

**The `_on_upstream_message` handler type check.** `isinstance(message, types.ToolListChangedNotification)` at `daemon.py:517` is correct — the SDK's `_handle_server_notification` at `session.py:1486` passes the typed notification object (after validation) to `message_handler`, and `ToolListChangedNotification` is a `ServerNotification` subclass. The handler also receives `Exception` items on transport faults, but the `isinstance` check correctly filters those out.

---

## Test honesty assessment

**The notification relay test (`test-mcp-front-daemon.sh` Phase 4.1 section).** The test opens a GET stream, triggers `list_changed` via the stub's `--emit-list-changed-on-call` flag, and asserts `notifications/tools/list_changed` appears in the stream output. This is an effect assertion (the notification actually reached the client's stream), not a mock. The 15-second timeout (`--max-time 15`) is generous enough for the debounce window. The test does NOT verify that the `listChanged: true` capability is what the client acted on — it checks the initialize response body for `"listChanged":true`, which is the handshake path. Finding 1 above shows the discover path is untested.

**The version mismatch test (`test-mcp-front-daemon.sh` Phase 4.2 section).** The test configures `"version": "9.9.9"` and the stub reports `1.0-stub`. It asserts the mismatch appears in `init.out` (in-band via instructions), in `daemon.log` (human log), and in `version-mismatches.json` (persisted). The test also asserts the persisted file contains the found version. This is effect-based. However, the test does NOT verify that a RECONNECT to a different found version updates the note correctly (finding 8), and it does NOT test the unbounded-growth concern (finding 7) — both are deferred gaps, not tautologies.

**The repo-daemon test (`test-mcp-front-repo-daemon.sh`).** The test verifies the installer places files, the launchd plist parses, the port is deterministic, `.mcp.json` is written, a second repo steps past a squatter, self-preemption keeps the port stable, and the foreign listener is left alone. The collision test uses a Python socket squatter, not a real daemon — this is correct (it isolates the stepping-past behavior from the self-preempt behavior). The test does NOT cover the TOCTOU race (finding 6) or the crash-loop (finding 3) — both would require concurrent launches or a loaded plist, which are harder to test deterministically.

**RED control.** The `red` assertion at `test-mcp-front-repo-daemon.sh:26` verifies the installer refuses HOME with exit code 64 and the word "refusing" — this is a proper RED control (the command must fail with the expected code and diagnostic). The test suite follows the lib.sh doctrine.

**Timing assumptions.** The `sleep 1` between preempt and probe in the test (`test-mcp-front-repo-daemon.sh:67`) mirrors the `sleep 1` in `run.sh:31`. If the sleep is too short on a loaded machine, the test flakes — but this is a test-environment concern, not a code defect. The `--max-time` timeouts (10s for curl, 15s for the stream) are generous.
