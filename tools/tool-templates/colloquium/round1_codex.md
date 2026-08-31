**1. HOLES.**

1. **The deployment unit is undefined.** A template is installed per repository, but the wrapper is a persistent user-level service on a fixed port. One daemon per repository causes port collisions and recreates the approval-serialization ceiling. One global daemon cannot expose different sieves for different repositories. The specification identifies the multiple-daemon failure but leaves it unresolved ([SPEC.md](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/SPEC.md:38)). Use one user-level broker with shared upstream connections and named profile routes, such as `/mcp/<profile-id>`. Each repository selects a logical profile without spawning another `mcpbridge`.

2. **Several templates cannot safely write one generated MCP file.** The specification first names `_MCP_Config.json`, then `_wrapped_mcps.json`, and later `_mcp_info.json` ([SPEC.md](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/SPEC.md:25), [SPEC.md](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/SPEC.md:46), [SPEC.md](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/SPEC.md:183)). If Mac and iOS installers each rewrite the same underscore file, the last installer erases the other template’s contribution. Use `_mcp_info.json` and `mcp_info.json` consistently. A single resolver must recompute the union of all installed templates and write the machine file atomically.

3. **The current aggregation algorithm does not implement MCP pagination correctly.** It sends one downstream cursor to every upstream and concatenates their responses ([daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:700)). Upstream cursors belong to different cursor spaces. A paginated server will return missing, repeated, or invalid pages. Either drain every upstream list into a complete cached snapshot or issue aggregate cursors that encode each upstream’s position.

4. **`tools/listChanged` needs an end-to-end design, not only a promise to reapply the sieve.** The specification requires reapplication after the notification ([SPEC.md](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/SPEC.md:131)), but the current daemon neither consumes upstream notifications nor notifies downstream clients. Build immutable surface snapshots. Replace a snapshot only after listing, filtering, mapping, and collision validation all pass. Then send one downstream list-changed notification.

5. **A healthy empty server is indistinguishable from a disconnected server.** `Upstream.list_tools()` returns an empty list in both cases ([daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:463)). The aggregator then returns zero tools if any upstream returned zero ([daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:715)). This contradicts its own instruction that other upstreams remain available ([daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:783)). Track connection state separately. Keep the last known valid surface during an outage, and return an explicit error only when somebody calls the unavailable upstream.

6. **The inherited heartbeat and watchdog conflict with supported call lengths.** Tool calls may run for 600 seconds, while the process exits after 180 seconds without recorded progress ([daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:159), [daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:298)). The heartbeat also bypasses the upstream lock while a tool call holds it ([daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:482), [daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:612)). A three-minute build can therefore receive an untested concurrent `tools/list`, or a corrected serialized heartbeat can cause the watchdog to kill the build. Track active requests and connection-manager progress separately. One wedged upstream must restart only its own worker, because the current `os._exit(75)` drops healthy upstreams and their active calls.

7. **Version warnings cannot reliably appear in `initialize` with the current lifecycle.** The wrapper constructs static instructions before its background upstreams initialize, and it discards every upstream initialization result ([daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:551), [daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:759)). A downstream client can initialize before the wrapper knows any live versions. Gate readiness until the first upstream initialization completes, or implement a dynamic initialization response. Do not classify generic version strings as “newer” or “older”; `serverInfo.version` is opaque unless that upstream declares a comparator. Exact mismatch is the only generic conclusion.

8. **“Warn, never refuse” conflicts with stale-map behavior.** The specification says a version mismatch never prevents service, but it also calls an unresolved map entry a hard error ([SPEC.md](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/SPEC.md:97), [SPEC.md](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/SPEC.md:163)). A renamed upstream tool triggers both rules. The runtime needs a defined degraded state. My recommendation is to reject the invalid alias, continue serving the valid surface, and report the omitted alias in-band and through the human notification channel.

9. **Prefix routing is ambiguous.** The current behavior changes all tool names when the configured upstream count changes, because a single upstream is unprefixed ([daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:695)). It also routes by first matching prefix ([daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:727)). Prefixes `a` and `a__b` make `a__b__tool` order-dependent. Build an exact exposed-name-to-source dispatch table from the validated surface. Reject duplicate prefixes, duplicate exposed names, duplicate upstream tool names, and mapping collisions before activation. A prefix must not depend on how many servers happen to be configured.

10. **The sieve and map lack a fixed evaluation order.** A block could name an upstream tool, a prefixed tool, or a mapped tool. The specification also does not say whether mapping replaces the original name or adds an alias. Apply these phases in order: list upstream tools, identify each as `server/tool`, apply source-qualified restrictions, replace mapped names, rewrite exact description references, validate global uniqueness, then publish. `map` should replace the original. A separate `alias` operation can preserve both names when explicitly requested.

