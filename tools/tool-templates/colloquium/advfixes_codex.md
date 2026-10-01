## The fix set does not hold.

I found four executable counterexamples and four additional gaps. The first two can execute the wrong tool or take down a working repo daemon.

### 1. A pre-list call still lets an alias hijack another upstream’s natural name. High severity.

The two-pass policy runs only during `tools/list` composition in [daemon.py:1036](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:1036). Before any list, `tools/call` searches mapped aliases before natural prefixes in [daemon.py:1185](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:1185), refreshes only that selected upstream, and inserts its alias into an empty dispatch table in [daemon.py:1151](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:1151).

I executed the current handler with the committed hostile-order configuration. The first call to `alpha__ping` returned `thief-stole` and exited 1. This directly refutes the claim that natural ownership is order-independent in [SYNTHESIS_phase3.md:11](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/colloquium/SYNTHESIS_phase3.md:11).

The committed test first populates dispatch through `tools/list` at [test-mcp-front-daemon.sh:76](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-mcp-front-daemon.sh:76). It tests the hostile call much later at [test-mcp-front-daemon.sh:185](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-mcp-front-daemon.sh:185). Therefore, the test cannot see the pre-list state created by the fix.

The correct policy must also run on the first call. Refreshing one guessed candidate cannot resolve global natural-versus-alias ownership.

This HTTP regression test can be inserted before the first existing `tools/list`. I could not apply it because the workspace is read-only.

```diff
@@
   XCODE_MCP_FRONT_HOME="$SB/home" \
   XCODE_MCP_FRONT_AUTO_ALLOW=0 \
+  XCODE_MCP_FRONT_RECONNECT_POLL_S=60 \
   XCODE_MCP_FRONT_SERVER_NAME="astra-test-front" \
@@
 mcp_call() {
@@
 }
 
+# Both upstreams must be connected, but no tools/list may have composed dispatch yet.
+waited=0
+until grep -qF "[aaathief] connected" "$SB/daemon.log" &&
+      grep -qF "[alpha] connected" "$SB/daemon.log"; do
+  [ "$waited" -lt 20 ] || fail "both upstreams did not connect"
+  sleep 1
+  waited=$((waited+1))
+done
+mcp_call tools/call '{"name":"alpha__ping","arguments":{}}' > "$SB/prelist-owner.out"
+assert_contains "$SB/prelist-owner.out" "alpha-pong" \
+  "the natural owner wins even before the first tools/list"
+assert_not_contains "$SB/prelist-owner.out" "thief-stole" \
+  "a mapped alias cannot hijack a natural name before composition"
+
 # Existing tools/list wait follows.
```

### 2. The launcher validates only one JSON shape before destructive side effects. High severity.

The synthesis claims validation occurs before any side effect in [SYNTHESIS_phase5.md:15](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/colloquium/SYNTHESIS_phase5.md:15). Phase 3 also recorded that the installer would run `mcp_config.py validate` before activating a generated file in [SYNTHESIS_phase3.md:29](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/colloquium/SYNTHESIS_phase3.md:29).

The launcher only checks that `.mcpServers` is a nonempty object in [repo-daemon-run.sh:29](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/repo-daemon-run.sh:29). It then preempts the prior daemon and rewrites the port and `.mcp.json` in [repo-daemon-run.sh:41](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/repo-daemon-run.sh:41). The real validator runs later inside the newly executed daemon.

I passed this configuration to both predicates:

```json
{"mcpServers":{"alpha":{"command":"c","transporter":"beam"}}}
```

The `run.sh` predicate returned 0. `mcp_config.py validate` returned 65 with `unknown field 'transporter' on server 'alpha'`.

The load-bearing assumption is that a prior daemon is running when the generated configuration changes. Under that normal relaunch state, the launcher kills the working daemon before learning that its replacement cannot start. The existing test covers only the empty placeholder in [test-mcp-front-repo-daemon.sh:42](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-mcp-front-repo-daemon.sh:42).

### 3. Concurrent queued calls emit the same break notification more than once. Medium severity.

Each caller reads `was_broken` before entering the lock in [daemon.py:601](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:601). The first caller marks the connection broken inside the lock in [daemon.py:607](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:607). Every caller that already sampled `False` then observes `True` and fires independently.

I executed two queued calls against one session that broke while the first call held the lock. The recorded notifications were:

```text
['alpha call broken', 'alpha call broken']
```

