Now I have everything I need. Here is my review.

---

## 1. HOLES

### 1.1 The "refuse to serve partial tool list" decision is a silent availability regression for independent upstreams

`daemon.py` lines 760–770: when any upstream is missing in multi-upstream mode, `on_list_tools` returns `tools=[]` — zero tools, for all upstreams, including the ones that are connected and healthy. The spec says each upstream's connection is independent ("each upstream has its own independent connection"), and the daemon's own instructions text (line 806) tells the model that if one upstream is down, "the others are unaffected." But the tool list contradicts that promise. A client that only needs `drews__` tools (which never need Xcode approval) gets nothing while mcpbridge is reconnecting. The model sees an empty tool list and concludes the daemon is broken, when only one of two upstreams is.

This is the kind of defect that only surfaces late — during a real Xcode restart mid-session, when Drew's tools vanish for 5–15 seconds and the model stops calling them.

**Fix:** Return the connected upstreams' tools with a notification that some are missing. The MCP protocol doesn't have a "partial" list concept, but the daemon can log the missing upstreams and include a note in the next `initialize` response's instructions. Or, more simply, just serve what's connected — the model will notice the missing prefix and retry.

### 1.2 `listChanged` notification handling has no home in a live-proxy architecture

The spec (line 93) says: "A sieve that reads the list once at startup is therefore knowingly wrong; it should re-apply on `listChanged`." But the daemon is a live pass-through — it fetches from the upstream on each `tools/list` call, so it doesn't cache a tool list to invalidate. The sieve is applied per-call, which means `listChanged` is already handled de facto: the next `tools/list` call will fetch the new list and re-filter.

But the spec also says the wrapper should subscribe to `notifications/tools/list_changed` and forward it to the client. The current daemon doesn't subscribe to upstream notifications at all — it's a request-response proxy. Adding `listChanged` forwarding means the daemon needs to listen for notifications from each upstream's `ClientSession` and re-broadcast them, which is a different I/O pattern than the current fetch-and-forward design. This isn't called out as a design change; it's described as if it's a minor addition.

**What breaks if you skip it:** the client (Claude Code) holds a cached tool list from its last `tools/list` call. If Xcode adds a tool mid-session, the client doesn't know until it re-lists. The `listChanged` notification is the protocol's way of telling the client to re-list. Without forwarding, the client's cache goes stale and the model never sees the new tool. The sieve's "re-apply on `listChanged`" requirement is architecturally homeless — it needs the daemon to become a notification relay, not just a request proxy.

### 1.3 The config format claims Claude Code copy-paste portability but `quirks` breaks it in both directions

The spec (line 61) says reusing Claude Code's `.mcp.json` shape means "an entry can be moved between the two files by copy and paste." But:

- **Outbound broken:** an entry with `"quirks": {"requires_app": "Xcode"}` pasted into Claude Code's `.mcp.json` will either be rejected (strict validation) or silently ignored (lenient). Either way, the quirk is lost, and a user who copy-pastes from the wrapper config to Claude Code's config gets a server that connects without the approval-clicker, which is the exact failure the quirk exists to prevent.
- **Inbound broken:** an entry with `"type": "http", "url": "..."` pasted from Claude Code's config into the wrapper config will fail because `mcp_tools.py` `probe()` says "http upstreams are not supported yet" (line 73 of `mcp_tools.py`). The format claims to support the full Claude Code shape, but step one only implements the stdio subset.

The spec acknowledges the http gap in the "worthwhile extension" paragraph but doesn't flag it as a format-level contradiction. A user who copies an http entry and expects it to work will get a confusing error rather than the silent passthrough the format promises.

**Fix:** Either restrict the documented format to stdio-only for step one (and say so explicitly), or implement http upstream support in the same increment. Don't claim Claude Code shape compatibility while the http half is unimplemented.

### 1.4 The verb-based human override can't detect new template decisions the repo hasn't seen

The spec (lines 191–197) proposes human-file verbs: `block`, `unblock`, `map`, `unmap`, `override-description`. The effective config is the machine file with verbs applied in order. This handles the case where the repo wants to undo a template decision. But it can't handle the case where a template *update introduces a new block* that the repo would have wanted to override if it knew about it.

Scenario: Template v1 blocks nothing. Repo installs template, adds no override verbs. Template v2 adds a block on `drews__switch_scheme`. The repo's verb list is empty, so the new block takes effect silently. The repo never reviewed it. This is exactly the "silent narrowing" the spec says it wants to prevent (line 166: "the surface silently narrows forever").

The verb approach handles *removal* of existing template decisions and *addition* of new repo decisions, but it has no mechanism to surface *new template decisions* that the repo hasn't seen. A template update diff — "these blocks are new" — needs to be part of the update flow, not just the merge.

**Fix:** On template update, the installer should diff the old and new machine files and report any new blocks or maps as "new template decisions — review these." The verb file handles overrides; the update flow handles awareness.

### 1.5 Version-mismatch dialog persistence has no eviction

The spec (line 122) says the human dialog "fires once per distinct mismatch and then stays quiet: keyed on server name plus the version pair, persisted rather than held in memory." But this store grows forever. Jonathan has Xcode.app (26.6) and Xcode-beta.app (27.0) on this machine. Every beta update produces a new version pair. After a few months of beta cycling, the store has dozens of entries, none of which will ever fire again. And if a genuinely new mismatch arrives that happens to share a version pair with an old one (unlikely but possible after a version revert), the dialog is suppressed.

More practically: there's no command to clear acknowledged mismatches, no TTL, and no way to say "I've seen this one, stop tracking it." The persistence is write-only.

**Fix:** The store should be a simple JSON file with a last-shown timestamp. Entries older than N days with no re-occurrence are evicted. Or simpler: the store only needs to remember the *last* version pair per server name, not every pair ever seen. If the version changes again, show the dialog again. That's one entry per server, not an growing log.

### 1.6 The "suggest running the collision tool" trigger has no mid-session path

The spec (line 149) says the wrapper notices the version change cheaply and suggests running the collision tool. The in-band note goes in the `initialize` response's `instructions` string (line 115). But the model reads `instructions` once at session start. If the upstream version changes mid-session (Xcode updates can restart mcpbridge while the daemon is running), the model has already consumed its instructions and won't see the suggestion until it re-initializes.

The `listChanged` notification could carry it, but that's for tool-list changes, not version changes. There's no MCP notification for "the server's version changed." The daemon could reject the next `tools/list` with an error containing the suggestion, but that's a hack.

**What breaks:** an Xcode update mid-session changes the tool list, the daemon reconnects at the new version, the model never sees the "suggest collision tool" message because it already read its instructions. The version change is silent to the model for the rest of the session.

**Fix:** The daemon should log the version change prominently and, if it supports `listChanged` forwarding, include the version-change note in the notification's data. If it doesn't, the honest answer is "the suggestion only reaches new sessions" — say so in the spec rather than implying it's solved.

### 1.7 The approval-serialisation ceiling is a scaling cliff built into the composition mechanism

The spec (lines 40–44) says three daemons would need ~18s of exclusive dialog time, exceeding the 15s connect timeout. The template system's central value proposition is composition — a Mac+Swift template that wraps 3–4 servers. If two of those servers need Xcode approval (mcpbridge and MacControlMCP both might), the ceiling hits. The spec says "either the connect timeout grows with the number of daemons, or approval handling moves into one shared place." But neither is designed, and the template system is the *first* thing being built after the generic aggregator.

