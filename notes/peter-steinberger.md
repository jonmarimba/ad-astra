**Peter Steinberger**

I swear this dude used to attend conferences I spoke at…

https://github.com/steipete

@ghost — Anything in here interesting to us? Maybe a medium-effort triage pass to find the top n things he’s working on we might like to dig deeper into.

**GhOST reply, 2026-08-06 11:45:**

Real person, real prolific output — and yes, plausible you crossed paths at conferences (he's a well-known ex-PSPDFKit founder turned agent-tooling builder, now doing agent infra work). Verified every star count directly via GitHub's API rather than trusting the first search summary — caught one real hallucination doing that:

OpenClaw itself was reported as &quot381k stars," actual number is 16. Everything else checked out close to accurate. Corrected triage, most interesting first:

* **OpenClaw** (16 stars, early-stage) — &quotyour own personal AI assistant, any OS, any platform" — this is the umbrella project/org behind several tools you've already independently found and are using (imsg is literally openclaw/imsg). Worth knowing the org exists as a through-line connecting a bunch of your other tagged notes.
* **CodexBar** (19,716 stars, genuinely popular) — macOS menubar utility showing real-time usage/cost limits for Claude Code and OpenAI Codex, no login required. Directly useful to you given how much you care about token spend — probably worth just installing.
* **openclaw/Peekaboo** (4,969 stars) — Swift macOS CLI + MCP server letting AI agents screenshot apps/the whole system with optional visual QA via local or remote models. Relevant to any kicker2 node that needs to &quotsee" a screen — adjacent to your own shotq OCR pipeline but agent-facing instead of a search index.
* **openclaw/mcporter** (4,881 stars) — calls MCP servers via a plain TypeScript API, or packages them as CLIs. Useful if you ever want to expose GhOST's own tools (mailq/notesq/etc) as MCP-callable without hand-rolling a server each time.
* **openclaw/gogcli** (8,254 stars) — Google Workspace (Gmail/Calendar/Drive/Contacts) in the terminal. Given how much of your own life-admin tooling is Google-account-adjacent, worth a look as a possible building block instead of writing more one-off Google API glue.
* **agent-scripts** (6,508 stars) — shared knowledge base of rules/patterns specifically for coding with AI agents. Same genre as your own AGENTS.md/CLAUDE.md conventions — worth skimming for ideas, not necessarily adopting wholesale.
* **summarize** (6,525 stars) — point at any URL/YouTube/podcast/file, get the gist, CLI + Chrome extension. Minor but genuinely handy utility. Skipped as lower-signal for you specifically: fs-safe/proxyline/crabline (low-level runtime primitives, useful if you're building agent infra from scratch, not obviously needed given kicker's already-built plumbing), ClawHub (a skills marketplace, not clear you need a marketplace vs. your own curated set).

@ghost - put anything you think we should try in the tech to try list

@ghost migrate the tech to try list to @astra and track it there exclusively. Remind me we did this.

@ghost symlink (?) the tech to try list into the obsidian area I'm pointed to where the notes live so I always see it in obsidian.

@ghost symlink any graphify obsidian you make for Maharam and its submod there as well. I want all of the obsidian things in my machine in a Chokepoint.

**GhOST reply, 2026-08-18:**

Researched, and the verdict is in the canonical tech-to-try list in @astra, symlinked into Obsidian as *tech-to-try.md*. Replying here because the work landed but the note was never marked answered.

The triage pass was done. Three things came out of it worth your time: **CodexBar** (19.7k stars) — menubar live usage and cost for Claude Code and Codex, which is directly relevant since you care about token spend; **Peekaboo** (5k stars) — a Swift CLI and MCP letting agents screenshot apps with optional visual QA, adjacent to kicker seeing the screen; and **gogcli** (8.3k stars) — Gmail, Calendar, Drive and Contacts in the terminal, a possible building block instead of one-off Google API glue.