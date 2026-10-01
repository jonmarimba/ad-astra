Now I have all the evidence I need. Here is my review.

---

## Findings

### 1. CORRECT NON-FINDING: `page.next_cursor` attribute name is correct

A reviewer who knows pydantic's default behavior (field name = attribute name, not alias) might flag line 496 (`cursor = page.next_cursor`) as wrong, since `PaginatedResult` declares the field as `nextCursor: Cursor | None = None`. I verified by instantiating `ListToolsResult` from the installed `mcp` package: the attribute IS `next_cursor`, not `nextCursor`. The mcp library's pydantic config maps the camelCase JSON alias to the snake_case Python attribute. The code is correct.

### 2. CORRECT NON-FINDING: Cursor refusal surfaces as a JSON-RPC error with the message

The daemon raises `ValueError` on an unexpected cursor (line 741). I traced the exception path through the installed mcp library: `JSONRPCDispatcher` catches it at `jsonrpc_dispatcher.py:752`, `handler_exception_to_error_data` returns `None` for a plain `ValueError`, and the dispatcher falls through to `ErrorData(code=0, message=str(e))` at line 757. The client receives a JSON-RPC error object with the full message text. The `code=0` is non-standard (should be `INTERNAL_ERROR` per JSON-RPC 2.0), but the message is not lost. The test assertion `assert_contains "$SB/cursor.out" "error"` passes for the right reason — the response contains `"error"` as a JSON-RPC key, and the message text is included. The cursor refusal is spec-legal for a server that never issues `nextCursor`.

### 3. CORRECT NON-FINDING: A connected-but-empty upstream is distinguished from disconnected

The `Upstream.list_tools` method returns `None` on disconnected/failed (line 506) and `ListToolsResult(tools=[])` on connected-but-empty (line 498). The `on_list_tools` handler checks `if result is None` (line 751) to skip unavailable upstreams and log them, while a connected upstream returning zero tools contributes zero tools to the aggregate. The test covers this directly: `delta` connects and has zero tools, `gamma` dies instantly, and `alpha` keeps serving. The assertions check `alpha__ping` is present, `gamma__` is absent, and `delta__` is absent. This is correct.

### 4. The pagination drain holds the upstream lock for up to 600 seconds, blocking the heartbeat

