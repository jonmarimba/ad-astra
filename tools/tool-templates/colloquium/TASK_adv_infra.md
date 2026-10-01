# ADVERSARIAL round — refute the infrastructure that never faced a panel

You are one voice in a three-brand ADVERSARIAL panel. REFUTE, do not review. This surface shipped with tests the driver wrote and watched go red, but no independent brand has attacked any of it. Default to disbelief; report "attacked and held" only after naming the attack.

Repo: `~/svnCheckouts/js-db-ad-astra`, branch `tool-templates`.

## The surface

1. **`tools/tests/lib.sh`** — the rewritten `red()` (exact rc + literal diagnostic) and its self-test `test-lib.sh`. Attack: can a call site satisfy the new contract while proving nothing (a diagnostic substring so generic it matches unrelated failures; an rc that several distinct guards share)? Sample real migrated call sites across `tools/tests/test-*.sh` and hunt for ones where the wrong guard could still produce the expected pair.
2. **`tools/tests/run-all.sh` / `run-slow.sh` / `test-run-tiers.sh`** — the parallel fast tier with the 15-second self-budget. Attack: output interleaving or rc aggregation losing a failure; the marker convention; xargs behavior when a test file name ever contains a space; the budget as an assertion (can a hung test file stall the tier forever with no verdict?).
3. **`tools/tool-templates/mcp_tools.py`** — the id-matched framing rewrite and `test-mcp-tools.sh`. Attack: the byte-buffer line splitter (CRLF, huge lines, partial UTF-8 at chunk boundaries), the deadline arithmetic, the stderr-drain thread lifetime, compare's refusal logic.
4. **`tools/lib/template.py`** — composition (`resolve_tools`), transitive claims, the record-only-clean-runs change, the `ASTRA_TEMPLATES_JSON` seam. Attack: uninstall ordering when a wrapper and leaf are removed in one session; the flat-list fallback for unresolvable recorded templates (can it over- or under-claim?); a member list plus tools list interleaving that dedup mangles.
5. **`tools/lib/tooljson.py`** and `test-tooljson.sh`. Attack: the legacy-token gate, ecosystem parsing edge cases (`brew:` empty coordinate is checked — what about whitespace, duplicates across ecosystems?), `list` exit semantics when one descriptor of seven is broken.
6. **`tools/lib/astra-update`** — the source-resolution fallback chain and `test-astra-update-portability.sh`. Attack: a WRONG sibling directory shadowing the intended source (same basename, different repo — the fallback would feed updates from an impostor checkout); the note printing once per tool but resolution being per-tool (mixed sources).
7. **The member installers** — `tools/ponytail/install.sh`/`uninstall.sh`, `tools/dedup-scan/install.sh`/`uninstall.sh`, and the swift-ios template edit. Attack: template uninstall of swift-ios on a machine where periphery is real (what does `uninstall-common`'s brew path actually do?); ponytail's network dependency inside a template install; idempotency claims.

## Rules of engagement

- Cite file:line; separate read / inferred / executed.
- WRITE A TEST for your best finding: a runnable command or script against the real code demonstrating the break (copy-paste runnable if your sandbox cannot execute). A failing test outranks three plausible paragraphs.
- Rank most-severe-first; "attacked and held" verdicts last, each naming the attack.