11. **Mechanical description replacement can corrupt prose.** Blind replacement can change a tool name embedded inside another identifier or alter an ordinary word. It also ignores titles, annotations, and other human-readable fields. Replace only exact recognized tool references. Warn on remaining references to renamed tools. Require an explicit description override when the text cannot be repaired mechanically.

12. **The advertised config shape exceeds the implementation.** The design accepts stdio entries with `env` and HTTP entries with `url` ([SPEC.md](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/SPEC.md:52)). The daemon passes only command and arguments to `StdioServerParameters` ([daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:559)). The comparison tool explicitly rejects HTTP ([mcp_tools.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/mcp_tools.py:62)). Step one must either implement `env`, working directory, and HTTP transport or reject those fields with a precise error. Advertising unsupported Claude-compatible fields will produce late failures.

13. **A repository config is an arbitrary-code execution boundary.** Every `command` runs inside a long-lived user process. Auto-loading an untrusted checkout’s config would execute its commands outside the repository’s immediate agent session. The broker should consume only validated configurations installed into a user-owned runtime directory by `astra apply`. It should never scan arbitrary repositories. It should execute argument arrays without a shell, reject non-loopback binding by default, and keep secret values out of generated repository files.

14. **The comparison script can report the wrong response.** It assumes the next stdout line belongs to the request it just sent ([mcp_tools.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/mcp_tools.py:82)). A server notification before response ID 2 is misread as the `tools/list` response. Its undrained stderr pipe can also fill and deadlock the child. Finally, the semantic pass receives only the first 200 description characters ([mcp_tools.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/mcp_tools.py:205)). Read JSON-RPC messages until the requested ID arrives, drain stderr concurrently, reap the child, and send complete descriptions to the comparison pass. Add an N-server comparison mode before templates compose three or more servers.

15. **The current template installer records states that did not occur.** It writes the template name after attempting all member installations even when one or more failed ([template.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/template.py:225)). It also records only template names, then interprets them through the current template definitions. If membership changes after installation, uninstall reasons from a different graph than the one originally applied. Store the exact resolved member graph, versions, sources, and hashes in a lock file. Record a new lock only after the complete apply operation passes.

16. **The specification calls overlap behavior undecided, but the repository already decided it.** The existing template tool says installations are non-exclusive, overlap freely, and retain a shared tool until its last claimant is removed ([template.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/template.py:17)). The new design should preserve this behavior. Template conflicts should fail resolution unless `mcp_info.json` explicitly resolves them.

17. **The existing update record is not portable.** `astra-install.sh` records an absolute source checkout path ([astra-install.sh](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/astra-install.sh:89)), and `astra-update` later requires that path to exist ([astra-update](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/astra-update:79)). A cloned repository cannot update on another machine. Record a source coordinate, release version, and artifact digest. A local checkout path can be an optional development override.

18. **The RED helper does not prove the stated failure reason.** `red()` accepts almost every nonzero exit except 126 and 127, while discarding all output ([lib.sh](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/lib.sh:53)). A missing config, parser crash, or unrelated dependency error can make the RED control pass. Replace it with a helper that requires an expected exit code and an expected literal diagnostic or external effect.

**2. QUESTIONS FOR THE OWNER.**

1. Should a limiting policy fail closed with an allow-list, or should new tools appear while producing a warning? A deny-list cannot guarantee that a prohibited capability stays absent after an upstream update.

2. When an upstream update invalidates a map entry, should the wrapper omit only that alias and continue, or preserve the alias as a callable error? Refusing the whole wrapper conflicts with the “warn, never refuse” rule.

3. Does “Homebrew is the sanctioned dependency mechanism” mean that Homebrew must install every payload? The current tools use Homebrew for runtimes while npm and `uvx` install packages. The manifest schema changes depending on that answer.

4. Are “Andrew’s Swift tooling,” Drew’s Xcode MCP, and `ponytail` distinct packages? Their exact package identities and sources are required before the Swift template can be resolved.

**3. ROADMAP.**

1. **Create a process-level characterization harness.** The user-facing behavior is the current two-upstream prefixed surface over real HTTP. The test launches the shipped daemon with two deterministic stdio MCP fixture programs, calls both tools, and verifies separate effect files. It fails if either call reaches the wrong fixture, loses arguments, or does not return the fixture’s result.

2. **Replace the lossy environment string with strict `_mcp_info.json`.** The behavior is parity with today’s `xcode__` and `drews__` wrapper, including arguments containing colons and commas and child environment values. The test supplies hostile argument values and verifies the exact bytes received by each fixture. It fails under the current split-based parser.

3. **Add schema and namespace validation.** The behavior is a stable, unambiguous tool namespace. Tests exercise duplicate JSON keys, duplicate prefixes, overlapping prefixes, missing commands, unsupported fields, and one-server configurations. Each invalid file must exit with its precise diagnostic. The one-server test fails if removing a second server renames the remaining tools.