The same race scales to every queued caller. The relay test exercises an upstream-generated `list_changed` event in [test-mcp-front-daemon.sh:122](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-mcp-front-daemon.sh:122), but no current test exercises a call-path transport break.

### 4. The registry cap can evict a live legacy listener while retaining abandoned sessions. Medium severity.

The registry moves entries by request activity and evicts the oldest at 128 entries in [daemon.py:960](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:960). A timed-out send is not removed because `move_on_after` does not raise; only an exception reaches the removal branch in [daemon.py:983](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:983).

I registered one active session followed by 128 transient sessions. The current registry reported `128 False`, meaning the active session’s key had been evicted. The test client creates a new session for every call in [test-mcp-front-daemon.sh:62](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-mcp-front-daemon.sh:62), so the registry counts sequential churn, not concurrent clients. The claim that 128 exceeds the concurrent-client count does not protect a quiet but active legacy listener.

### 5. A stale pid file can still identify and kill a bystander. Medium severity, inferred.

The launcher trusts the recorded PID if that process’s command contains the daemon path anywhere, then sends TERM and possibly KILL in [repo-daemon-run.sh:45](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/repo-daemon-run.sh:45). If the old daemon exited and its PID was reused by `tail -f <same daemon.py>`, the substring predicate accepts the bystander.

The current test starts the bystander under a different PID while the pid file still names the real old daemon in [test-mcp-front-repo-daemon.sh:133](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-mcp-front-repo-daemon.sh:133). It does not exercise stale-PID reuse.

This finding is inferred because the sandbox blocked `ps`. It requires both PID reuse and a reused process whose arguments contain the same path. Those conditions are uncommon, but the resulting KILL is destructive.

### 6. The worktree fix also accepts any nested directory as a repository target. Low severity.

The installer checks only `git rev-parse --is-inside-work-tree` in [repo-daemon-install.sh:38](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/repo-daemon-install.sh:38). It does not compare the requested path with `git rev-parse --show-toplevel`.

I ran the predicate against `js-db-ad-astra/tools/tests`. It returned `true`, while `--show-toplevel` returned `js-db-ad-astra`. The installer would consequently create `.astra`, `.mcp.json`, and a daemon identity under the nested directory. The committed test passes an actual repository root in [test-mcp-front-repo-daemon.sh:25](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-mcp-front-repo-daemon.sh:25).

### 7. A small explicit connect timeout bypasses the repo default and causes a startup abort. Low severity.

The launcher preserves any nonempty caller value in [repo-daemon-run.sh:91](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/repo-daemon-run.sh:91). The daemon rejects a timeout at or below the default six-second foreign grace in [daemon.py:300](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:300).

I imported the daemon with `XCODE_MCP_FRONT_CONNECT_TIMEOUT_S=5`. It exited 1 with the foreign-grace diagnostic. Therefore, a template using the advertised per-repo override must also know to lower `XCODE_MCP_FRONT_FOREIGN_GRACE`.

The deployed combined instance does not have this break. Its [config:1](/Users/jonathan/.xcode-combined-front/config:1) sets 60 seconds, and the current default grace is six seconds.

### 8. An empty expected version disables the version check while passing validation. Low severity.

The loader accepts every string, including `""`, in [mcp_config.py:121](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/mcp_config.py:121). The daemon checks only truthy expected versions in [daemon.py:726](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:726).

I validated a configuration containing `"version": ""`; it returned 0. The current test rejects only a non-string version in [test-mcp-front-config.sh:174](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-mcp-front-config.sh:174).

## Five attacks held.

- I injected a failed client drain. It returned `None` while preserving both `known_broken=False` and the session reference, consistent with [daemon.py:576](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:576).
- I injected an upstream `MCPError`. The result preserved the message, remained an error result, and kept the connection healthy through [daemon.py:615](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:615).
- I checked repeated cursors, fresh cursors forever, and elapsed-time failure paths. The repeated-cursor set, page ceiling, and timeout independently bound the drain in [daemon.py:554](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:554).
- I queried the installed MCP 2.1.1 capability path for protocol `2026-07-28`. It returned `list_changed=True`; the `ListenHandler` wiring in [daemon.py:1302](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:1302) held.
- I attacked overlapping rewrite keys. The longest-first ordering in [daemon.py:875](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:875) prevents the claimed `foo` versus `foo-bar` partial rewrite. The acknowledged non-word-edge limitation remains deferred rather than falsely fixed.
## The fix set does not hold.

