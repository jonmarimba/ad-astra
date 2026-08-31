I read all of it, plus the parts of the repo the spec does not mention. Three claims below are things I ran rather than reasoned about; I say so where it applies.

---

## 1. HOLES

### H1 — The daemon is machine-global. The templates are per-repo. Nothing in the spec resolves that. (Headline)

`daemon.py` reads its configuration from environment variables and one file at `~/.xcode-mcp-front/config` (`daemon.py:127-141`), and binds one port from `XCODE_MCP_FRONT_PORT` (`daemon.py:146`). It is one launchd job for the whole machine. Templates install into `<repo>/.astra/` and are forbidden from writing anywhere global (`tools/lib/astra-install.sh:55-60`). So a per-repo `_mcp_info.json` carrying a per-repo sieve and map cannot drive a machine-wide daemon. Two repos that want different surfaces cannot both be served, and the first symptom is a repo seeing another repo's renames or losing its own blocks. This surfaces only on the second repo, which is late.

Change: serve profiles rather than one surface. One daemon, one approved PID, one port, but a path segment per resolved config (`/mcp/swift-ios`, `/mcp/legal`). Each repo's `.mcp.json` points at its own path. That keeps the single-approval property that justifies the daemon existing, and it sidesteps the three-daemon approval ceiling the spec worries about, because the ceiling is a count of *processes*, not of surfaces.

### H2 — A template system already exists in this repo, and `SPEC.md` says "Nothing here is built"

`tools/lib/template.py` installs named tool groups per repo. `tools/lib/templates.json` defines four of them today (`swift-ios`, `legal-pdf`, `kicker-dev`, `writing`). `tools/lib/astra-install.sh` decides that everything lands in `<repo>/.astra/<tool>/` and records provenance and per-file hashes in `.astra/manifest.json`. `tools/lib/astra-update` is the pull-side updater vendored into each repo. `tools/lib/registry.py` finds stale copies. Seven `tools/mcp-*/tool.json` files already describe MCP tools with `name`, `server`, `description`, `dependencies`, `provides` and `backed_by`.

Two of the spec's three "open questions Jonathan left open on purpose" are already answered in code and covered by a test. Overlap when two templates share a tool is decided by `template.py:145-158` (`tools_still_claimed`), and it de-duplicates rather than erroring or last-one-wins. Whether a repo records which templates it installed is answered by `template.py:82-142`, which writes them into `.astra/manifest.json`. The version half of that question is genuinely open, and only that half.

This is the "too many systems of record" failure Jonathan already named, arriving before either system is finished. Change: `SPEC.md` section on templates should be rewritten as "finish `template.py`", and the open-questions section should lose the two items that are already decided.

### H3 — `tool.json` is read by nothing

I grepped the whole repo. Zero consumers. Seven files describe seven tools in a format no code parses, so nothing validates them and nothing notices when they drift. It is already the ad astra tool format, abandoned at the halfway point. Section 5 below builds on it rather than inventing a third one.

### H4 — Composition is not expressible in the format that exists, and adding it breaks the uninstall logic

`templates.json` entries carry a flat `tools` array with no member-template key, so "Mac+Swift is those three as members" cannot be written today. Worse, `tools_still_claimed` computes claims one level deep. Add nesting without making that traversal transitive and you reintroduce exactly the bug `tools/lib/test-templates.sh` was written for on 2026-08-18: uninstalling one template removed tools another still needed. Change: nesting and the transitive closure land in the same increment, never separately.

### H5 — The tool map breaks prefix routing, and the spec does not say what replaces it

`on_call_tool` routes by `name.startswith(prefix)` (`daemon.py:731-732`). The spec states that a mapped exposed name "need not carry the `xcode__` style prefix." A mapped call therefore matches no prefix, falls to the error branch at `daemon.py:743-750`, and is rejected as unknown — for a tool the daemon itself advertised one call earlier. There is also no check that a mapped name cannot equal a real prefixed name from another upstream. Change: build one explicit `exposed name -> (upstream, upstream tool name)` table when the list is composed, consult it first, keep prefix routing only as the fallback for unmapped tools, and refuse at load time when a mapped name collides with any prefixed name.

### H6 — A legitimately empty upstream deletes the entire surface, and the sieve will cause exactly that

