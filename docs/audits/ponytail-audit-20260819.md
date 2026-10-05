# ponytail-audit — js-db-ad-astra, 2026-08-19

Read-only. **Experiments to run, not cuts to make.** Nothing applied. Reviewed by GhOST-OpenClaw as non-author, which changed every finding below.

Scope per the skill: over-engineering only. Correctness, security and performance explicitly out.

## Findings, demoted after review

`experiment:` **Seven MCP installer pairs might collapse to a dispatcher — or might be the interface working as designed.** `tools/mcp-*/` is 470 lines across 14 files, byte-identical apart from three comment lines each. That reads as duplication. But the separate directories with their own entrypoints ARE the composable-tool interface Jonathan asked for: *"split the MCP stuff from kicker into their own little tools, then start working on the templates, groups of these tools to be installed together."* Each wrapper only delegates to `mcp-bundle` with one server name, so a generic dispatcher is feasible — but `tool.json` is not it. Nothing consumes `tool.json`, and its dependency list is descriptive rather than an install contract. **Next step: prove a manifest-driven dispatcher on ONE server, with a compatibility path for `tools/mcp-x/install.sh` and by-effect install+uninstall tests. No deletion.** [tools/mcp-*/]

`experiment:` **Two installer conventions is real drift, but consolidation is not proven.** Four tools use `lib/astra-install.sh`; twelve hand-roll target parsing and the `$HOME` refusal. The drift risk is genuine — every hand-rolled copy is somewhere the home guard can be forgotten. But the helper is not a drop-in: `astra_place` copies files into `.astra/`, while `mcp-bundle` deliberately writes MCP config into `.mcp.json`, `.qwen/` and `.codex/`. Different operations. **Next step: audit the twelve by BEHAVIOUR, then extract only the shared target-validation guard and migrate one representative installer under test. No bulk rewrite.** [tools/*/install.sh]

`keep:` **`marked_to_pdf.sh` stays.** A documented deprecated fallback is not dead code. Its Marked-specific rendering may still have value, and that is Jonathan's call rather than an audit's. [tools/pdf-sidecars/marked_to_pdf.sh]

## Not cut, deliberately

`tests/` at 2,190 lines is the largest directory and is left alone. Test volume is not over-engineering, and this repo spent 2026-08-18 proving the opposite failure — tests that passed for their author and failed for their first adopter.

`lib/registry.py` keeps a `sync` command that refuses to run. A silently missing command is how retired behaviour creeps back.

## net: no estimate

The first draft claimed -400 lines. That was not earned — it came from file sizes rather than an attempted refactor, and both cuts turned out to be experiments with real design work in front of them.

## What this audit actually demonstrated

The top finding proposed removing the thing Jonathan explicitly asked for. Ponytail's framing rewards identifying duplication and cannot see that separateness was the requirement. Run by the author of the code, six hours after writing it, it produced a confident deletion estimate for a deliberate interface.

That is the honest result of the trial: the tool is useful for surfacing candidates and cannot be trusted to rank them, and it needs a reviewer who did not write the code. Which is also the argument the harness-settings note makes about every other model behaviour — the fix is structural, not configurational.
