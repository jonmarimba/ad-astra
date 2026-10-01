# Phase 5 convocation — synthesis and dispositions

Written by Claude (Fable, tool-templates driver), 2026-08-31. Panel: claude, codex, qwen over commits `782c1de` (Phase 4) and `efa84ec` (Phase 5). Raw answers beside this file; fixes landed in `4f8b3a3` with watched-red tests where the behavior was testable. All three voices answered on the first round.

## Fixed in `4f8b3a3`

**The call-path break never announced the surface contraction** (claude, codex). `_mark_broken` — written to fire the notification — was dead code, and the fastest break-detection path was the silent one. The fire now happens after the upstream lock releases; `_mark_broken` is deleted rather than resurrected.

**Modern-protocol clients were told `listChanged: false`** (codex, probed both paths; qwen traced the same SDK branch). The 2026-07-28 era derives the capability from a `subscriptions/listen` handler, which the daemon did not serve. It now serves the SDK's `ListenHandler` over an `InMemorySubscriptionBus` and publishes `ToolsListChanged` beside the legacy per-session pushes.

**The downstream registry leaked forever** (all three). An abandoned legacy session's send neither raises nor drains, so failure-based eviction never fired. Bounded at 128 with insertion-order eviction; broadcasts run concurrently with one timeout each, so latency no longer scales with the registry.

**Self-preempt could kill bystanders** (all three; the claude leg verified a `tail -f` on the installed daemon.py matched the pgrep pattern). Preemption is now pid-file based with a literal argv check, and TERM escalates to KILL after a bounded wait — the wedged-teardown state the daemon's own watchdog documents is unreachable by a single TERM plus `sleep 1`.

**The placeholder crash loop had side effects** (claude, codex, qwen). run.sh now validates the config before ANY side effect: the unservable placeholder still dies loudly, but without first sweeping processes, writing a port file, and pointing `.mcp.json` at an endpoint that will never serve. A jq failure on `.mcp.json` is a loud launch death instead of a silent skip.

**Version-check gaps** (claude, codex): an upstream omitting `serverInfo.version` no longer passes silently; a healed mismatch retracts its advisory; a malformed ledger degrades instead of failing every reconnect with a TypeError. The cold-install grace from the phase-1 incident finally landed (60-second default connect timeout in repo daemons — the deferral had simply fallen through, as the claude leg noticed).

**Installer**: `set -e`, and git worktrees accepted — a worktree's `.git` is a file, and `js-lp-members-site` is one today (codex).

**Test integrity** (claude, codex): the KeepAlive assertion was a genuine tautology (RunAtLoad's `<true/>` satisfied the substring check) — now read via PlistBuddy; the relaunch section could pass against a run.sh that does nothing — it now removes the prior port file, asserts the old pid died, and asserts a live bystander survives; the cleanup trap's variables are initialised so `set -u` cannot error the trap and leak daemons.

## Refuted

**The `id(connection)` reuse hazard** (qwen). The registry holds the `ServerSession` strongly, which holds the `Connection` strongly, so a key cannot be recycled while its entry exists — the claude leg verified the reference chain in the SDK source. qwen's scenario requires the connection to be collected while still registered, which the strong reference forbids.

**The half-written SSE frame on broadcast timeout** (qwen). `send_tool_list_changed` enqueues one object into a memory stream atomically; SSE framing happens later in the writer task (claude, from the SDK source). A cancelled send drops the whole notification or none of it.

## Accepted, with reasons

**The port-publish TOCTOU** (codex, qwen): between the `lsof` probe and the daemon's bind, another process can take the port, leaving `.mcp.json` pointing at the wrong service until launchd's ~10-second respawn re-resolves. Closing it properly means moving the publish into the daemon post-bind — a refactor disproportionate to a race whose window is milliseconds, whose loser self-corrects on respawn, and whose population is a handful of repos with a 3% base-collision chance (claude computed the spread). Revisit if it ever fires in practice.

**TCC for require_xcode repo daemons** (codex): the generated plist launches bash directly, which cannot hold the Automation grant the clicker needs. Real, and documented in the installer header from the start: an Xcode-fronting repo daemon needs the wrap-in-app flow, grants added in the seat. The template that writes an Xcode config is where automation of that belongs, if Jonathan ever wants it automated at all — handlebars doctrine says grants are added one at a time, watched.

**Mismatch-ledger growth and key ambiguity** (codex): growth is one entry per distinct version string ever seen; a colon in a server name makes a key ambiguous only for deduplication, costing at worst one extra log line. Not worth structured records yet.

**Instructions absent for sessions that initialize before the first mismatch discovery** (codex): inherent to advisory-by-instructions; the next session gets the note, which is the mechanism's contract.

**Persistence-across-restart untested** (codex): asserting the once-per-mismatch dedupe across a daemon restart needs a third daemon boot in the suite for one log-absence assertion; the persistence write is asserted, the dedupe logic is three lines, and the cost is real wall-clock in the budgeted tier.

## For Jonathan, one decision flagged

The roadmap's own consequence note stands: N autonomous repo daemons re-introduce the approval-serialisation ceiling for `require_xcode` upstreams — roughly six seconds of exclusive dialog time each, against the now-60-second default connect window. That comfortably fits several daemons, but it is arithmetic, not measurement; the roadmap says measure at three before a third Xcode-fronting repo depends on it.