`daemon.py:721` decides an upstream is missing when `results_by_upstream.get(u.name)` is falsy, which is true both for "not connected" and for "connected, returned zero tools." Today every upstream always has tools, so the conflation is invisible. The limiting purpose of the sieve is to block capabilities. Block every tool on one small upstream and the aggregate serves nothing at all, from every upstream. The safety feature and the new feature destroy each other. Change: track connection state explicitly on `Upstream`, decide "missing" from that, and apply the sieve after the missing-check rather than before it.

### H7 — `listChanged` is advertised by the upstreams, dropped by the daemon, and never sent downstream

There is no notification handling anywhere in `daemon.py`. The sieve section's requirement to "re-apply on `listChanged`" is not implementable until the daemon can both receive that notification and emit its own. This compounds H6 into a live defect today: a client that calls `tools/list` while one upstream is reconnecting receives zero tools, caches them, and — with no `tools/list_changed` notification ever arriving — never re-lists. That is the "the Xcode tools vanished from my session" report, and restarting the client is currently the only cure.

### H8 — `mcp_tools.py` reports a working server as broken whenever it says anything unexpected on stdout

I wrote two throwaway stdio servers and ran the real script against them. A server that prints one banner line before answering produces an unhandled `JSONDecodeError` traceback at `mcp_tools.py:95`. A server that emits a spec-legal `notifications/message` between the request and the response reports `tools/list returned no result field`, exit 2, and `compare` then refuses to run at all. The file's own docstring says the one thing it must never do is report silence as emptiness; it does the equivalent for any server that talks. Change: read messages in a loop, dispatch on `id`, ignore anything without a matching `id`, and never `json.loads` an unvalidated line outside a try. Also `p.kill()` at `mcp_tools.py:116` without a following `wait()` leaves a zombie per probe.

### H9 — The heartbeat races client calls on the same session

`Upstream.list_tools` and `Upstream.call_tool` both take `self.lock` (`daemon.py:464`, `daemon.py:486`). The heartbeat calls `session.list_tools()` directly at `daemon.py:624`, outside that lock. The module header claims calls to a given upstream are serialised and that concurrent tolerance is untested. With one human-paced client the overlap is rare. Front five upstreams for a Mac+Swift template with several agents attached and it becomes routine, presenting as a random `Connection closed` followed by a reconnect. Change: take the lock in the heartbeat, or delete the serialisation claim and test concurrency for real. Do not leave the code and the header disagreeing.

### H10 — "Pin a sieve entry to a version" contradicts "decisions, never inventory"

The sieve section proposes that an entry can be pinned to a server version. A per-entry version is inventory in a decision's clothing: every upstream bump makes every entry stale at once, and the diff becomes unreviewable, which is precisely what the config section forbids. Record the verified version once per server. Nowhere else.

### H11 — The in-band warning only reaches sessions that start after the change

`instructions` is composed inside `build_server()`, once, at process start (`daemon.py:753` onward). MCP has no notification for changed instructions. An upstream that updates while the daemon runs therefore cannot tell any already-connected model. Change: also put the mismatch text into the error body of any call that fails, and re-compose instructions on reconnect so at least the next session is correct.

### H12 — Homebrew is not the dependency mechanism, and the repo's own Brewfiles say so

`tools/convocation/Brewfile` warns in a comment against adding fake brew lines for the two npm globals. `ambrosio`, `pdf-sidecars` and `graphify-repo` install `uv` tools. `xcode-mcp-front` needs an Automator `.app`, a launchd plist, and TCC grants a human clicks. A format that models only brew under-declares more than half of what is here, and the under-declaration is silent. Section 5 declares dependencies by ecosystem.

### H13 — `why` cannot be enforced where the spec puts the enforcement

The machine file is generated by a template, so a template author supplies each `why`. Rejecting the file at load time therefore fails the *repo*, at daemon startup, for a sentence someone forgot in astra. Enforce `why` as a test over the template source, where the author can see it. At runtime, warn loudly and serve.

### H14 — The test tiers are inverted today

`tools/tests/test-xcode-mcp-front.sh` allows 90 seconds for Xcode to start (line 33), sleeps a fixed 10 seconds (line 40), and allows another 90 seconds for a workspace to appear (lines 162-168). Preconditions alone can reach roughly three minutes, and the file opens Xcode and depends on window focus. It is in the ship gate through `run-all.sh`. Meanwhile `tools/lib/test-templates.sh` and `tools/lib/test-astra-update.sh` sit outside `tools/tests/`, and `run-all.sh` globs only `"$HERE"/test-*.sh` — so the single test guarding the non-exclusive template property never runs at ship time. The slow GUI test gates releases and the fast logic test does not.

### H15 — Comparing through the running daemon defeats the comparison

