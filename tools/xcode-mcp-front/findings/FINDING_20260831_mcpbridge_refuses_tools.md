# mcpbridge refuses tool requests, and no approval dialog is ever offered

Author: GhOST-Claude, 2026-08-31 08:15. Verified by effect, standalone, with both daemons out of the picture.

## What is established

`xcrun mcpbridge` answers `initialize` and answers `ping` (with a real "unknown method" result, so the
process is live and parsing). It goes **silent on `tools/list` and on `tools/call`**, on both
`2025-06-18` and `2024-11-05`, and then exits 0 with no stderr. Reproduced four times from a plain
Python harness that keeps stdin open — the earlier "mcpbridge is broken" claim came from a probe that
closed stdin and was wrong, so this was re-tested from scratch.

Xcode is running with a real workspace open (the AstraProbe package), confirmed through MacControlMCP's
window list rather than inferred.

**No approval dialog exists anywhere on the system.** All 76 windows across every running app were
enumerated; there is no pending prompt, in Xcode or elsewhere, before or after a full suite run.

## Why that combination is the finding

The daemon design assumes a dialog appears and its clicker answers it — Jonathan, 2026-08-30: "the
daemons HAVE to depend on a clicker." No dialog appears, so there is nothing to click, and tool access
is never granted. The clicker is not failing; it is being handed an empty room.

That is consistent with Xcode having **remembered a denial**. Jonathan on 2026-08-30: "I killed xcode and
said don't allow in everything." A remembered "Don't Allow" would produce exactly this pair — no prompt,
because the decision is already made, and no tools, because the decision was no.

**The counterevidence, which is why this is a lead and not a conclusion.** The same exit-0-on-tools
behaviour was recorded in this test's own comments on 2026-08-27, days before that denial. There are
also mcpbridge crash reports (`EXC_BREAKPOINT`, a Swift assertion inside `MCPBridge.main()`) dated 8/26,
8/27 and 8/30 19:08 — but none from today's probes. So there may be two distinct causes across the
window rather than one, and the crash cause is definitely not what is happening now.

I did not find where Xcode persists a per-client MCP approval. It is not in `com.apple.dt.Xcode`'s
obvious keys and hunting it further was becoming a rabbit hole.

## What this means for the suite

Four assertions require mcpbridge to serve tools. They cannot pass while it refuses, and no change to
our daemons can make them pass — the refusal reproduces with the daemons uninvolved. Current state is
6 ok, 4 failed, with the four being exactly the mcpbridge-dependent ones.

## The one action that would settle it

Someone in the seat re-allows the Xcode MCP prompt. If a prompt then appears and is accepted and the
tools start answering, the remembered-denial theory is confirmed and the suite should go green. If no
prompt appears even then, the cause is inside Apple's binary and this is not ours to fix.

That is a human action in a GUI, on a decision Jonathan made deliberately, so it is his to reverse.
