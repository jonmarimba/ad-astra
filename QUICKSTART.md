# Quickstart

This repo is a toolbox that installs AI development tooling into other repos. It holds MCP servers, command-line tools, skills, and operating doctrine. You install a named template into your project, and the template installs everything a project of that kind needs. A template only ever changes your repo. A few tools need software on the machine itself, and "Where each kind of tool lives" below explains which and why.

## Install a template into your project

Clone this repo anywhere, then point a template at your project checkout. The examples use `~/astra` as the clone location. The toolbox needs macOS, git, Python 3.9 or newer, and jq. Run `tools/astra doctor` after the clone to check them.

```
git clone https://github.com/jonmarimba/ad-astra.git ~/astra
cd ~/astra/tools/lib
python3 template.py install swift-ios --into ~/path/to/YourApp
```

Re-running the same command is a way to update. Installers pull their external dependencies fresh every time, so a re-run also upgrades the tools themselves. If you edited an installed file by hand, the re-run keeps your edit and tells you so. Set `ASTRA_FORCE=1` on the command to overwrite it instead.

## Which template

The `base` template installs what every repo gets: the writing discipline, convocation (cross-brand review panels), and the act-first doctrine. That doctrine tells agents to do obvious, reversible, local work without asking, and to ask only before something they cannot take back. The writing discipline is a set of skills that check and de-AI prose, plus a doctrine file that orders bots to use them. The kind templates compose `base` in, so you normally install one of these and never think about `base`:

- `swift-ios` is for iOS app work. It adds the Xcode aggregator, Swift code-quality tools, Mac and simulator control, the axe CLI, and the ios-ui-driving skill.
- `mac-swift` is for Mac app work. It is the same minus the iOS simulator pieces. QUICKSTART-ios.md covers both.
- `legal-pdf` is for document repos. It adds PDF-to-text sidecars on top of `base`. QUICKSTART-pdf.md covers it.
- `writing` alone gives just the prose stack. QUICKSTART-writing.md describes each piece.

Run `python3 template.py list` to see all of them with descriptions. Run `tools/astra tree` to see how they nest: a template can hold other templates, to any depth, and the README shows the whole tree. You can also build your own set from existing templates and tools. README.md explains how.

## What lands in your repo

Everything the installer writes stays inside your repo. `.mcp.json` gains MCP server entries for Claude Code, and `.qwen/settings.json` and `.codex/config.toml` gain the same for those agents. `.claude/skills/` gains the skills. `.doctrine/` gains the doctrine files, and marked import blocks in `CLAUDE.md` and `AGENTS.md` load them into every session. `.astra/` gains the update machinery and the manifest.

Restart your agent session after an install. Agents read the config files at session start.

## Where each kind of tool lives, and why

Every directory under `tools/` is one of four kinds, and `tools/astra upgrade` refreshes the software of any of them. The kind decides where the tool lands and how it stays current. Each tool's `install.sh` declares its kind on a `# astra-scope:` line near the top. `tools/tests/test-tool-kinds.sh` fails on any tool that declares nothing or cannot be uninstalled.

### Files in your repo

These tools declare `# astra-scope: repo`. Skills, doctrine, and small scripts are copied into the repo as ordinary committed files: `.claude/skills/`, `.doctrine/`, and `.astra/<tool>/`. Anyone who clones the repo gets them, with no astra on their machine.

`.astra/manifest.json` records every file and its hash. The post-commit and post-merge hooks run `.astra/astra-update --pull` in the background. That command replaces a file only while it is still exactly what the installer wrote. A file you edited is reported and left alone.

The copies live in the repo for three reasons. The repo must work on a machine that has never seen this toolbox. Two repos can sit at different versions. And a bug in the toolbox cannot reach into a repo that did not ask for an update.

### Config in your repo

These tools declare `# astra-scope: repo-config`. An MCP server is not a file to copy. Each agent reads its own list from `.mcp.json`, `.qwen/settings.json`, or `.codex/config.toml`, so the installer writes an entry there.

The manifest does not track these entries, and the hooks do not refresh them. To change one, re-run the installer with `tools/astra add <tool>` or the template command. The program the entry names updates on its own schedule, not through astra. An `npx` server is resolved by `npx` each time the agent launches it. The Xcode aggregator is one daemon on the machine, and the entry only points at it.

### Software on the machine

These tools declare `# astra-scope: machine`. Some things exist once per machine and cannot live in a repo. Homebrew formulas such as `axe` are one example. Background daemons such as the Xcode aggregator are another. So are signed `.app` wrappers that hold macOS permission grants, and downloaded model files.

A repo install never runs these. Adding a set to a repo must not install software on your machine as a side effect. When a set needs one, the install prints `MACHINE <tool>: install once per machine` with the command. Run that tool's `install.sh` yourself, once. Its `uninstall.sh` keeps shared software unless you pass `--deps`.

### Updating the software on the machine

Re-running a repo install already upgrades the software its tools need, but it also rewrites the repo. `tools/astra upgrade` does only the machine half. It runs each tool's `deps.sh` and nothing else, so it touches no repo.

Run `tools/astra upgrade --list` to see the plan, `tools/astra upgrade` to refresh everything, or `tools/astra upgrade axe speech-bee` to refresh named tools. A failing tool does not stop the others. The command prints which ones failed and exits 1.

