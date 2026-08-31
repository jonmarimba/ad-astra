# Convocation checkpoint — Phases 2 and 3 of the tool-template aggregator

You are one voice in a three-brand review panel. Review the sieve and map implementation in `~/svnCheckouts/js-db-ad-astra`, branch `tool-templates`, commits `321b6ca` (sieve) and `9dc9c2e` (map), building on the Phase 1 work you can see in `colloquium/SYNTHESIS_phase1.md`. Findings are leads for the driver, who verifies each against the code before acting; cite file and line, and say what you read versus what you infer.

## What landed

Read in full before judging:

- `tools/xcode-mcp-front/mcp_config.py` — per-server `block: [{tool, why}]` and `map: [{tool, name, why, description?}]`. `why` is mandatory data: hard error in the validate CLI (authoring time), warn-and-apply in the daemon's lenient load. Contradictions rejected: a tool both blocked and mapped, duplicate exposed names within a server, two servers claiming one exposed name.
- `tools/xcode-mcp-front/daemon.py` — the composition loop declares the fixed evaluation order (availability, then sieve, then rename+description rewrite, then global uniqueness, then publish). Blocked tools are neither listed, dispatched, nor callable (the call refusal carries the recorded why). A mapped name is final: it replaces prefix+bare, the original is refused, and a pre-first-list call is recognised from the static map tables. Descriptions: explicit override wins (warned if it still speaks old names); otherwise a per-upstream word-boundary regex rewrites sibling references. Stale entries degrade: dropped alias, surface keeps serving, one warning each.
- `tools/tests/test-mcp-front-config.sh`, `tools/tests/test-mcp-front-daemon.sh`, `tools/tests/stub_mcp_server.py` — the fast-tier coverage.
- Context: `tools/tool-templates/ROADMAP.md` (Phases 2–3 and Jonathan's decisions: deny-list only; drop-the-alias-keep-serving), `SPEC.md` sieve/map sections.

## What to attack

Phase 4 (listChanged forwarding, version recording) and Phase 5 (per-repo autonomous daemons) build on this. Attack, roughly in order:

1. **Sieve completeness.** Is there any path where a blocked tool is still reachable — a race between dispatch rebuilds, the passthrough mode, the refresh path, a mapped name that resolves to a blocked bare name, case sensitivity, a name that collides after prefix stripping?
2. **Map correctness.** The rename replaces the original: any path where the old name still routes? The static-map lookup on the call path scans `u.maps.values()` per call — correctness and cost. Collision degradation (alias dropped, prefixed original served): does the fallback interact sanely with dispatch staleness and with a SECOND collision?
3. **The description rewrite.** The word-boundary regex: tool names containing regex metacharacters are escaped — but what about names with characters `\b` mishandles (leading/trailing underscores are word chars — fine; names with dots or dashes like `foo.bar` or `foo-bar`, where `\b` sits inside the name)? Can a rewrite produce a name that another upstream serves, misleading the model cross-upstream? Is rewriting the OVERRIDE description only a warning the right call?
4. **The why policy split.** Strict-at-authoring, lenient-at-runtime: any hole where a template ships to a repo unvalidated and the lenient path becomes the only enforcement anywhere?
5. **Test honesty.** Anything tautological; any assertion passing against a broken implementation; RED controls failing for wrong reasons. The suite runs the daemon against stubs — name anything the stubs cannot represent that a real upstream would do differently on these paths.
6. **Evaluation-order gaps** (2.3): the declared order versus what the code actually does, especially interactions — a tool that is mapped while its upstream flaps, blocks on a tool that reappears after a stale warning, dispatch entries surviving across availability transitions.

## Output

A numbered list of findings, most severe first: claim, file:line evidence, concrete failure scenario, proposed fix in one or two sentences. Include verified non-findings for anything a reviewer would flag that you checked and found correct. Do not restate the roadmap; judge the code.
