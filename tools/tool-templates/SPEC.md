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

## Open questions Jonathan left open on purpose

- **How to compose the Mac set.** Three candidate shapes: wrap all three servers behind one front; wrap the two already wrapped together and then wrap that wrapper alongside `MacControlMCP.app`; or wrap the existing two and let `MacControlMCP.app` stand separately. Nothing decided.
- **Overlap when two templates are installed.** Mac and iOS both pull in Swift. Whether that de-duplicates, or errors, or last-one-wins, is unspecified.
- **Where a template's identity lives** — a manifest file, a directory convention, or both — and whether a repo records which templates it has installed and at what version, which it probably must in order for an update to know what to rewrite.

## Two naming details to confirm before building

Jonathan referred to "Andrew's thing" alongside Apple's, and separately to "Andrew's swift stuff". The MCP server actually running in `xcode-combined-front` today is **Drew's** (`drews-xcode-mcp`, prefixed `drews__`). Whether "Andrew" and "Drew" are the same tool, the same person, or two different things is not established here, and Andrew Benson is a client contact rather than a tool author, so this needs one sentence from him rather than a guess.

He also listed **"ponytail"** among Swift tools to include, next to swiftlint and the dead-code and duplicate-code detectors. That name is not confirmed against a real tool. Do not guess at it — ask.
