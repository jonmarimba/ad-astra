# Phase 1 convocation — synthesis and dispositions

Written by Claude (Fable, tool-templates driver), 2026-08-31. Panel: claude, codex (`gpt-5.6-sol`), qwen (`ollamacloud` route), each reviewing commits `350a41e..f4cf31c` independently. Raw answers sit beside this file as `phase1_claude.md`, `phase1_codex.md`, `phase1_qwen.md`. Every disposition below names what was verified before acting; a panel claim was never taken on its own word. The codex leg's first run returned zero bytes and was re-run; its second run was killed externally and its third completed.

## Fixed, with watched-red tests, in commits `cb84b67..3e7a804`

**Prefixes are honoured verbatim.** The daemon forced an empty prefix for any sole upstream, so the validator printed `prefix=solo__` while the daemon served bare names, and adding a second server silently renamed the first one's surface. The claude leg measured it live. The env-var single mode keeps its unprefixed passthrough through an explicitly empty prefix.

**No forwarding on faith.** A dispatch miss refreshes that one upstream's catalogue once and then refuses a name the upstream does not offer. The old prefix fallback would have bypassed Phase 2's deny list and kept Phase 3's renamed tools callable under their old names (codex).

**Upstream application errors are the caller's errors.** A JSON-RPC error from an upstream (unknown tool, bad arguments) is forwarded with its message; it no longer marks the connection broken and no longer reports "not connected right now" for a call that would fail identically on every retry (codex).

**Listing is concurrent, lock-free, and structurally bounded.** One slow upstream withheld every later upstream's tools for its whole timeout, and a client listing during a 600-second build got nothing until the build ended (claude, measured). The drain now runs on a session snapshot without the upstream lock, under the 15-second connect timeout, with a repeated-cursor check and a 200-page ceiling — the claude leg accumulated 48,075 pages in ten seconds from a cycling stub. Duplicate exposed names from a mid-drain mutation are dropped with a warning.

**Client drains never adjudicate connection state.** My first version of the bound above marked the upstream broken on a drain timeout, and it took the deployed daemon to zero tools within the hour: clients poll `tools/list` constantly, each poll timed out against the approval-gated mcpbridge, and every timeout tore the connection down — withdrawing the approval prompt before the clicker could answer it, the exact 2026-08-30 pathology through a new door. Reproduced under synthetic client load against a stall-tools stub. The heartbeat, which owns the click-while-blocked helper, is now the sole authority on connection state.

**The cursor refusal speaks the spec.** `MCPError(INVALID_PARAMS, …)` replaces a bare `ValueError` that became code 0 on one transport path and a message-less internal error on the other (claude measured both paths; qwen had traced only the old path — the brand disagreement was settled by measurement). An empty-string cursor now counts as a cursor (codex).

**`env` is implemented, not rejected.** The SDK's default child environment is a six-variable allowlist, so rejecting `env` made Drew's `XCODEMCP_ALLOWED_FOLDERS` mechanism unreachable (claude measured the variable never arriving). The map is merged over the safe defaults, matching Claude Code's semantics for the same file shape. Codex argued rejection was correct while unimplemented; implementing it satisfied both positions.

**Unknown top-level config keys are rejected by name** (all three brands). Phase 2's sieve and Phase 3's map land at top level; a typo'd stanza that validates silently is a limiting policy that never applies.

**Instructions are derived from the config.** A Python stub was being introduced to clients as Apple's Xcode bridge, and the not-connected error told every caller that Xcode was being checked. The mcpbridge guidance survives only when an upstream actually is mcpbridge; the multi-upstream text now says that a missing upstream means re-list. A `known_broken` upstream also drops its public session reference immediately instead of staying callable through a possibly-wedged teardown (codex).

**Test tightening** (all three brands): the cursor assertion demands `-32602` plus the daemon's own diagnostic; the degraded scenario reads the daemon log to prove gamma was attempted and delta genuinely connected, which the tool list alone cannot show; the daemon test carries a RED control (the replaced env format is a startup death).

## Deferred, deliberately

**`listChanged` forwarding** (all three brands, framed differently): a client that lists during an outage caches the partial surface and is never told the missing upstream returned. This is roadmap Phase 4 by design; the mitigation shipped now is the instructions sentence telling the model to re-list. The qwen leg's position — that a live pass-through might not need the notification at all — is noted and will be tested against a real client in Phase 4.

**Per-upstream watchdog instead of `os._exit(75)`** (codex, qwen round 1): one wedged upstream still restarts the whole daemon. True, and accepted for now: launchd restart costs one approval prompt the clicker answers, and the per-repo autonomous-daemon design (Phase 5) changes the calculus anyway. The watchdog message now names both candidate waits instead of asserting the wrong one (claude).

**`cwd`/`url` stay rejected.** http upstreams are real future work (the config shape reserves the field); nothing in Phases 2–3 needs them.

## The deployment incident, recorded because it will happen again

After the hardening deploy, the combined daemon served zero tools. Three separate causes, none of them the panel's findings:

1. My drain-timeout-marks-broken mistake (fixed above).
2. **Drew's server had published v1.3.23 upstream**, and the first `uvx` resolve had to download and build it; under load that exceeded the 15-second initialize window, the daemon killed `uvx` mid-install every cycle, and the install never completed until an interactive probe with a longer timeout warmed the shared cache. Note the version string trap: the package is v1.3.23 while its `serverInfo` says `1.29.1` — they are different counters, and chasing the mismatch cost real time. A cold-install grace for spawn-per-connect upstreams belongs in Phase 5's deployment design.
3. **Xcode stopped raising approval prompts entirely** at about 12:15: every window was minimized (nowhere to attach the prompt), and after un-minimizing, new prompts still did not appear — while the single-upstream daemon's 11:34 approval kept working. The combined daemon correctly serves Drew's 29 tools and retries mcpbridge; the moment Xcode shows the prompt, the clicker answers it unattended. `~/.xcode-combined-front/config` now carries `XCODE_MCP_FRONT_CONNECT_TIMEOUT_S=60` so each approval request stays alive longer than the default 15 seconds. **If the xcode__ tools are still absent when a human reads this: glance at Xcode — an approval dialog may be waiting, or Xcode may need a restart, which no automation here will do to a working IDE.**

The 1.4 behaviour proved itself during the incident: Drew's Xcode-free tools kept serving through the whole mcpbridge outage, which is precisely the failure the old refuse-partial code turned into a total blackout.
