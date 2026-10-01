# ADVERSARIAL round — refute the post-panel fix commits

You are one voice in a three-brand ADVERSARIAL panel. Your job is to REFUTE, not to review: the driver landed fix commits AFTER each checkpoint panel reviewed, so these commits' claims have never faced hostile eyes. Default to disbelief. A claim you cannot break after genuinely trying is worth reporting as "attacked and held" — but the attack must be real: name what you tried.

Repo: `~/svnCheckouts/js-db-ad-astra`, branch `tool-templates`.

## The commits whose claims you are attacking

- `4333ffb` + `920dd05` — daemon hardening after the Phase 1 panel (concurrent lock-free listing, bounded drains, MCPError forwarding, env pass-through, dispatch-first routing, client drains never adjudicating connection state).
- `cb84b67` — config hardening (env implemented, top-level key rejection).
- `91858cd` — sieve/map hardening after the Phase 3 panel (two-pass composition, add-only refresh, from_env passthrough gate, effective rename table, longest-first alternation).
- `4f8b3a3` — relay/deployment hardening after the Phase 5 panel (call-path break fires surface change, ListenHandler for the modern era, bounded downstream registry, pid-file preempt with escalation, validate-before-side-effects, version-check gap closures).

Read the commits (`git show <sha>`) AND the current state of `tools/xcode-mcp-front/daemon.py`, `mcp_config.py`, `repo-daemon-run.sh`, `repo-daemon-install.sh`, and the test files they cite. The three `SYNTHESIS_phase*.md` files in `colloquium/` state what was claimed fixed and what was deferred — treat every "fixed" line there as a claim to attack.

## Attack surface, concretely

1. **Each fix's own new bugs.** A fix landed under time pressure after a panel is the classic place for a regression the original tests do not see. The two-pass composition, the add-only refresh, the call_tool wrapper split (`call_tool` / `_call_tool_locked`), the LRU registry eviction, the pid-file preempt — trace each for a state the fix itself creates.
2. **Fixes that only half-close the panel's finding.** Compare each synthesis "fixed" claim against the code: is there a path the fix does not cover? (Example shape: the call-path break now fires — do ALL break paths fire exactly once, or can a flap fire zero or twice?)
3. **Interactions between fixes from different rounds.** The bounded registry meets the debounced broadcaster; the from_env passthrough gate meets the single-repo candidate fallback; the 60-second connect timeout meets the foreign-dialog grace assertion (`FOREIGN_DIALOG_GRACE_SECONDS >= CONNECT_TIMEOUT_SECONDS` is a startup abort — check what the repo-daemon's env default does to instances that ALSO set a small connect timeout, and what the deployed combined instance's config file now contains).
4. **The tests added with the fixes.** Same standard as always: can any pass against a broken implementation? Did the watched-red discipline actually hold (the commit messages claim red counts — check the assertions would really have been red)?

## Rules of engagement

- Cite file:line for every claim; separate read from inferred from executed.
- WRITE A TEST for your best finding where feasible: a runnable command or script against the real code that demonstrates the break (or would, if you cannot execute in your sandbox — then make it copy-paste runnable and say so). A finding with a failing test outranks three plausible paragraphs.
- Rank findings most-severe-first. "Attacked and held" verdicts go at the end, each with the attack named.
