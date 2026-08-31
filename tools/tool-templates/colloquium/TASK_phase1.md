# Convocation checkpoint — Phase 1 of the tool-template aggregator

You are one voice in a three-brand review panel. Review the Phase 1 implementation of the generic MCP aggregator in `~/svnCheckouts/js-db-ad-astra`, branch `tool-templates`, commits `350a41e..f4cf31c`. Your findings are leads for the driver, who verifies each against the code before acting; cite file and line for every claim, and say what you actually read versus what you infer.

## What Phase 1 did

Read these files in full before judging anything:

- `tools/xcode-mcp-front/mcp_config.py` — new config loader. Claude-Code-shaped `_mcp_info.json`, additive `prefix` and `quirks` fields, rejection by name of `env`/`cwd`/`url`/unknown keys, prefix-set ambiguity checks, and `resolve_specs()` which makes a set `XCODE_MCP_FRONT_UPSTREAMS` a startup error.
- `tools/xcode-mcp-front/daemon.py` — the aggregator. Changes: upstreams built from the config file; an explicit dispatch table (exposed name -> upstream, bare name) rebuilt on each `tools/list` and consulted before prefix fallback on `tools/call`; a disconnected upstream no longer blanks the whole surface (connected-but-empty is distinguished from disconnected); each upstream's pages are drained into a snapshot and a downstream cursor the daemon never issued is refused with a raised `ValueError`.
- `tools/tests/test-mcp-front-config.sh`, `tools/tests/test-mcp-front-daemon.sh`, `tools/tests/stub_mcp_server.py` — the fast-tier tests: the daemon is booted on a scratch port against dependency-free stub upstreams and asserted over real HTTP.
- Context, if you need it: `tools/tool-templates/ROADMAP.md` (the increments and Jonathan's decisions), `tools/tool-templates/SPEC.md`.

The deployed combined daemon was restarted on the new config and serves the same live surface as before: 50 tools, 21 `xcode__`, 29 `drews__`.

## What to attack

Phase 2 (a deny-list sieve with a required `why`) and Phase 3 (a rename map plus description rewriting) build directly on the dispatch table and the availability semantics, so a wrong call here gets expensive. Attack, in rough priority order:

1. **The 1.4 degraded-surface semantics.** The daemon used to refuse to serve a partial list (zero tools plus a loud log) whenever any upstream was missing; now it serves what is available and logs the rest. Its `instructions` text and any client behaviour that depended on all-or-nothing: is anything now lied to? Is there a state where a client caches the partial list and never learns the missing upstream came back (no `listChanged` is forwarded yet — Phase 4)?
2. **Dispatch-table staleness.** The table is rebuilt only on `tools/list`. An upstream reconnects with a different tool set, or dies after listing: what does `tools/call` do with a stale entry, and is the failure honest? Is the prefix fallback after a miss ever a misroute rather than a convenience?
3. **The pagination drain.** `Upstream.list_tools` drains all pages under the upstream's lock inside one `CALL_TIMEOUT_SECONDS` (600s) window. A pathological or looping upstream (cursor cycles, never-ending pages): what bounds the drain? Is one `fail_after` around the whole loop the right shape, and does a 600s hold on the lock starve the heartbeat?
4. **Cursor refusal.** `on_list_tools` raises `ValueError` on an unexpected cursor. How does the mcp server library surface a raised `ValueError` to the client — a clean JSON-RPC error, or an internal-error 500 with the message lost? Is refusing a cursor spec-legal for a server that never issues `nextCursor`?
5. **The config model before the sieve lands on it.** Prefix ambiguity rules (duplicates, prefix-of-prefix, empty-beside-others), the quirks set, the rejection of `env` — anything that will need to be walked back once Phase 2/3 add sieve and map stanzas to the same file?
6. **Test honesty.** The fast-tier daemon test: anything tautological, any assertion that would pass against a broken implementation, any RED control that fails for the wrong reason?

## Output

A numbered list of findings, most severe first. For each: the claim, the file:line evidence, a concrete failure scenario (inputs and state leading to wrong observable behaviour), and a proposed fix in one or two sentences. If you verify something is CORRECT that a reviewer might flag, say that too — a checked non-finding beats silence. Do not restate the roadmap; judge the code.
