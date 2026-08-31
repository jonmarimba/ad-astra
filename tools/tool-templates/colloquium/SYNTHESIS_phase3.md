# Phase 3 convocation — synthesis and dispositions

Written by Claude (Fable, tool-templates driver), 2026-08-31. Panel: claude, codex (`gpt-5.6-sol`), qwen, each reviewing the sieve (`321b6ca`) and map (`9dc9c2e`) commits independently. Raw answers sit beside this file. Every disposition names what was verified; the fixes landed in `91858cd` with watched-red tests.

## Fixed

**The passthrough bypassed the sieve and map for file configs** (all three brands, each independently). The bare-name passthrough was built for the env-var single mode, which cannot carry blocks — but it also fired for a file config with an empty prefix, leaving blocked tools hidden from the listing yet callable by anyone who knew the name. Gated to the env contract via a `from_env` flag; a single-server file config's dispatch misses now route through the block check and refresh. The suite boots exactly that config and calls the blocked name.

**The call-time refresh could hijack another upstream's published name** (all three; the claude leg ranked it worst — wrong-tool execution reachable from any dispatch miss). The refresh wrote into dispatch with none of the composition's collision handling. Now add-only (`setdefault`); names it leaves stale are corrected by the next full list. This also bounds the qwen leg's refresh-vs-rebuild race: a stale refresh can no longer overwrite fresh entries.

**Alias-versus-natural ownership depended on config order** (all three). First-inserted-wins meant an earlier-listed upstream's alias could take a later upstream's genuine prefixed name, and the genuine tool was silently dropped as a "duplicate". Composition is now two-pass — natural names reserve the surface, aliases are admitted where room remains — so a natural name beats an alias in every order. The suite runs the hostile order: server `aaathief`, listed first, maps a tool to `alpha__ping` and loses to alpha's real ping.

**A duplicated mapped tool resurrected its replaced original** (codex). The collision branch treated a second copy of the same mapped tool as an alias collision and published the prefixed original beside the alias. An identical `(upstream, bare)` target is now recognised and dropped.

**Descriptions could instruct the model to call a name not on the surface** (claude, codex). The rewrite substituted the CONFIGURED alias even when collision degradation had dropped it. Pass 3 now rewrites from the effective table — old bare name to the name actually published — so a degraded alias rewrites to its prefixed fallback.

**Alternation order mangled overlapping names** (codex, measured: `foo` before `foo-bar` rewrote `use foo-bar` as `use <mapped>-bar`). Longest-first sorting in the pattern.

**An exposed name shadowing a blocked tool on the same server** (claude) let call timing decide between refusal-with-why and routing. Rejected at load.

**Message and hygiene fixes**: the stale-alias refusal names what was asked instead of a prefix-stripped mangle (`'erved'`); collision and stale-override warnings log once per key instead of on every client poll; stale-entry bookkeeping forgives a tool that reappears so a later re-staleness warns again (qwen).

## Deferred, with reasons

**Names with non-word-character edges** (`-foo`, `foo.`) never match `\b` and are silently un-rewritten (claude, codex — both ranked it low; neither knows a real MCP server naming tools that way). Noted; revisit if one appears.

**Dispatch generation control across concurrent lists** (codex): two concurrent full lists can still race clear/update; the loser's snapshot wins. Both snapshots pass the same collision policy, so the damage is bounded to a momentarily older-but-valid surface. Phase 4's notification work — which makes rebuilds more frequent — is where a generation counter belongs.

**The strict-why gate is not yet wired to an installer** (all three, framed as codex's "available but not connected"). True by construction: the template layer that will write `_mcp_info.json` files does not exist yet. The Phase 5/6 installer runs `mcp_config.py validate` before a generated file becomes active — recorded here so it cannot be forgotten. The run script's hand-written config is covered by the daemon test suite meanwhile.

**A mutable/concurrent stub mode** (codex): the stub cannot emit duplicate tool names (dict-keyed) or change its catalogue between requests, so the duplicated-mapped-tool fix is covered by code reading rather than an executed test. Accepted for now; the stub grows those modes when Phase 4 needs `listChanged` emission anyway.

## Verified non-findings the panel established

The sieve holds on every non-passthrough path including races (a shrunken dispatch only sends calls to the miss path, which re-applies it). Static contradiction checks are correct as far as they go. `re.escape` handles interior dots and dashes. The muzzled-call test is not tautological — the refusal text cannot contain the stub's reply. The static-map scan runs only on dispatch misses. No Phase 2–3 assertion was found tautological by any brand.
