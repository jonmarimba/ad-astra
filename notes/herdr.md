**Herdr**

Herdr

@ghost better for us than tmux???

**GhOST reply, 2026-08-06 11:59:**

Yes, and genuinely a big one for the Fable+Sol rebuild — worth reading this whole reply before deciding anything else about the spec. Herdr (Rust, released March 2026) is a purpose-built agent multiplexer, not a tmux fork or wrapper. The core distinction, straight from its own comparison page: &quottmux persists terminals;

Herdr persists agent workspaces and understands agent state." tmux only knows panes exist — Herdr natively tracks whether an agent is blocked, working, done, or idle, via automatic process-name matching + terminal-output heuristics, zero config, no hooks to wire.

This is the exact problem that cost real documented effort in js-llmKicker (the whole &quotBusy / idle signatures per CLI" section in CLI-LIFECYCLE-CAPABILITY-MATRIX.md — manually reverse-engineering that Claude's busy glyph is non-enumerable, Codex's suffix pattern, etc., for each CLI separately).

Herdr already supports 15+ agents out of the box by name, including Claude Code, Codex, Pi, OpenCode, Gemini CLI, Cursor Agent, Kimi Code CLI — essentially the exact roster you'd be wiring into a Fable+Sol-based kicker2. It also exposes a Unix Socket API — &quotread, send, wait, split, attach" — that scripts or agents (not just humans) can drive:

query whether a specific agent is blocked/working/done/idle, programmatically send input, use `wait` to synchronize between multiple agents, dynamically split panes based on state. That's an agent-shaped orchestration API, not generic terminal scripting — closer to what kicker's root/conductor layer needs than tmux's raw pane model.

It also does remote sessions (herdr --remote ssh://...) with session persistence across sleep/WiFi drops/SSH disconnects, same durability property tmux gives you now. Given you're about to write the Fable+Sol spec:

this is worth evaluating as the actual session-management substrate BEFORE committing to tmux again by default, since it may eliminate an entire category of bespoke plumbing (busy/idle detection, cross-CLI signature matching) that kicker had to hand-build.

@ghost - let's put this near the top of my tech to try list. Remind me of this list tomorrow afternoon.

@astra

**GhOST reply, 2026-08-18:**

This was researched and the verdict is recorded in the canonical tech-to-try list, which now lives in @astra and is symlinked into the Obsidian vault at *tech-to-try.md*. Replying here because the research landed but this note was never marked answered, which is why it kept resurfacing in the pending queue.

**Herdr** is at the top of the list and marked as your top priority. A Rust agent multiplexer rather than a tmux fork: it persists agent workspaces and understands agent state, tracking blocked, working, done and idle per agent across fifteen-plus agents by name, with a Unix-socket API and remote sessions. It would replace the whole bespoke busy/idle-signature problem in the kicker CLI lifecycle matrix.

Your ask to be reminded of the list was fulfilled on 2026-08-13. Answering your other question directly: better than tmux for coordinating agents, yes, because it models agent state rather than terminals. Whether it is better for GhOST and OpenClaw talking to each other is untested — that pair currently uses a plain tmux socket and it works.

@ghost — I think this and the aggregation of MCP tools along with having templates for installing our other tools along with a selection of MCP tools will be super useful going forward. Put those things at the top of our playing-with-nerdery pile.

**GhOST reply, 2026-08-19:**

Done. Section A of tech-to-try now opens with your three, above everything including the DeepSeek Harness, and your reasoning is quoted at the top of the section so a later pass does not quietly re-sort them.

**Herdr** and **mcp-aggregator** were already on the list further down and have been moved rather than duplicated. The third leg needed writing from scratch, because it did not exist as an item: **repo install templates** — a named bundle saying “a repo of this kind gets these tools, this doctrine, and this MCP selection,” installed in one command instead of remembering the set.

The half of that which already exists is the placement machinery. The astra installer drops tools into a repo's *.astra/* with a manifest and a vendored updater, so a repo already knows where it was installed from and can pull its own updates. What is missing is the naming layer above it — the template that picks the set.

The two pair better than they look separately. The template chooses the MCP servers; the aggregator fronts them as a single endpoint. So a new repo ends up with one server entry rather than eight, and one approval prompt rather than one per server — which is the same Xcode-popup problem you flagged in the MCP-merging note, solved once at install time instead of every session.

Written to the portable rule you set: the template names capabilities and policy, never GhOST, so another bot's repo can install the same bundle without being us.