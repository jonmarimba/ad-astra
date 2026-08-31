# Driver prompt — paste this to start the implementation

Suggested model: **Fable**, in Claude Code. Reasoning at the bottom.

---

You are implementing the tool-template system in `~/svnCheckouts/js-db-ad-astra`. Work on a branch named `tool-templates`. Commit after every increment, never per phase.

## Read these first, in this order, before writing anything

1. `tools/tool-templates/INVENTORY.md` — what already exists. **Read this first and take it seriously.** The specification for this project was written three times against things that were already built: a template system, a tool descriptor format, and a code-quality toolchain. Each time the author had to point it out. Your first instinct on any "we need X" should be to search for X.
2. `tools/tool-templates/ROADMAP.md` — the ordered increments, and Jonathan's answers, which override the colloquium panel wherever they differ.
3. `tools/tool-templates/QUESTIONS.md` — his answers in his own words, inline under each question.
4. `tools/tool-templates/SPEC.md` — the design. It has been corrected several times; where it disagrees with the roadmap, the roadmap is newer.
5. `tools/tool-templates/colloquium/` — three independent reviews, from Claude, Codex and GLM. Their findings are leads, not sources. Several are wrong. Verify before acting on any of them.

Then read the code you are changing: `tools/xcode-mcp-front/daemon.py`, `tools/lib/template.py`, `tools/lib/templates.json`, `tools/mcp-bundle/`, and `tools/tests/lib.sh`.

## The rules that are not negotiable

**No tautological tests. Ever.** Jonathan: *"If the test just describes the code, it's not a test. Our tests need to test the user-facing BEHAVIOR of the system. Any test that doesn't contribute to that picture is a waste of time."* Every test asserts an effect a user could observe — a tool appears in a listing, a call routes to the right server, a config is rejected with a specific message. Never that a function was called.

**Every test must be able to fail, and you must have watched it fail.** Write the test, run it against the unfixed code, see red, then fix. If you cannot make a test fail, you have not written a test. Note that `red()` in `tools/tests/lib.sh` is itself broken — it discards output and accepts almost any nonzero exit, so it passes when a command fails for a missing file or a typo'd flag. Fixing it is increment 0.1 and everything after depends on it.

**Two test tiers.** A fast sanity tier that runs in **under fifteen seconds total** with good coverage, and a slower tier for edges — still not slow. Jonathan will not watch more than fifteen seconds of basic tests. Assert the time budget inside the fast tier so it fails when it grows, rather than trusting anyone's stopwatch. Anything needing a running Xcode or a GUI approval dialog belongs in the slow tier by definition.

**Small increments.** Time is not the constraint; correctness is. An increment that cannot be described in one sentence is two increments.

## How to work

**Use subagents for work that does not need your judgement** — reading files to answer a specific question, running a suite and reporting failures, drafting a fixture, checking whether a claim about the code is true. Keep your own attention for design decisions and for the moments where a wrong call is expensive. The Agent tool takes a per-subagent model override; use a cheaper model for mechanical work.

**Run a convocation at the end of Phase 1, Phase 3 and Phase 5.** The dispatcher is `~/svnCheckouts/js-db-ad-astra/tools/convocation/panel TASK.md --out DIR --agents claude,codex,qwen`. Read `.doctrine/convocation.md` first — search convoq before firing, and mix brands, because a same-brand panel is an echo chamber. Those three points are where a wrong decision becomes expensive to reverse.

**When you find that the design is wrong, say so and fix the design.** Several sections of `SPEC.md` were written before the author read the existing code, and they are marked where known. Assume more of that remains.

## Where to start

Phase 0.1 — fix `red()` so a RED control proves the failure reason, not merely that something failed. Then 0.2, splitting the suites. Then Phase 1.

## Things that will bite you, from the record

- Xcode's MCP approval prompt is bound to the **live connecting process**; killing the client withdraws the prompt. A reconnect loop can cancel its own approval request, which reads exactly like the server refusing to serve tools. This cost a full night on 2026-08-30.
- Xcode's dialogs **do not stack**. One unanswered prompt blocks every prompt behind it.
- `python3` in a login shell on this machine is `/usr/bin/python3`, which is **3.9.6**, while an interactive prompt may give you Homebrew's 3.14. Scheduled jobs get the former. `datetime.fromisoformat` rejects a `Z` suffix before 3.11.
- Jonathan's tests must never terminate or click through his applications to fix their own preconditions. Detect a bad state, say what a human should do, and refuse to produce a verdict.

---

## Why Fable

The deciding factor is delegation rather than raw capability. The Agent tool takes a per-subagent model override, which is exactly the "use subagents for work its genius is not necessary for" instruction — a driver that hands mechanical work to a cheaper model and keeps itself for judgement. It inherits the repo doctrine automatically through `CLAUDE.md` and `.doctrine/`, and `panel` is a shell tool so convocations work regardless of who is driving.

**Not Sol**, and for a principled reason rather than a preference: Sol is `gpt-5.6-sol`, already the Codex voice in every convocation on this machine. Making it the driver collapses one of three independent review brands into the thing being reviewed, which is what the mix-brands rule exists to prevent. It is worth more as the adversary.

**Not GLM** — the qwen-route voice, and the lightest of the three.

**Marked assumption:** I have not watched Fable on a long implementation run, so "it sustains a multi-day TDD loop" is untested. Cheap check: give it Phase 0 and Phase 1 alone, then look at whether the tests it wrote can actually fail before handing it the rest.
