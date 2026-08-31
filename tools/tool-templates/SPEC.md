# Tool templates — composable per-repo MCP and tooling setups

Author: GhOST-Claude, 2026-08-31, from Jonathan's design as dictated. Status: **specification, shelved.** Nothing here is built. The name `tool-templates` is provisional.

## What this is for

A repository needs a set of capabilities that depends on what kind of development happens in it, and that set is currently assembled by hand, one repo at a time, from memory. Mac work needs one collection of MCP servers and command-line tools. Swift work needs a different one. iOS work needs the Swift collection plus a way to drive the simulator. These collections overlap heavily and are re-derived every time, which is how they drift apart and how a repo ends up missing something nobody noticed was missing.

The proposal is to keep the collections in `js-db-ad-astra` as **templates**, install them per-repo, and let templates contain other templates.

## The composition model

A template is a named bundle of three kinds of thing: **MCP server configuration**, **tools** (CLIs, scripts, wrappers), and **skills**. A template may also list other templates as members, and that is the point — composition is the mechanism, not a convenience.

The worked example Jonathan gave:

- An **Xcode** template: whatever is needed to drive Xcode. Today that is the `xcode-mcp-front` daemon fronting Apple's `mcpbridge`, and Drew's `xcode-mcp-server` alongside it.
- A **Swift** template: `swiftlint`, dead-code detection, duplicate-code detection, and Andrew's Swift tooling.
- A **Mac** template: what is needed to run and drive Mac applications, which is where `MacControlMCP.app` lives.
- A **Mac + Swift** template that is simply those three as members, because that is what Mac application development actually requires.
- An **iOS** template that is the Swift template plus simulator control.

A repo installs the highest-level template it needs. It may install more than one even when they overlap — Mac **and** iOS is a legitimate combination, and overlap resolution is the installer's problem rather than the author's.

## Generated versus human-owned, the mogenerator pattern

Jonathan's reference is `mogenerator` (rentzsch/mogenerator, verified 2026-08-31). Its elevator pitch: given a data model it generates two classes per entity, `_MyEntity` "intended solely for machine consumption" and "continuously overwritten to stay in sync", and `MyEntity` which subclasses it, "won't ever be overwritten and is a great place to put your custom logic."

Applied here, every generated artifact comes in two files:

- `_MCP_Config.json` — written by the template, overwritten freely whenever the template updates, never edited by a human.
- `MCP_Config.json` — imports or extends the generated one, owned by the repo, and **never written by a machine action.**

That gives per-repo extension and override without the update path and the customisation path fighting each other. Updating a template is then a safe, repeatable operation rather than a merge conflict, which is the property that makes templates worth having at all. The same split should apply to any other generated configuration a template emits, not only MCP config.

This also matches the existing rule that astra installers pull external dependencies fresh from source every time and are re-run to update. A template update is an installer re-run that rewrites only the underscore files.

## Constraints carried in from the daemon work, 2026-08-31

Two facts learned while fixing `xcode-mcp-front` today bear directly on this design.

**Separate the generic front-daemon from the per-upstream quirk.** What `xcode-mcp-front` does splits cleanly in two. Multiplexing several stdio upstreams behind one HTTP endpoint with name prefixing (`xcode__`, `drews__`), plus the durability layer — reconnect loop, heartbeat that catches a dead upstream before a client does, stall watchdog that exits so launchd restarts it — is generic and worth reusing for any front daemon. Suppressing Xcode's per-PID approval dialog is a quirk of one upstream. If the generic part is the template's building block and the quirk is a plugin attached to a specific upstream, then a template composing three MCP servers does not inherit Xcode's problems for the two that do not have them.

**Approval serialisation is per-Xcode and does not scale.** Xcode shows one approval dialog at a time and each front daemon needs roughly six seconds of exclusive dialog time to answer its own. Two daemons serialise inside the fifteen-second connect timeout and both get through, which is verified. Three would need about eighteen seconds and would likely fail, presenting as timeouts that look like Xcode refusing to serve tools. **A template design that spins up a front daemon per tool group will hit this ceiling**, so either the connect timeout grows with the number of daemons, or approval handling moves into one shared place rather than being first-come-first-served per daemon. This number is derived from the observed six seconds, not measured at three daemons; measure before relying on it.

## Step one: a generic wrapping MCP driven by `_wrapped_mcps.json`

Jonathan's first milestone, 2026-08-31: "duplicate what we did with Andrew + Apple's Xcode MCP in a generic MCP. So we can have `_wrapped_mcps.json`, which can be inspired by the mcp setup for claude code."

So the combined daemon stops being an Xcode tool that happens to take a second upstream, and becomes a general one-endpoint-many-upstreams front that is told what to wrap by a file. The underscore in the filename is the mogenerator convention already: that file is written by a template and overwritten on update, with a sibling the repo owns.