4. **Build exact dispatch tables and complete cached snapshots.** The behavior is deterministic routing and continued access to healthy tools during an upstream outage. A fixture server dies after its first list while the other handles a call. The test fails if the healthy call is dropped, the complete surface becomes empty, or a stale tool routes elsewhere.

5. **Repair connection supervision.** The behavior is that a long call survives heartbeats and one wedged upstream does not restart healthy upstreams. Tests use scaled timing values and a fixture that blocks for several heartbeat intervals. They fail if the long call receives concurrent traffic, the broker exits, or a healthy fixture observes a disconnect.

6. **Record and report compatible upstream identity.** The behavior is continued service plus an in-band version warning. A notifier executable supplied through a production injection point records human notifications. Tests cover equal and unequal versions, restart the broker, and require one human record per mismatch pair. They fail if service is refused, the model warning is missing, or the human warning repeats.

7. **Implement pagination and `tools/listChanged`.** The behavior is a complete surface that changes after an upstream notification. A fixture exposes two pages, then adds a tool and emits the notification. The test fails on missing tools, duplicates, invalid cursors, partial snapshots, or a missing downstream notification.

8. **Add the disallow list.** Every entry requires a nonempty `why`. A blocked tool must be absent from `tools/list` and rejected by `tools/call`. The fixture writes a marker only when called. The test fails if the marker exists, which proves that hiding the listing alone is insufficient.

9. **Add the limiting policy selected by the owner.** For an allow-list policy, an unrecorded tool added after `listChanged` must remain unavailable. The test fails if the new tool appears or can be called. For a warning policy, the test instead requires the tool and a specific warning.

10. **Add name mapping.** A mapped name replaces the prefixed source name, its descriptions use the exposed vocabulary, and calls reach the original source tool. The test verifies the upstream effect record. RED cases cover duplicate exposed names, nonexistent source tools, and unresolved description references.

11. **Add `_mcp_info.json` plus `mcp_info.json` operations.** The behavior is a repository override that can block, unblock, map, unmap, and override a description without modifying generated data. Tests re-run the template generator and require the human file’s hash to remain unchanged. They fail if an update overwrites the human file or silently turns an operation into a no-op.

12. **Introduce the versioned tool manifest and validate every existing tool.** The behavior is one install, uninstall, doctrine, dependency, and test contract. A schema test parses every `tools/*/tool.json` and resolves every referenced file. It fails on untyped dependencies, missing lifecycle scripts, missing tests, or a nonexistent doctrine source.

13. **Replace flat templates with a deterministic DAG resolver.** The behavior is nested Xcode, Swift, Mac, Mac+Swift, and iOS templates with diamond de-duplication. A fixture graph makes two parents share one tool. The test verifies that the shared installer runs once and remains installed until its last claimant is removed. Cycle and conflicting-version fixtures must fail with the complete dependency path.

14. **Make apply and update transactional at the repository boundary.** The behavior is that a failed member does not alter the active generated config or lock record. The test poisons the second of three installers and compares all tracked output hashes with their pre-run values. It fails if the template is recorded, `_mcp_info.json` changes, or an earlier member becomes active.

15. **Adopt a third-party tool without a submodule.** The behavior is installation from a versioned external package or release, with an artifact digest recorded in the lock. A local package registry fixture avoids network access in sanity tests. The test changes the artifact without changing its declared version and requires refusal. It fails if unverified content is installed.

16. **Migrate the real Xcode profile.** Generate a profile containing Apple and Drew from the new template system, then compare its effective config with today’s combined daemon. The deep test calls one real tool from each upstream. It fails if the prefixed inventory or either routing effect differs.

17. **Add Mac, Swift, Mac+Swift, and iOS templates one at a time.** Each increment installs one newly resolved capability set into a disposable repository. Tests inspect the resulting MCP surface, installed commands, doctrines, and lock ownership. Each test removes one member or poisons one dependency so that an incomplete template cannot report itself as applied.

**4. TEST ARCHITECTURE.**

The current Xcode test belongs in the deep tier. It can wait 90 seconds for Xcode to start, another 90 seconds for a workspace, and 30 seconds per HTTP call ([test-xcode-mcp-front.sh](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-xcode-mcp-front.sh:25), [test-xcode-mcp-front.sh](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-xcode-mcp-front.sh:125), [test-xcode-mcp-front.sh](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-xcode-mcp-front.sh:160)). It cannot be part of a fifteen-second gate.

The fast tier should run `tools/tests/run-sanity.sh` and enforce a fifteen-second total wall-clock ceiling. It should contain:

