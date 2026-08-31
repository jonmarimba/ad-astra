# Colloquium: find the holes in this design, then give us an incremental TDD roadmap

You are one of several models, from different vendors, reviewing the same design independently. Do not be agreeable. The value you add is the hole nobody else spotted and the question nobody thought to ask.

## Read these first — they are real files on this machine, go and read them

- `~/svnCheckouts/js-db-ad-astra/tools/tool-templates/SPEC.md` — the design under review, dictated by the owner (Jonathan) over this morning.
- `~/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/daemon.py` — the hard-coded aggregator that exists TODAY and works. Step one is to generalise exactly this.
- `~/svnCheckouts/js-db-ad-astra/tools/xcode-mcp-front/README.md`
- `~/svnCheckouts/js-db-ad-astra/tools/tests/test-xcode-mcp-front.sh` and `lib.sh` — the current test style, including its `red`/`need` helpers.
- `~/svnCheckouts/js-db-ad-astra/tools/tool-templates/mcp_tools.py` — a tool-listing and collision-comparison script built this morning.
- `~/svnCheckouts/js-db-ad-astra/tools/convocation/install.sh` and any `Brewfile` under `tools/*/` — the existing shape of an "ad astra tool", which we want to make consistent.

## What exists today, verified this morning — do not re-derive it

The combined daemon fronts two MCP servers behind one HTTP endpoint, prefixing their tools `xcode__` and `drews__`. Upstream one is Apple's `xcrun mcpbridge` (`serverInfo`: `xcode-tools` / `24952`), upstream two is Drew's `uvx drews-xcode-mcp` (`Xcode MCP Server` / `1.29.1`, 29 tools). Apple's exposes 21 tools on Xcode 26.6.

Facts established today by direct measurement, which the design leans on:

- Xcode's MCP approval prompt is bound to the **live connecting process**. Kill the client and the prompt withdraws. A reconnect loop therefore cancels its own approval request.
- Xcode's dialogs do **not** stack, so one unanswered prompt blocks every prompt behind it.
- `initialize` returns `serverInfo` with name and version, and `capabilities.tools.listChanged: true`, so the tool list is explicitly a moving target with a change notification.
- Tool lists are mostly additive across Xcode versions but not always: 26.4.1→26.5 added one tool and removed none; 26.5→26.6 **renamed** one (`ExecuteSnippet` → `RunCodeSnippet`) with the count unchanged at 21.
- Two front daemons deadlocked because a foreign-dialog grace period (45s) exceeded the connect timeout (15s). Fixed; the relationship is now asserted at startup.

## The owner's constraints, in his words where it matters

**Build order.** First, a generic aggregator driven by a Claude-Code-shaped `mcp.json(c)` file that reproduces what the hard-coded one does for Drew + Apple. Then the disallow list ("sieve"). Then the name mapping. Then the wider template system.

**Templates.** Composable — an Xcode template, a Swift template, a Mac template; Mac+Swift is those as members; iOS is Swift plus simulator control. A repo installs the top-level one, may install two that overlap, and can extend and override.

**mogenerator split.** `_mcp_info.json` is machine-owned and overwritten on every template update; `mcp_info.json` is the repo's and never written by a machine.

**The config records decisions, never inventory.** No exhaustive tool list in the file — only what is filtered and what is renamed, and every entry must say WHY.

**Version handling warns, never refuses.** "I don't want to die in a fire if the mcp version changes." Warn the controlling LLM in-band, and warn the human via a dialog from the wrapper's own `.app`. On a new version, *suggest* running the collision tool rather than auto-running it.

**Ad astra tool consistency.** Make the format of an ad astra tool consistent enough to work "kind of like a package manager / dependency manager", so third-party tools and skills can be described and adopted **without making them submodules**. Homebrew is the sanctioned dependency mechanism; Brewfiles already live beside install scripts.

**Testing — these are hard requirements, not preferences.**

> "I don't want tautological tests, EVER. If the test just describes the code, it's not a test. Our tests need to test the user-facing BEHAVIOR of the system. Any test that doesn't contribute to that picture is a waste of time."

> "Tests themselves must be FAST. I'm not spending more than 15 seconds watching basic sanity tests go by. Any longer tests ... can be placed in a sort of 'if you want to fully validate, these tests take longer, but are more complete' kind of pile."

So: a **fast sanity tier** with good coverage, total runtime under fifteen seconds, and a **slower deeper tier** for edges — still not slow. TDD is the rule of the day, in small increments. Time to completion does not matter; quality does.

## What to produce

Be concrete and cite file paths and line numbers where you can. Structure your answer exactly as:

**1. HOLES.** Specific defects, contradictions, or unstated assumptions in `SPEC.md` or in the plan. For each: what breaks, under what conditions, and what you would change. Prioritise ones that would only be discovered late.

**2. QUESTIONS FOR THE OWNER.** Things genuinely undecidable without him. Keep this short and high-value; do not pad it with things you could decide yourself.

**3. ROADMAP.** An ordered list of small increments from today's hard-coded aggregator to the full template system. For each increment state the user-facing behaviour it delivers, the test that proves it, and how that test could FAIL. An increment whose test cannot fail is not an increment.

**4. TEST ARCHITECTURE.** How to split fast-sanity from slow-deep for this specific system, given that some behaviour depends on a running Xcode and a GUI approval dialog. Name what belongs in each tier and how the fast tier stays under fifteen seconds while still testing user-facing behaviour rather than internals. Say explicitly which parts CANNOT be tested quickly and what the honest substitute is.

**5. THE AD ASTRA TOOL FORMAT.** A concrete proposal for describing a tool or skill — including a third-party one adopted without a submodule — covering identity, version, dependencies (Homebrew), install, uninstall, doctrine, and tests. Say how a repo declares which tools it wants and how an update is applied.

Judge harshly. If part of this design is wrong, say so plainly and say what to do instead.
