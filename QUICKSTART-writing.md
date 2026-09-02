# Quickstart: the writing template

This guide describes the prose-improvement stack: what the `writing` template installs and what each piece does. The general template mechanics are in QUICKSTART.md. Written 2026-09-02 by Claude (Fable), reviewed against the live installers and skill files.

## Install

```
cd js-db-ad-astra/tools/lib
python3 template.py install writing --into ~/path/to/YourRepo
```

Every kind template (`swift-ios`, `mac-swift`, `legal-pdf`) already includes `writing` through `base`, so run this only for a repo that gets no kind template. Re-running the same command is the update path. Restart your agent session afterward, because skills are read at session start.

## What lands where

The skills land in `.claude/skills/`. The mechanical checker lands in `.astra/check-prose/`. The doctrine lands in `.doctrine/writing.md`, and marked import blocks in `CLAUDE.md` and `AGENTS.md` load it into every session.

## The pieces

The **prose** skill is the orchestrator and the entry point. It runs the other skills in the one order that works: `asd-ste100` first for structure, `humanizer` second for voice, then a mechanical pre-Grammarly cleanup. It also settles the conflicts between them. The STE sentence ceiling beats any advice to combine sentences for flow. The humanizer may vary rhythm only inside that ceiling. Fragments are banned outright, and the banned-vocabulary list outranks everything. Ask your agent to run the `prose` skill over any draft a person will read.

The **asd-ste100** skill is sentence mechanics, modeled on the aerospace Simplified Technical English standard for readers working in a second language. Complete sentences, active voice, one idea per sentence, roughly 20 words in instructions and 25 in description. It also carries the three-question gate. Ask the questions in order and stop at the first no. Does this need to be said? Does it need to be said by me? Does it need to be said right now? Each question kills a different failure. The first kills the summary nobody asked for. The second kills narrating your own process. The third kills the caveat that belongs in the follow-up, not in the document that asks someone to act.

The **humanizer** skill removes AI tells and then adds a specific person's voice. The tell-removal layer is the upstream `blader/humanizer` skill, pulled fresh from GitHub at install time, working from the signs of AI writing that Wikipedia catalogues. The voice layer calibrates the draft against Jonathan's register files: attorney, business-client, or casual. The result sounds like him rather than a de-slopped nobody. Those files live in the `js-project-GhOST` checkout; on a machine without it, only the tell-removal layer applies.

The **check-prose** tool is the mechanical gate. `node .astra/check-prose/check-prose.js <file>` flags banned words and phrases, candor disclaimers, label-plus-fragment shapes, sentences about the document itself, and sentences past 25 words. It exits nonzero on any finding, so it works in scripts and hooks. The rules are data in `rules.json` beside the script, and a repo extends them without forking by adding `.check-prose.json` at its root.

The **grammarly-pass** skill drives a real browser (claude-in-chrome or the Safari MCP) through Grammarly's web editor with a finished draft. It accepts mechanical corrections, rejects voice-flattening rewrites, never touches quoted material, and leaves judgement calls unapplied but reported. It needs a browser that is already signed in to Grammarly, and it stops at any login wall. It is the newest piece of the stack and has not yet had a live run.

The **writing-doctrine** tool installs `.doctrine/writing.md`, the rules that sit above the sentence. Those rules cover what belongs in a client email and why the action goes first while corrections wait. They also cover how to ask a paid expert for a decision. And the doctrine carries the standing order that makes the rest of the stack fire: run the tools before any prose reaches a human. A model's opinion of its own prose is not evidence.

## Day to day

Draft the document. Ask the agent to run the `prose` skill over it. Run `node .astra/check-prose/check-prose.js <file>` and fix what it flags. Only then let a human see the result.
