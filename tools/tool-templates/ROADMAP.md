# Roadmap — from the hard-coded aggregator to the tool-template system

Synthesised by GhOST-Claude, 2026-08-31, from a three-brand colloquium: Claude, Codex (`gpt-5.6-sol`) and GLM-5.2 via ollama-cloud, each reviewing the same brief independently. Raw answers are in `colloquium/`. Every claim below that carries a line number was **verified against the file by me**, not taken on a panelist's word — a verdict from another agent is a lead, not a source.

## What the colloquium changed about the plan

**The template system already exists.** `tools/lib/template.py`, `templates.json` with `swift-ios`, `legal-pdf`, `kicker-dev` and `writing` already defined, `astra-install.sh` placing everything under `<repo>/.astra/` with per-file hashes in `.astra/manifest.json`, the vendored `astra-update`, and `registry.py`. Seven `tools/mcp-*/tool.json` files already describe MCP tools — and **zero code reads them**. The job is finishing what is there, not building beside it. Two of the spec's three "open questions" were already answered in code.

**Three defects were found independently by all three brands**, which is the strongest signal this exercise produced:

1. **A healthy-but-empty upstream is indistinguishable from a disconnected one, and one empty upstream blanks the entire surface.** `on_list_tools` returns zero tools for *every* upstream when any one is missing, while the daemon's own instructions text promises the opposite. It is live today: during an Xcode reconnect, Drew's tools — which need no Xcode at all — vanish for the duration. **And the sieve makes it catastrophic**: blocking every tool on one small upstream would serve nothing from anywhere.
2. **Prefix routing cannot survive the tool map.** Routing is `name.startswith(prefix)`, so a mapped name that drops the prefix is advertised and then rejected as unknown. Prefixes also change when the upstream *count* changes, because a single upstream is unprefixed — so adding a second server silently renames every tool the first one offered.
3. **`mcp_tools.py`, which I wrote this morning, misreads any server that says anything unexpected.** It assumes the next stdout line answers the request just sent. A banner line or a spec-legal notification arriving first is misread or crashes it. Its own docstring forbids exactly this class of error.

## Ordered increments

TDD throughout. **An increment whose test cannot fail is not an increment**, so each states how its test goes red. Small on purpose; time is not the constraint, correctness is.

### Phase 0 — make the tests worth trusting

**0.1 Fix the RED helper.** `red()` discards stdout and stderr and accepts any nonzero exit except 126 and 127, so a control passes when the command fails for a missing config, an import error or a typo'd flag. It proves something broke, not that the guard rejected bad input. Replace with an expected exit code plus an expected literal diagnostic; `assert_rc` already does the first half. *Red when*: a deliberately mis-typed flag makes an old-style RED control pass and the new one fail.

**0.2 Split the suites.** `run-all.sh` becomes the fast tier; a second entry point carries the slow tier. *Red when*: the fast tier exceeds its time budget — assert the budget in CI, do not trust a stopwatch.

### Phase 1 — the generic aggregator, reproducing today's behaviour exactly

**1.1 Config loader.** Read `_mcp_info.json` in the Claude Code shape. Reject `env`, `cwd` and `url` with a precise message naming the unimplemented field rather than ignoring them — the spec advertises the full shape and the daemon passes only command and args, which is a late failure waiting to happen. *Red when*: a config with `url` is accepted silently.

**1.2 Replace the colon-delimited env var with the file.** Same two upstreams, same prefixes, same served surface. *Red when*: a command path containing a colon or an argument containing a comma — both currently corrupt — round-trips wrongly.

**1.3 Explicit dispatch table.** Build `exposed name -> (upstream, upstream tool name)` when the surface is composed. Consult it first; keep prefix matching only as fallback. Reject duplicate prefixes, duplicate exposed names, and prefixes that are prefixes of each other (`a` and `a__b` make `a__b__tool` order-dependent) at load. *Red when*: two upstreams both offering `version` resolve to the same exposed name without an error.

**1.4 Separate connection state from emptiness.** Track connectedness on `Upstream`. A connected upstream returning zero tools contributes zero tools; a disconnected one is reported as unavailable and **does not blank the others**. *Red when*: with one upstream stopped, `tools/list` returns zero tools instead of the other's.

**1.5 Correct pagination or refuse it.** One downstream cursor is currently passed to every upstream, and cursors are per-server opaque tokens. Either drain all upstreams into a snapshot, or encode per-upstream positions in an aggregate cursor. *Red when*: a stub upstream that paginates returns a duplicated or missing page.

### Phase 2 — the sieve

