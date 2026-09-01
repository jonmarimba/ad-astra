---
name: grammarly-pass
description: Drive a real browser through Grammarly's web editor with a draft, and accept or reject its suggestions the way Jonathan would. Use when asked to run a draft through Grammarly, or as the automated final step after the prose skill. Works with whichever browser MCP the session has (claude-in-chrome or safari-mcp-stp).
license: APACHE
metadata:
  author: Jonathan Saggau
---

# The Grammarly pass, automated

Push a finished draft through the real Grammarly web editor and triage its suggestions by Jonathan's standing rules. This automates the pass he historically did by hand; he still owns the final read, and any suggestion this skill is unsure about stays UNAPPLIED and gets reported instead.

## Preconditions

- The draft is DONE: asd-ste100 structure, humanizer voice, and the pre-Grammarly mechanical pass (prose skill) have already run. Grammarly is the last polish, not the editor.
- A browser MCP is in the session: claude-in-chrome (tabs, find, form_input, read_page) or safari-mcp-stp (navigate, content, and its interaction tools). Use whichever is present.
- The browser is already signed in to Grammarly. If a login wall appears, STOP and tell Jonathan to sign in - never touch credentials.
- Only push text that is headed for Grammarly anyway (drafts for email, client docs). It is an external service; that is Jonathan's established flow for this material, not a new exposure.

## Flow

1. Open app.grammarly.com, create a new document, paste the draft. Wait for analysis to finish (the suggestion count stops moving).
2. Walk the suggestion cards one at a time. Read each card's category, the flagged text, and the proposed replacement.
3. Decide per the rules below: accept, dismiss, or leave-and-report.
4. When done, extract the final document text and return it VERBATIM, plus the report.
5. Leave the Grammarly doc in place (his account, his history); do not delete it.

## Decision rules

**Accept - mechanical correctness.** Spelling and typos. Subject-verb agreement. Comma splices. Missing or doubled punctuation. Repeated words. Apostrophe placement. Wrong homophone where context is unambiguous. These are the classes the pre-Grammarly pass targets; Grammarly catching a leftover means the pass missed one - accept it and say so.

**Reject - voice flattening.** Everything Jonathan overrides every time, per the prose doctrine: removing contractions. "Sound more formal / confident / friendly" tone rewrites. Word-choice swaps sold as engagement or variety. Deleting a sentence-initial "And" or "But". Softening profanity. Hedge insertions. Any full-sentence rewrite (including anything from Grammarly's generative features - mechanical suggestions only, never the AI rewrites). Any replacement whose text lands on the banned-phrases list (js-project-GhOST/policy/banned-phrases.txt) - a smoother phrasing that lands on that list is worse than the original.

**Reject unconditionally - quoted material.** If the flagged span is inside quotation marks or a quoted block (an email being cited, a text message, a court document, a contractor's words), dismiss without consideration. Quotes are evidence; fixing someone's grammar inside a quotation is falsifying it.

**Leave and report - judgement calls.** Conciseness trims and clarity rewrites that do not change meaning but do change rhythm. Do not apply these; list them in the report with Grammarly's proposal so Jonathan can take the ones he likes in his own read.

## Reporting

One line per class, per the pre-Grammarly convention: "accepted N spelling, N punctuation; rejected N tone rewrites, N contraction removals; left N judgement calls (listed)." If Grammarly had nothing, say that - silence reads as "not run." Return the final text as one unwrapped paragraph per real paragraph (never hard-wrapped).