This is late-discovered because it only manifests when a real repo installs a composite template with multiple approval-needing upstreams. Two daemons at 6s each barely fits in 15s. Three doesn't. The design says "measure before relying on it" but doesn't make the measurement a precondition of the template work.

**Fix:** Before building the template system, either (a) consolidate approval handling into one daemon that fronts all approval-needing upstreams (which is what the generic aggregator already does — so the design should say "one daemon, multiple upstreams, not multiple daemons"), or (b) make the connect timeout a function of the number of approval-needing upstreams. Option (a) is already the architecture; the spec should explicitly say that a template composes upstreams within one daemon instance, not multiple daemon instances, and that the approval ceiling is why.

### 1.8 The stall watchdog's `os._exit(75)` kills all upstreams when one wedges

`daemon.py` line 571: `stall_watchdog` calls `os._exit(75)` when one upstream makes no progress for `STALL_EXIT_SECONDS`. In multi-upstream mode, this kills the entire daemon — including all healthy upstreams — because one upstream's reconnect loop is stuck in `stdio_client` teardown. Drew's upstream might be perfectly healthy, serving tools, and the watchdog kills it because mcpbridge's teardown hung.

The spec talks about independent upstreams, but the process model makes them all-or-nothing. A stuck mcpbridge teardown takes Drew's tools down too, and the model loses access to everything until launchd restarts and re-approves.

**Fix:** The watchdog should be per-upstream, not per-process. An upstream that's wedged should be marked broken and its tools removed from the list, not kill the process. The `os._exit` is a sledgehammer that was appropriate for single-upstream mode but is wrong for multi-upstream.

### 1.9 `_parse_multi_upstreams` uses `split(":", 3)` — the same colon-in-path bug the spec says JSON fixes

`daemon.py` line 697: `name, require_xcode, command, argstr = chunk.split(":", 3)`. The spec (line 73) says: "A command path containing a colon runs into the argument field." This is the exact bug the JSON config is supposed to fix. But step one (the generic aggregator) replaces this parser with JSON, and until that step ships, the colon bug is live. More importantly, if the JSON config parser has the same class of bug (a key name containing a delimiter), the problem moves but doesn't disappear. JSON doesn't have this issue for strings, but the spec should note that the env-var parser is the *current* bug and the JSON config is the fix, not that they coexist.

### 1.10 The `mcp_tools.py compare` command spawns fresh children and re-triggers approval

`mcp_tools.py` `probe()` spawns a fresh subprocess for each server. For Apple's mcpbridge, that's a fresh PID and a fresh approval dialog. The spec acknowledges this (line 164: "point it at the running daemon rather than at a fresh child") but the extension isn't built. This means the "suggest running the collision tool" flow — which is supposed to be opt-in and human-initiated — still raises an approval dialog that a human has to answer, which is the exact friction the daemon exists to eliminate. The collision tool can't run unattended against Apple's tools.

This isn't a hole in the design per se, but it's a hole in the *workflow*: the spec says "suggest running the collision tool" as if it's a clean, cheap operation, when for approval-gated upstreams it requires a human at the keyboard.

---

## 2. QUESTIONS FOR THE OWNER

**Q1. Sieve limiting mode.** The spec explicitly flags this as yours to decide (line 99): deny-list fails open for the "limiting" purpose. Do you want an allow-list mode (explicitly permit only named tools, everything else blocked), or a deny-list plus "anything not named here is new, tell me" notification mode? These have opposite operational profiles: the allow-list is safe by default and requires maintenance when upstreams add useful tools; the notify mode is permissive by default and requires attention when upstreams add dangerous tools.

**Q2. Template overlap.** Mac and iOS both pull in Swift. When both are installed, do you want de-duplication (Swift installed once), an error (you installed overlapping templates, pick one), or last-one-wins? The spec lists this as open (line 205). This blocks the template manifest format because the manifest needs to record what's installed, and the install/update logic depends on the answer.

**Q3. "Ponytail" and "Andrew".** The spec flags both (lines 210–212). Is "ponytail" a real Swift tool? Is "Andrew" the same person as "Drew" (drews-xcode-mcp)? These are one-sentence answers that block the Swift template's contents.

---

## 3. ROADMAP

Each increment delivers a user-facing behavior, names the test that proves it, and states how that test fails. Increments are ordered so each one's test can fail independently.

### Increment 1: JSON config parsing replaces the env-var parser

**Delivers:** The daemon reads `_wrapped_mcps.json` (Claude Code shape: `{"mcpServers": {"<name>": {"command", "args", "env"}}}`) instead of `XCODE_MCP_FRONT_UPSTREAMS`. The existing two-upstream behavior (xcode + drews) is reproduced from a file, not an env var.

**Test (fast, no Xcode):** Feed the parser a config file with two servers. Assert it produces two `Upstream` objects with the right names, commands, args, and `require_xcode` flags. Feed it a config with a command path containing a colon (`/usr/local/bin:weird/mcpbridge`) and assert the path is intact, not split. Feed it a config with `env` for a child process and assert the env vars are passed through.

**How it fails:** The colon-path test fails if the parser uses `split(":")` anywhere. The env test fails if `env` is ignored. The two-server test fails if the parser only reads one entry.

### Increment 2: Quirks field per upstream

**Delivers:** A `quirks` field in the config entry carries `{"requires_app": "Xcode"}` for Apple's upstream and is absent for Drew's. The daemon's approval-clicker only runs for upstreams with `requires_app: "Xcode"`. This replaces the positional `require_xcode` boolean.

**Test (fast, no Xcode):** Parse a config where one upstream has `quirks: {"requires_app": "Xcode"}` and another has no quirks. Assert the first upstream's `require_xcode_running` is `True` and the second's is `False`. Assert that a quirk key the daemon doesn't recognize (e.g., `{"foo": "bar"}`) is rejected at load time with a message naming the unknown quirk — not silently ignored.

**How it fails:** The unknown-quirk test fails if the parser accepts arbitrary keys. The `require_xcode` test fails if quirks don't drive the boolean.

### Increment 3: Prefix defaults to server name, is overridable

**Delivers:** Tool name prefixing defaults to the server name from the config (as today), but the config can specify a different prefix. This is the last piece of the generic aggregator.

**Test (fast, no Xcode):** Parse a config with `"prefix": "apple"` for a server named `"xcode"`. Assert the prefix is `apple__`, not `xcode__`. Parse a config with no prefix field and assert it defaults to the server name.

**How it fails:** The override test fails if the prefix is hardcoded to the server name. The default test fails if the prefix field is required.

### Increment 4: Live integration — the generic daemon serves both upstreams from the file

**Delivers:** The real daemon, launched with `_wrapped_mcps.json` instead of env vars, serves both `xcode__` and `drews__` tools. This is the slow test that proves the config-driven daemon works end-to-end.

**Test (slow, needs Xcode):** Same shape as the existing `test-xcode-mcp-front.sh` combined-daemon assertions: `tools/list` has both prefixes, `xcode__XcodeListWindows` returns a workspace path, `drews__version` returns Drew's version, an unknown prefixed tool returns a real error.

