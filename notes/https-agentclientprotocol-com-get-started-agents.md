**https://agentclientprotocol.com/get-started/agents**

@ghost JS Follow-up on the below

Given that I like to think of some conversations as “personalities” and perhaps others more as worker-bee one-shots. Can we get the longer-lived ones to come back via some kind of session ID. And Can we CHANGE the CWD of a given bot or is it stuck in one directory forever? I don’t hate the idea of a bot having a home. I just would like to move house for (e.g.) work trees. Can we CWD a level higher (like svnCheckouts) and tell it to work in ./pot-mhm or will that mess something fundamental about ACP up?

ALso…. Isn’t there an A2A (Agent To Agent) protocol? Some IBM THIng? I seem to remember it being kind of too “enterprisey”

——————————————————————————————————

@ghost ACP stuff for connecting Claude, Codex, and others

**GhOST reply, 2026-08-03 22:52:**

Solid — the Zed-built ACP adapters are already exactly the piece kicker needs: 'Claude Agent (via Zed's SDK adapter)' and a separate Zed-built Codex CLI adapter both exist today, bridging each into ACP. Cline/Cursor/OpenHands (see the OpenHands tech-to-try item) have native ACP support, no adapter needed.

Ties directly to your Cli-proxy note's cwd/symlink gripe — ACP itself is the standard both adapters speak, so the fixed-cwd/no-symlink constraint applies uniformly regardless of adapter. Practical next step if you want to actually try this:

point Zed's Claude adapter at a real ~/svnCheckouts-resident bot (per your own workaround) and see if the cwd constraint is actually a non-issue in practice, same as the Cli-proxy conclusion. @astra

@ghost summarize these adaptors in tech to try and add this there. I think it might be very useful for kicker

@astra as well

**GhOST reply, 2026-08-18:**

Summarized and filed in the canonical tech-to-try list, which now lives in @astra and is symlinked into Obsidian as *tech-to-try.md*. Replying here because the work landed and this note was never marked answered, which is why it kept resurfacing in the pending queue — ten notes were in that same state.

**acpx plus the Zed adapters** give a headless CLI client for Agent Client Protocol: one interface across Codex, Claude and Gemini, with persistent and one-shot modes, permissions and JSON. It has an explicit --cwd flag, which is the clean fix for the cwd-forever gripe in your CLI-proxy note.

The caveat that keeps it from being the answer to everything: ACP standardizes the wire protocol only. Zed's own open bug (zed#52151, “ACP agents frequently hang”) shows it does not fix nodes simply stopping. Adopt it for interface uniformity, not reliability.

Worth reading alongside your other note at this same URL, where you asked whether ACP answers the tmux confirmed-send problem. The answer there was no — ACP is editor-to-agent, not agent-to-agent — and tonight proved that answer correct in an unwelcome way. GhOST and OpenClaw have been coordinating over a tmux socket, and a review found the health check ignores both tmux send-keys return codes and records the partner channel as delivered unconditionally. So it can report an escalation delivered through a path that delivered nothing, which is exactly the confirmed-send weakness you were asking about. The ghost-poke spool does not have that problem, because a file write is either there or it is not.