- Real broker processes speaking stdio to deterministic MCP fixture processes and Streamable HTTP to the test client.
- Exact argument, environment, prefix, routing, filtering, mapping, pagination, notification, and reconnect behavior.
- Disposable repository installs using local source fixtures.
- Template DAG, overlap, uninstall ownership, transaction, and lockfile behavior.
- Notifier and GUI-inspector transport substitutes supplied through production configuration points.
- Exact RED exit codes, diagnostics, and external effects.
- Static validation of generated launchd plists and every tool manifest.

These fixtures are not mocks of broker functions. They are small MCP servers whose external behavior is controlled. The shipped broker must cross both real transport boundaries before the test passes.

The deep tier should run `tools/tests/run-deep.sh`. It should include:

- Apple’s live `mcpbridge`, Drew’s live server, an open workspace, and actual calls through the `.app`.
- Approval binding to the connecting PID, prompt withdrawal after process death, and two-daemon serialization.
- TCC persistence across script changes and loss after rebuilding the `.app`.
- Screen-lock and frontmost-workspace behavior.
- launchd restart, login persistence, stalled-child recovery, and active-call preservation.
- Live Homebrew dependency checks and selected install/uninstall acceptance runs.
- Remote package acquisition and the optional model-assisted semantic collision pass.

The deep runner must fail its preflight when Xcode, the workspace, the unlocked GUI, or required grants are absent. It must not report a skip.

Several behaviors cannot be proved quickly. A fixture cannot establish that Xcode’s real dialogs do not stack, that macOS attributes a prompt to the intended PID, or that TCC preserves a grant. A fixture also cannot prove a real Homebrew download, a remote package’s availability, or the quality of an LLM’s semantic collision judgment. The truthful substitute is a fast contract test at the transport boundary plus a separately invoked live acceptance test that records the observed Xcode version, server versions, timestamp, and result.

**5. THE AD ASTRA TOOL FORMAT.**

Each tool or skill should have one strict `tool.json`. Comments should not appear in JSON. Human explanations belong in required fields or Markdown doctrine.

A third-party MCP descriptor can use this shape:

```json
{
  "schema_version": 1,
  "id": "drews-xcode-mcp",
  "kind": "mcp-server",
  "version": "1.0.0",
  "summary": "Expose Drew's Xcode MCP server through a managed stdio entry.",
  "source": {
    "type": "pypi",
    "package": "drews-xcode-mcp",
    "version": "1.29.1"
  },
  "dependencies": {
    "brewfile": "Brewfile",
    "system_checks": []
  },
  "lifecycle": {
    "install": ["bash", "install.sh"],
    "uninstall": ["bash", "uninstall.sh"],
    "update": "reinstall"
  },
  "provides": [
    {
      "type": "mcp-server",
      "id": "xcode-mcp-server",
      "transport": "stdio"
    }
  ],
  "doctrine": [
    {
      "source": "doctrine.md",
      "slug": "drews-xcode-mcp"
    }
  ],
  "tests": {
    "sanity": {
      "command": ["bash", "tests/sanity.sh"],
      "max_seconds": 3
    },
    "deep": {
      "command": ["bash", "tests/deep.sh"]
    }
  }
}
```

Its adjacent `Brewfile` installs the package runner:

```ruby
brew "uv"
```

`schema_version` describes the manifest language. `version` describes the Astra adoption package. `source.version` identifies the upstream release. The lock file records the resolved artifact URL, complete digest, and observed MCP `serverInfo`. These versions must not be collapsed into one field.

An in-tree tool uses `"source": {"type": "astra", "path": "tools/xcode-mcp-front"}`. A remote release archive uses `type`, URL, release tag, and required digest. A skill uses `"kind": "skill"` and declares its installed skill directory in `provides`. The same lifecycle, doctrine, dependency, and test fields apply.

The repo declares desired top-level packages in a human-owned `astra.json`:

```json
{
  "schema_version": 1,
  "templates": [
    "mac-swift",
    "ios"
  ],
  "tools": [
    "frame-review"
  ],
  "pins": {
    "drews-xcode-mcp": "1.29.1"
  }
}
```

The resolver writes `.astra/lock.json`. That file contains the exact expanded template graph, package versions, source coordinates, artifact digests, installed paths, ownership counts, and installed hashes. It also generates `_mcp_info.json`. The repository owns `mcp_info.json`, and no machine action writes it.

`astra apply --into <repo>` resolves and validates the desired graph, checks Brewfile dependencies, stages artifacts, runs lifecycle commands, validates the effective MCP surface, and atomically replaces generated repository files and the lock. `astra update --into <repo>` re-resolves unpinned packages against the current catalog and applies the same process. `astra uninstall` removes only lock-owned files whose hashes still match their installed hashes. It reports locally changed files and leaves them in place.

Third-party adoption needs no submodule. Astra retains the small descriptor directory, its Brewfile, adapter scripts, doctrine, and tests. The package manager or verified release archive supplies the upstream payload. The lock supplies reproducibility and provenance.
**1. HOLES.**