**Claim:** `Upstream.list_tools` (line 483-505) drains all pages inside `self.lock` under a single `anyio.fail_after(CALL_TIMEOUT_SECONDS)` (600s). While this drain is in progress, no other call to this upstream can acquire `self.lock` — not a `tools/call`, and not the heartbeat in `connection_manager` (line 603, which calls `session.list_tools()` without acquiring `self.lock` — but that's a separate issue). The heartbeat's `list_tools` call is NOT under `self.lock`, so it can run concurrently with the drain. However, the drain itself blocks the `on_list_tools` caller for up to 600s, and since `on_list_tools` is a single handler that iterates all upstreams sequentially (line 749-756), a slow-draining upstream delays the entire aggregate surface for up to 600s.

**Evidence:** `daemon.py:484` (`async with self.lock:`), `daemon.py:493` (`with anyio.fail_after(CALL_TIMEOUT_SECONDS):`), `daemon.py:749` (`for u in upstreams: result = await u.list_tools(None)`).

**Failure scenario:** An upstream that paginates slowly (or an upstream whose `nextCursor` cycles, creating an infinite loop) holds the `on_list_tools` handler for the full 600s timeout. During this time, the daemon's HTTP endpoint appears hung for `tools/list`. The heartbeat at line 603 runs concurrently (it does not acquire `self.lock` for `session.list_tools()`), so it can still detect a dead upstream — but a pathological upstream that responds quickly with endless pages keeps the drain alive for the full 600s, making the aggregate surface unresponsive.

**Proposed fix:** Bound the drain with a page count or total tool count limit, not just a wall-clock timeout. A 600s timeout is the right ceiling for a single legitimate long call, but a drain that fetches thousands of pages in seconds is pathological and should be cut early. Consider a secondary limit on page count (e.g. 100 pages) as a safety valve.

### 5. Dispatch-table staleness: a stale entry routes to a dead or changed upstream

**Claim:** The dispatch table is rebuilt only inside `on_list_tools` (line 754-755: `dispatch.clear(); dispatch.update(new_dispatch)`). Between the last `tools/list` and the next, an upstream can disconnect, reconnect with a different tool set, or die entirely. A `tools/call` for a name in the stale dispatch table routes to the upstream's `call_tool`, which returns `None` if `self.session is None` (line 522), producing the "not connected right now" error — which is honest. But if the upstream reconnected with a *different* tool set, the stale entry maps the exposed name to a bare name that no longer exists on the upstream. The upstream returns a JSON-RPC error for the unknown tool, which is forwarded as-is.

**Evidence:** `daemon.py:754-755` (dispatch rebuilt only on `tools/list`), `daemon.py:765-766` (dispatch consulted first on `tools/call`), `daemon.py:522` (`if self.session is None: return None`).

**Failure scenario:** Upstream `alpha` lists tools `ping` and `build`. The dispatch table maps `alpha__ping` to `(alpha, "ping")`. Alpha disconnects and reconnects, now serving only `pong`. A client calls `alpha__ping`. The dispatch table still has the stale entry, so it routes to `alpha` with bare name `ping`. Alpha's upstream returns an error for the unknown tool `ping`. The client sees an upstream error message, not the daemon's "not connected" message — which is misleading, since the tool genuinely no longer exists, but the client cached it from the old list.

**Severity:** Medium. The failure is honest (an error is returned), but the message points at the upstream rather than the daemon's stale table. The prefix fallback (line 767-770) is not reached for a stale dispatch entry, so it never gets a chance to re-discover. This is acceptable for Phase 1 (the roadmap says `listChanged` forwarding is Phase 4), but it means a client's cached list can go stale with no notification.

**Proposed fix:** No code change needed for Phase 1 — this is the documented gap that Phase 4 (`listChanged` forwarding) closes. The dispatch-table-first lookup is the right order; the fallback exists for the "never listed" case. The stale-entry case is bounded by the next `tools/list` call, which rebuilds the table.

### 6. The prefix fallback can misroute after a `tools/list` that removes a tool

**Claim:** If an exposed name was in the dispatch table but the upstream removed that tool on the next `tools/list`, the dispatch table is rebuilt without it. A subsequent `tools/call` for the old name misses the dispatch table and falls through to the prefix walk (line 767-770). The prefix walk routes by `name.startswith(prefix)`, which sends the call to the upstream with the bare name. This is a *convenience* that routes to the right upstream but calls a tool the upstream no longer has.

**Evidence:** `daemon.py:767-770` (prefix fallback after dispatch miss), `daemon.py:754-755` (dispatch rebuilt without removed tools).

**Failure scenario:** Upstream `xcode` lists `BuildProject`. Dispatch maps `xcode__BuildProject`. Xcode is updated and `BuildProject` is renamed to `RunBuild`. The next `tools/list` rebuilds dispatch without `xcode__BuildProject`. A client that cached the old list calls `xcode__BuildProject`. It misses dispatch, hits the prefix fallback, routes to `xcode` with bare name `BuildProject`, and gets an upstream error for an unknown tool. The prefix fallback was a convenience but produced a misroute in the sense that it forwarded a call the daemon already knew was invalid from the last listing.

**Severity:** Low. The upstream returns an error either way. The prefix fallback exists explicitly as a convenience for names not yet listed in this daemon's lifetime (line 723-724), and the comment is honest about its role. The misroute is not worse than rejecting the call.

**Proposed fix:** Once Phase 3's rename map lands, a name that was mapped but is no longer in the dispatch table should be rejected outright, not forwarded via prefix fallback. For now, the fallback is acceptable since the upstream error is the same either way.

### 7. The degraded-surface `instructions` text does not mention that some upstreams may be unavailable

**Claim:** The multi-upstream `instructions` text (line 817-825) says "each upstream has its own independent connection" and "a short retry should work," but never says that `tools/list` may return a partial surface when an upstream is disconnected. A client that caches the partial list has no textual signal that tools are missing, only the log warning on the server side (which the client never sees).

**Evidence:** `daemon.py:817-825` (multi-upstream instructions), `daemon.py:757-759` (warning logged but not in instructions), `daemon.py:746` (returns `ListToolsResult(tools=all_tools)` with no `nextCursor` and no unavailable annotation).

**Failure scenario:** Xcode is restarting. `tools/list` returns only Drew's 29 tools. The client caches this. Xcode reconnects, but the client never calls `tools/list` again (no `listChanged` notification until Phase 4). The client's cached list is missing 21 tools, and the `instructions` text gave no warning that this could happen.

**Severity:** Medium for Phase 1, but this is the documented Phase 4 gap. The `instructions` text could be improved now by adding a sentence about partial surfaces.

**Proposed fix:** Add to the multi-upstream instructions: "If fewer upstreams are connected at startup, the tool list reflects only those currently available. A subsequent `tools/list` will include tools from upstreams that have reconnected." This costs nothing and sets the client's expectation correctly.

### 8. Config loader: `_check_prefixes` does not catch a single-upstream config with an empty prefix

**Claim:** `_check_prefixes` short-circuits for `len(specs) < 2` (line 113-114: `if len(specs) < 2: return`). This means a single-upstream config with `prefix: ""` passes validation, which is correct for single-upstream mode (the daemon uses empty prefix). But if a second upstream is added to the same file later, the empty prefix beside another upstream becomes unroutable — the check that catches this (`_check_prefixes` line 120-123) only runs when there are already two or more specs. The check is correct for the current file; the concern is whether a future edit that adds a second upstream to a file that had one with `prefix: ""` will be caught. It will, because the check runs on the new two-spec list. This is actually correct.

**Evidence:** `mcp_config.py:113-114` (short-circuit for single spec), `mcp_config.py:120-123` (empty-prefix check for 2+ specs).

**Verdict:** Correct. A single upstream with `prefix: ""` is the legitimate single-upstream-mode config. Adding a second upstream triggers the check. No fix needed.

### 9. Config loader: the `UNIMPLEMENTED_FIELDS` list will need revision when Phase 2/3 add sieve and map stanzas

**Claim:** The config loader rejects unknown fields by name (`mcp_config.py:72-73`). Phase 2 adds a `deny` or `sieve` stanza per upstream; Phase 3 adds a `map` or `rename` stanza. These will need to be added to `IMPLEMENTED_FIELDS` (line 43). The current rejection of unknown keys means a Phase 2 config that adds a `deny` field will fail at load with `unknown field 'deny'`, which is the right behavior — it forces the loader to be updated before the config can use the field. No walk-back will be needed because the rejection is explicit and names the field.

**Evidence:** `mcp_config.py:43` (`IMPLEMENTED_FIELDS = frozenset({"command", "args", "prefix", "quirks"})`), `mcp_config.py:72-73` (unknown field rejection).

**Verdict:** Correct design. The rejection-by-name policy means new fields are added deliberately, not silently. No fix needed.

### 10. Test honesty: the degraded-surface test's wait loop could pass against a broken implementation

**Claim:** The degraded-surface test (test-mcp-front-daemon.sh, line 91-101) waits for the daemon's HTTP to answer, then polls up to 8 seconds for `alpha__ping` to appear. If `alpha` never connects (e.g., a real bug in the connection manager), the loop exits after 8 seconds and the assertion `assert_contains "$SB/dlist.out" "alpha__ping"` fails — which is the right behavior. But the test does not assert that `gamma` (the dead upstream) actually tried to connect and failed. It only asserts `gamma__` is absent from the list. If gamma's connection manager had a bug that prevented it from even trying, the test would still pass, because `gamma__` would still be absent. This is a gap in coverage, not a tautology.

**Evidence:** `test-mcp-front-daemon.sh:83-90` (gamma config: `sys.exit(1)`), `test-mcp-front-daemon.sh:103` (`assert_not_contains "$SB/dlist.out" "gamma__"`).

**Failure scenario:** A bug in `_build_upstreams` that drops gamma entirely (e.g., a config loader that skips servers with invalid args) would make gamma never connect, `gamma__` would be absent, and the test would pass. The test does not verify that gamma was even attempted.

**Severity:** Low. The config loader is tested separately (test-mcp-front-config.sh), so a dropped server would be caught there. The daemon test focuses on the aggregation behavior, not the config parsing.

**Proposed fix:** Assert that the daemon log contains a connect-attempt line for gamma, confirming the daemon tried and failed rather than never trying. One `assert_contains "$SB/daemon2.log" "gamma" "gamma was attempted"` suffices.

### 11. Test honesty: the cursor-refusal test does not verify the error code

**Claim:** The cursor-refusal test (test-mcp-front-daemon.sh, line 73-74) asserts `assert_contains "$SB/cursor.out" "error"`. This passes for any JSON-RPC error, including an unrelated error (e.g., a transport error from a bad request shape). The test does not verify that the error message contains the cursor text or the daemon's name, so a generic 500 error would also pass.

**Evidence:** `test-mcp-front-daemon.sh:73` (`assert_contains "$SB/cursor.out" "error"`).

**Failure scenario:** A bug that causes `tools/list` with any params to fail with a generic error (e.g., a params validation error) would pass this assertion, because `"error"` appears in any JSON-RPC error response.

**Proposed fix:** Assert the response contains a substring from the daemon's error message, e.g. `assert_contains "$SB/cursor.out" "unexpected cursor"` or `assert_contains "$SB/cursor.out" "bogus-cursor"`. This verifies the refusal was for the cursor specifically, not a generic failure.