**2.1 Block list with a required `why`.** Applied *after* the availability check from 1.4, never before. *Red when*: blocking every tool on one upstream empties the whole surface.
**2.2 Enforce `why` at template-authoring time, not at daemon start.** Rejecting at load fails the repo, at startup, for a sentence someone forgot in astra. Test the template source; warn and serve at runtime.
**2.3 Fixed evaluation order**, declared and tested: list, identify each tool as `server/tool`, apply source-qualified blocks, apply renames, rewrite descriptions, validate global uniqueness, publish.

### Phase 3 — the map

**3.1 Rename with source qualification**, replacing the original name; a separate `alias` verb if both names are ever wanted.
**3.2 Description rewriting that cannot corrupt prose.** Replace only exact recognised tool references, never substrings inside other identifiers. Warn on any remaining reference to a renamed tool. *Red when*: a tool named `read` renames and mangles the word "already" in another tool's description.
**3.3 Degraded state for a stale map entry.** "Warn, never refuse" and "a stale map entry is a hard error" contradict each other, and an upstream rename triggers both. Resolution: drop the invalid alias, keep serving the valid surface, report it in-band and to the human.

### Phase 4 — notifications and versions

**4.1 Forward `listChanged`.** The sieve is already re-applied per call because the daemon is a live pass-through; the real breakage is the *client's* cached list going stale with no notification. This turns the daemon from a request proxy into a notification relay — a design change, not an addition.
**4.2 Version recording and warning.** Exact mismatch is the only generic conclusion; `serverInfo.version` is opaque, so do not classify "newer" or "older" without a per-upstream comparator. Warn in-band and, once per distinct mismatch and persisted, to the human. Suggest running the collision tool; never auto-run it.

### Phase 5 — the deployment unit, which the spec never resolved

The daemon is machine-global and one launchd job; templates are per-repo. Two repos wanting different surfaces cannot both be served, and the first symptom appears only on the second repo. **Both Claude and Codex independently proposed the same fix**: one broker, one approved PID, one port, with a named profile per resolved config (`/mcp/<profile>`), each repo's `.mcp.json` pointing at its own path. This also dissolves the three-daemon approval ceiling, because that ceiling counts processes, not surfaces.

Security boundary, raised by Codex and worth stating plainly: every `command` in a config runs inside a long-lived user process. The broker must consume only configs installed into a user-owned runtime directory by an explicit apply step, never scan arbitrary checkouts, and execute argument arrays without a shell.

### Phase 6 — the ad astra tool format

Build on `tool.json`, which exists and has no reader, rather than inventing a third format. Give it a reader first — that single increment converts seven dead files into a validated registry. Declare dependencies **by ecosystem**, not brew-only: the repo already installs via npm, `uv` and Homebrew, and `xcode-mcp-front` additionally needs an Automator `.app`, a launchd plist and TCC grants a human clicks. A brew-only model under-declares more than half of what is here, silently.

Third-party adoption without submodules: a descriptor naming source coordinate, pinned version and artifact digest, with a local checkout path as an optional development override. Note that `astra-install.sh` currently records an **absolute** source path that `astra-update` later requires to exist, so a cloned repo cannot update on another machine — that must change for third-party tools to work at all.

## Questions only Jonathan can answer

1. **Sieve default direction.** Deny-list fails open, which suits coherence and silently defeats limiting when an upstream adds a tool. Allow-list, deny-list, or both?
2. **Profile granularity.** One profile per repo, or per template combination shared across repos?
3. **Does a repo's `mcp_info.json` get to add an upstream**, or only filter and rename ones the template chose? This is the difference between configuration and arbitrary command execution.

## Driving the implementation

**Model: Fable**, in this harness. The deciding factor is delegation — the Agent tool takes a per-subagent model override, which is exactly "use subagents for work its genius is not necessary for." It inherits the repo doctrine automatically, and `panel` is a shell tool so convocations work regardless.

**Not Sol**, for a principled reason: Sol is already the Codex voice in every convocation here, so making it the driver collapses one of three independent review brands into the thing being reviewed. Keep it as the adversary. Agreed on not GLM — it is the qwen-route voice and the lightest of the three.

**Assumption, marked:** Fable is untested by me on a long implementation run. Cheap check — give it Phase 1 alone and watch whether it holds TDD discipline before committing the whole roadmap to it.

**Branch:** `tool-templates`. Commit per increment, never per phase. **Convocation checkpoints** at the end of Phase 1, Phase 3 and Phase 5 — each is a point where a wrong decision becomes expensive to reverse.
