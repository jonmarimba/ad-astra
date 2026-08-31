# Convocation checkpoint — Phases 4 and 5 of the tool-template aggregator

You are one voice in a three-brand review panel. Review commits `782c1de` (notifications and versions) and `efa84ec` (per-repo autonomous deployment) in `~/svnCheckouts/js-db-ad-astra`, branch `tool-templates`. Prior context: `colloquium/SYNTHESIS_phase1.md` and `SYNTHESIS_phase3.md` record what earlier panels found and how it was dispositioned. Findings are leads for the driver, who verifies each before acting; cite file and line, and separate what you read from what you infer.

## What landed

Read in full:

- `tools/xcode-mcp-front/daemon.py`, Phase 4 parts — the notification relay: `tools.listChanged` advertised by overriding `create_initialization_options` with a partial; upstream `ToolListChangedNotification` tapped via the client session's `message_handler`; surface-change events (connect, break, upstream listChanged) debounced 0.5s and broadcast to a registry of downstream sessions (latest per-connection `ServerSession`, keyed by `id(connection)` — one deliberate private-attribute read, commented); a 1-second `move_on_after` per send so a client that never drains its GET stream cannot wedge the broadcaster. Version checks: per-server `version` in the config, exact-string compare at connect, mismatch appended to `server.instructions` (re-read at each new session's initialize) and logged once per distinct (name, expected, found), persisted to `version-mismatches.json`.
- `tools/xcode-mcp-front/repo-daemon-install.sh` and `repo-daemon-run.sh` — Phase 5 per Jonathan's per-repo-autonomy decision (overriding the panel's broker design; do not re-litigate the decision, judge the implementation): APFS-cloned copies under `<repo>/.astra/mcp-front`, deterministic base port from the repo path via `cksum`, self-preempt only of the repo's own `daemon.py` by full path, step past foreign listeners without touching them, resolved port written to `./port` and the repo's `.mcp.json` via write-beside-rename, generated-but-unloaded launchd plist with bare-true KeepAlive.
- `tools/tests/test-mcp-front-daemon.sh` (Phase 4 sections), `tools/tests/test-mcp-front-repo-daemon.sh`, `tools/tests/stub_mcp_server.py`.
- Context: `ROADMAP.md` Phase 4–5; `SPEC.md` on version warnings ("warns, never refuses"; the two-audience design; the 21-modals hazard).

## What to attack

1. **Relay correctness.** Races between broadcast and session teardown; the `id(connection)` key being reused after GC for a new connection (a real Python hazard — is it reachable here?); the `move_on_after` send leaving a half-written frame; whether skipped-but-kept sessions eventually leak the registry; notification storms under a flapping upstream despite the debounce.
2. **Capability honesty.** Does the partial-override of `create_initialization_options` survive the SDK paths this daemon actually serves (handshake vs modern envelope)? Are there paths that still advertise `listChanged: false`?
3. **Version-check gaps.** A server whose `serverInfo` omits `version`; expected set but upstream found `None`; the persisted file growing unboundedly (a qwen phase-1-style eviction concern); mismatch notes accumulating in instructions across reconnects to DIFFERENT found versions.
4. **Port policy.** `cksum`-derived base ports: collision distribution across Jonathan's ~15 repos in a 3000-port range; the sleep-1 between preempt and probe (is a dying daemon's socket reliably released?); TOCTOU between the `lsof` probe and bind (two repos launching simultaneously); `.mcp.json` corruption paths; the `port` file going stale when launch fails after writing it.
5. **Self-preempt safety.** `pgrep -f "$HERE/daemon.py"` — can it match an unrelated process (an editor with the path in argv, another repo's daemon whose path contains this path as a prefix)? Is `kill` without `-TERM`-then-`-KILL` escalation enough for a wedged daemon?
6. **Installer contract.** The unservable `{"mcpServers": {}}` placeholder (loud death by design — is the launchd KeepAlive loop it causes acceptable, or a 5-second crash loop forever?); the HOME-refusal list's coverage; what a re-install over an existing installation does to a running daemon.
7. **Test honesty**, as always: anything that passes against a broken implementation, RED controls failing for the wrong reason, timing assumptions that flake under load.

## Output

Numbered findings, most severe first: claim, file:line, concrete failure scenario, one-to-two-sentence fix. Verified non-findings welcome. Judge the code, not the roadmap.
