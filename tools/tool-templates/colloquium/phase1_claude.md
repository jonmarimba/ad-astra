Cleanup done — no probe daemons left running. Here is the review.

I read `mcp_config.py`, `daemon.py`, both new tests, `stub_mcp_server.py`, `run-all.sh`, `lib.sh`, `xcode-combined-front-run.sh` and the ROADMAP in full, and I read the resolved `mcp` 2.1.1 SDK sources for the three questions that depend on library behaviour. Everything marked *measured* below is from a probe daemon I booted against stub upstreams on scratch ports; everything else is from the source.

## 1. A hung or merely busy upstream still blanks the entire surface, then kills the process about three minutes later

`Upstream.list_tools` takes `self.lock` at `daemon.py:480` and only then opens the 600-second window at `:491`. `call_tool` takes the same lock at `:515`. `on_list_tools` awaits each upstream in sequence at `:746-747`. So the aggregate list is serialised behind every upstream's in-flight call, and the 1.4 fix only covers an upstream that fails *fast*.

Measured, with one healthy stub and one `--stall-tools` stub: a client `tools/list` returned nothing for the full 40 seconds I gave it, while the healthy upstream sat connected the whole time. Measured separately, with a stub whose `tools/call` sleeps 25 seconds: a second client's `tools/list` took 23.0 seconds and the healthy upstream's tools were withheld for all of it. With the real 600-second `CALL_TIMEOUT_SECONDS` (`:182`) and a real `xcode__BuildProject`, any client that connects during a build gets no tool list at all until the build ends.

It gets worse. The heartbeat marks the upstream broken and breaks out, but the reconnect loop's `async with self.lock: self.session = None` at `:673-674` then blocks behind the same held lock, so `last_progress` stops advancing and `stall_watchdog` calls `os._exit(75)` at `:577`. Measured: the process exited 185 seconds after the stall, taking the healthy upstream down with it. One downstream `tools/list` arriving during one upstream's approval-dialog gate is enough to restart the whole daemon, which in production costs a fresh Xcode approval.

Fix: bound the lock acquisition, not just the call — wrap the whole `list_tools` body in a short `fail_after` (the heartbeat already uses `CONNECT_TIMEOUT_SECONDS` for the identical operation at `:642`), and run the per-upstream lists concurrently in a task group instead of the sequential loop at `:746`.

## 2. The stall watchdog asserts a cause that is wrong in the case above

`daemon.py:572-576` logs "almost certainly blocked in stdio_client teardown waiting on an mcpbridge child that will not exit." In the scenario I measured it was blocked on the daemon's own `self.lock`, held by a client-triggered drain. A future diagnosis reads that line and goes after the child process, which is the wrong component.

Fix: record which of the two waits is outstanding (a flag set around the lock-held region) and name it in the message, or soften the claim to "the reconnect loop made no progress" and list both candidates.

## 3. The pagination drain has no bound except the timeout

`daemon.py:492-497` loops on `page.next_cursor` with no seen-cursor set, no page cap and no tool cap. Measured against a stub that returns one tool plus a fresh cursor forever, with `CALL_TIMEOUT_SECONDS` forced to 10: the daemon drained **48,075 pages in 10 seconds**. At the 600-second default that is roughly 2.9 million pages accumulated in one list, which will exhaust memory long before the timeout fires. A cursor that simply repeats is the same shape and is a common upstream bug.

Fix: keep a `seen` set of cursors and break with a named error on a repeat, cap total pages (a few hundred is generous), and bound the drain by a list-sized timeout rather than the build-sized one.

## 4. A single-upstream config file silently discards its declared prefix

`daemon.py:713` forces the prefix to `""` whenever `len(upstreams) == 1`, overriding whatever the config said. Measured with a one-server `_mcp_info.json` carrying `"prefix": "solo__"`: `mcp_config.py validate` prints `prefix=solo__`, and the daemon serves the tool as bare `ping`. The validator and the daemon disagree about the same file.