1. **The deployment unit is undefined.** A template is installed per repository, but the wrapper is a persistent user-level service on a fixed port. One daemon per repository causes port collisions and recreates the approval-serialization ceiling. One global daemon cannot expose different sieves for different repositories. The specification identifies the multiple-daemon failure but leaves it unresolved ([SPEC.md](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/SPEC.md:38)). Use one user-level broker with shared upstream connections and named profile routes, such as `/mcp/<profile-id>`. Each repository selects a logical profile without spawning another `mcpbridge`.

2. **Several templates cannot safely write one generated MCP file.** The specification first names `_MCP_Config.json`, then `_wrapped_mcps.json`, and later `_mcp_info.json` ([SPEC.md](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/SPEC.md:25), [SPEC.md](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/SPEC.md:46), [SPEC.md](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/SPEC.md:183)). If Mac and iOS installers each rewrite the same underscore file, the last installer erases the other template’s contribution. Use `_mcp_info.json` and `mcp_info.json` consistently. A single resolver must recompute the union of all installed templates and write the machine file atomically.

3. **The current aggregation algorithm does not implement MCP pagination correctly.** It sends one downstream cursor to every upstream and concatenates their responses ([daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:700)). Upstream cursors belong to different cursor spaces. A paginated server will return missing, repeated, or invalid pages. Either drain every upstream list into a complete cached snapshot or issue aggregate cursors that encode each upstream’s position.

4. **`tools/listChanged` needs an end-to-end design, not only a promise to reapply the sieve.** The specification requires reapplication after the notification ([SPEC.md](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/SPEC.md:131)), but the current daemon neither consumes upstream notifications nor notifies downstream clients. Build immutable surface snapshots. Replace a snapshot only after listing, filtering, mapping, and collision validation all pass. Then send one downstream list-changed notification.

5. **A healthy empty server is indistinguishable from a disconnected server.** `Upstream.list_tools()` returns an empty list in both cases ([daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:463)). The aggregator then returns zero tools if any upstream returned zero ([daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:715)). This contradicts its own instruction that other upstreams remain available ([daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:783)). Track connection state separately. Keep the last known valid surface during an outage, and return an explicit error only when somebody calls the unavailable upstream.

6. **The inherited heartbeat and watchdog conflict with supported call lengths.** Tool calls may run for 600 seconds, while the process exits after 180 seconds without recorded progress ([daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:159), [daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:298)). The heartbeat also bypasses the upstream lock while a tool call holds it ([daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:482), [daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:612)). A three-minute build can therefore receive an untested concurrent `tools/list`, or a corrected serialized heartbeat can cause the watchdog to kill the build. Track active requests and connection-manager progress separately. One wedged upstream must restart only its own worker, because the current `os._exit(75)` drops healthy upstreams and their active calls.

7. **Version warnings cannot reliably appear in `initialize` with the current lifecycle.** The wrapper constructs static instructions before its background upstreams initialize, and it discards every upstream initialization result ([daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:551), [daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:759)). A downstream client can initialize before the wrapper knows any live versions. Gate readiness until the first upstream initialization completes, or implement a dynamic initialization response. Do not classify generic version strings as “newer” or “older”; `serverInfo.version` is opaque unless that upstream declares a comparator. Exact mismatch is the only generic conclusion.

8. **“Warn, never refuse” conflicts with stale-map behavior.** The specification says a version mismatch never prevents service, but it also calls an unresolved map entry a hard error ([SPEC.md](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/SPEC.md:97), [SPEC.md](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/SPEC.md:163)). A renamed upstream tool triggers both rules. The runtime needs a defined degraded state. My recommendation is to reject the invalid alias, continue serving the valid surface, and report the omitted alias in-band and through the human notification channel.

9. **Prefix routing is ambiguous.** The current behavior changes all tool names when the configured upstream count changes, because a single upstream is unprefixed ([daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:695)). It also routes by first matching prefix ([daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:727)). Prefixes `a` and `a__b` make `a__b__tool` order-dependent. Build an exact exposed-name-to-source dispatch table from the validated surface. Reject duplicate prefixes, duplicate exposed names, duplicate upstream tool names, and mapping collisions before activation. A prefix must not depend on how many servers happen to be configured.

10. **The sieve and map lack a fixed evaluation order.** A block could name an upstream tool, a prefixed tool, or a mapped tool. The specification also does not say whether mapping replaces the original name or adds an alias. Apply these phases in order: list upstream tools, identify each as `server/tool`, apply source-qualified restrictions, replace mapped names, rewrite exact description references, validate global uniqueness, then publish. `map` should replace the original. A separate `alias` operation can preserve both names when explicitly requested.