The spec suggests pointing `mcp_tools.py` at the daemon's approved endpoint to avoid the dialog. The daemon's list is prefixed and, after this work, sieved and mapped. A curated surface has no collisions by construction, so the tool would always report success. If you want that endpoint, it must serve raw per-upstream lists on a separate debug path.

### H16 — Two premises I checked rather than assumed

Claude Code tolerates unknown keys in `.mcp.json`. I put a server entry carrying `prefix`, `quirks` and `block` into a temporary project file and ran `claude mcp list`; it listed the server normally. The additive-fields plan is safe. The same run showed the server as `Pending approval (run claude to approve)`, so a template that writes `.mcp.json` does not produce a usable server until a human runs `claude` once in that repo. Say that in the installer's output, or the first report will be "the template installed nothing."

Also, `ponytail` is real and is already in this repo. `tools/ponytail/install-into-repo.sh` fetches `DietrichGebert/ponytail` from GitHub raw into `<repo>/.claude/skills/`. It is a code-laziness review skill, not a Swift tool, so it belongs in a general development template rather than the Swift one. That resolves one of the two naming items without asking him. It is also the best existing example of a third-party adoption with no submodule, and it has no version pin, no integrity check and no `uninstall.sh` — which section 5 fixes.

---

## 2. QUESTIONS FOR THE OWNER

1. **Per-repo surface, or one machine-wide surface?** This is H1 and it decides the whole shape. My recommendation is one daemon serving named profiles on distinct URL paths, because it keeps the single Xcode approval and still gives each repo its own sieve.
2. **Deny-list or allow-list for the limiting purpose?** The spec says this is yours. My recommendation is both: deny for coherence, allow for limiting, chosen per upstream, because a deny-list fails open and the limiting purpose cannot tolerate that.
3. **Is `Xcode-beta.app` at 27.0 in scope?** Measuring it needs a system-component install, which is your call. Until then the version-mismatch path has one test case and no second data point.
4. **"Andrew's Swift stuff"** — one sentence naming the actual tool. `ponytail` and `periphery` are resolved; that one is not.

---

## 3. ROADMAP

Increment 0 is a prerequisite for every increment after it, because without it the tests do not run at ship time.

**0. Move the template tests into the gate.** Behaviour: `run-all.sh` covers the template layer. Test: a new `tools/tests/test-suite-completeness.sh` asserts that every `test-*.sh` in the repo lives under `tools/tests/`. Fails when: plant a test file in `tools/lib/` and the assertion goes red. Also replace `test-templates.sh`'s `git clone ~/svnCheckouts/js-llmKicker` (line 12) with `git init` in a tmpdir, which removes seconds and a dependency on another repo.

**1. A fake stdio MCP server fixture.** Behaviour: none, directly. This is the piece that makes everything below fast, so it comes first. A roughly forty-line Python script that speaks initialize, tools/list and tools/call, takes its tool list from a JSON argument, and appends every received call to a log file. Test: the fixture answers a handshake in under 200 ms and logs a call. Fails when: break the handshake and the assertion sees no `serverInfo`.

**2. JSON-driven upstreams.** Behaviour: the combined daemon reads `_wrapped_mcps.json` in Claude Code's shape and serves the same prefixed surface it serves today. Test: two fixtures in one config file, `tools/list` returns both prefixes, a call routes to the right one, proved by each fixture's own log. RED control: a command path containing a colon and an argument containing a comma. The JSON path must carry both verbatim; feed the same values to `_parse_multi_upstreams` (`daemon.py:648-660`) and assert it corrupts them. That control proves the migration fixed a defect rather than moved one.

**3. Connection state replaces tool count.** Behaviour: an upstream that is connected and offers zero tools no longer empties the surface; a disconnected upstream still refuses a partial list. Test: fixture A with three tools, fixture B with an empty list — the surface has A's three. Then stop B — the surface is empty and the log names B. Fails when: restore the `daemon.py:721` check and the first case serves nothing.

**4. `listChanged` forwarded downstream.** Behaviour: a client's tool list updates without reconnecting. Test: fixture changes its list and emits the notification; the HTTP client receives `tools/list_changed` and a re-list shows the new tool. Fails when: drop the forwarding and the notification never arrives.

**5. The sieve, listing side.** Behaviour: a blocked tool is absent from `tools/list`, and every entry carries a `why`. Test: three tools, one blocked, two listed. RED: a block naming a tool the fixture does not have makes `astra mcp audit` exit nonzero and name the entry.