**The format follows Claude Code's, because it already exists and he already reads it.** His `.mcp.json` today is `{"mcpServers": {"<name>": {...}}}`, where a stdio entry carries `command`, `args` and `env`, and an http entry carries `url`. Reusing that shape means no second mental model, and it means an entry can be moved between the two files by copy and paste.

The wrapper needs two things Claude Code's format does not carry, and they should be additive rather than a fork of it:

- **A prefix**, defaulting to the server name, since that is exactly what `xcode__` and `drews__` already do.
- **Quirks**, as a named list per upstream. This is where `requires_app: "Xcode"` and the approval-dialog clicker go. **Keeping them per-upstream is the whole point**: today `require_xcode` is a positional boolean in the core parser, so every upstream is described in Xcode's terms whether or not it has anything to do with Xcode. As a quirk list, a template that wraps three servers gives the dialog handling to the one that needs it and the other two never inherit it.

**The format it replaces is not merely ugly, it is lossy.** Upstreams are configured today through one environment variable holding `name:require_xcode:command:arg1,arg2;name2:...`, parsed with `split(":", 3)`. A command path containing a colon runs into the argument field. An argument containing a comma splits into two arguments. There is no way to express an environment variable for a child process at all, which the Claude Code format has and which any real server eventually needs. Those are silent corruptions rather than errors, so the move to JSON fixes a defect and is not a matter of taste.

Everything else in the daemon is already generic and stays: the reconnect loop, the heartbeat that catches a dead upstream before a client does, the stall watchdog that exits so launchd restarts it, and tool-name prefixing with a real error for an unrecognised name.

## Build order, per Jonathan 2026-08-31

1. **Glue two MCPs together from a Claude-Code-shaped `mcp.json(c)` file.** Nothing else. The wrapper reads the file, connects the upstreams, prefixes and serves. This is the existing combined daemon with its positional environment-variable config replaced.
2. **Add the disallow list.**
3. **Add the name mapping.**

**Record the compatible upstream version in step one, not later.** Two Xcodes are installed on this machine right now — `Xcode.app` at 26.6, currently selected, and `Xcode-beta.app` at 27.0 — and the beta carries a lot that has not been tried. A wrapped server's tool list is a property of its version, so a config that names upstreams without recording which version was verified against them cannot tell "this tool is gone" from "you are pointed at a different Xcode." Both servers already supply what is needed: `initialize` returns `serverInfo`, giving `xcode-tools 24952` for Apple's bridge and `Xcode MCP Server 1.29.1` for Drew's.

### The comparison script

Built 2026-08-31, ahead of the rest, because the sieve and the map both need its output before they can be written: `tools/tool-templates/mcp_tools.py`.

`list` prints one server's tools with its version. `compare` puts two side by side and reports exact name collisions and the same-words-different-order kind — Jonathan's `window_open` against `open_window` — which is what string comparison can honestly find. `--summarize` hands both annotated lists to the default `llm` model for the pass string comparison cannot do: pairs that do the same job under unrelated names. Note that `llm` takes its prompt positionally; `-p` is the codex and qwen convention and means something else here.

It refuses two things on purpose, both learned the same day. A server that answers `initialize` and never answers `tools/list` is reported as a timeout with the approval dialog named as the likely cause, never as a server with zero tools. And `compare` refuses to run at all if either side failed to list, because a server whose tools are unknown shows up as having no overlaps, which reads as "no collisions" and is the opposite of what is known.

**A worthwhile extension: point it at the running daemon rather than at a fresh child.** The config shape already carries `url` for http upstreams. Comparing through the daemon's already-approved endpoint would sidestep the per-process approval entirely, so listing Apple's tools would stop raising a dialog at whoever is at the keyboard.

## The sieve: per-upstream tool filtering

Jonathan, 2026-08-31: each wrapped MCP gets a list of blocked tools that are not offered to the controlling LLM — which he calls the user throughout. Two distinct purposes, and they want different defaults.

**Coherence.** When two wrapped servers cover the same ground, the sieve decides which one does the job, so the user is not offered two ways to do one thing and made to choose. Note that prefixing has already removed any literal name clash — `xcode__` and `drews__` cannot collide — so this is about semantic overlap and choice paralysis, not namespace conflict.

**Limiting.** Sometimes a capability should simply not be available. His example: not wanting the user able to switch schemes. Block it.

### What the protocol already gives us

Verified against a live `mcpbridge` on 2026-08-31: `initialize` returns `serverInfo` carrying a name and a version — `{"name": "xcode-tools", "version": "24952"}` — so a sieve entry can be pinned to a version. It also advertises `capabilities.tools.listChanged: true`. **The protocol states outright that the tool list is a moving target and offers a notification when it moves.** A sieve that reads the list once at startup is therefore knowingly wrong; it should re-apply on `listChanged`.