11. **Mechanical description replacement can corrupt prose.** Blind replacement can change a tool name embedded inside another identifier or alter an ordinary word. It also ignores titles, annotations, and other human-readable fields. Replace only exact recognized tool references. Warn on remaining references to renamed tools. Require an explicit description override when the text cannot be repaired mechanically.

12. **The advertised config shape exceeds the implementation.** The design accepts stdio entries with `env` and HTTP entries with `url` ([SPEC.md](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/SPEC.md:52)). The daemon passes only command and arguments to `StdioServerParameters` ([daemon.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py:559)). The comparison tool explicitly rejects HTTP ([mcp_tools.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/mcp_tools.py:62)). Step one must either implement `env`, working directory, and HTTP transport or reject those fields with a precise error. Advertising unsupported Claude-compatible fields will produce late failures.

13. **A repository config is an arbitrary-code execution boundary.** Every `command` runs inside a long-lived user process. Auto-loading an untrusted checkout’s config would execute its commands outside the repository’s immediate agent session. The broker should consume only validated configurations installed into a user-owned runtime directory by `astra apply`. It should never scan arbitrary repositories. It should execute argument arrays without a shell, reject non-loopback binding by default, and keep secret values out of generated repository files.

14. **The comparison script can report the wrong response.** It assumes the next stdout line belongs to the request it just sent ([mcp_tools.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/mcp_tools.py:82)). A server notification before response ID 2 is misread as the `tools/list` response. Its undrained stderr pipe can also fill and deadlock the child. Finally, the semantic pass receives only the first 200 description characters ([mcp_tools.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/mcp_tools.py:205)). Read JSON-RPC messages until the requested ID arrives, drain stderr concurrently, reap the child, and send complete descriptions to the comparison pass. Add an N-server comparison mode before templates compose three or more servers.

15. **The current template installer records states that did not occur.** It writes the template name after attempting all member installations even when one or more failed ([template.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/template.py:225)). It also records only template names, then interprets them through the current template definitions. If membership changes after installation, uninstall reasons from a different graph than the one originally applied. Store the exact resolved member graph, versions, sources, and hashes in a lock file. Record a new lock only after the complete apply operation passes.

16. **The specification calls overlap behavior undecided, but the repository already decided it.** The existing template tool says installations are non-exclusive, overlap freely, and retain a shared tool until its last claimant is removed ([template.py](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/template.py:17)). The new design should preserve this behavior. Template conflicts should fail resolution unless `mcp_info.json` explicitly resolves them.

17. **The existing update record is not portable.** `astra-install.sh` records an absolute source checkout path ([astra-install.sh](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/astra-install.sh:89)), and `astra-update` later requires that path to exist ([astra-update](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/astra-update:79)). A cloned repository cannot update on another machine. Record a source coordinate, release version, and artifact digest. A local checkout path can be an optional development override.

18. **The RED helper does not prove the stated failure reason.** `red()` accepts almost every nonzero exit except 126 and 127, while discarding all output ([lib.sh](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/lib.sh:53)). A missing config, parser crash, or unrelated dependency error can make the RED control pass. Replace it with a helper that requires an expected exit code and an expected literal diagnostic or external effect.

**2. QUESTIONS FOR THE OWNER.**

1. Should a limiting policy fail closed with an allow-list, or should new tools appear while producing a warning? A deny-list cannot guarantee that a prohibited capability stays absent after an upstream update.

2. When an upstream update invalidates a map entry, should the wrapper omit only that alias and continue, or preserve the alias as a callable error? Refusing the whole wrapper conflicts with the “warn, never refuse” rule.

3. Does “Homebrew is the sanctioned dependency mechanism” mean that Homebrew must install every payload? The current tools use Homebrew for runtimes while npm and `uvx` install packages. The manifest schema changes depending on that answer.

4. Are “Andrew’s Swift tooling,” Drew’s Xcode MCP, and `ponytail` distinct packages? Their exact package identities and sources are required before the Swift template can be resolved.

**3. ROADMAP.**

1. **Create a process-level characterization harness.** The user-facing behavior is the current two-upstream prefixed surface over real HTTP. The test launches the shipped daemon with two deterministic stdio MCP fixture programs, calls both tools, and verifies separate effect files. It fails if either call reaches the wrong fixture, loses arguments, or does not return the fixture’s result.

2. **Replace the lossy environment string with strict `_mcp_info.json`.** The behavior is parity with today’s `xcode__` and `drews__` wrapper, including arguments containing colons and commas and child environment values. The test supplies hostile argument values and verifies the exact bytes received by each fixture. It fails under the current split-based parser.

3. **Add schema and namespace validation.** The behavior is a stable, unambiguous tool namespace. Tests exercise duplicate JSON keys, duplicate prefixes, overlapping prefixes, missing commands, unsupported fields, and one-server configurations. Each invalid file must exit with its precise diagnostic. The one-server test fails if removing a second server renames the remaining tools.