**6. The sieve, call side.** Behaviour: calling a blocked tool by its exact name fails. Test: call it directly and assert both the error to the caller and that the fixture's log does not contain the call. Fails when: filter only the listing, and the fixture logs it.

**7. Allow-list mode.** Behaviour: on an allow-listed upstream, a tool added by an upstream update is withheld and reported. Test: fixture starts with two tools, restarts with three, the third is absent and named in the audit output. Fails when: treat the allow-list as a deny-list and the new tool appears.

**8. The tool map, both directions.** Behaviour: an exposed name from the map appears in the list, the original prefixed name does not, and a call on the exposed name reaches the right upstream tool. Test: all three assertions, the last proved by the fixture's log. RED: a map entry naming a tool the upstream does not have must abort startup nonzero — a hard error, per the spec.

**9. Description substitution.** Behaviour: a description referring to a renamed tool refers to the new name. Test: fixture tool whose description says "use window_close"; the exposed description says `close_current_window`. RED: a description referring to a renamed tool in a form the substitution misses produces a warning; assert the warning fires.

**10. Version record and the two warnings.** Behaviour: a mismatch is served, not refused, and is reported to both audiences with the affected entries named. Test: fixture reports version 1 against a config pinned to 2; the `instructions` string carries both numbers and names the entries that no longer resolve. The human dialog is asserted by effect on its persistence file — first mismatch writes the key, a second identical mismatch does not fire again. RED: delete the persistence file and the second run fires, which proves the once-per-mismatch rule is real.

**11. Profiles.** Behaviour: two repos get two surfaces from one daemon and one Xcode approval. Test: two configs, two paths, each list contains only its own tools. Fails when: share one resolved config and the two lists become identical. Blocked on question 1.

**12. Nested templates with transitive closure.** Behaviour: `mac-swift` names `mac`, `swift` and `xcode` as members and installs all their tools. Test: install `mac-swift` and `ios`, uninstall `ios`, assert every `mac-swift` tool survives at the grandchild level. Fails when: leave `tools_still_claimed` one level deep and a grandchild tool disappears.

**13. `tool.json` becomes real.** Behaviour: `astra tool validate` rejects a malformed descriptor, and `template.py` reads dependencies from it rather than from a comment. Test: validate all existing descriptors, then a deliberately broken one. RED: the broken one must exit nonzero.

---

## 4. TEST ARCHITECTURE

**Fast tier — default, target under fifteen seconds, run on every commit.** Everything in increments 1 through 10 that uses the fake stdio fixture: config parsing and its refusals, prefixing, routing, the sieve on both list and call, the map in both directions, description substitution, `listChanged` forwarding, the connected-but-empty case, the version-mismatch text, and the dialog's once-per-mismatch persistence. Plus `template.py`'s overlap and corrupt-state logic against a `git init` fixture repo, and descriptor validation. None of it touches Xcode, System Events, launchd or a GUI. The daemon starts against fixtures in well under a second, and each assertion is one HTTP round trip on loopback. Budget roughly 8 seconds of work against a 15-second ceiling, and add a hard timeout to `run-all.sh` so exceeding it is a failure rather than a slow drift.

The reason this stays under fifteen seconds while still testing user-facing behaviour is the fixture. Every one of those tests asserts what a client sees over real HTTP against a real daemon process. Nothing is mocked inside the daemon. The only fake is the upstream server, which is a transport boundary — the same seam the house rules already sanction for `IMSG_BIN` and `SSH_BIN`.

**Slow tier — `run-all.sh --full`, run before shipping and after any change to the clicker.** The current `test-xcode-mcp-front.sh` unchanged. A launchd test that kills the daemon and asserts respawn, which exists to protect the bare-`true` `KeepAlive` finding. A two-daemon concurrent-connect test that asserts both reach a served tool list inside the connect timeout, which is the only thing standing between the current configuration and the deadlock that cost a night. A three-daemon version of the same, to measure the ceiling the spec says is derived rather than measured.

**What cannot be tested quickly, and the substitute.**

The clicker's decision can be tested fast and its *effect* cannot. Put the `osascript` call behind an injectable binary (`ASTRA_OSASCRIPT_BIN`), feed the decision function three recorded dialog texts — our own PID, a dead PID, a live foreign PID — and assert the chosen action and the grace-period timing. Name that test for the decision, not for clicking, because it proves nothing about the real dialog. The defect that actually shipped was a straight apostrophe where Xcode uses U+2019, and no fast test could ever have caught it. The substitute is one slow test that reads the button titles from a real approval dialog and compares them character by character against the literals in `daemon.py`. That test is the only thing that would have found it, so it belongs in the slow tier and must not be dropped for being awkward.

