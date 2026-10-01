I've read all the relevant files in full. Here are my findings.

---

## Phase 2/3 review — sieve and map

### Finding 1 — Sieve bypassed at call time in passthrough mode

**Claim:** A blocked tool is hidden from `tools/list` but remains callable via `tools/call` when the daemon is in passthrough mode (single upstream, empty prefix).

**Evidence:** `daemon.py:848` sets `passthrough = upstreams[0] if single and upstreams[0].prefix == ""`. In `on_list_tools`, the sieve applies unconditionally (line 919: `if bare in u.blocks: continue`), so the blocked tool is absent from the listing. But in `on_call_tool` (lines 1029–1033), when `candidate is passthrough`, the code forwards the call directly to the upstream without checking `candidate.blocks`:

```python
if candidate is passthrough:
    result = await candidate.call_tool(name, params.arguments)
    if result is None:
        return _not_connected_result(candidate)
    return result
```

The block check at line 1037 (`if bare in candidate.blocks`) is reached only for non-passthrough candidates.

**Failure scenario:** A config file with `{"mcpServers": {"solo": {"command": "c", "prefix": "", "block": [{"tool": "dangerous", "why": "limiting"}]}}}` loads and validates — `_check_prefixes` (line 207) returns early for a single spec, so empty prefix is accepted. The daemon sets `passthrough`. A model that knows the name `dangerous` from a prior session calls it and the call reaches the upstream, sieve defeated. This is the exact "listing filter is decoration" defect the ROADMAP (2.1) says the sieve must prevent.

**Proposed fix:** If `passthrough` is set and the upstream has non-empty `blocks` or `maps`, either refuse to start (passthrough is documented as env-var-only, which never carries blocks) or fall through to the normal dispatch path instead of the passthrough shortcut.

### Finding 2 — `_refresh_upstream_dispatch` silently overwrites dispatch entries

**Claim:** The refresh path called on `tools/call` for a dispatch miss can overwrite another upstream's dispatch entry without collision detection, silently rerouting a working tool.

**Evidence:** `daemon.py:974–986`:

```python
async def _refresh_upstream_dispatch(u: Upstream) -> bool:
    result = await u.list_tools(None)
    if result is None:
        return False
    prefix = prefix_of[u]
    for t in result.tools:
        if t.name in u.blocks:
            continue
        entry = u.maps.get(t.name)
        exposed = entry.exposed if entry else f"{prefix}{t.name}"
        dispatch[exposed] = (u, t.name)
    return True
```

`on_list_tools` has collision degradation (lines 933–946): when a mapped name collides with an already-published name, it drops the alias and serves the prefixed original, logging a warning. `_refresh_upstream_dispatch` has none of this — it unconditionally overwrites.

**Failure scenario:** `on_list_tools` composes the dispatch table with proper collision handling: `dispatch["shared_name"] = (alpha, "read")`. A call arrives for `beta__unknown` (not in dispatch). The prefix walk finds beta. `_refresh_upstream_dispatch(beta)` runs. Beta now offers a tool that, mapped or prefixed, produces the exposed name `shared_name`. The refresh overwrites `dispatch["shared_name"] = (beta, "other")`. Subsequent calls to `shared_name` route to beta instead of alpha, silently. No warning is logged.

**Proposed fix:** In `_refresh_upstream_dispatch`, check `if exposed in dispatch` before overwriting. If the entry belongs to a different upstream, skip it (or apply the same collision degradation as `on_list_tools`).

### Finding 3 — `_refresh_upstream_dispatch` leaves stale dispatch entries

**Claim:** The refresh path adds entries to the dispatch table without removing the candidate upstream's old entries, so a tool renamed between the last `on_list_tools` and a refresh leaves a stale route.

**Evidence:** Same function, lines 974–986. It iterates `result.tools` and adds `dispatch[exposed] = (u, t.name)` for each. It never removes entries for tools the upstream no longer offers. `on_list_tools` avoids this by building `new_dispatch` from scratch and swapping (`dispatch.clear(); dispatch.update(new_dispatch)`).

