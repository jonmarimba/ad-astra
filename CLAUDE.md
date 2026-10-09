# CLAUDE.md — js-db-ad-astra

This repo is the shared toolbox for AI/dev tools, skills, and operating doctrine used across Jonathan's repos. Everything here is designed for per-repo installation, never global.

## Repo layout

**Tools are in `tools/<name>/`.** Each directory is one of four kinds. A `# astra-scope:` line near the top of its `install.sh` declares `repo`, `repo-config`, or `machine`. A `RUN-IN-PLACE` file in place of an `install.sh` declares the fourth. Every installable tool has an `uninstall.sh`. A machine tool has a `deps.sh` and a `Brewfile` for the software it owns. Templates in `tools/lib/templates.json` group tools, and a template can hold other templates. `tools/tests/test-tool-kinds.sh` enforces all of this. Some tools install operating doctrine into the target repo by calling `tools/lib/install-doctrine.sh`. Examples: `convocation`, `graphify-repo`, `xcode-mcp-front`, `handlebars`, `drew-kit`.

**Skills are in `agents-and-prompts/skills/<name>/`.** Each skill has a `SKILL.md`. A tool of the same name, such as `tools/asd-ste100`, installs it into a target repo's `.claude/skills/<name>/` and records it in the manifest. The humanizer is the largest example: its installer copies a vendored upstream `SKILL.md` and our voice-calibration layer beside it. `tools/astra new <name> --kind skill` scaffolds the tool for a new skill.

**Doctrine has one installer, `tools/lib/install-doctrine.sh`.** It installs a tool's operating rules into a target repo's `.doctrine/<slug>.md`. It also writes `@`-import blocks into CLAUDE.md and AGENTS.md (repo-relative paths, so they survive clone/move). Only capability-and-policy tools ship doctrine — convocation's convoq-first and mix-brands rules, the ASD-STE100 writing standard, and so on. Pure-mechanism tools do not. Companion scripts `uninstall-doctrine.sh` and `uninstall-common.sh` reverse the process.

## The cardinal rule

Nothing from this repo is ever installed globally (`--global`, `~/.agents/`, `~/.claude/skills/`). Everything is per-repo. When installing a skill or tool into a repo, run the installer FROM this repo INTO the target repo, with `tools/astra add <tool-or-template>` or `python3 tools/lib/template.py install <name> --into <repo>`.

Each kind of tool stays current a different way. Files in a repo (`# astra-scope: repo`) are refreshed by the repo's post-commit and post-merge hooks, which run `.astra/astra-update --pull`. Config entries (`repo-config`) change when you re-run the installer. Software on the machine (`machine`) is refreshed by `tools/astra upgrade`, which runs each tool's `deps.sh` and nothing else. Run-in-place tools update with `git pull`. QUICKSTART.md explains all four.

Installers pull external dependencies fresh from their source, and a re-run keeps a file the user edited by hand. Do not snapshot an external dependency as a local file, because that freezes it and cuts off updates. The one deliberate exception is the humanizer's upstream `SKILL.md`, vendored under `agents-and-prompts/skills/humanizer/upstream/` with its commit recorded; refresh it with `tools/humanizer/vendor.sh`.

To add a tool, run `tools/astra new <name> --kind <kind>`. CONTRIBUTING.md explains the kinds, the promises each keeps, and the tests that check them.

## Reference install scripts

Read these before writing a new one:

- `tools/convocation/install.sh` — tool with doctrine installation via `--into <repo>`
- `tools/drew-kit/install-into-repo.sh` — tool installed into another repo's MCP config
- `tools/lib/install-doctrine.sh` — the shared doctrine installer (writes `.doctrine/` files + `@`-import blocks)
- `agents-and-prompts/skills/humanizer/install.sh` — skill with third-party dependency pulled from external source per-repo

## Writing standards

All prose that a human reads follows ASD-STE100 Simplified Technical English: complete sentences, active voice, one idea per sentence. Sentences run roughly 20 words for instructions and 25 for description. No fragments, no bold-label-then-fragment, no sentences about the document itself.

Markdown is never hard-wrapped. One paragraph per line, let the editor soft-wrap.
