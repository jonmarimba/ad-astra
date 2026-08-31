# What already exists — read this before designing anything else

Written by GhOST-Claude, 2026-08-31, after Jonathan pointed out that I was specifying things that were already built. This is the third correction in one morning of the same kind, so it gets its own file rather than a paragraph.

## The pattern I keep repeating

I wrote a specification for a template system without reading the template system. I wrote that "ponytail" could not be verified without searching for it. Both times the answer was in the repository or in his notes, and both times he had to tell me. **Read the inventory first.** The rest of this file is that inventory.

## Tools in ad astra: 34

`ai-setup-diff` `ambrosio` `bio-build` `botline` `botmsg` `check-prose` `convocation` `dedup-scan` `drew-kit` `frame-review` `geo-evidence` `graphify-repo` `handlebars` `harness-settings` `lib` `mcp-bundle` `mcp-ios-simulator` `mcp-kickerd` `mcp-mac-control-mcp` `mcp-mobile-mcp` `mcp-xcode-mcp-server` `mcp-xcode` `mcp-XcodeBuildMCP` `ollama-watch` `omniroute-model-sync` `omniroute-speed` `pdf-sidecars` `peer-review` `periphery` `ponytail` `speech-bee` `tests` `tool-templates` `wrap-in-app` `xcode-mcp-front`

Seven carry a `tool.json` descriptor, all of them `mcp-*`, and **nothing reads those files**. Twelve carry a `Brewfile`.

## The Swift and code-quality tools he asked about are already here

- **`ponytail`** — real, and not a Swift tool. `DietrichGebert/ponytail`, MIT. It is an **agent skill**: a decision ladder run before writing code — does this need to exist, does stdlib do it, is it one line — explicitly not applied to input validation, error handling, security or accessibility. GhOST researched it on 2026-08-06 and the assessment is in the Apple Note "Ponytail", including a real documented limitation: on a task that genuinely needs complexity it cost 6,000 tokens against 2,300, because the ladder itself is overhead. The ad astra entry point is `install-into-repo.sh`; the skill body is fetched from GitHub at install time, so there is no vendored copy to go stale.
- **`periphery`** — dead-code scanning for Swift, with a Brewfile.
- **`dedup-scan`** — duplicate-code detection.
- **`check-prose`** — the ASD-STE100 mechanical checker.

An Apple Note dated 2026-08-18, "Dead code and duplicate code detection (swift and others)", holds the research behind the last two. There is also a standing tech-to-try list in Notes — Exo, OpenHands, Firecrawl, TickTick, Brett Terpstra's TerminalWidget — which is the intake queue for future template members.

## Andrew Benson IS Drew — one person, both things

Corrected by Jonathan, 2026-08-31, immediately after I concluded the opposite. `Andrew Benson <db@nuclearcyborg.com>` wrote `drews-xcode-mcp` — the `Xcode MCP Server 1.29.1` running in the combined daemon right now — **and** contributes to this repo.

His ad astra contributions are `agents-and-prompts/`: the components tree (`Coding.md`, `NamingThings.md`, `CodeComments.md`, `BuildingAppleProjects.md`, `AccessibilitySuperPrompt.md`), the commands (`swiftlint.md`, `3way.md`, `recheck.md`, `stupid.md`), and the Jira tooling.

So "Andrew's thing" and "Andrew's Swift stuff" may refer to either the MCP server or the prompt-and-skill material, and both are his. When either is ambiguous in future, it is one person to ask rather than two things to disambiguate.

**Why I got it wrong is worth keeping.** I found a contributor named Andrew, found an MCP server named for Drew, observed they were different kinds of artifact, and concluded they were different people — reasoning from artifact type to identity, which is not an inference at all. The git log gave me the email address that would have settled it and I did not use it.

## Four templates already defined

`swift-ios`, `legal-pdf`, `kicker-dev`, `writing`, in `tools/lib/templates.json`. The file's own comment states the overlap rule: non-exclusive, installing one never removes another's tools, and two may overlap freely.

**`swift-ios` is already close to the "Mac + Swift" template he described** — `mcp-xcode`, `mcp-XcodeBuildMCP`, `mcp-ios-simulator`, `mcp-mobile-mcp`, `mcp-mac-control-mcp`. What it lacks is the code-quality set: `ponytail`, `periphery`, `dedup-scan`. That is an edit to one JSON file, not a system to build.

## Per-repo MCP configuration already exists, for three agents

`mcp-bundle` describes itself as "the first astra tool that is really a bundle of tools." It configures the same server set for three agents that each store configuration differently: Claude Code via `.mcp.json`, Qwen Code via `.qwen/settings.json`, Codex CLI via `.codex/config.toml`.

This matters for the roadmap in two ways. The per-repo install mechanism is not the missing piece. And **any aggregator design must account for three consumer formats**, not just Claude Code's — a point no panelist raised, because none of them looked at `mcp-bundle` either.

## What is genuinely missing

1. A **generic aggregator** driven by a config file, replacing the hard-coded two-upstream daemon.
2. The **sieve** and the **map**.
3. A **reader for `tool.json`**, which would turn seven dead files into a validated registry.
4. **Template composition** — templates containing templates — which `templates.json` cannot express today, since entries carry a flat `tools` array.
5. The code-quality tools **added to `swift-ios`**.