**Failure scenario:** `on_list_tools` at T1: alpha offers `old_name` → `dispatch["alpha__old_name"] = (alpha, "old_name")`. Alpha's upstream renames `old_name` to `new_name` between T1 and T2. A call to `alpha__new_name` arrives at T2 — not in dispatch. `_refresh_upstream_dispatch(alpha)` adds `dispatch["alpha__new_name"] = (alpha, "new_name")` but does not remove `dispatch["alpha__old_name"]`. A subsequent call to `alpha__old_name` finds the stale entry, routes to `(alpha, "old_name")`, and the upstream returns an error for a tool it no longer offers.

**Proposed fix:** Before adding the refreshed entries, remove the candidate's existing entries from `dispatch` (or rebuild only that upstream's entries, as `on_list_tools` does for the whole table).

### Finding 4 — Dispatch table races between `on_list_tools` and `_refresh_upstream_dispatch`

**Claim:** The shared `dispatch` dict is mutated by both `on_list_tools` (clear + rebuild) and `_refresh_upstream_dispatch` (add) without synchronization. An `on_list_tools` that runs during a refresh's `await` can have its fresh entries overwritten by the refresh's stale result.

**Evidence:** `dispatch` is a closure variable (line 854). `on_list_tools` does `dispatch.clear(); dispatch.update(new_dispatch)` (lines 975–976). `_refresh_upstream_dispatch` does `dispatch[exposed] = (u, t.name)` (line 984) after an `await u.list_tools(None)` (line 976). In asyncio, the await yields control, allowing `on_list_tools` to run and rebuild dispatch. When the refresh resumes, it writes stale entries on top of the fresh dispatch.