4. **Build exact dispatch tables and complete cached snapshots.** The behavior is deterministic routing and continued access to healthy tools during an upstream outage. A fixture server dies after its first list while the other handles a call. The test fails if the healthy call is dropped, the complete surface becomes empty, or a stale tool routes elsewhere.

5. **Repair connection supervision.** The behavior is that a long call survives heartbeats and one wedged upstream does not restart healthy upstreams. Tests use scaled timing values and a fixture that blocks for several heartbeat intervals. They fail if the long call receives concurrent traffic, the broker exits, or a healthy fixture observes a disconnect.

6. **Record and report compatible upstream identity.** The behavior is continued service plus an in-band version warning. A notifier executable supplied through a production injection point records human notifications. Tests cover equal and unequal versions, restart the broker, and require one human record per mismatch pair. They fail if service is refused, the model warning is missing, or the human warning repeats.

7. **Implement pagination and `tools/listChanged`.** The behavior is a complete surface that changes after an upstream notification. A fixture exposes two pages, then adds a tool and emits the notification. The test fails on missing tools, duplicates, invalid cursors, partial snapshots, or a missing downstream notification.

8. **Add the disallow list.** Every entry requires a nonempty `why`. A blocked tool must be absent from `tools/list` and rejected by `tools/call`. The fixture writes a marker only when called. The test fails if the marker exists, which proves that hiding the listing alone is insufficient.

9. **Add the limiting policy selected by the owner.** For an allow-list policy, an unrecorded tool added after `listChanged` must remain unavailable. The test fails if the new tool appears or can be called. For a warning policy, the test instead requires the tool and a specific warning.

10. **Add name mapping.** A mapped name replaces the prefixed source name, its descriptions use the exposed vocabulary, and calls reach the original source tool. The test verifies the upstream effect record. RED cases cover duplicate exposed names, nonexistent source tools, and unresolved description references.

11. **Add `_mcp_info.json` plus `mcp_info.json` operations.** The behavior is a repository override that can block, unblock, map, unmap, and override a description without modifying generated data. Tests re-run the template generator and require the human file’s hash to remain unchanged. They fail if an update overwrites the human file or silently turns an operation into a no-op.

12. **Introduce the versioned tool manifest and validate every existing tool.** The behavior is one install, uninstall, doctrine, dependency, and test contract. A schema test parses every `tools/*/tool.json` and resolves every referenced file. It fails on untyped dependencies, missing lifecycle scripts, missing tests, or a nonexistent doctrine source.

13. **Replace flat templates with a deterministic DAG resolver.** The behavior is nested Xcode, Swift, Mac, Mac+Swift, and iOS templates with diamond de-duplication. A fixture graph makes two parents share one tool. The test verifies that the shared installer runs once and remains installed until its last claimant is removed. Cycle and conflicting-version fixtures must fail with the complete dependency path.

14. **Make apply and update transactional at the repository boundary.** The behavior is that a failed member does not alter the active generated config or lock record. The test poisons the second of three installers and compares all tracked output hashes with their pre-run values. It fails if the template is recorded, `_mcp_info.json` changes, or an earlier member becomes active.

15. **Adopt a third-party tool without a submodule.** The behavior is installation from a versioned external package or release, with an artifact digest recorded in the lock. A local package registry fixture avoids network access in sanity tests. The test changes the artifact without changing its declared version and requires refusal. It fails if unverified content is installed.

16. **Migrate the real Xcode profile.** Generate a profile containing Apple and Drew from the new template system, then compare its effective config with today’s combined daemon. The deep test calls one real tool from each upstream. It fails if the prefixed inventory or either routing effect differs.

17. **Add Mac, Swift, Mac+Swift, and iOS templates one at a time.** Each increment installs one newly resolved capability set into a disposable repository. Tests inspect the resulting MCP surface, installed commands, doctrines, and lock ownership. Each test removes one member or poisons one dependency so that an incomplete template cannot report itself as applied.

**4. TEST ARCHITECTURE.**

The current Xcode test belongs in the deep tier. It can wait 90 seconds for Xcode to start, another 90 seconds for a workspace, and 30 seconds per HTTP call ([test-xcode-mcp-front.sh](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-xcode-mcp-front.sh:25), [test-xcode-mcp-front.sh](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-xcode-mcp-front.sh:125), [test-xcode-mcp-front.sh](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-xcode-mcp-front.sh:160)). It cannot be part of a fifteen-second gate.

The fast tier should run `tools/tests/run-sanity.sh` and enforce a fifteen-second total wall-clock ceiling. It should contain:

