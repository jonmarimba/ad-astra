# The daemons were cancelling their own approval prompt — RESOLVED 2026-08-31

Author: GhOST-Claude. Written first at 08:15 with the wrong conclusion, rewritten at 08:40 once the cause was found and the suite went green. The wrong version is in git history; it is not preserved here, because a document that leaves a discredited conclusion standing above a correction is a document that gets read top-down and believed.

**Verdict: this was never Apple's bug. It was ours, in two places, and both are fixed. The suite is 10 of 10 with zero approval dialogs left queued.**

## What the symptom looked like

`xcrun mcpbridge` answered `initialize` and answered `ping`, then went silent on `tools/list` and `tools/call` and exited 0 with nothing on stderr. It reproduced from a plain harness with the daemons uninvolved, on both protocol versions, with and without `MCP_XCODE_PID` pinned, before and after a clean Xcode restart. No approval dialog was ever visible — all 76 windows across every running application were enumerated repeatedly and there was never a prompt. Apple's own agent config uses the identical bare stdio invocation, and a public repository carries a captured `tools/list` for this exact Xcode build, so the bridge plainly works elsewhere.

Every one of those observations was accurate. The conclusion drawn from them — that mcpbridge refuses to serve tools — was wrong.

## What was actually happening

**The approval prompt is bound to the live connecting process.** Kill the client and Xcode withdraws the question. That single fact explains the entire investigation: the daemons reconnect every five seconds, so each attempt raised a prompt and then killed its own child on timeout, retracting the request before anyone could answer. Nothing was ever on screen when the window list was taken because the prompt existed for a couple of seconds at a time. Holding one bridge open by hand produced the dialog immediately, and clicking Allow returned **21 tools**.

**Defect one, the clicker ran after the call it was supposed to unblock.** Xcode raises the prompt lazily, on the first real `list_tools` rather than at the handshake — the daemon's own comment had said so since 2026-08-14. So `list_tools` blocks until the dialog is answered, and `_click_allow_if_present()` was called on the line *after* the awaited `list_tools`. It could only run once the call had already returned, and on the timeout path the `except` branch marked the upstream broken and broke out before reaching it at all. The one thing that could unblock the call was scheduled to run only after the call unblocked. It now polls concurrently while the call is in flight.

**Defect two, two daemons deadlock by arithmetic.** `FOREIGN_DIALOG_GRACE_SECONDS` was 45 against a `CONNECT_TIMEOUT_SECONDS` of 15. Xcode's dialogs do not stack, so with both front daemons running, each clicker finds the other's dialog, correctly classifies it as foreign-and-alive, and waits out a grace period three times longer than the connection attempt it is holding up. Its own prompt never surfaces, its `list_tools` times out, its child dies, and both sides repeat forever. This is exactly the interference Jonathan asked about. Grace is now 6 seconds, and the relationship is checked at startup rather than trusted to a comment, because a grace at or beyond the timeout is a permanent deadlock whenever a second client exists — and it presents as Xcode refusing to serve tools, which is how it presented, for a night.

## Verified by effect, 2026-08-31 08:33–08:37

Both daemons loaded together. Each logged `clicked Allow for our own connection-approval prompt` within seconds. Since that moment: **zero heartbeat failures on either daemon**, one connect each, both ports serving, and Xcode holding a single window with no alert. The suite reports **10 ok, 0 failed**, including the four assertions that need mcpbridge to serve tools.

Before the fix the single-upstream daemon logged a heartbeat failure every twenty seconds, indefinitely, while reporting itself healthy.

## What to distrust in your own reasoning next time

The reasoning failure was not a missing fact. It was treating a *reproduction with our code removed* as proof that our code was innocent. Removing the daemons removed the reconnect loop, but the manual probe was itself killed after each attempt, so it reproduced the same self-cancellation by hand — the harness inherited the bug it was built to exonerate. The tell was available and ignored: the probe process was being killed at the end of every trial, and the dialog vanished with it.

Second tell: a public capture of `tools/list` for this exact build meant the bridge worked for someone else on identical software. That is strong evidence for a local, stateful cause and it was noted and then not acted on.