This is colloquium defect 2, named in the roadmap's own words at `ROADMAP.md:12` — "prefixes also change when the upstream *count* changes… so adding a second server silently renames every tool the first one offered" — and increment 1.3 closed without fixing it. Failure scenario: a template ships a one-upstream config with a prefix, clients are wired to `xcode__BuildProject`, every call fails as unknown; then someone adds a second upstream and the first upstream's entire surface renames itself. Phase 3's map keys off exposed names, so a map written against a two-upstream file breaks the moment one server is commented out.

Fix: delete the `single` special case in `prefix_of` and honour `spec.prefix` always; give the env fallback in `resolve_specs` an explicit `prefix=""` and let `_check_prefixes` keep allowing an empty prefix when it is the only one.

## 5. The cursor refusal loses its message on the modern wire and never carries the spec's error code

`on_list_tools` raises a bare `ValueError` at `daemon.py:740-742`. `handler_exception_to_error_data` (`mcp/shared/jsonrpc_dispatcher.py:98-102`) maps only `MCPError` and pydantic `ValidationError`, so a `ValueError` falls to each transport's catch-all. Measured on the same daemon:

- protocol `2025-06-18` → `{"code":0,"message":"…issued no cursor; got unexpected cursor 'bogus'"}`. The message survives, but `0` is not a JSON-RPC error code at all.
- protocol `2026-07-28` → `{"code":-32603,"message":"Internal server error"}`. The message is discarded (`mcp/server/runner.py:534-548`) and only logged server-side.

The modern path is reachable today: `streamable_http_manager.py:180-183` routes any non-handshake protocol version there. On refusing at all — that is spec-legal, and the spec asks for `-32602` on an invalid cursor, which the current code never returns on either path.

Fix: `raise MCPError(INVALID_PARAMS, "<same message>")` from `mcp.shared.exceptions`. That maps through the shared ladder on both transports, keeps the message, and gives the spec code.

## 6. The single-upstream instructions text claims to be Apple's bridge regardless of what the upstream is

`daemon.py:802-824` hardcodes "This is a persistent proxy in front of Apple's own Xcode MCP bridge (`xcrun mcpbridge`) — same tools it exposes", plus a paragraph about other Xcode-adjacent servers. Before 1.2, `single` meant the env-var mode, which really was mcpbridge by default. Now it also fires for any one-server config file. Measured: a one-upstream config running a Python stub was described to the client as Apple's bridge.

To answer the review question directly — this is the lie 1.2 introduced, not one 1.4 introduced. The multi-upstream text at `:826-835` is accurate as written.

Fix: derive the text from the spec (name the upstreams and their commands) and keep the mcpbridge paragraph only when a `require_xcode` upstream running `xcrun mcpbridge` is actually present.

## 7. A partial list has no client-visible signal, and the daemon tells clients not to expect one

`daemon.py:760-763` logs the unavailable upstreams and returns the rest. Measured on the initialize response: `"tools":{"listChanged":false}`. That is derived correctly by the SDK (`server.py:602`, since the daemon serves no `subscriptions/listen` and passes no `NotificationOptions`), so it is not a protocol lie — but it is a promise that the list will not change, made about a list that now genuinely changes. A client that lists once at connect and caches, which is the normal client, sees 29 tools instead of 50 for its whole session and concludes the 21 do not exist. Nothing tells it otherwise until Phase 4.

Fix, cheap and available now: name the configured upstream set in the `instructions` string, with a sentence saying that an upstream missing from the tool list is reconnecting and that re-listing will pick it up. The client then has something to compare the surface against.

## 8. Unknown top-level config keys are accepted silently

`mcp_config.py:107` reads `cfg.get("mcpServers")` and never looks at any other top-level key, so the "EVERYTHING ELSE IS REJECTED BY NAME" policy at `:14` is enforced per-server only. Measured: a file with `denyList` and `toolMap` at top level validates with rc 0.