- Real broker processes speaking stdio to deterministic MCP fixture processes and Streamable HTTP to the test client.
- Exact argument, environment, prefix, routing, filtering, mapping, pagination, notification, and reconnect behavior.
- Disposable repository installs using local source fixtures.
- Template DAG, overlap, uninstall ownership, transaction, and lockfile behavior.
- Notifier and GUI-inspector transport substitutes supplied through production configuration points.
- Exact RED exit codes, diagnostics, and external effects.
- Static validation of generated launchd plists and every tool manifest.

These fixtures are not mocks of broker functions. They are small MCP servers whose external behavior is controlled. The shipped broker must cross both real transport boundaries before the test passes.

The deep tier should run `tools/tests/run-deep.sh`. It should include:

- Apple’s live `mcpbridge`, Drew’s live server, an open workspace, and actual calls through the `.app`.
- Approval binding to the connecting PID, prompt withdrawal after process death, and two-daemon serialization.
- TCC persistence across script changes and loss after rebuilding the `.app`.
- Screen-lock and frontmost-workspace behavior.
- launchd restart, login persistence, stalled-child recovery, and active-call preservation.
- Live Homebrew dependency checks and selected install/uninstall acceptance runs.
- Remote package acquisition and the optional model-assisted semantic collision pass.

The deep runner must fail its preflight when Xcode, the workspace, the unlocked GUI, or required grants are absent. It must not report a skip.

Several behaviors cannot be proved quickly. A fixture cannot establish that Xcode’s real dialogs do not stack, that macOS attributes a prompt to the intended PID, or that TCC preserves a grant. A fixture also cannot prove a real Homebrew download, a remote package’s availability, or the quality of an LLM’s semantic collision judgment. The truthful substitute is a fast contract test at the transport boundary plus a separately invoked live acceptance test that records the observed Xcode version, server versions, timestamp, and result.

**5. THE AD ASTRA TOOL FORMAT.**

Each tool or skill should have one strict `tool.json`. Comments should not appear in JSON. Human explanations belong in required fields or Markdown doctrine.

A third-party MCP descriptor can use this shape:

```json
{
  "schema_version": 1,
  "id": "drews-xcode-mcp",
  "kind": "mcp-server",
  "version": "1.0.0",
  "summary": "Expose Drew's Xcode MCP server through a managed stdio entry.",
  "source": {
    "type": "pypi",
    "package": "drews-xcode-mcp",
    "version": "1.29.1"
  },
  "dependencies": {
    "brewfile": "Brewfile",
    "system_checks": []
  },
  "lifecycle": {
    "install": ["bash", "install.sh"],
    "uninstall": ["bash", "uninstall.sh"],
    "update": "reinstall"
  },
  "provides": [
    {
      "type": "mcp-server",
      "id": "xcode-mcp-server",
      "transport": "stdio"
    }
  ],
  "doctrine": [
    {
      "source": "doctrine.md",
      "slug": "drews-xcode-mcp"
    }
  ],
  "tests": {
    "sanity": {
      "command": ["bash", "tests/sanity.sh"],
      "max_seconds": 3
    },
    "deep": {
      "command": ["bash", "tests/deep.sh"]
    }
  }
}
```

Its adjacent `Brewfile` installs the package runner:

```ruby
brew "uv"
```

`schema_version` describes the manifest language. `version` describes the Astra adoption package. `source.version` identifies the upstream release. The lock file records the resolved artifact URL, complete digest, and observed MCP `serverInfo`. These versions must not be collapsed into one field.

An in-tree tool uses `"source": {"type": "astra", "path": "tools/xcode-mcp-front"}`. A remote release archive uses `type`, URL, release tag, and required digest. A skill uses `"kind": "skill"` and declares its installed skill directory in `provides`. The same lifecycle, doctrine, dependency, and test fields apply.

The repo declares desired top-level packages in a human-owned `astra.json`:

```json
{
  "schema_version": 1,
  "templates": [
    "mac-swift",
    "ios"
  ],
  "tools": [
    "frame-review"
  ],
  "pins": {
    "drews-xcode-mcp": "1.29.1"
  }
}
```

The resolver writes `.astra/lock.json`. That file contains the exact expanded template graph, package versions, source coordinates, artifact digests, installed paths, ownership counts, and installed hashes. It also generates `_mcp_info.json`. The repository owns `mcp_info.json`, and no machine action writes it.

`astra apply --into <repo>` resolves and validates the desired graph, checks Brewfile dependencies, stages artifacts, runs lifecycle commands, validates the effective MCP surface, and atomically replaces generated repository files and the lock. `astra update --into <repo>` re-resolves unpinned packages against the current catalog and applies the same process. `astra uninstall` removes only lock-owned files whose hashes still match their installed hashes. It reports locally changed files and leaves them in place.

Third-party adoption needs no submodule. Astra retains the small descriptor directory, its Brewfile, adapter scripts, doctrine, and tests. The package manager or verified release archive supplies the upstream payload. The lock supplies reproducibility and provenance.