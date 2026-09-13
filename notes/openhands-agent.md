**Openhands agent**

@ghost research openhands

@Ghost Also download Andrew's thing.

@GhOST research Higgsfield

Case insensitive to.

**GhOST reply, 2026-08-03 19:03:**

OpenHands: open-source (MIT), model-agnostic autonomous coding agent (formerly OpenDevin, org: All-Hands-AI). 81K+ GitHub stars, 188+ contributors. Acts as a full software engineer — writes code, runs shell commands, browses for docs, opens PRs — not just inline suggestions like Cursor/Cline. ~72% on SWE-bench Verified with Sonnet 4.5.

Free self-hosted or hosted cloud version at openhands.dev. Started as a community response to Cognition's Devin; HN threads compare the two directly. Relevant to the kicker ensemble: same shape as what Root/XO are building, just a mature, well-starred prior-art project worth diffing against before reinventing pieces of it. Higgsfield:

AI video-generation platform (ex-Google Brain founders, 2026 Series A at ~$1.3B valuation, 15-20M+ users). Aggregates Sora 2/Veo 3.1/Kling 3.0 etc. behind one subscription, plus cinematic camera presets, character consistency, lip-sync, face-swap. Pricing: Starter $15/mo (200 credits), Plus $39/mo (1,000 credits), Ultra $99/mo (3,000-9,000 credits).

Real complaints found (TeamBlind, not just marketing): 'unlimited' plans throttled via a battery/credit system, weak support, users banned without clear reason. Doesn't do product hero shots or static social ads — it's built for cinematic/narrative video specifically.

No obvious tie to your current projects that I can see — flag if there's a reason you tagged it. 'Andrew's thing' — I can't identify what this refers to from mail/notes/iMessage (checked Andrew Benson's recent Bitbucket/Jira activity and the June chess-engine-from-zero mention in the Vas thread — neither reads as 'download this'). Need a pointer:

a link he sent, a repo name, or where you saw it.

**GhOST reply, 2026-08-03 19:08:**

Found it — 'Andrew's thing' is drewster99/xcode-mcp-server (the one TOOLING.md calls 'Drew's'). It's been renamed: 'With several unrelated projects sharing that name — and Xcode itself now shipping a built-in MCP server — this project is now drews-xcode-mcp.' Old PyPI name still forwards for compat, but migration is:

update MCP config from xcode-mcp-server to drews-xcode-mcp (uvx drews-xcode-mcp), and if you used the default server key anywhere (allowlists etc.), rename mcp\_\_xcode-mcp-server\_\_ to mcp\_\_drews-xcode-mcp\_\_. Custom server keys don't need changes. Ties directly into your über-Xcode-MCP idea:

right now kicker juggles three separate Xcode-adjacent MCPs (Apple's built-in xcode/xcrun mcpbridge, drews-xcode-mcp for run/screenshot, XcodeBuildMCP for iOS sim build/run) — exactly the fragmentation the Merge MCP note (mcp-aggregator/combine-mcp) was aimed at.

A single aggregator process fronting all three would also solve the per-connection approval-popup problem you flagged there, since it's one stable PID instead of three.

@astra

@ghost add the MCP-merging stuff near the top of tech to try and reorganize tech to try by category and priority for kicker.

**GhOST reply, 2026-08-18:**

This was researched and the verdict is recorded in the canonical tech-to-try list, which now lives in @astra and is symlinked into the Obsidian vault at *tech-to-try.md*. Replying here because the research landed but this note was never marked answered, which is why it kept resurfacing in the pending queue.

**OpenHands** — MIT-licensed autonomous coding agent, 81k stars, roughly 72 percent on SWE-bench with Sonnet 4.5, and it has native ACP support. Filed as prior art worth diffing kicker against rather than adopting.

Your second line, download Andrew's thing, is not something I can act on without knowing which thing you mean. Say the word and I will fetch it.

@ghost ^ I think you migrated Andrews Xcode MCP to the new name, yeah?

**GhOST reply, 2026-08-19:**

**Half of it, and the half that is done is the half that matters less.**

**The package is migrated.** Both places it is configured — pot-mhm and js-llmKicker — already run *uvx drews-xcode-mcp*, so what actually gets pulled and executed is the new name. Nothing is fetching the deprecated package.

**The server key is not.** Both files still name the server *xcode-mcp-server*, and that key is what forms the tool prefix, so tools still appear as mcp\_\_xcode-mcp-server\_\_\*. That is precisely the second half the migration notice called out: if you used the default server key anywhere, rename the prefix too.

**The good news is that the remaining half has no blast radius.** I searched for anything depending on the old prefix and every hit is a session transcript in ~/.claude/projects — historical records that cannot be affected. No settings file, no allowlist, no permission rule references it. So the rename is two lines in two files with nothing downstream to break.

Your TODO says to batch it with the account swap, so I have left it alone rather than doing it unilaterally. Say when and it is a thirty-second change.