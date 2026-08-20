---
name: humanizer
description: Rewrite machine-written text so it reads like a specific person wrote it. Combines AI-tell removal (the 33 Wikipedia patterns) with voice calibration from Jonathan's register files. Use this skill on any draft that will go out under his name.
license: APACHE
metadata:
  author: Jonathan Saggau
  version: "1.0"
  upstream: https://github.com/blader/humanizer
---

# Humanizer

This skill rewrites machine-written text into something a person would write. It has two layers: removing AI tells, and adding a specific person's voice.

## Layer 1: AI-tell removal

The upstream skill at `github.com/blader/humanizer` works from the 33 patterns listed on Wikipedia's "Signs of AI writing" page. It carries an audit pass and a rule against inventing facts or citations the source text does not contain.

The upstream is installed per-repo by running `install.sh` in this directory, which calls `npx skills add blader/humanizer` inside the target repo. Re-run the installer anytime to pull updates from the external source. The upstream is a prompt-only Markdown file with no executable code, no network calls, and no data sent externally. Text stays inside the session.

Jonathan's standing rule: a pass over live client-facing content changes voice only, and he reviews the diff before anything ships.

## Layer 2: Voice calibration

De-slopping alone produces generic prose that "sounds like nobody." Voice calibration adds the person.

Voice register files live at `js-project-GhOST/reference/voice/`. Each file is grounded in Jonathan's actual sent mail and texts. Pick the register that fits the recipient:

- `attorney.md` — for Jake and legal correspondence
- `business-friendly-client.md` — for Maharam, Nicole, Agat, David
- `casual-contractor-and-text.md` — for Dan, iMessage, informal exchanges

### How to use voice files when drafting

1. Pick the register file that fits the recipient.
2. Draft in that voice from the start. Do not write generic prose and humanize after. That path lands on nobody's voice. Start Jonathan.
3. Read the draft against the register's opener menu, sign-off menu, and vocabulary. If it opens "Dear Jake, I hope this email finds you well" or closes "Best regards," it has failed. He never writes that.

### Cross-register DNA (true in every register)

- Signature: `++js; // Jonathan` (C increment operator plus a code comment). Also `--j;`, `++js;` bare, or just `J`.
- He uses em-dashes, semicolons, and italics-for-emphasis naturally. The blanket "strip em-dashes" humanizer rule was actively de-Jonathan-ing him. His em-dashes stay.
- Metaphor is how he argues. Reach for the figure, not the abstraction.
- Folksy-Southern affect over precise substance. "Howdy," "y'all," "a fella," contractions. Underneath the drawl the content is exact. Never sand off the drawl to sound professional, and never dumb down the substance to match the drawl.
- Direct imperatives when he has decided. "Send it!" Short. No hedging once the call is made.
- Honest about his own process, including LLM use. He discloses the seams rather than faking polish.

## What this skill does NOT do

- It does not check sentence length or fragment structure. Use the `asd-ste100` skill for that.
- It does not verify facts. It can change meaning. The diff must be reviewed.
- It does not replace Jonathan's editorial judgment. It is a first pass, not a final one.

## Open items

1. Nothing wires the voice register files to the upstream humanizer plugin. A humanizer pass that reads the register before it rewrites would produce his voice rather than a generic de-slopped one.
