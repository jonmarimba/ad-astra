# Questions for Jonathan — tool templates

From the three-brand colloquium, 2026-08-31. Deduplicated: where all three panelists asked the same thing, it appears once. Each has a recommendation so you can agree or override rather than compose an answer. Ordered by what they block.

---

## 1. Sieve direction — deny-list, allow-list, or both?

All three brands raised this, and it is the one you already flagged as yours.

A **deny-list fails open**: an upstream adds a tool and it appears. That is right for the coherence purpose and wrong for the limiting purpose, because the capability you deliberately withheld comes back on an upstream update and nothing says so.

An **allow-list fails closed**: safe for limiting, and it needs maintenance every time an upstream adds something useful.

**Recommendation:** both, chosen per upstream. Deny for coherence, allow for limiting. Build the deny-list first with a "these tools are new since you last looked" report, because that is useful on its own and the allow-list is a small addition on top.

**Blocks:** Phase 2 entirely.

---

## 2. Is "Andrew's Swift stuff" the same as Drew's Xcode MCP? And what is "ponytail"?

All three asked. One sentence each unblocks the Swift template.

What is actually running today is `uvx drews-xcode-mcp`, reporting itself as `Xcode MCP Server 1.29.1`. You have referred to "Andrew's thing" and "Andrew's Swift stuff" — possibly the same package, possibly a second one I have never seen.

**"Ponytail"** does not match a Swift tool I can verify. Nearest real things are `periphery` (dead code) and `swiftlint`, both of which you named separately, so it is probably neither.

**Blocks:** the Swift template's contents. Nothing else.

---

## 3. One surface per repo, or one surface for the machine?

Claude and Codex independently reached the same answer, which is worth something.

Today the daemon is one machine-global launchd job on one port. Templates install per repo. Two repos wanting different sieves cannot both be served, and you would not discover it until the second repo — the first symptom is a repo seeing another repo's renames.

**Recommendation:** one broker, one approved Xcode PID, one port, with a named profile per surface (`/mcp/swift-ios`, `/mcp/legal`). Each repo's `.mcp.json` points at its own path. This keeps the single-approval property that justifies the daemon existing, and it dissolves the multi-daemon approval ceiling, because that ceiling counts **processes**, not surfaces.

**Blocks:** Phase 5, but it shapes Phase 1, so it is worth deciding early.

---

## 4. May a repo's `mcp_info.json` add an upstream, or only filter and rename?

This is the line between configuration and arbitrary code execution, and it was not in the original design.

Every `command` in a config is executed inside a long-lived user process. If a repo's human-owned file may introduce a new upstream, then checking out a repository and starting the broker runs whatever that file names.

**Recommendation:** no. A repo may block, unblock, rename and override descriptions on upstreams the template chose. Adding an upstream is a template-level change, made in astra, reviewed there.

**Blocks:** the loader in Phase 1.1 — it needs to know which verbs are legal in the human file.

---

## 5. Does "lean on Homebrew" mean Homebrew installs everything?

Codex raised it and the repo already answers it in practice: `convocation` installs two npm globals and its Brewfile has a comment warning against faking brew lines for them; `ambrosio`, `pdf-sidecars` and `graphify-repo` install `uv` tools; `xcode-mcp-front` needs an Automator `.app`, a launchd plist, and TCC grants that a human clicks.

**Recommendation:** Homebrew for runtimes and system binaries, declared per-ecosystem for the rest — npm, uv, and a fourth category for "a human must grant this in System Settings", which is real here and which a brew-only model would silently under-declare.

**Blocks:** the tool descriptor schema, Phase 6.

---

## 6. When an upstream rename invalidates a map entry, what happens?

Two rules in the spec collide, and an upstream rename triggers both: "a version mismatch warns, never refuses" against "a map entry naming a missing tool is a hard error."

**Recommendation:** drop the invalid alias, keep serving everything else, and report it both in-band to the model and once to you. Refusing to start would let an Xcode update take the whole surface down.

**Blocks:** Phase 3.3.

---

## 7. Is Xcode 27 in scope, and do you want its components installed?

Measuring the beta's tool list needs its system-wide components installed, which is an administrative change I will not make on your behalf. I launched it, it showed "Install Required", and I quit it.

Worth knowing: 26.5 → 26.6 was **not** additive — `ExecuteSnippet` became `RunCodeSnippet` — so a major-version jump is worth measuring rather than assuming.

**Blocks:** nothing. It gives the version-mismatch path a second real data point instead of one.

---

## Already decided in code — confirm rather than answer

Two of the three "open questions" in my spec turned out to be answered already, and I had not read the existing system before writing it down.

**Template overlap** de-duplicates. `template.py` tracks claims and keeps a shared tool until its last claimant is removed. Two panelists asked what the rule should be; the repo already has one, and it is the sensible one.

**Installed templates are recorded** in `.astra/manifest.json`. Only the *version* half of that question is genuinely open — the manifest records names, not a resolved member graph with versions and digests, so an uninstall after a template's membership changes reasons from the wrong graph.