### Three things that decide whether this works

**A deny-list fails open, and for the limiting purpose that is the wrong direction.** If a server adds a tool after the block-list was written, it is offered by default. For the coherence purpose that is fine and even desirable. For the limiting purpose it is a silent failure: the capability that was deliberately withheld reappears on an upstream update and nothing says so. So the sieve probably needs both forms — a deny-list for coherence and an allow-list for limiting — or a deny-list plus an explicit "anything not named here is new, tell me" mode. **This is a policy choice, not an implementation detail, and it is Jonathan's to make.**

**The sieve has to be applied at `tools/call`, not only at `tools/list`.** Filtering the listing alone hides a tool from discovery while leaving it callable by anyone who knows the name, and the controlling LLM knows names from its own context, from documentation, and from previous sessions. For the coherence purpose a listing filter is enough. For the limiting purpose a listing filter is decoration.

**Stale entries must surface rather than rot.** A blocked tool that the upstream no longer offers is a line that now protects nothing, and a version bump is exactly when that happens. The wrapper knows both the configured list and the live list, so it can say so. Silence here is how a sieve comes to look protective years after it stopped being.

### The tool map

Jonathan, same conversation: the same file also carries a **tool map**. Where the sieve subtracts, the map renames and redirects, and together they are the full control over the surface the user sees.

An entry maps an **exposed name** to an upstream and the tool's name on that upstream. That gives three things at once:

- **A canonical name across servers.** Two upstreams that both read a file can be presented as one `read_file`, with the map naming which upstream actually serves it. This is the ownership idea from the section below, made concrete — the map is where it gets expressed, so it need not be a separate mechanism.
- **A stable name over a moving upstream.** When a server renames a tool between versions, the map absorbs it and the user's vocabulary does not change. Without that, every upstream rename is a change to how the controlling LLM has learned to work.
- **A name that fits the surface rather than the vendor.** A mapped name is the final exposed name, so it need not carry the `xcode__` style prefix. The prefix is a good default for unmapped tools and a poor one for a curated surface.

Three things it has to get right:

**Translate back on the way in.** The map is applied to `tools/list` going out and must be reversed on `tools/call` coming in, or a renamed tool is advertised and then rejected as unknown. Same failure shape as applying the sieve to only one of the two.

**Renaming is for the coherence of the aggregate, and the new name need match neither upstream.** Jonathan's example: one server offers `window_open` and `window_close`, another offers `open_window` and `close_window`. Whichever implementation is chosen, the exposed name can be `close_current_window` — a name neither server uses, chosen because it reads correctly in the combined surface. The map is not a compatibility shim for one server's naming; it is where the surface gets its own vocabulary.

**The description travels with the name, and usually should not.** Tool descriptions are written by the upstream and mention the upstream's own tool names, so exposing `window_close` as `close_current_window` while keeping a description that says "use window_close to…" hands the model a contradiction between the name it can call and the name it is told to call. This needs two levels, per Jonathan: the ability to **extend or override** a description outright, and "at least" a mechanical **find-and-replace of references to our munged names**.

The mechanical pass is the one that scales. A curated surface renames many tools, and every description mentioning any renamed tool goes stale at the same moment — hand-editing each is how a surface drifts back into incoherence one upstream update at a time. So the rename table itself should drive the substitution across all descriptions automatically, with the explicit override reserved for what a substitution cannot fix, such as a description whose whole framing is wrong for the new name. A rename that leaves an un-substituted reference behind deserves a warning rather than silence, because that is precisely the state that misleads the model.

**A map entry naming a tool the upstream does not have is a hard error, not a skip.** It means the surface promised something that will fail on first use, and unlike a stale sieve entry — which merely stops protecting — a stale map entry actively breaks a call the user was told it could make.

### Expressing collisions as ownership rather than as blocks

For the coherence purpose, writing per-server deny-lists means that adding a third server that also covers the same ground requires editing every other server's list, and getting one wrong reintroduces the duplicate. Saying instead that a given capability is **owned** by one named upstream puts the decision in one place and makes a third server's arrival a single edit. Both shapes are expressible in the same file; this is a recommendation, not a decision.

## The config records decisions, never inventory

Jonathan, 2026-08-31: the jsonc file must not hold an exhaustive tool list. The script produces the full list on demand; the file keeps only what is filtered out and what is renamed, and nothing else.

This is the difference between a config that ages well and one that rots. An exhaustive list is a mirror of upstream state, so every upstream version bump makes it wrong and it has to be regenerated — and a regenerated file cannot be reviewed, because every line changed. An exceptions list changes only when a decision changes, so its diff is always meaningful and its size stays proportional to how much has been decided rather than to how many tools exist.