TCC grants cannot be tested at all after an `.app` is re-signed, because the failure is a silent EPERM with no prompt. The substitute is a slow-tier assertion that the wrapper `.app`'s code-signing hash equals the one recorded at grant time, which converts a silent permission death into a loud test failure naming the pane the human must open.

Xcode's frontmost-window requirement stays in the slow tier and stays a precondition check that refuses rather than a step that acts, exactly as the current file does it.

---

## 5. THE AD ASTRA TOOL FORMAT

Extend `tool.json`, which already exists in seven directories and is read by nothing. Every field below other than `name` and `description` is new.

```jsonc
{
  "name": "ponytail",
  "version": "1.2.0",
  "description": "Code-laziness review skill: does this need to exist, stdlib, platform, existing dependency, one line.",
  "provides": ["skill"],
  "kind": "third-party",

  "source": {
    "type": "github-raw",
    "repo": "DietrichGebert/ponytail",
    "ref": "v1.2.0",
    "paths": ["skills/ponytail/SKILL.md", "skills/ponytail-audit/SKILL.md"],
    "sha256": { "skills/ponytail/SKILL.md": "…" }
  },

  "dependencies": [
    { "ecosystem": "brew",  "name": "jq" },
    { "ecosystem": "npm-g", "name": "@anthropic-ai/claude-code", "provides_bin": "claude" },
    { "ecosystem": "uvx",   "name": "drews-xcode-mcp" },
    { "ecosystem": "macos-tcc", "grant": "full-disk-access", "app": "XcodeMCPFront.app",
      "why": "launchd runs outside the gui domain, so the grant needs an app identity" }
  ],

  "install":   "install.sh --into {repo}",
  "uninstall": "uninstall.sh --into {repo}",
  "test":      "tools/tests/test-ponytail.sh",
  "doctrine":  null,
  "installs_to": [".claude/skills/ponytail", ".claude/skills/ponytail-audit"]
}
```

**Identity and version.** `name` is the directory name and is the key everywhere. `version` is the tool's own, bumped by whoever edits it, and it is what `.astra/manifest.json` records so an update knows what it is replacing. Today the manifest records file hashes but no version, which is the one genuinely open question the spec asks and the code does not answer.

**Third-party adoption without a submodule.** `kind: "third-party"` plus a `source` block. The `ref` is a tag or commit, never a branch, so an install is reproducible. The `sha256` map is checked after fetching, so a changed upstream file is a loud failure rather than a silent substitution. The current `tools/ponytail/install-into-repo.sh` fetches from `main` with no pin and no integrity check, so it installs a different thing on different days and nothing says so. That is the concrete defect this field fixes.

**Dependencies by ecosystem.** `brew`, `npm-g`, `uvx`, `pip`, `macos-app`, `macos-tcc`, `launchd`. Brewfiles stay as generated output rather than hand-written source, produced from the `brew` entries, so the comments now warning people away from fake brew lines become unnecessary. `macos-tcc` entries carry a `why` and drive the install script's closing instruction to the human, which is the step that is currently only in prose.

**Doctrine.** A path or null. When present, the installer calls `tools/lib/install-doctrine.sh`, which already exists and already writes `.doctrine/<slug>.md` plus the `@`-import blocks.

**Tests.** A path to the tool's test file. `astra tool validate` fails a descriptor whose `test` path does not exist, which is what stops a tool shipping untested. Increment 0 above puts every one of those files where `run-all.sh` can see it.

**How a repo declares what it wants.** It does not maintain a list. It runs `template.py install <name> --into <repo>` once, and `.astra/manifest.json` records the templates and the tools with their versions, sources and file hashes. That file already exists and is already written atomically. The one change is adding the version alongside the hashes.

**How an update is applied.** Unchanged from what is already built, and it is the right design. The repo pulls: `.astra/astra-update` compares each installed file against its source and reports current, behind, locally modified or missing, and `--pull` replaces only the files whose hash still equals what was installed. Astra never reaches into another repo. For a template update the same rule extends to the mogenerator split: an update rewrites `_mcp_info.json` freely, never touches `mcp_info.json`, and reports any human verb in the second file that no longer applies to the first.

**Not part of the format.** No exhaustive tool list, and no per-entry version pin. One verified upstream version per server, and decisions with a mandatory `why`, validated where the author can see the failure.
