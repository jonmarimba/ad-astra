---
name: asd-ste100
description: Write like ASD-STE100 Simplified Technical English. Apply this skill to any prose that a human will read, especially client-facing documents, emails, and technical descriptions. Enforces complete sentences, active voice, concrete language, and the three-question gate.
license: APACHE
metadata:
  author: Jonathan Saggau
  version: "1.0"
  ref: https://www.asd-ste100.org/STE_faq.html
---

# ASD-STE100 Simplified Technical English

ASD-STE100 is a controlled language written by the aerospace industry for readers who work in a second language. Jonathan adopted it after spending half an hour rewriting a client document by hand. His words: "I'd rather make simple words more elegant than gibberish into coherence any day."

## The three questions (ask in order, stop at the first no)

1. Does this need to be said?
2. Does this need to be said by me?
3. Does this need to be said by me right now?

The second and third are about position and timing, not modesty. Saying a true thing at the wrong moment is a different mistake from saying a false one. Question one kills the summary nobody asked for. Question two kills narrating your own process. Question three kills the caveat that belongs in the follow-up, not in the document asking someone to act.

## Sentence rules

- Keep sentences near 20 words in instructions and 25 in description.
- Use the active voice for anything the reader must do.
- Give one idea per sentence.
- Use ordinary words, each in a single sense.
- Never drop the subject, the verb, or the article to shorten a sentence. A fragment is not concise. It is ambiguous, and the reader has to rebuild the missing half before judging whether it is even correct.

## Document rules

- Never write a sentence about the document itself. "Three asks and one question" and "Criteria rather than a list" are banned shapes.
- Never tell the reader to notice something.
- Use a table only for several rows of genuinely similar facts. Never mix kinds in one table, because a column heading true for two rows will mislead on the third.
- Put every number inside a sentence that says what it means.

## Banned vocabulary

These words are LLM tells. Use the concrete consequence instead.

matters, crucial, pivotal, delve, tapestry, testament, "it's worth noting," "that said," "at the end of the day," "not just X but Y," footgun, leverage, robust, seamless, honest/honestly/to be honest, "not gonna lie"

## Formatting

- Never hard-wrap markdown. One paragraph per line. Let the editor soft-wrap.
- Real newlines only for genuine paragraph breaks, list items, and headings.

## Pre-send check

Read every sentence aloud. If a sentence requires a second pass to understand, split it or rewrite it. If a paragraph opens with a label followed by a fragment, rewrite it as a complete sentence. If a heading names the writer's speech act ("Summary of findings") instead of the subject ("Findings"), rename it.

## Mechanical enforcement

Run `.astra/check-prose/check-prose.js <file>` over the draft. It flags sentences over 25 words, banned vocabulary, bold-label fragments, hard-wrapped paragraphs, and speech-act headings. It exits non-zero when it flags anything.

The rules live beside it in `.astra/check-prose/rules.json` and are data, not code. Add a word there rather than editing the checker. A repo may extend the rules without forking them by adding `.check-prose.json` at its root. If the checker is not present, the repo does not have the tool installed — install it from astra rather than writing a local copy, because a local copy is exactly the drift this arrangement exists to end.