It also makes staleness auditable instead of invisible. Run the comparison script against the version recorded in the config, and every block or rename naming a tool the upstream no longer has is a decision that has quietly stopped applying. That audit is only possible because the file holds decisions; against an inventory it would be noise.

**Every block and every rename carries a reason, and the reason should be a field rather than a comment.** Jonathan's requirement is that each entry says WHY. That is the right requirement and it is the thing that rots first — without it, a later session cannot tell a block that still protects something from one that outlived its cause, and the safe-looking move is always to leave it, so the surface silently narrows forever.

The tension: he also asked for jsonc so we can comment, and a jsonc comment cannot be enforced or read back. Any parser discards it, so nothing can require it, nothing can grep it, and any tool that rewrites the file loses it. If the reason matters enough to be mandatory — and the argument above says it does — it has to be data: a required `why` string on every sieve and map entry, rejected at load time when missing or empty. Comments stay allowed for everything else, which is where they are genuinely better than a field, such as explaining a group of related entries or leaving a note about an upstream bug.

So: `why` required and enforced; jsonc comments permitted alongside it. That keeps his intent, which is that no entry exists without a stated cause, and makes it survive a machine reading the file.

## Repo override of the sieve and the map, and what the two files actually mean

The sieve and the map are template output, so they get the mogenerator treatment like everything else. On install a template writes `_mcp_info.json`, machine-owned and overwritten on every update, and the repo owns `mcp_info.json` beside it, which no machine action ever writes. Jonathan raised `_mcp_info_machine.json` / `_mcp_info_human.json` as an alternative: it says out loud what the underscore only implies, which helps a newcomer, at the cost of breaking the mogenerator analogy that makes the whole convention memorable. The underscore pair is the recommendation, weakly held.

**The merge semantics are the hard part, not the file names.** In mogenerator the override is a subclass, so "override" has one obvious meaning: a method replaces a method. JSON has no such rule, and the sieve makes the ambiguity concrete. If the template blocks four tools and the repo also wants three blocked, the human file adds to the machine list. If the template blocks a tool the repo actually needs, the human file must remove an entry the machine file asserts. Those are opposite operations and a deep merge cannot tell them apart from the values alone.

So the human file should carry **verbs rather than values** — block and unblock, map and unmap, override-description — and the effective configuration is the machine file with the human file's operations applied in order. That has three properties worth having: a repo can undo a template decision without editing generated output, a template update cannot silently reinstate something the repo removed, and the human file reads as a list of deliberate departures, which is the thing someone actually wants to see six months later.

It also gives the installer something to check. A human `unblock` naming a tool the template no longer blocks, or a `map` for a tool that no longer exists, is a departure that has quietly become a no-op — exactly the staleness the sieve and map sections already say must surface rather than rot.

**On jsonc.** The human file is where someone records *why* a tool is blocked, and that reason is the first thing lost without comments, so comments belong there. Two costs to weigh. Standard tooling does not read it: `jq` fails on comments, and Python's `json` module fails on them, which matters here because the house rule is to reach for `jq` on JSON rather than write Python for it. And Claude Code's own `.mcp.json`, whose shape this format deliberately borrows, is strict JSON — so a jsonc human file could no longer be copy-pasted into it, which was one of the stated reasons for borrowing the shape.

A middle position keeps both: the machine file stays strict JSON, since it is generated and its provenance header can be a normal string field, and only the human file allows comments. Whoever implements it then needs a comment-tolerant parser on exactly one path, and every existing tool still works on the generated file.

## Open questions Jonathan left open on purpose

- **How to compose the Mac set.** Three candidate shapes: wrap all three servers behind one front; wrap the two already wrapped together and then wrap that wrapper alongside `MacControlMCP.app`; or wrap the existing two and let `MacControlMCP.app` stand separately. Nothing decided.
- **Overlap when two templates are installed.** Mac and iOS both pull in Swift. Whether that de-duplicates, or errors, or last-one-wins, is unspecified.
- **Where a template's identity lives** — a manifest file, a directory convention, or both — and whether a repo records which templates it has installed and at what version, which it probably must in order for an update to know what to rewrite.

## Two naming details to confirm before building

Jonathan referred to "Andrew's thing" alongside Apple's, and separately to "Andrew's swift stuff". The MCP server actually running in `xcode-combined-front` today is **Drew's** (`drews-xcode-mcp`, prefixed `drews__`). Whether "Andrew" and "Drew" are the same tool, the same person, or two different things is not established here, and Andrew Benson is a client contact rather than a tool author, so this needs one sentence from him rather than a guess.

He also listed **"ponytail"** among Swift tools to include, next to swiftlint and the dead-code and duplicate-code detectors. That name is not confirmed against a real tool. Do not guess at it — ask.