**Failure scenario:** A `tools/call` triggers `_refresh_upstream_dispatch(alpha)` which awaits `alpha.list_tools()`. During that await, a `tools/list` from another client runs `on_list_tools`, rebuilding dispatch with alpha's current tool list. The refresh resumes with alpha's pre-rebuild tool list and re-adds entries for tools that `on_list_tools` just dropped (because they're gone). Those stale entries now route calls to non-existent tools until the next `on_list_tools`.

**Proposed fix:** Have `_refresh_upstream_dispatch` build a local dict and merge atomically, or guard the dispatch table with a lock (the upstream lock is already available — `candidate.lock`).

### Finding 5 — Load-time validation misses mapped name vs prefixed name collision on the same server

**Claim:** `_check_exposed_names` checks mapped exposed names against other servers' mapped names, but not against a non-mapped tool's potential prefixed name on the same or another server. A map entry whose exposed name matches a prefixed tool name causes the prefixed tool to be silently dropped at composition.

**Evidence:** `mcp_config.py:224–235` (`_check_exposed_names`) iterates only `s.maps.values()` — it never considers `s.prefix + bare_tool_name` for tools that are NOT mapped. In `daemon.py:933–946`, when the collision is detected at runtime, a non-mapped duplicate is silently skipped (`continue`).

**Failure scenario:** Server `alpha` maps `read` → `alpha__build` (the same string alpha's own `build` tool would be prefixed to). This passes load validation. At composition, alpha's `read` is processed first (mapped to `alpha__build`), occupying `new_dispatch["alpha__build"]`. When alpha's `build` is processed, `exposed = "alpha__build"` is already in `new_dispatch`. The `else` branch fires (line 943–946): "duplicate exposed name, keeping the first occurrence" — alpha's `build` is silently dropped. The model can never call `alpha__build` to reach the `build` tool; that name routes to `read` instead.

**Proposed fix:** In `_check_exposed_names`, also check each map entry's exposed name against the prefix + bare name pattern for all tools on the same server (or defer to the daemon to refuse this at composition with a named error rather than a silent drop).

### Finding 6 — `\b` word boundary fails for tool names starting or ending with non-word characters

**Claim:** The rename pattern uses `\b` anchors, which do not match at a boundary between two non-word characters. A tool name starting with `.` or `-` (or ending with one) will not be rewritten in descriptions in some contexts.

**Evidence:** `daemon.py:476–478`:

```python
self._rename_pattern = (
    re.compile(r"\b(" + "|".join(re.escape(old) for old in self.maps) + r")\b")
    if self.maps else None)
```

`\b` matches the transition between `\w` (`[a-zA-Z0-9_]`) and `\W`. If a tool name starts with `.` (a non-word char) and appears after a space (also non-word), there is no word boundary before the `.` — the pattern does not match.

**Failure scenario:** A tool named `.hidden` is mapped to `reveal_hidden`. A sibling tool's description says "call .hidden to inspect." The pattern `\b(\.hidden)\b` does not match at the `.` because both the preceding space and the `.` are non-word characters — no boundary. The description keeps the old name, misleading the model.

**Note:** MCP tool names in practice start with a letter or underscore, so this is a theoretical gap, not a live defect. But the code doesn't guard against it. Names with dots or dashes *inside* them (like `foo.bar` or `foo-bar`) work correctly because `\b` sits at the start and end of the whole pattern, and those names start and end with word characters.

**Proposed fix:** Use `(?<!\w)(...)(?!\w)` instead of `\b(...)\b` — negative lookbehind/lookahead for word characters handles non-word-character boundaries correctly.

### Finding 7 — Stale entry reporting never resets across flaps

**Claim:** `_stale_blocks_reported` and `_stale_maps_reported` are only added to, never cleared. A tool that disappears, reappears, and disappears again is reported stale only on the first removal.

**Evidence:** `daemon.py:955–968`. The staleness check is `set(u.blocks) - offered - u._stale_blocks_reported`. Once an entry is in `_stale_blocks_reported`, it's excluded from future checks even if the tool reappears and then disappears again.

**Failure scenario:** Alpha upgrades and removes `old_tool` (stale map entry reported once). Alpha rolls back (tool returns, map works). Alpha upgrades again (tool removed again). The second removal is silent because `"old_tool"` is already in `_stale_maps_reported`. An operator monitoring logs for staleness misses the second occurrence.

**Proposed fix:** When a previously-stale entry reappears in `offered`, remove it from `_stale_*_reported` so a subsequent disappearance is reported again.

### Finding 8 — Collision degradation's fallback can silently drop a tool

**Claim:** When a mapped name collides and the prefixed fallback also collides, the tool is silently dropped with only the first collision logged.

**Evidence:** `daemon.py:933–942`:

```python
if exposed in new_dispatch:
    if entry:
        log.warning(...)
        exposed = f"{prefix}{bare}"
        if exposed in new_dispatch:
            continue
```

The `continue` silently drops the tool. The log warning is only for the first collision (the mapped name), not for the second (the prefixed fallback).

**Failure scenario:** Server alpha maps `read` → `alpha__build` (collides with alpha's own `build` tool's prefixed name). In `on_list_tools`, the mapped `read` occupies `new_dispatch["alpha__build"]`. When `build` is processed, `exposed = "alpha__build"` collides. The fallback to `alpha__build` also collides (it's the same string). The `continue` drops `build` entirely. The model cannot call `build` under any name. The log only warns about the mapped collision, not about `build` being dropped.

**Proposed fix:** Log a second warning when the fallback also collides, naming the tool that was dropped. Or reject this configuration at load (see finding 5).

### Finding 9 — No automated gate between template authoring and daemon deployment

**Claim:** The strict/lenient split means a template that ships without running `validate` has the lenient runtime path as its only enforcement. A missing `why` becomes a warning and the block/map applies with a placeholder reason.

**Evidence:** `mcp_config.py:288` — `resolve_specs` calls `load(info, strict=False)`. The `validate` CLI (line 302) calls `load(argv[2])` with default `strict=True`. There is no pre-deployment hook, CI gate, or install-time check that forces `validate` to run before a config file reaches a daemon.

**Note:** This is by design (ROADMAP 2.2: "Enforce `why` at template-authoring time, not at daemon start"). The trade-off is deliberate. But the prompt asks about the hole, and it's real: a template author who skips `validate` ships a config where the `why` field is unenforced, and the daemon's warning on stderr may not be monitored. The block/map still applies, so the surface is shaped by a decision whose rationale is lost.

**Proposed fix:** Add a `validate` step to `astra-install.sh` when it places a config file, so the strict check runs at install time as a deployment gate, not just when a human remembers to run the CLI.

### Verified non-findings

**A tool both blocked and mapped is rejected at load.** `mcp_config.py:152` — `if tool in blocks: raise ConfigError(...)`. The call path's block check uses the wrong key for mapped names (it checks the exposed name against a dict keyed by bare names), but this can never fire because the combination is rejected before the daemon sees it. Correct.

**The old prefixed name of a mapped tool is refused on call.** When `read` is mapped to `fetch_file`, `_refresh_upstream_dispatch` adds only `dispatch["fetch_file"] = (alpha, "read")`, not `dispatch["alpha__read"]`. A call to `alpha__read` finds it's not in dispatch, the prefix walk finds alpha, the refresh runs but doesn't add the old name, and the final `if name not in dispatch` check returns "does not currently offer." Correct.

**The static map lookup on the call path finds the right upstream for a pre-first-list call.** `daemon.py:1003–1006` scans `u.maps.values()` for a matching exposed name. Load-time `_check_exposed_names` ensures no two servers claim the same exposed name, so the first match is the only match. Correct.

**Case sensitivity is consistent.** Tool names, blocks, and maps are all compared with case-sensitive dict lookups, matching MCP tool name semantics. Not a bug, though a config author who writes `block: [{"tool": "Read"}]` for a tool named `read` gets a silent no-op (the stale-block warning fires). This is a documentation problem, not a code defect.

**Concurrent `on_list_tools` calls don't corrupt dispatch.** Two `on_list_tools` coroutines both clear and rebuild dispatch, but asyncio processes them sequentially between await points. The last one wins, and dispatch is consistent. Not a race.

**The `on_list_tools` sieve applies after the availability check.** Line 913–914: unavailable upstreams are skipped before blocks are checked. A block on a dead upstream is inert (its stale entry is reported, but since the upstream isn't offered anything, `set(u.blocks) - offered` includes all blocks). The test config exercises this with gamma. Correct.

**The description rewrite's `already` test is RED-capable.** The test asserts `assert_contains "$SB/list.out" "already fetch_file the docs, then fetch_file again"`. If the rewrite mangled `already` (as the roadmap's red case describes), this assertion would fail. The stub's `--describe` flag provides the test input. A mutation to the regex that breaks word boundaries would go red here.

### Test honesty observations

The stubs cannot represent three things that a real upstream would do differently on these paths:

1. **A tool list that changes between calls.** The stub's tool list is fixed at startup. A real upstream can add, remove, or rename tools between the daemon's `list_tools` and `call_tool`, which is the TOCTOU window findings 2 and 3 exploit. The tests can't exercise the stale-dispatch-entry scenario because the stub never changes its offerings.

2. **Concurrent list+call on the same upstream.** The stub is synchronous (one stdin line at a time). A real MCP upstream multiplexes concurrent requests by id. The daemon's lock-free listing and locked calling can't be stress-tested against a stub that serializes everything.

3. **A `listChanged` notification.** The stub advertises `listChanged: true` but never sends the notification. The daemon doesn't forward it (Phase 4), so this is expected — but it means the tests can't verify that a stale dispatch table is ever refreshed by a notification, only by the next `tools/list` call.
