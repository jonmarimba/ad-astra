---
name: prose
description: Run the three writing skills in the one order that works, and settle the conflicts between them. Use on any draft a person will read — client email, attorney correspondence, a note going out under Jonathan's name. Composes asd-ste100, humanizer, and a pre-Grammarly pass.
license: APACHE
metadata:
  author: Jonathan Saggau
  version: "1.0"
  composes: asd-ste100, humanizer, grammarly-prep
---

# Prose

Three skills touch the same sentences and they disagree. Run alone, each one undoes part of another's work. This skill is the order and the tie-break.

Jonathan's ask, 2026-08-27: *"I want Grammarly alongside our humanizer and the skill that is for tech writing for ESL users. I'd like these skills combinable."*

## What Grammarly is here, and what it is not

**Grammarly is not a skill and cannot be one.** He edits in Grammarly himself — that is the last step before a draft is pasted into email, and it happens in his hands, not the agent's. The only "grammarly" package on the skills registry (`membranedev/application-skills@grammarly`) is a Membrane API connector for reading Grammarly *account data*; it requires a Membrane account, touches the network, and checks no prose at all. Installing it would satisfy the letter of the request and none of its purpose.

What an agent can do is a **pre-Grammarly pass**: leave behind a draft that Grammarly has little to say about, so his editing pass is about judgement rather than mechanics. Concretely, that means fixing the things Grammarly reliably flags — passive voice where an actor exists, sentences past about 25 words, comma splices, dangling modifiers, "there is/there are" openings, and noun stacks — before he ever opens it.

## The order

**1. asd-ste100 first.** It decides sentence structure: complete sentences, one idea each, active voice, roughly 20 words in instructions and 25 in description, ordinary words in a single sense. Structure has to be settled before anything works on rhythm, because fixing a fragment changes the sentence that surrounds it.

**2. humanizer second.** It removes AI tells and calibrates register against the voice files. This must come after structure, because the tells live in phrasing — and rewriting a fragment into a sentence often introduces one.

**3. The pre-Grammarly pass last.** Mechanical cleanup only. It runs last because the first two rewrite whole sentences, and there is no point resolving a comma splice in a clause that is about to be replaced.

## Where they conflict, and who wins

**Sentence length: ASD-STE100 wins.** Grammarly's readability advice sometimes wants sentences combined for flow. STE's ceiling holds. He adopted it after rewriting a client document by hand, and short-and-plain is the point.

**Rhythm: humanizer wins over STE, in one direction only.** STE pushed to its limit produces uniform, mechanical sentences. The humanizer may vary rhythm and length *within* the STE ceiling. It may never restore a fragment, a dropped subject, or an em-dash appositive to get there.

**Fragments: nobody wins, they are banned.** "A fragment is not concise, it is ambiguous." No skill may produce one, whatever it buys.

**Banned vocabulary outranks all three.** The authority is `policy/banned-phrases.txt` in the GhOST repo, enforced by `tools/check-banned-phrases.sh` beside it. **Those paths are repo-relative to js-project-GhOST, not to wherever this skill is installed** — resolve them from that checkout, and if it is not present on the machine, say the check could not run rather than assuming the draft is clean. A skill that silently skips its own highest-priority rule is worse than one that never claimed it. If a suggested phrase is on that list, the list wins, silently.

**Passive voice: STE wins, with an exception.** STE wants the active voice for anything the reader must do. Where the actor is genuinely unknown or deliberately unnamed — which happens constantly in the legal drafts — the passive stays and Grammarly's flag is ignored.

## What none of them may do

Write a sentence about the document itself. "Three asks and one question" and "Criteria rather than a list" are both banned shapes. Never tell the reader to notice something. Never hard-wrap a paragraph — one paragraph per line, always, because these get pasted into email and hard breaks carry through.

## Using it

Run the three in order on the draft. Then state, in one line each, what changed and what was left alone and why — his judgement is the last pass, and he needs to see what was touched before he opens Grammarly.

The three-question gate applies to the whole exercise. Does this need to be said. Does it need to be said by me. Does it need to be said right now. Stop at the first no.
