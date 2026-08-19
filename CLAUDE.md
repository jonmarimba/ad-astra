# CLAUDE.md — js-db-ad-astra

This repo is the shared toolbox for AI/dev tools, skills, and operating doctrine used across Jonathan's repos. Everything here is designed for per-repo installation, never global.

## Repo layout

**Tools** (`tools/<name>/`): each tool directory contains an `install.sh` that installs system-level dependencies (via npm/brew, pulled fresh from the external source every time — never a snapshot) and a `Brewfile` listing those dependencies. Some tools accept `--into <repo>` to install operating doctrine into a target repo by calling `tools/lib/install-doctrine.sh` under the hood. Examples: `convocation`, `graphify-repo`, `xcode-mcp-front`, `handlebars`, `drew-kit`.

**Skills** (`agents-and-prompts/skills/<name>/` or `skills/<name>/`): each skill has a `SKILL.md` that gets installed into a target repo's `.claude/skills/<name>/`. Some skills have their own `install.sh` for pulling third-party dependencies from an external source. The humanizer skill is the canonical example: its `install.sh` runs `npx skills add blader/humanizer` per-repo to get the upstream 35-pattern AI-tell detection, then copies our voice-calibration layer alongside it as a separate file. Skills without an install script are plain file copies.

**Doctrine** (`tools/lib/install-doctrine.sh`): installs a tool's operating rules into a target repo's `.doctrine/<slug>.md` and writes `@`-import blocks into CLAUDE.md and AGENTS.md (repo-relative paths, so they survive clone/move). Only capability-and-policy tools ship doctrine — convocation's convoq-first and mix-brands rules, the ASD-STE100 writing standard, and so on. Pure-mechanism tools do not. Companion scripts `uninstall-doctrine.sh` and `uninstall-common.sh` reverse the process.

## The cardinal rule

Nothing from this repo is ever installed globally (`--global`, `~/.agents/`, `~/.claude/skills/`). Everything is per-repo. When installing a skill or tool into a repo, run the installer FROM this repo INTO the target repo. The installer pulls any external dependencies fresh from their source every time, so re-running the installer is the update path. Never snapshot an external dependency as a local file — that freezes it and cuts off updates.

## Reference install scripts

Read these before writing a new one:

- `tools/convocation/install.sh` — tool with doctrine installation via `--into <repo>`
- `tools/drew-kit/install-into-repo.sh` — tool installed into another repo's MCP config
- `tools/lib/install-doctrine.sh` — the shared doctrine installer (writes `.doctrine/` files + `@`-import blocks)
- `agents-and-prompts/skills/humanizer/install.sh` — skill with third-party dependency pulled from external source per-repo

## Writing standards

All prose that a human reads follows ASD-STE100 Simplified Technical English: complete sentences, active voice, one idea per sentence, roughly 20 words for instructions and 25 for description. No fragments, no bold-label-then-fragment, no sentences about the document itself.

Markdown is never hard-wrapped. One paragraph per line, let the editor soft-wrap.