I found four executable counterexamples and four additional gaps. The first two can execute the wrong tool or take down a working repo daemon.

### 1. A pre-list call still lets an alias hijack another upstream’s natural name. High severity.

The two-pass policy runs only during `tools/list` composition in [daemon.py:1036](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:1036). Before any list, `tools/call` searches mapped aliases before natural prefixes in [daemon.py:1185](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:1185), refreshes only that selected upstream, and inserts its alias into an empty dispatch table in [daemon.py:1151](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:1151).

I executed the current handler with the committed hostile-order configuration. The first call to `alpha__ping` returned `thief-stole` and exited 1. This directly refutes the claim that natural ownership is order-independent in [SYNTHESIS_phase3.md:11](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/colloquium/SYNTHESIS_phase3.md:11).

The committed test first populates dispatch through `tools/list` at [test-mcp-front-daemon.sh:76](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-mcp-front-daemon.sh:76). It tests the hostile call much later at [test-mcp-front-daemon.sh:185](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-mcp-front-daemon.sh:185). Therefore, the test cannot see the pre-list state created by the fix.

The correct policy must also run on the first call. Refreshing one guessed candidate cannot resolve global natural-versus-alias ownership.

This HTTP regression test can be inserted before the first existing `tools/list`. I could not apply it because the workspace is read-only.

```diff
@@
   XCODE_MCP_FRONT_HOME="$SB/home" \
   XCODE_MCP_FRONT_AUTO_ALLOW=0 \
+  XCODE_MCP_FRONT_RECONNECT_POLL_S=60 \
   XCODE_MCP_FRONT_SERVER_NAME="astra-test-front" \
@@
 mcp_call() {
@@
 }
 
+# Both upstreams must be connected, but no tools/list may have composed dispatch yet.
+waited=0
+until grep -qF "[aaathief] connected" "$SB/daemon.log" &&
+      grep -qF "[alpha] connected" "$SB/daemon.log"; do
+  [ "$waited" -lt 20 ] || fail "both upstreams did not connect"
+  sleep 1
+  waited=$((waited+1))
+done
+mcp_call tools/call '{"name":"alpha__ping","arguments":{}}' > "$SB/prelist-owner.out"
+assert_contains "$SB/prelist-owner.out" "alpha-pong" \
+  "the natural owner wins even before the first tools/list"
+assert_not_contains "$SB/prelist-owner.out" "thief-stole" \
+  "a mapped alias cannot hijack a natural name before composition"
+
 # Existing tools/list wait follows.
```

### 2. The launcher validates only one JSON shape before destructive side effects. High severity.

The synthesis claims validation occurs before any side effect in [SYNTHESIS_phase5.md:15](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/colloquium/SYNTHESIS_phase5.md:15). Phase 3 also recorded that the installer would run `mcp_config.py validate` before activating a generated file in [SYNTHESIS_phase3.md:29](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/colloquium/SYNTHESIS_phase3.md:29).

The launcher only checks that `.mcpServers` is a nonempty object in [repo-daemon-run.sh:29](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/repo-daemon-run.sh:29). It then preempts the prior daemon and rewrites the port and `.mcp.json` in [repo-daemon-run.sh:41](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/repo-daemon-run.sh:41). The real validator runs later inside the newly executed daemon.

I passed this configuration to both predicates:

```json
{"mcpServers":{"alpha":{"command":"c","transporter":"beam"}}}
```

The `run.sh` predicate returned 0. `mcp_config.py validate` returned 65 with `unknown field 'transporter' on server 'alpha'`.

The load-bearing assumption is that a prior daemon is running when the generated configuration changes. Under that normal relaunch state, the launcher kills the working daemon before learning that its replacement cannot start. The existing test covers only the empty placeholder in [test-mcp-front-repo-daemon.sh:42](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-mcp-front-repo-daemon.sh:42).

### 3. Concurrent queued calls emit the same break notification more than once. Medium severity.

Each caller reads `was_broken` before entering the lock in [daemon.py:601](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:601). The first caller marks the connection broken inside the lock in [daemon.py:607](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:607). Every caller that already sampled `False` then observes `True` and fires independently.

I executed two queued calls against one session that broke while the first call held the lock. The recorded notifications were:

```text
['alpha call broken', 'alpha call broken']
```

