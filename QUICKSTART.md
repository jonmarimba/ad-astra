# Quickstart

This repo is a toolbox that installs AI development tooling into other repos. It carries MCP servers, command-line tools, skills, and operating doctrine. You install a named template into your project, and the template installs everything a project of that kind needs. Nothing installs globally. Written 2026-09-01 by Claude (Fable), reviewed against the live system.

## Install a template into your project

Clone this repo, then point a template at your project checkout:

```
cd js-db-ad-astra/tools/lib
python3 template.py install swift-ios --into ~/path/to/YourApp
```

Re-running the same command is the update path. Installers pull their external dependencies fresh every time, so a re-run also upgrades the tools themselves.

## Which template

The `base` template installs what every repo gets: the writing discipline (skills that check and de-AI prose, plus a doctrine file that orders bots to use them) and convocation (cross-brand review panels). The kind templates compose `base` in, so you normally install one of these and never think about `base`:

- `swift-ios` is for iOS app work. It adds the Xcode aggregator, Swift code-quality tools, Mac and simulator control, the axe CLI, and the ios-ui-driving skill.
- `mac-swift` is for Mac app work. It is the same minus the iOS simulator pieces.
- `legal-pdf` is for document repos. It adds PDF-to-text sidecars on top of `base`.
- `writing` alone gives just the prose stack.

Run `python3 template.py list` to see all of them with descriptions.

## What lands in your repo

Everything the installer writes stays inside your repo. `.mcp.json` gains MCP server entries for Claude Code, and `.qwen/settings.json` and `.codex/config.toml` gain the same for those agents. `.claude/skills/` gains the skills. `.doctrine/` gains the doctrine files, and marked import blocks in `CLAUDE.md` and `AGENTS.md` load them into every session. `.astra/` gains the update machinery and the manifest.

Restart your agent session after an install. Agents read the config files at session start.

## The Xcode aggregator

The template does not install separate Xcode MCP servers into your repo. It writes one HTTP entry, `xcode-combined`, pointing at a single daemon on this machine (port 8767). That daemon fronts Apple's Xcode bridge, Drew's server, and a slice of XcodeBuildMCP behind one endpoint, with the overlapping tools resolved by measurement: each capability appears once, under one name, from the vendor that won a head-to-head on real projects. The daemon runs under launchd, survives reboots, and waits for Xcode on its own. Xcode's approval prompt is answered once, for the daemon, and no per-session bridge ever spawns to ask again.

The practical consequences: build with the `build` tool (it returns warnings inline with file and line). When Xcode is not running you still get `xbm__build_run_sim`, `xbm__test_sim`, and the coverage tools, because that slice is headless. The tool named for what you want is the right one; there are no duplicate vendor variants to choose between.

## What is installed, where

Each repo answers for itself: `.astra/manifest.json` records which templates the repo has, the full resolved tool list, and the exact content hashes of every installed file. There is no central registry by design. The first push-based design let a bug in this repo damage other repos, so the direction was inverted: each repo pulls, and this repo never reaches into anyone.

## How updates happen

`.astra/astra-update --pull`, run inside your repo, asks this repo whether anything moved on and updates in place. It only touches files that are still exactly what the installer wrote; anything you edited locally is reported, never overwritten. A post-commit hook runs it in the background on every commit, so a repo you commit to stays current without anyone thinking about it. If the hook is missing, install it:

```
cp js-db-ad-astra/tools/lib/astra-post-commit.hook YourApp/.git/hooks/post-commit
chmod +x YourApp/.git/hooks/post-commit
```

## How bots know their tooling is current

They mostly do not need to. The post-commit hook keeps a working repo fresh, and MCP servers are read at session start, so a new session is a new snapshot of current config. For a long-running session in a repo nobody commits to, `.astra/astra-update --pull` is safe to run at any time; `.astra/update.log` says what the last run did. A locally modified file blocks its own update and appears in that log, which is the one staleness case that needs a human decision.
