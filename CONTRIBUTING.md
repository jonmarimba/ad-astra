# Contributing

This guide explains how to add a tool, a skill, or a template to the toolbox, and which tests check your work. Read QUICKSTART.md first, because it explains the four kinds of tool and why each one lands where it does.

## Add a tool

Run one command from the toolbox root:

```
tools/astra new my-tool --kind repo
```

The name uses lowercase letters, digits, and hyphens. The kind is one of five values, and each value matches what the tool must do.

- `skill` is a repo tool whose only payload is a `SKILL.md`. The command creates `agents-and-prompts/skills/my-tool/SKILL.md` for you to write. Its installer copies that file to `.claude/skills/my-tool/` in the target repo.
- `repo` is a tool with files that belong in the target repo, such as a script or a doctrine file. Its installer copies them to `.astra/my-tool/` and records each one in `.astra/manifest.json`. The post-commit hook then keeps them current.
- `repo-config` is a tool whose payload is an entry in an agent's config file, such as an MCP server in `.mcp.json`. The installer writes the entry. Re-running the installer is how the entry changes, because the manifest does not track these entries.
- `machine` is a tool that owns software on the machine: a Homebrew formula, a daemon, a signed app. It has a `deps.sh` that installs and upgrades the software and nothing else. A repo install never runs it.
- `run-in-place` is a script that runs from this checkout. It has a `RUN-IN-PLACE` file whose one line says why nothing needs installing, and it has no `install.sh`.

The command also writes `tools/tests/test-my-tool.sh`. Edit that test until it checks what your tool does. Then run:

```
bash tools/tests/test-my-tool.sh
bash tools/tests/test-tool-kinds.sh
```

If the tool belongs in a template, add its name to that template's `tools` list in `tools/lib/templates.json`.

## The promises every tool keeps

`tools/tests/test-tool-kinds.sh` fails if a directory under `tools/` declares no kind, or breaks the promises of its kind. Every tool with an `install.sh` has an `uninstall.sh` that undoes it. The first five lines of `install.sh` hold a `# astra-scope:` line that names the kind. A machine tool has a `deps.sh`, or says why it has none with a `# no-deps:` line.

An uninstaller removes what its installer wrote and nothing else. It keeps shared software unless the user passes `--deps`. It keeps a file the user edited by hand and says so. `tools/lib/astra-install.sh` and `tools/lib/uninstall-common.sh` hold the helpers that do this correctly, so use them.

Nothing may assume where the checkout lives or whose machine it runs on. Never write `~/svnCheckouts` or `/Users/<name>` in a script. Take a path from an environment variable or from `~/.config/astra/config`, and fail with a message that names the setting when it is missing. Put Homebrew on `PATH` with `export PATH="${ASTRA_PATH:-<default>}"`, so a test can hide the real one. Nothing installs globally. A tool that writes to `~/.claude`, `~/.codex`, or another home location is wrong.

## Write the test first

`tools/tests/TESTING.md` sets the standard. A test asserts the effect in the world: a file exists, an entry is in the config, the exit code is right. Every test file has at least one RED control, an input that must fail. A missing dependency is a loud failure, never a quiet skip. Fake only what would touch a person or another machine, and fake it at an environment seam in the tool itself.

The fast tier, `tools/tests/run-all.sh`, has a 20-second budget. A test that takes longer belongs in the slow tier: put `# TIER: slow` and a reason in its first three lines. Both tiers must pass before you push. `tools/tests/test-clone-portability.sh` runs them from a copy of the checkout on an empty home directory.

## Add a template

A template is an entry in `tools/lib/templates.json` with a `description`, a `templates` list of member templates, and a `tools` list. Both lists are optional. Members resolve in order, and a tool reached twice installs once. Prefer composing existing templates to listing their tools again. After any change, run these two commands:

```
tools/lib/refresh-readme-tree.sh
bash tools/tests/test-template-tree.sh
```

The first rewrites the template tree in `README.md`. The second fails if the tree and the catalogue disagree.

## Write for the reader

Every `.md` file here follows ASD-STE100 Simplified Technical English: complete sentences, active voice, one idea per sentence, about 20 words per sentence in instructions. Run the checks on a document before you commit it:

```
node tools/check-prose/check-prose.js README.md
tools/check-banned-phrases/check-banned-phrases.sh README.md
```

Never run them on a PDF sidecar. A sidecar is a verbatim record of its PDF, and the prose tools skip those files by name.