The same race scales to every queued caller. The relay test exercises an upstream-generated `list_changed` event in [test-mcp-front-daemon.sh:122](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-mcp-front-daemon.sh:122), but no current test exercises a call-path transport break.

### 4. The registry cap can evict a live legacy listener while retaining abandoned sessions. Medium severity.

The registry moves entries by request activity and evicts the oldest at 128 entries in [daemon.py:960](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:960). A timed-out send is not removed because `move_on_after` does not raise; only an exception reaches the removal branch in [daemon.py:983](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:983).

I registered one active session followed by 128 transient sessions. The current registry reported `128 False`, meaning the active session’s key had been evicted. The test client creates a new session for every call in [test-mcp-front-daemon.sh:62](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-mcp-front-daemon.sh:62), so the registry counts sequential churn, not concurrent clients. The claim that 128 exceeds the concurrent-client count does not protect a quiet but active legacy listener.

### 5. A stale pid file can still identify and kill a bystander. Medium severity, inferred.

The launcher trusts the recorded PID if that process’s command contains the daemon path anywhere, then sends TERM and possibly KILL in [repo-daemon-run.sh:45](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/repo-daemon-run.sh:45). If the old daemon exited and its PID was reused by `tail -f <same daemon.py>`, the substring predicate accepts the bystander.

The current test starts the bystander under a different PID while the pid file still names the real old daemon in [test-mcp-front-repo-daemon.sh:133](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-mcp-front-repo-daemon.sh:133). It does not exercise stale-PID reuse.

This finding is inferred because the sandbox blocked `ps`. It requires both PID reuse and a reused process whose arguments contain the same path. Those conditions are uncommon, but the resulting KILL is destructive.

### 6. The worktree fix also accepts any nested directory as a repository target. Low severity.

The installer checks only `git rev-parse --is-inside-work-tree` in [repo-daemon-install.sh:38](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/repo-daemon-install.sh:38). It does not compare the requested path with `git rev-parse --show-toplevel`.

I ran the predicate against `js-db-ad-astra/tools/tests`. It returned `true`, while `--show-toplevel` returned `js-db-ad-astra`. The installer would consequently create `.astra`, `.mcp.json`, and a daemon identity under the nested directory. The committed test passes an actual repository root in [test-mcp-front-repo-daemon.sh:25](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-mcp-front-repo-daemon.sh:25).

### 7. A small explicit connect timeout bypasses the repo default and causes a startup abort. Low severity.

The launcher preserves any nonempty caller value in [repo-daemon-run.sh:91](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/repo-daemon-run.sh:91). The daemon rejects a timeout at or below the default six-second foreign grace in [daemon.py:300](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:300).

I imported the daemon with `XCODE_MCP_FRONT_CONNECT_TIMEOUT_S=5`. It exited 1 with the foreign-grace diagnostic. Therefore, a template using the advertised per-repo override must also know to lower `XCODE_MCP_FRONT_FOREIGN_GRACE`.

The deployed combined instance does not have this break. Its [config:1](/Users/jonathan/.xcode-combined-front/config:1) sets 60 seconds, and the current default grace is six seconds.

### 8. An empty expected version disables the version check while passing validation. Low severity.

The loader accepts every string, including `""`, in [mcp_config.py:121](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/mcp_config.py:121). The daemon checks only truthy expected versions in [daemon.py:726](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:726).

I validated a configuration containing `"version": ""`; it returned 0. The current test rejects only a non-string version in [test-mcp-front-config.sh:174](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-mcp-front-config.sh:174).

## Five attacks held.

- I injected a failed client drain. It returned `None` while preserving both `known_broken=False` and the session reference, consistent with [daemon.py:576](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:576).
- I injected an upstream `MCPError`. The result preserved the message, remained an error result, and kept the connection healthy through [daemon.py:615](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:615).
- I checked repeated cursors, fresh cursors forever, and elapsed-time failure paths. The repeated-cursor set, page ceiling, and timeout independently bound the drain in [daemon.py:554](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:554).
- I queried the installed MCP 2.1.1 capability path for protocol `2026-07-28`. It returned `list_changed=True`; the `ListenHandler` wiring in [daemon.py:1302](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:1302) held.
- I attacked overlapping rewrite keys. The longest-first ordering in [daemon.py:875](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:875) prevents the claimed `foo` versus `foo-bar` partial rewrite. The acknowledged non-word-edge limitation remains deferred rather than falsely fixed.