**How it fails:** Any of the four assertions fails if the config parsing, prefixing, or routing is wrong. The RED control (unknown tool name) fails if routing doesn't reject unknown prefixes.

### Increment 5: Version recording and mismatch detection

**Delivers:** The config records the compatible upstream version per server. On connect, the daemon compares the live `serverInfo.version` against the recorded one. A mismatch is noted in the `instructions` string. The human dialog fires once per distinct mismatch (persisted to a file).

**Test (fast, no Xcode):** Feed a config with `"compatible_version": "24952"` and a live version of `"24953"`. Assert the `instructions` string contains "24952" and "24953" and a mismatch indicator. Assert the dialog-suppression file gets an entry. Feed a matching version and assert no mismatch note and no new file entry.

**How it fails:** The mismatch-note test fails if the version comparison is skipped or the note is absent. The suppression test fails if the dialog fires on every connect instead of once per pair. Feed the *same* mismatch twice and assert the second connect produces no new file entry — this fails if the suppression is in-memory only (doesn't survive a restart).

### Increment 6: Stale entry detection — sieve and map entries that no longer resolve

**Delivers:** The config carries a sieve (blocked tools) and a map (renamed tools). On connect, the daemon checks each entry against the live tool list. An entry naming a tool the upstream doesn't offer is reported.

**Test (fast, no Xcode):** Feed a config with a sieve entry blocking `"xcode__OldToolName"` and a live tool list that doesn't contain `OldToolName`. Assert the daemon reports "stale sieve entry: OldToolName no longer offered." Feed a config with a map entry for a tool that exists and assert no stale report.

**How it fails:** The stale-entry test fails if the daemon doesn't compare entries against the live list. The clean-entry test fails if the daemon reports staleness for entries that do resolve.

### Increment 7: Sieve enforcement at `tools/call`

**Delivers:** A blocked tool is not just hidden from `tools/list` but rejected at `tools/call` with an error naming the tool and the reason it's blocked.

**Test (fast, no Xcode):** Feed a config that blocks `"drews__switch_scheme"` with `why: "limiting"`. Call `tools/call` with that name. Assert the response is an error containing the tool name and the `why` string. Call `tools/list` and assert the tool is absent.

**How it fails:** The `tools/call` test fails if blocked tools are only filtered from the listing. The `why` assertion fails if the reason isn't included in the error. Call an *unblocked* tool and assert it succeeds — this fails if the sieve is applied too broadly.

### Increment 8: Map — rename and reverse-translate

**Delivers:** A map entry exposes `xcode__XcodeGetCurrentFile` as `current_file`. `tools/list` shows `current_file`. `tools/call` with `current_file` routes to `xcode__XcodeGetCurrentFile`.

**Test (fast, no Xcode):** Feed a config with a map entry `{"expose": "current_file", "upstream": "xcode", "tool": "XcodeGetCurrentFile"}`. Assert `tools/list` contains `current_file` and not `xcode__XcodeGetCurrentFile`. Assert `tools/call` with `current_file` calls the upstream with `XcodeGetCurrentFile`. Assert `tools/call` with `xcode__XcodeGetCurrentFile` returns an error (the old name is no longer exposed).

**How it fails:** The list test fails if the old name appears. The call test fails if the reverse translation is missing. The old-name test fails if both names are accepted (which means the map is cosmetic, not a redirect).

### Increment 9: Description substitution

**Delivers:** When a tool is renamed via the map, its description has references to the old name replaced with the new name automatically. An explicit description override is also supported.

**Test (fast, no Xcode):** Feed a config that maps `XcodeGetCurrentFile` to `current_file` with the upstream description "Use XcodeGetCurrentFile to read the active file." Assert the exposed description contains `current_file` and not `XcodeGetCurrentFile`. Feed an explicit `"description": "Read the file open in the editor."` and assert that overrides entirely.

**How it fails:** The substitution test fails if the old name survives in the description. The override test fails if the substitution runs on top of the explicit override (it shouldn't — explicit means full replacement).

### Increment 10: Human override verbs — unblock and unmap

**Delivers:** The human file (`mcp_info.json`) carries verbs that modify the machine file's decisions: `unblock` removes a template block, `unmap` removes a template rename. The effective config is the machine file with verbs applied.

**Test (fast, no Xcode):** Machine file blocks `drews__switch_scheme`. Human file has `{"unblock": "drews__switch_scheme"}`. Assert the effective config does not block it. Machine file maps `XcodeGetCurrentFile` to `current_file`. Human file has `{"unmap": "current_file"}`. Assert the effective config exposes the original name.

**How it fails:** The unblock test fails if the merge doesn't apply verbs. The unmap test fails if verbs are applied before the map is built (order matters). Feed an `unblock` for a tool the machine file *doesn't* block and assert a "stale override" warning — this fails if no-ops are silent.

### Increment 11: `why` field enforced at load time

**Delivers:** Every sieve and map entry in the machine file must have a `why` string. The parser rejects the config (exit nonzero) if any entry is missing it.

**Test (fast, no Xcode):** Feed a config with a sieve entry lacking `why`. Assert the parser exits with an error naming the entry. Feed the same config with `why` present and assert it loads.

**How it fails:** The missing-`why` test fails if the parser accepts the entry. The present-`why` test fails if the parser is over-strict.

### Increment 12: Template manifest and install

**Delivers:** A template is a directory with a manifest (`template.json`), an `install.sh`, a `Brewfile`, and a `_mcp_info.json` (the generated config). A repo runs `install.sh --into <repo>` and gets the `_mcp_info.json` and `mcp_info.json` placed in the right location. Re-running `install.sh` rewrites only the underscore file.

**Test (fast, no Xcode):** Create a minimal template with two upstreams and a sieve. Run `install.sh --into /tmp/test-repo`. Assert `_mcp_info.json` exists and is valid JSON with the expected content. Assert `mcp_info.json` does not exist (the repo creates it). Run `install.sh` again with a modified template. Assert `_mcp_info.json` is overwritten and `mcp_info.json` (if the test created one) is untouched.

**How it fails:** The overwrite test fails if the installer touches the human file. The re-run test fails if the installer appends instead of overwrites the underscore file.

---

## 4. TEST ARCHITECTURE

### Fast sanity tier (target: under 15 seconds, no Xcode, no network, no GUI)

Everything that is pure logic with crafted inputs and expected outputs. The daemon's I/O layer (HTTP, stdio, approval dialogs) is excluded; the logic that sits above it is tested directly.

**What belongs here:**

1. **Config parsing** — JSON in, `Upstream` objects out. Colon-in-path, missing fields, unknown quirks, `env` passthrough. Pure function, sub-millisecond.
2. **Prefix logic** — default to server name, override from config. Pure function.
3. **Sieve application** — given a tool list and a sieve config, assert which tools survive. Applied to both `tools/list` (filter) and `tools/call` (reject). Pure function.
4. **Map forward and reverse** — given a map and a tool name, assert the exposed name and the upstream name. Pure function.
5. **Description substitution** — given a rename table and a description string, assert the substituted output. Pure function.
6. **Stale entry detection** — given a config (sieve + map) and a live tool list, assert which entries are stale. Pure function.
7. **Version comparison** — given a recorded version and a live version, assert the mismatch direction (newer, older, same) and the warning text. Pure function.
8. **Human override verb application** — given a machine file and a verb list, assert the effective config. Pure function.
9. **`why` field enforcement** — given a config, assert it's accepted or rejected. Pure function.
10. **Template install** — create a temp dir, run `install.sh --into`, check files. Filesystem, no network, sub-second.

**How the fast tier stays under 15 seconds:** All of the above are Python function calls or shell file operations. No subprocess spawns (except `install.sh` which is local). No HTTP. No Xcode. No approval dialogs. The entire fast tier is one `pytest` or `bash test-fast.sh` invocation that runs in under 2 seconds.

**How it tests user-facing behavior, not internals:** Each test asserts what the *model* or the *user* would see: the tool names in a listing, the error message on a blocked call, the description text, the warning text on a version mismatch. The internal representation (dicts, objects) is never the assertion target — the *exposed surface* is.

### Slow deep tier (target: under 60 seconds, needs Xcode and running daemons)

**What belongs here:**

1. **Live daemon integration** — the generic config-driven daemon serves both upstreams over HTTP, with real tool calls and real responses. This is the existing `test-xcode-mcp-front.sh` shape, adapted for config-file input.
2. **Approval dialog interaction** — the clicker finds and clicks the right dialog. This needs a real Xcode with a real approval prompt.
3. **Reconnect after Xcode restart** — kill Xcode, assert the daemon reconnects, assert tools come back. This needs a real Xcode.
4. **`listChanged` forwarding** (when implemented) — trigger a tool-list change upstream and assert the client sees the notification. Needs a real upstream.
5. **Version mismatch dialog** — the human-facing pyobjc dialog. Needs a real `.app` and a real desktop.

**What CANNOT be tested quickly and the honest substitute:**

- **The approval-clicker logic** cannot be tested without a real Xcode dialog. The honest substitute: test the *decision logic* in the fast tier (given a dialog PID and our PID, assert the action: Allow, Don't Allow, or wait), and test the *osascript execution* in the slow tier against a real dialog. The fast tier proves the branching is correct; the slow tier proves the AppleScript runs.
- **HTTP serving** cannot be tested without binding a port. The honest substitute: test the `on_list_tools` and `on_call_tool` handler functions directly in the fast tier (they're async functions that take params and return results — call them in-process with a mock `Upstream` that returns canned tool lists). The slow tier tests the real HTTP round-trip.
- **launchd lifecycle** (KeepAlive, restart on crash) cannot be tested in CI. The honest substitute: assert the plist shape in the fast tier (already done in the existing test), and verify launchd behavior manually after install.

### The split line

The principle: if it depends on Xcode being running, it's slow. If it depends on a port being bound, it's slow. Everything else — and that's most of the logic — is fast. The fast tier should have more tests than the slow tier, because the fast tier is where the logic lives. The slow tier is where the wiring is verified.

---

## 5. THE AD ASTRA TOOL FORMAT

A concrete proposal, derived from the existing patterns in `tools/convocation/`, `tools/periphery/`, and the other tools already in this repo.

### Directory layout

Every ad astra tool is a directory under `tools/` (or a third-party path adopted without becoming a submodule) containing:

```
tool-name/
├── tool.json          # manifest — identity, version, dependencies
├── install.sh         # installs dependencies via Homebrew, places files
├── uninstall.sh       # reverses install.sh
├── Brewfile           # Homebrew dependencies (formulae, taps, casks)
├── doctrine.md        # rules for using this tool (installed into repos via --into)
├── tests/
│   ├── test-fast.sh   # fast tier, no external deps, under 15s
│   └── test-slow.sh   # slow tier, may need Xcode/network/etc
└── ...                # the tool's actual code, scripts, etc.
```

### The manifest: `tool.json`

```json
{
  "name": "convocation",
  "version": "1.2.0",
  "description": "Multi-agent convocation: convoq-first search, brand mixing, session coordination.",
  "type": "tool",
  "dependencies": {
    "brew": ["node", "qwen-code"],
    "npm": ["@anthropic-ai/claude-code", "@openai/codex"]
  },
  "conflicts": ["other-convocation-tool"],
  "provides": ["convocation", "convoq"],
  "install": "install.sh",
  "uninstall": "uninstall.sh",
  "doctrine": "doctrine.md",
  "tests": {
    "fast": "tests/test-fast.sh",
    "slow": "tests/test-slow.sh"
  }
}
```

**Fields:**

- `name` — unique identifier, matches the directory name.
- `version` — semver. Used by the update flow to decide whether to re-run.
- `description` — one line, for humans and for `tool list` output.
- `type` — `tool`, `template`, or `skill`. Templates install MCP configs; tools install CLIs; skills install doctrine only.
- `dependencies.brew` — entries that go in the `Brewfile`. The `Brewfile` is the canonical source; this field mirrors it for programmatic access.
- `dependencies.npm` — npm globals, installed by `install.sh` (not Homebrew). The convocation pattern:Now I have the full picture. Here is my review.

---

## 1. HOLES

**HOLE 1: The sieve applied at `tools/call` breaks when a tool is mapped AND blocked — order of operations is unspecified.**

A tool can be in both the sieve (blocked) and the map (renamed). If a caller sends the mapped name, the wrapper must reverse-map before checking the sieve, or the sieve check runs against the exposed name and misses. If it reverse-maps first, a block on the upstream name catches it. If it checks the sieve first against the exposed name, a block keyed on the upstream name misses it. The SPEC describes sieve and map as independent mechanisms (sections "The sieve" and "The tool map") but never says which applies first on the `tools/call` path, and they compose differently depending on the answer. This is the kind of defect that surfaces only when a real user blocks `drews__scheme_switch` and maps it to something else at the same time — late, confusing, and intermittent.

*Fix:* State the pipeline explicitly. On `tools/list`: apply sieve (filter), then map (rename) — so the user never sees a blocked name and sees only the mapped name. On `tools/call`: reverse-map the exposed name to the upstream name, then check the sieve against the upstream name. Document this as a single invariant: the sieve always operates in upstream-name space, the map always translates between the two spaces.

**HOLE 2: `listChanged` re-application has no replay semantics — a call in flight when the list changes gets an old list or a stale rejection.**

SPEC.md lines 102-104 note that `capabilities.tools.listChanged: true` means the tool list is a moving target and the sieve should re-apply on notification. But the daemon's `on_list_tools` (daemon.py line 745) is a synchronous call that fetches from the upstream and returns. If the upstream fires `notifications/tools/list_changed` between a client's `tools/list` and its `tools/call`, the client holds names that the sieve may have just re-evaluated differently. The SPEC says "re-apply on listChanged" but does not say what happens to in-flight calls that reference names valid under the old list but not the new. An LLM that got the old list and calls a just-removed tool gets a hard error with no explanation of why the tool it was just shown is now gone.

*Fix:* Define the contract: a `tools/list` response is a snapshot valid until the next `listChanged` notification. A `tools/call` for a name that was valid in the snapshot but is no longer in the live list returns a specific error naming the version transition, not a generic "unknown tool." The LLM can then re-list and adapt.

**HOLE 3: The human-file "verbs not values" merge has no conflict semantics for two repos composing templates.**

SPEC.md lines 192-200 propose the human file carrying verbs (`block`, `unblock`, `map`, `unmap`). This works for one repo overriding one template. But the SPEC also says a repo may install two overlapping templates (Mac and iOS both pull in Swift). If both templates emit `_mcp_info.json` files and both have human files, the merge order of the two human files' verb streams is undefined. A Mac template human file says `unblock window_close` and an iOS template human file says `block window_close` — which wins? Last-applied? First-applied? Error? The SPEC identifies overlap resolution as "the installer's problem" (line 30) but never defines the resolution rule for conflicting verbs across two installed templates.

*Fix:* Define a composition order: templates apply in declaration order, each template's machine file then its human file, and a later template's `unblock` overrides an earlier template's `block`. Record the effective decision chain in the generated output so a human can read what happened. Alternatively, refuse overlapping verbs and require the repo to resolve in a single top-level human file.

**HOLE 4: The version-mismatch dialog persisted to disk has no invalidation path when the human switches Xcode versions deliberately.**

SPEC.md lines 130-140 say the human dialog fires once per distinct mismatch, keyed on server name plus version pair, persisted so a launchd restart does not re-raise it. But if Jonathan deliberately switches from Xcode 26.6 to Xcode-beta 27.0, the persisted "seen" entry for `xcode-tools 24952 → 24953` is now stale — he is on a different version entirely. The next mismatch (27.0's version against whatever was recorded) might or might not fire the dialog depending on whether the pair matches. The SPEC has no invalidation logic for "the user changed the upstream on purpose." The persisted store grows monotonically with every version pair ever seen and never tells the human "you switched versions, here is what changed from your last known-good."

*Fix:* Key the persistence on the last-known-good version, not on the mismatch pair. When the live version differs from the last-known-good, fire the dialog once, then update last-known-good. When the user switches Xcode deliberately (detected by the app path changing or the version going backwards), reset last-known-good to the new version so the next mismatch is from the new baseline, not the old one.

**HOLE 5: The generic daemon has no answer for an http upstream that is itself an aggregator.**

SPEC.md line 83 says the config follows Claude Code's shape, where an http entry carries `url`. The existing daemon (daemon.py) only supports stdio upstreams — `StdioServerParameters` in the `Upstream` class, no HTTP client path. The SPEC says "the config shape already carries `url` for http upstreams" (line 168) as if this is handled, but it is not. An http upstream that is itself another aggregator (the "wrap the wrapper alongside MacControlMCP.app" option from the open questions, line 207) would need an HTTP client session, not a stdio child. This is not a quirk; it is a second transport. The SPEC's build order (line 73) says "glue two MCPs together from a Claude-Code-shaped file" as step one, but step one as written only handles stdio entries, and the Claude Code shape allows http.

*Fix:* Either implement http upstreams in step one (the `Upstream` class gains an `http_client` path alongside `stdio_client`), or explicitly scope step one to stdio-only and say http upstreams are a later increment. The SPEC should not imply parity with the Claude Code shape if http is deferred.

**HOLE 6: The comparison script's `--summarize` model pass has no deterministic contract — the same input can produce different collision lists across runs.**

`mcp_tools.py` line 137 hands both tool lists to the default `llm` model for a semantic pass. The SPEC (line 165) says this is "the semantic pass, since Xcode's new tool need not be named anything like Drew's." But an LLM call is nondeterministic. Two runs against the same upstream versions can produce different collision lists, which means the "suggest running the collision tool" path (SPEC line 73) gives inconsistent advice. If the collision tool's output drives a config decision (which tool to block), and the decision is different on a re-run, the config is not reproducible. The SPEC treats the model pass as a reliable comparator without acknowledging that it is not.

*Fix:* Either pin the model and temperature for the comparison pass and accept that it is best-effort advisory (not a gate), or require the human to review and commit the collision output into the config as a deliberate decision, so the model pass is a suggestion and the config is the source of truth. The SPEC should say which.

**HOLE 7: The stall watchdog's `os._exit(75)` on a multi-upstream daemon kills ALL upstreams when one stalls.**

daemon.py line 600: `os._exit(75)` exits the entire process when one upstream's reconnect loop is wedged. In multi-upstream mode, a wedged mcpbridge connection takes down Drew's perfectly healthy connection too, and the whole daemon restarts under launchd — costing a fresh Xcode approval prompt for the mcpbridge side while Drew's side had nothing wrong. The SPEC's generic daemon is supposed to isolate upstreams ("different upstreams' calls are fully independent," daemon.py line 37), but the watchdog violates that isolation at the process level.

*Fix:* In multi-upstream mode, a stalled upstream should be killed at the task level (cancel its connection_manager task and restart just that upstream's loop), not at the process level. Reserve `os._exit` for single-upstream mode where there is nothing else to lose. Or, if the stall is truly unrecoverable (wedged in `stdio_client.__aexit__`), isolate it by running each upstream in a subprocess rather than a task — but that is a bigger change and should be a conscious design decision.

**HOLE 8: The `why` field is required and enforced at load time, but the SPEC never says what happens to a config that was valid before the `why` requirement was added.**

SPEC.md lines 203-208 say `why` is required on every sieve and map entry and rejected at load time. But the existing `_wrapped_mcps.json` (the thing step one replaces) has no `why` field because it has no sieve or map yet. When step two adds the sieve, the first config ever written has `why` on every entry — fine. But when a template update adds a new blocked tool to `_mcp_info.json` and the template author forgot the `why`, the load fails and the daemon does not start. The SPEC has no migration path for "config was valid yesterday, the template added entries without `why`, and now the daemon is down." That is an upstream-update-caused outage, which is exactly the class of failure the SPEC says to avoid (line 114: "refusing to start would mean an Xcode update takes the whole surface down").

*Fix:* Distinguish machine-generated entries (which should always have `why` and fail loud if missing) from human entries (which should also have `why` but degrade to a warning if missing, not a startup failure). A template update with a missing `why` is a template bug, not a reason to take the daemon down.

**HOLE 9: The description find-and-replace pass can produce descriptions that mention upstream names the user cannot see.**

SPEC.md lines 156-162 say the rename table drives automatic find-and-replace across all tool descriptions. But descriptions can reference tool names from the upstream that are themselves blocked by the sieve. If `drews__scheme_switch` is blocked and `drews__window_open` is mapped to `open_window`, the description for `open_window` might say "use scheme_switch to set the active scheme first" — and `scheme_switch` is not in the exposed surface. The mechanical substitution handles renamed tools but has no awareness of blocked tools. The SPEC says a rename leaving an un-substituted reference deserves a warning (line 162), but a reference to a *blocked* tool is a different defect: the description tells the model to call something that does not exist in any form.

*Fix:* The description post-processing pass should check references against the effective exposed surface (after sieve and map), not just the rename table. A reference to a blocked tool in a visible tool's description is a warning: "description mentions `scheme_switch` which is blocked — the description is misleading." This is the kind of incoherence the sieve exists to prevent, and it arrives through descriptions rather than through the tool list.

---

## 2. QUESTIONS FOR THE OWNER

**Q1.** The sieve has two purposes (coherence and limiting) with opposite failure directions. A deny-list fails open (new tools appear); an allow-list fails closed (new tools are hidden). You said this is your policy choice. The SPEC proposes "both forms, or a deny-list plus a 'tell me about new tools' mode." Which do you want built first — deny-list with new-tool alerts, or deny-list plus allow-list as separate modes? They are different implementations and the build order depends on your answer.

**Q2.** The SPEC's open questions (line 206) ask how to compose the Mac set and whether overlap de-duplicates, errors, or last-one-wins. This is undecidable without you because it depends on your mental model of what a "template install" means: is it additive (two templates merge their upstreams) or exclusive (one wins)? The build order cannot proceed past the single-aggregator milestone without this, because composing two templates into one `_wrapped_mcps.json` requires knowing the merge rule.

**Q3.** "Andrew" vs "Drew" (SPEC line 214): is the `drews-xcode-mcp` running in the combined daemon the same tool you referred to as "Andrew's thing," or are these two different people/tools? "Ponytail" (line 217) — is this a real tool name or shorthand? These need one sentence each from you before the Swift template can list its tools.

---

## 3. ROADMAP

Each increment delivers a user-facing behaviour, a test that proves it, and how that test can fail. Tests that cannot fail are not included.

### Increment 1: Config-driven multi-upstream from JSON (replaces env-var parsing)

**Behaviour.** The daemon reads `_wrapped_mcps.json` in Claude Code's `{"mcpServers": {...}}` shape and connects all listed stdio upstreams, prefixing tool names with the server name. The existing `XCODE_MCP_FRONT_UPSTREAMS` env var is removed. A config with two entries reproduces exactly what the combined daemon does today.

**Test.** Start the daemon with a two-entry config pointing at `xcrun mcpbridge` and `uvx drews-xcode-mcp`. Assert `tools/list` returns both `xcode__` and `drews__` prefixed tools. Assert `xcode__XcodeListWindows` returns a workspace path. Assert `drews__version` returns Drew's version string. Assert a call to `NotARealTool` returns the "no known upstream prefix" error. This is the existing test suite adapted to read from a config file instead of env vars.

**How it fails.** Remove one entry from the config — the test must see zero tools from that prefix. Corrupt the JSON — the daemon must fail loud, not start with zero upstreams. Swap a stdio entry for an http entry — the daemon must report "http upstreams not supported in this increment" rather than silently ignoring it.

### Increment 2: Version recording and mismatch warning (in-band only)

**Behaviour.** The config file records the `serverInfo` version observed when each upstream was verified. On `initialize`, the daemon reads each upstream's live `serverInfo` and compares. If the version differs, the daemon's `instructions` string in the `initialize` response includes a warning line: "xcode-tools: compatible with 24952, found 24953." No human dialog yet — that comes later.

**Test.** Write a config that records `xcode-tools` version `00000` (deliberately wrong). Start the daemon. Assert the `initialize` response's `instructions` field contains the string "compatible with 00000, found" (the live version). Then write a config with the correct version. Assert the `instructions` field does NOT contain "compatible with." The test proves the warning fires on mismatch and is absent on match.

**How it fails.** If the daemon does not read `serverInfo` at all, the warning never appears and the "compatible with" assertion fails. If the daemon reads it but does not put it in `instructions`, the assertion fails. If the warning fires even on a match, the "does NOT contain" assertion fails.

### Increment 3: The sieve (deny-list, applied at both `tools/list` and `tools/call`)

**Behaviour.** The config file gains a `sieve` object per upstream, listing blocked tool names with a required `why` field. `tools/list` omits blocked tools. `tools/call` rejects a blocked tool name with an error: "tool `xcode__BuildProject` is blocked by the sieve: <why>."

**Test.** Write a config that blocks `xcode__XcodeListWindows` with `why: "testing"`. Assert `tools/list` does NOT contain `xcode__XcodeListWindows`. Assert `tools/call` for `xcode__XcodeListWindows` returns an error containing "blocked by the sieve" and the why string. Assert `xcode__XcodeGetCurrentFile` (not blocked) still appears in `tools/list` and still routes on `tools/call`. The RED control: assert a `tools/call` for a blocked tool does NOT return a successful result.

**How it fails.** If the sieve is only applied to `tools/list`, the `tools/call` assertion for the blocked tool returns a successful result instead of the error. If the sieve is not applied at all, the blocked tool appears in `tools/list`. If `why` is not enforced, a config with a missing `why` loads silently — add a separate assertion that a config entry without `why` causes a startup failure.

### Increment 4: Stale sieve entry detection

**Behaviour.** On startup and on `listChanged`, the daemon compares the sieve entries against the live tool list. A sieve entry naming a tool the upstream no longer offers is logged as a warning and surfaced in the `initialize` instructions: "sieve entry `xcode__ExecuteSnippet` no longer matches any live tool." This is the cheap direction — catches renames and removals, not additions.

**Test.** Write a config that blocks `xcode__ExecuteSnippet` (a tool that was renamed to `RunCodeSnippet` in 26.6). Start the daemon against Xcode 26.6. Assert the `initialize` instructions contain "no longer matches." Assert the same config against a mock upstream that DOES offer `ExecuteSnippet` produces no such warning. (The mock here is a tiny stdio MCP server that advertises one tool — it is a real subprocess, not a mock framework, per the house testing rule.)

**How it fails.** If the stale detection does not run, the "no longer matches" assertion fails. If it runs but does not surface in `instructions`, same. If it fires for tools that DO exist, the mock-upstream assertion fails.

### Increment 5: The tool map (rename, applied at `tools/list` and reversed at `tools/call`)

**Behaviour.** The config gains a `map` object mapping exposed names to upstream names. `tools/list` shows the mapped (exposed) name. `tools/call` accepts the exposed name, reverses to the upstream name, and routes. A mapped tool need not carry the prefix.

**Test.** Write a config that maps `list_windows` to `xcode__XcodeListWindows`. Assert `tools/list` contains `list_windows` and does NOT contain `xcode__XcodeListWindows`. Assert `tools/call` for `list_windows` returns a real workspace path. The RED control: assert `tools/call` for `xcode__XcodeListWindows` (the old upstream name) returns an error, not a successful result — because the mapped surface no longer exposes it under that name.

**How it fails.** If the reverse map is missing, `tools/call` for `list_windows` returns "unknown tool." If the map is only applied to `tools/list`, the `tools/call` for the exposed name fails because the upstream does not know `list_windows`. If the old name is still accepted, the RED control fails.

### Increment 6: Description find-and-replace on mapped tools

**Behaviour.** When a tool is renamed by the map, its description is scanned for references to the old upstream name and replaced with the exposed name. A reference to a name that is neither in the exposed surface nor in the upstream surface produces a warning in the `initialize` instructions.

**Test.** Write a config that maps `list_windows` to `xcode__XcodeListWindows`, and a mock upstream whose `XcodeListWindows` description says "Calls XcodeListWindows to get windows." Assert the `tools/list` response for `list_windows` has a description containing `list_windows` (the exposed name) and NOT containing `XcodeListWindows` (the old name). Add a second mock tool whose description references `NonExistentTool` — assert the `initialize` instructions contain a warning about `NonExistentTool`.

**How it fails.** If the substitution does not run, the description still contains `XcodeListWindows` and the assertion fails. If the substitution runs but does not warn on dangling references, the `NonExistentTool` warning is absent.

### Increment 7: Quirks as a per-upstream named list

**Behaviour.** The config gains a `quirks` list per upstream. Today's `requires_app: "Xcode"` and the approval-dialog clicker become quirk entries. An upstream with no quirks does not inherit Xcode's behavior. The `require_xcode` positional boolean in the parser is gone.

**Test.** Write a two-upstream config: one with `quirks: ["requires_xcode_app"]` and one without. Start the daemon with Xcode NOT running. Assert the first upstream's `tools/list` returns zero tools with a "waiting for Xcode" log line. Assert the second upstream's `tools/list` returns its full tool list (Drew's does not need Xcode). The RED control: swap the quirk to the wrong upstream and assert the behavior inverts.

**How it fails.** If quirks are not per-upstream (still a global flag), both upstreams wait for Xcode and Drew's returns zero tools. If the quirk is ignored entirely, the first upstream tries to connect without Xcode and fails with an unguarded error.

### Increment 8: Human dialog on version mismatch (once per distinct mismatch, persisted)

**Behaviour.** On a version mismatch, the daemon raises a native macOS dialog via pyobjc from the wrapper `.app`: "xcode-tools: compatible with 24952, found 24953; 2 blocked tools no longer match." The dialog fires once per distinct mismatch pair, persisted to `~/.xcode-mcp-front/seen_mismatches.json`. A launchd restart does not re-raise it. The in-band warning (increment 2) continues to fire every session.

**Test.** Write a config with a deliberately wrong version. Start the daemon (as the `.app`, not bare python, so pyobjc can raise the dialog). Assert the dialog appears (detected via `osascript` reading window text — the same mechanism the clicker uses). Kill the daemon, restart it. Assert the dialog does NOT appear again. Delete the persistence file. Restart. Assert the dialog appears again.

**How it fails.** If the persistence is not written, the dialog appears on every restart. If the persistence is written but never invalidated, the dialog never appears after the first time even for a new mismatch — add an assertion with a second wrong version pair and check the dialog fires for the new pair. If pyobjc cannot raise the dialog (the `.app` grant is dead), the assertion times out — this is a loud failure naming the grant, not a silent pass.

### Increment 9: Template install / update (the mogenerator split)

**Behaviour.** A template directory contains a `template.json` manifest and an `install.sh`. Running `install.sh --into <repo>` writes `_mcp_info.json` (machine-owned) into the repo and copies any human-owned `mcp_info.json` if it does not already exist. Re-running `install.sh --into <repo>` overwrites `_mcp_info.json` and leaves `mcp_info.json` untouched.

**Test.** Create a temp repo directory. Run the template's `install.sh --into <temp>`. Assert `_mcp_info.json` exists with the expected content. Assert `mcp_info.json` does NOT exist (first install). Manually create `mcp_info.json` with a custom block. Re-run `install.sh --into <temp>`. Assert `_mcp_info.json` was overwritten (new content). Assert `mcp_info.json` still contains the custom block (untouched). The RED control: delete `_mcp_info.json`, re-run install, assert it was recreated — proves the install is not a no-op.

**How it fails.** If the install overwrites the human file, the custom block is gone and the assertion fails. If the install does not write the machine file, `_mcp_info.json` is missing. If the install is a no-op on re-run, the deleted-file assertion fails.

### Increment 10: Human-file verbs (block, unblock, map, unmap)

**Behaviour.** The human-owned `mcp_info.json` carries verbs that modify the machine file's decisions. `unblock` removes a tool from the sieve. `block` adds one. `map` and `unmap` do the same for the map. The effective config is the machine file with the human verbs applied in order. A human verb that has become a no-op (e.g., `unblock` for a tool the template no longer blocks) produces a warning.

**Test.** Write a machine file that blocks `tool_a` and `tool_b`. Write a human file that `unblock`s `tool_a`. Assert the effective config blocks `tool_b` but not `tool_a`. Write a human file that `unblock`s `tool_c` (not blocked by the machine file). Assert a warning is produced. The RED control: remove the human file and assert both `tool_a` and `tool_b` are blocked — proves the human file is doing something.

**How it fails.** If the verbs are not applied, both tools stay blocked and the `tool_a` assertion fails. If the verbs are applied but the no-op detection does not run, the `tool_c` warning is absent. If the machine file is edited directly instead of through verbs, the RED control fails because the unblock had no effect.

---

## 4. TEST ARCHITECTURE

### Fast sanity tier (target: under 15 seconds, no Xcode required)

Everything in this tier runs against synthetic or local-only inputs — real subprocesses, never mock frameworks, but no GUI dependencies.

| Test | What it proves | How it can fail | Xcode needed? |
|---|---|---|---|
| Config parsing: valid JSON loads, invalid JSON fails loud | The loader rejects bad input | Corrupt the JSON — must get a named error, not a silent zero-upstream start | No |
| Config parsing: missing `why` on a sieve entry fails | The `why` requirement is enforced | Remove `why` — must get a startup failure | No |
| Prefix routing: a two-upstream config produces prefixed tools | The aggregator merges and prefixes | Remove one upstream — its prefix must disappear | No (use a mock stdio MCP) |
| Prefix routing: unknown prefix returns error | The RED control for routing | Send `NotATool` — must get the "no known upstream prefix" error | No |
| Sieve at `tools/list`: blocked tool absent | The sieve filters discovery | Remove the sieve — the tool must appear | No |
| Sieve at `tools/call`: blocked tool rejected | The sieve filters invocation, not just listing | Call the blocked tool — must get "blocked by the sieve" error, not a result | No |
| Map at `tools/list`: exposed name present, upstream name absent | The map renames on the way out | Remove the map — the upstream name must appear instead | No |
| Map at `tools/call`: exposed name routes correctly | The reverse map translates on the way in | Remove the reverse map — the call must fail with "unknown tool" | No |
| Stale sieve entry detection: warning in `initialize` instructions | Renames and removals are caught | Point at a mock that does not offer the blocked tool — must warn | No |
| Description substitution: old name replaced, dangling reference warned | Descriptions stay coherent after mapping | Skip the substitution — the old name must still be in the description | No |
| Mogenerator split: machine file overwritten, human file preserved | Template update does not clobber human decisions | Run install twice — human file must be unchanged | No |
| Human-file verbs: `unblock` removes a block, no-op `unblock` warns | Verbs compose with the machine file | Remove the human file — both tools must be blocked | No |

**How this stays under 15 seconds.** Every test in this tier uses a tiny stdio MCP server (a 20-line Python script that advertises two tools and answers `tools/call` with a fixed string) as the upstream, not `xcrun mcpbridge`. No Xcode launch, no approval dialog, no GUI. The daemon starts in under a second against a local mock. Each test is a start-daemon, one-or-two HTTP calls, stop-daemon cycle — 1-2 seconds per test, 12 tests, target 10-12 seconds total. The mock server is a real subprocess (not a mock framework), satisfying the "real systems over mocks" rule — it speaks the actual MCP protocol over real stdio.

### Slow deep tier (target: under 60 seconds, requires Xcode)

| Test | What it proves | Why it cannot be fast |
|---|---|---|
| Version mismatch warning in `initialize` instructions against live mcpbridge | The real upstream's `serverInfo` is read and compared | mcpbridge needs Xcode running and approved |
| Sieve against the real tool list (21 tools from mcpbridge, 29 from Drew's) | The sieve filters real tool names, not synthetic ones | Needs the real upstream's actual `tools/list` |
| Map against a real renamed tool (`ExecuteSnippet` → `RunCodeSnippet` on 26.6) | The map absorbs a real upstream rename | Needs the real Xcode version |
| Human dialog appearance and persistence via pyobjc | The dialog fires once, persists, and does not re-fire | Needs the `.app` wrapper and its TCC grant |
| Quirks: `requires_xcode_app` gates the upstream on real Xcode | The quirk actually waits for Xcode | Needs Xcode to be startable/stoppable |

**What cannot be tested quickly, and the honest substitute.**

The approval-dialog clicker (`_click_allow_if_present`) cannot be tested without a real Xcode showing a real dialog — it is a GUI automation behavior bound to a live process. The honest substitute is the one the existing test suite already uses: assert the behavior by effect against the real running daemon (a successful `tools/list` from the combined daemon proves the clicker worked, because without it mcpbridge never answers). This belongs in the slow tier and is gated on Xcode being up. It cannot be made fast without faking the dialog, which would be a mock asserting a mock — the exact thing the testing rules forbid.

The `listChanged` re-application cannot be tested quickly because no synthetic upstream fires `notifications/tools/list_changed` on demand. The honest substitute: a mock stdio MCP that sends a `listChanged` notification after its tool list changes on a signal, proving the daemon re-applies the sieve. This is buildable as a 30-line mock and could move to the fast tier — but only if the mock faithfully implements the MCP notification path, which is the thing being tested, so it risks tautology. Keep it in the slow tier and validate against a real upstream that supports `listChanged` (mcpbridge does).

### How the fast tier stays honest

Every fast-tier test has a RED control: a mutation that must cause failure. The config-parsing test mutates the JSON; the prefix-routing test removes an upstream; the sieve test removes the sieve; the map test removes the map. A test whose RED control passes (the mutation does NOT cause failure) is a tautology and the run fails — this is the `red()` helper from `lib.sh`, applied per test.

---

## 5. THE AD ASTRA TOOL FORMAT

### What a tool is

An ad astra tool is a directory under `tools/` with these required files:

```
tools/<tool-name>/
├── tool.json          # manifest — identity, version, dependencies
├── install.sh         # install (idempotent, check-first, same-method rule)
├── uninstall.sh       # undo what install.sh did
├── Brewfile           # Homebrew dependencies (the sanctioned dependency mechanism)
├── README.md          # what it does, how to use it, known gotchas
└── tests/
    └── test-<tool-name>.sh   # fast-tier test, sources lib.sh, runs in <15s
```

### `tool.json` — the manifest

```json
{
  "name": "periphery",
  "version": "1.0.0",
  "description": "Swift dead-code detection via peripheryapp's periphery",
  "category": "swift",
  "dependencies": {
    "brew": [
      {"tap": "peripheryapp/periphery", "formula": "peripheryapp/periphery/periphery"}
    ]
  },
  "conflicts": ["swiftlint-duplicate"],
  "install": "install.sh",
  "uninstall": "uninstall.sh",
  "test": "tests/test-periphery.sh",
  "doctrine": null,
  "provides": {
    "commands": ["periphery"],
    "mcp_servers": {},
    "skills": []
  }
}
```

Fields:

- **`name`** — matches the directory name. Unique across all tools. This is the identity a repo references.
- **`version`** — semver. Bumped when the tool's behavior, config shape, or dependencies change. A repo records which version it installed, so an update knows what to rewrite.
- **`category`** — one of `xcode`, `swift`, `mac`, `ios`, `utility`, `testing`. This is how templates compose: a template is a set of categories, and a tool's category determines which template pulls it in.
- **`dependencies.brew`** — the Brewfile contents as data, so a template can aggregate dependencies without parsing shell. The Brewfile file still exists for human `brew bundle` use; this field is the machine-readable mirror.
- **`conflicts`** — other tool names that provide overlapping capabilities. If two conflict, the installer warns and asks the human to pick. This is the coherence sieve at the tool level, not the MCP level.
- **`provides.commands`** — CLI binaries the tool installs. A repo can check these against `command -v` to verify an install.
- **`provides.mcp_servers`** — MCP server entries this tool contributes, in the Claude Code shape. A template aggregates these into the repo's `_wrapped_mcps.json` or `.mcp.json`.
- **`provides.skills`** — skill names this tool provides. Listed so a template knows what capabilities travel with the tool.
- **`doctrine`** — path to a doctrine file (like `convocation-doctrine.md`) or null. If present, `install.sh --into <repo>` copies it into the repo's `.doctrine/` directory.

### How a repo declares which tools it wants

A repo has an `astra.json` at its root:

```json
{
  "tools": [
    {"name": "xcode-mcp-front", "version": "0.4.0"},
    {"name": "periphery", "version": "1.0.0"},
    {"name": "convocation", "version": "1.0.0", "into": true}
  ]
}
```

- **`name`** — which tool.
- **`version`** — which version was installed. On update, the installer compares this against the tool's current `tool.json` version and re-runs `install.sh` if they differ.
- **`into`** — if true, the tool's doctrine is installed into the repo's instruction files (the `--into` flag from `convocation/install.sh`).

### How an update is applied

```sh
astra update                # for each tool in astra.json, compare version, re-run install.sh if newer
astra update <tool-name>    # update one tool
astra add <tool-name>       # add a new tool (writes it into astra.json, runs install.sh)
astra remove <tool-name>    # run uninstall.sh, remove from astra.json
```

`astra update` does the following for each tool:
1. Read the repo's `astra.json` and the tool's `tool.json`.
2. If the versions match, skip.
3. If they differ, run `install.sh` (which overwrites `_` files and leaves human files alone, per the mogenerator split).
4. Update `astra.json` with the new version.
5. Run the tool's test to verify the update did not break anything.

### Adopting a third-party tool without a submodule

A third-party tool (not in `js-db-ad-astra/tools/`) is declared the same way, but with a `source` field:

```json
{
  "tools": [
    {"name": "some-external-tool", "version": "0.1.0", "source": "github:owner/repo"}
  ]
}
```

`astra add some-external-tool` clones or downloads the tool's `tool.json` and install script into a cache directory (`~/.astra/cache/<tool-name>/`), validates that `tool.json` has the required fields, and runs `install.sh` from there. The tool is NOT a submodule of the repo — it is fetched on demand and cached. The repo's `astra.json` records the name, version, and source, so the update path can re-fetch. This is the "package manager" behavior Jonathan asked for: a repo declares what it wants, the installer fetches and installs it, and the repo's git history only records the declaration, not the dependency's source tree.

### What this does NOT include (and why)

- **No lockfile.** The Brewfile is the lock. Homebrew resolves versions. A lockfile would duplicate what `brew bundle` already does and would rot between `brew upgrade` runs.
- **No virtual environment.** Tools install into the system (Homebrew, npm global, pip). The "same method, check first" rule in `install.sh` prevents double-installs. A venv per tool would fragment the PATH and complicate the `command -v` checks that tests rely on.
- **No registry.** The tool list is the `tools/` directory and the `source` field. A registry would need hosting, authentication, and a deletion policy — none of which this project needs at its current scale.