A `deps.sh` refreshes software only: Homebrew formulas, pipx and uv tools, the MacControlMCP app, a model file. It never reloads a daemon, rewrites a schedule, or rebuilds a signed app wrapper. That is why the command never runs an `install.sh`. The Xcode daemon's installer reloads its launchd jobs, which restarts the daemon and raises Xcode's approval dialogs again. The wrapper apps hold macOS permission grants that a rebuild would destroy. A machine tool that owns no software says so with a `# no-deps:` line in its `install.sh`.

Some repo-config installers also install the program their entry points at. The `ios-simulator` installer installs idb, and the `mac-control-mcp` installer downloads the app. Their `deps.sh` holds exactly that step, so `upgrade` can refresh it without a repo.

### Run in place

These tools have a `RUN-IN-PLACE` file instead of an `install.sh`. Small scripts fall here, such as `peer-review`, `bio-build`, `omniroute-health`, `ambrosio`, and `ollama-watch`. The `model-lab` tool is also one. It scouts and benchmarks local models for a machine's hardware, and it runs on Windows as well as macOS. Run `ls tools/*/RUN-IN-PLACE` for the full list. They run straight from this checkout and install nothing. The `RUN-IN-PLACE` file in each directory says why. They update when you `git pull` the toolbox.

To see a tool's kind, read the first lines of its `install.sh`, or look for `RUN-IN-PLACE` in its directory. Every installable tool has an `uninstall.sh` that undoes its own install and nothing else.

## The Xcode aggregator

The template does not install separate Xcode MCP servers into your repo. It writes one HTTP entry, `xcode-combined`, pointing at a single daemon on this machine (port 8767). That daemon fronts Apple's Xcode bridge, Drew's server, and a slice of XcodeBuildMCP behind one endpoint. A head-to-head on real projects resolved the overlaps: each capability appears once, under one name, from the vendor that won. The daemon runs under launchd, survives reboots, and waits for Xcode on its own. Xcode's approval prompt is answered once, for the daemon, and no per-session bridge ever spawns to ask again.

The practical consequences: build with the `build` tool (it returns warnings inline with file and line). When Xcode is not running you still get `xbm__build_run_sim`, `xbm__test_sim`, and the coverage tools, because that slice is headless. The tool named for what you want is the right one; there are no duplicate vendor variants to choose between.

## What is installed, where

Each repo answers for itself. `.astra/manifest.json` records which templates the repo has, the full resolved tool list, and the exact content hashes of every installed file. There is no central registry by design. The first push-based design let a bug in this repo damage other repos, so the direction was inverted. Each repo pulls, and this repo never reaches into anyone.

## Where the astra checkout lives

Nothing assumes a fixed location. Clone this repo anywhere, under any name. A repo records where it was installed from in its manifest. Suppose you move the checkout, or clone a repo onto a machine with no copy at the recorded path. Set `ASTRA_SOURCE=<path to your astra checkout>`, and updates and `convoq` work again. Clone the checkout with `--recurse-submodules`, because `convoq` needs the engine in `vendor/authsec-bridge`. `tools/tests/test-portable-install.sh` proves all of this by installing from a renamed copy into a repo on a machine with an empty home directory.

## Settings that belong to one machine

Some tools need a value that is true for one person or one Mac. Examples are a phone number to text and the name of another Mac. These values never go in the repo. They live in one file per machine, `~/.config/astra/config`, as `KEY="value"` lines. Nothing creates the file, and git never sees it. A tool that needs a missing value stops and prints the key to add. Each key can also be set as an environment variable, which wins over the file.

- `ASTRA_NOTIFY_PHONE` and `ASTRA_NOTIFY_CHAT_ID` are used by `botline` and `ollama-watch`.
- `ASTRA_LMS_HOST` is used by `ambrosio` and `lms-prune`.
- `ASTRA_PEER_HOST` is used by `ai-setup-diff`.
- `ASTRA_LAUNCHD_PREFIX` sets the launchd labels astra creates. The default is `com.astra`.
- `ASTRA_WORKLOG` and `ASTRA_PEER_REVIEW_REPOS` are used by `peer-review`.
- `GHOST_REPO` is used by `handlebars notes-append`.

`tools/lib/astra-config.sh` documents the keys in one place. Treat the file as private, because it can hold a phone number.

## How updates happen

`.astra/astra-update --pull`, run inside your repo, asks this repo whether anything moved on and updates in place. It only touches files that are still exactly what the installer wrote; anything you edited locally is reported, never overwritten. Every install wires a post-commit hook and a post-merge hook that run it in the background. A repo you commit to or pull into stays current without anyone thinking about it.

The whole interface is one command, run inside the repo:

```
<astra checkout>/tools/astra add writing        # a set from templates.json, or a single tool
<astra checkout>/tools/astra remove adhd       # gone for good; no update brings it back
<astra checkout>/tools/astra status
<astra checkout>/tools/astra list
<astra checkout>/tools/astra tree
<astra checkout>/tools/astra doctor
```

A tool that arrived through a template cannot be removed alone. `astra remove` refuses it and names the template that holds it. Remove the template, or add the tool separately first. Git does not clone hooks, so on a new machine or a fresh clone run `astra sync` once. It wires the hooks in every repo beside the astra checkout (or under the directories you name) that has astra tools. A repo never needs astra to work: installed tools are ordinary committed files, and the hook stays silent when no astra checkout is present.

## How bots know their tooling is current

They mostly do not need to. The post-commit hook keeps a working repo fresh, and MCP servers are read at session start. So a new session is a new snapshot of current config. For a long-running session in a repo nobody commits to, `.astra/astra-update --pull` is safe to run at any time; `.astra/update.log` says what the last run did. A locally modified file blocks its own update and appears in that log, which is the one staleness case that needs a human decision.
