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

The `base` template installs what every repo gets: the writing discipline and convocation (cross-brand review panels). The writing discipline is a set of skills that check and de-AI prose, plus a doctrine file that orders bots to use them. The kind templates compose `base` in, so you normally install one of these and never think about `base`:

- `swift-ios` is for iOS app work. It adds the Xcode aggregator, Swift code-quality tools, Mac and simulator control, the axe CLI, and the ios-ui-driving skill.
- `mac-swift` is for Mac app work. It is the same minus the iOS simulator pieces. QUICKSTART-ios.md covers both.
- `legal-pdf` is for document repos. It adds PDF-to-text sidecars on top of `base`. QUICKSTART-pdf.md covers it.
- `writing` alone gives just the prose stack. QUICKSTART-writing.md describes each piece.

Run `python3 template.py list` to see all of them with descriptions.

## What lands in your repo

Everything the installer writes stays inside your repo. `.mcp.json` gains MCP server entries for Claude Code, and `.qwen/settings.json` and `.codex/config.toml` gain the same for those agents. `.claude/skills/` gains the skills. `.doctrine/` gains the doctrine files, and marked import blocks in `CLAUDE.md` and `AGENTS.md` load them into every session. `.astra/` gains the update machinery and the manifest.

Restart your agent session after an install. Agents read the config files at session start.

## The Xcode aggregator

The template does not install separate Xcode MCP servers into your repo. It writes one HTTP entry, `xcode-combined`, pointing at a single daemon on this machine (port 8767). That daemon fronts Apple's Xcode bridge, Drew's server, and a slice of XcodeBuildMCP behind one endpoint. A head-to-head on real projects resolved the overlaps: each capability appears once, under one name, from the vendor that won. The daemon runs under launchd, survives reboots, and waits for Xcode on its own. Xcode's approval prompt is answered once, for the daemon, and no per-session bridge ever spawns to ask again.

The practical consequences: build with the `build` tool (it returns warnings inline with file and line). When Xcode is not running you still get `xbm__build_run_sim`, `xbm__test_sim`, and the coverage tools, because that slice is headless. The tool named for what you want is the right one; there are no duplicate vendor variants to choose between.

## What is installed, where

Each repo answers for itself. `.astra/manifest.json` records which templates the repo has, the full resolved tool list, and the exact content hashes of every installed file. There is no central registry by design. The first push-based design let a bug in this repo damage other repos, so the direction was inverted. Each repo pulls, and this repo never reaches into anyone.

## Where the astra checkout lives

Nothing assumes a fixed location. Clone this repo anywhere, under any name. A repo records where it was installed from in its manifest. Suppose you move the checkout, or clone a repo onto a machine with no copy at the recorded path. Set `ASTRA_SOURCE=<path to your astra checkout>`, and updates and `convoq` work again. Clone the checkout with `--recurse-submodules`, because `convoq` needs the engine in `vendor/authsec-bridge`. `tools/tests/test-portable-install.sh` proves all of this by installing from a renamed copy into a repo on a machine with an empty home directory.

## How updates happen

`.astra/astra-update --pull`, run inside your repo, asks this repo whether anything moved on and updates in place. It only touches files that are still exactly what the installer wrote; anything you edited locally is reported, never overwritten. Every install wires a post-commit and a post-merge hook that run it in the background, so a repo you commit to or pull into stays current without anyone thinking about it.

The whole interface is one command, run inside the repo:

```
<astra checkout>/tools/astra add writing        # a set from templates.json, or a single tool
<astra checkout>/tools/astra remove humanizer   # gone for good; no update brings it back
<astra checkout>/tools/astra status
<astra checkout>/tools/astra list
```

Git does not clone hooks, so on a new machine or a fresh clone run `astra sync` once. It wires the hooks in every repo beside the astra checkout (or under the directories you name) that has astra tools. A repo never needs astra to work: installed tools are ordinary committed files, and the hook stays silent when no astra checkout is present. Tools marked `# astra-scope: machine` (brew formulas, global CLIs) are never installed by a repo install; a set that names one says so and gives the command.

## How bots know their tooling is current

They mostly do not need to. The post-commit hook keeps a working repo fresh, and MCP servers are read at session start. So a new session is a new snapshot of current config. For a long-running session in a repo nobody commits to, `.astra/astra-update --pull` is safe to run at any time; `.astra/update.log` says what the last run did. A locally modified file blocks its own update and appears in that log, which is the one staleness case that needs a human decision.