Phase 2's sieve and Phase 3's map land at top level. A typo there means the sieve silently does not apply, and tools the author believes are blocked stay exposed — the failure mode Phase 2 exists to prevent. Fix it now, while the only legal top-level key is `mcpServers`: reject any other, same wording as the per-server branch.

## 9. Rejecting `env` leaves no mechanism at all, not a different one

`mcp_config.py:35` rejects `env` on the grounds that "the wrapper passes only command and args to the child". There is no alternative to fall back on: `daemon.py:588` builds `StdioServerParameters(command, args)` with `env=None`, and `mcp/client/stdio.py:128` then passes `get_default_environment()`, an allowlist of six variables (`mcp/client/stdio.py:56`). Measured, with a stub that dumps its own environment: the child received `HOME, LC_CTYPE, LOGNAME, PATH, SHELL, TERM, USER, __CF_USER_TEXT_ENCODING` and nothing else. `XCODEMCP_ALLOWED_FOLDERS` set in the daemon's environment did not reach it.

So the daemon's own docstring at `:68-69` names an upstream auth mechanism the config forbids configuring, and `_load_config_file` at `:131-148` reads a config file whose entries are scrubbed before they reach any child. This is the field I would expect to be walked back first.

Fix: implement it rather than reject it — `env=spec.env or None` in `StdioServerParameters` is the whole change, and Jonathan's "sharper edges can cut off fingers" answer in the roadmap covers the objection.

## 10. The test that claims to separate connected-but-empty from disconnected cannot tell them apart

`test-mcp-front-daemon.sh:154-155` asserts that `delta__` is absent from the tool list. That is true when delta is connected with zero tools and equally true when delta is disconnected, so the assertion passes against an implementation that got 1.4 exactly backwards. Measured: the only observable that separates them is the warning line, which names `gamma` and not `delta` — and no test reads it.

The daemon test also carries no `red` control, against `lib.sh:8-9` ("every test file carries at least one"), and nothing in `run-all.sh` enforces that rule.

Fix: assert on `daemon2.log` that the unavailable-upstream warning names `gamma` and does not name `delta`. Add a red control — the `--stall-tools` stub is already built for it and is currently exercised only by `test-mcp-tools.sh`, which is a different subject.

## 11. Duplicate exposed names are not rejected at composition

Increment 1.3 asked for "duplicate prefixes, duplicate exposed names, and prefixes that are prefixes of each other". The first and third are enforced at load; the second is not. `daemon.py:756` does `new_dispatch[t.name] = (u, bare)`, which silently overwrites, while `:757` appends both to the surface. This became reachable with 1.5: an upstream that mutates its tool list between drained pages produces a snapshot with the same tool twice, where the old truncating code showed one.

Fix: skip and log a duplicate in the composition loop.

## Checked and correct

- **The adjacent-pair prefix check is complete.** `mcp_config.py:135-141` compares only neighbours in sorted order, which looks like a gap and is not: if `a ≤ b ≤ c` lexicographically and `a` is a prefix of `c`, then `b` starts with `a` too, so a non-adjacent violation cannot exist without an adjacent one.
- **Cross-upstream exposed-name collisions are impossible** given that check, which is why item 11 above is only about duplicates *within* one upstream.
- **`dispatch.clear()` then `update()` at `:758-759` is atomic.** There is no `await` between them, so no concurrent `tools/call` can observe the empty window.
- **Dispatch staleness fails honestly.** A stale entry routes to the same upstream, which either answers its own unknown-tool error or returns `None` and produces `[name] not connected right now`. The prefix fallback at `:773-777` cannot misroute given the validated prefix set — the first match is the only match.
- **The fast tier holds its budget.** `test-mcp-front-daemon.sh` boots two `uv run` daemons over real HTTP and finishes in 2.5 seconds against the 15-second budget.
- **1.4 works as advertised for the fail-fast case,** which is what the test covers: a dead `gamma` contributed nothing, `alpha` kept serving, and the warning named gamma alone.
