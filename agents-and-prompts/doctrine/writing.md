# Writing doctrine — Jonathan's communication patterns

These rules govern what belongs in a document, how to address a recipient, and how to structure asks. The ASD-STE100 skill handles sentence mechanics. This file handles everything above the sentence.

## Run the tools. Your opinion of your own prose is not evidence. (Jonathan, 2026-09-01)

Before any prose reaches a human — email draft, client document, README a person will read — run the installed writing tools. Run the prose skill (which chains asd-ste100 and the humanizer), then check-prose. This is not optional and not conditional on how good you judge the draft to be. Every model rates its own prose as fantastic; the AI tells the humanizer catches are precisely the ones the model that produced them cannot see. A draft presented without the tools having run is an unreviewed draft, and saying so afterward does not cure it. If the tools are not installed in the repo, say that instead of skipping silently.

## A client email is a relationship document, not a bug report (Jonathan, 2026-08-14)

The ASD-STE100 rules govern sentences. These govern what belongs in the document at all. Written after Jonathan rewrote a draft end to end, where the gap was not prose polish but audience. The draft was a findings list addressed to nobody; his rewrite was a letter to four named people that happened to contain findings.

Open with the causal story in one paragraph. His whole TL;DR was: we think you disabled a filter, that is what made us notice our own test code had been writing into production for years, it is now fixed, please delete the old records when you get a chance, and consider a regular cleanup. Five clauses carry the entire email. A list of findings is not an opening.

Name people and route the document. "This is mostly for Agat and David. There is one note below for Nicole." Then, inline at the place it applies, "Nicole, has Ms. Picinic mentioned this?" A document addressed to no one gets actioned by no one.

Own the fault early and plainly. "Sorry about that. This code has been around for years, and we only recently noticed it was doing the wrong thing." State what changed and on what date, then move on. Do not bury it under the diagnosis.

Phrase asks as suggestions and leave them an out. "Consider a periodic, automated cleanup?" and "perhaps just prior to the weekend CRON job?" beat a heading that reads "Ask: delete 22,622 records", which is a demand that opens with a number designed to alarm.

Hand them a lead, not only a symptom. "Check your version control for any change that removes or modifies how the code references the string 00 Js Test 000. That's your canary." Give the search string, the file path, the ticket number, the thing they can act on this morning.

Say when you are guessing. "I'm not sure whether this regression is related to the above. It feels like a coincidence to me." Certainty you do not have will be found out and costs the next claim its credibility.

A number is a tool with a direction, so decide it per placement rather than per fact. The same 14,000 would panic a client inside a deletion table. It is exactly right in a note asking a colleague whether the affected user ever complained.

Mark what is important rather than presenting every row as equal. Bold the one row that is hurting a real person and say underneath why it is bolded and why the rest are less urgent.

Put the operational material below the signature. Summary, details, thanks, sign-off, and then the deletion table and the cleanup request. The mail reads short, and the reference is still there for whoever has to do the work.

Offer to do their work. "Let us know if you'd like us to enter JIRA tickets for anything."

**Write the action first and hold the correction.** Every caveat handed to a client is a reason to argue instead of act. So the document that asks for something carries only what they need to do it. The corrections go in a second document that is written at the same time and sent later, or never, depending on whether they would care. Jonathan, 2026-08-15, on a Maharam email: he cut every caveat from the draft. He replaced "these are not the old numbers, you will have to decide about that". The single line "It looks to me like you've already updated the calculations in the Goals Tool" took its place. He closed with "with any luck, the job is already mostly done" so they had a win to claim. The footnote naming our internal term was offered as a development detail rather than a correction to their vocabulary. Leaving a true thing out of the first document is sequencing, not dishonesty.

## Asking a paid expert for a decision (Jonathan, 2026-08-14)

A companion to the client-email rules above, from a letter to Jonathan's attorney. Different genre, same principle: the client email was damage control, this one is buying a decision. Nearly every move in it exists to make the answer cheap to give.

Lead with the decision you need and what you need from them to make it. "Before we close out the file, I'd like a quick, concrete cost-benefit assessment for the limited records request suit." Not a task, not a discussion. A price, so the writer can decide.

Argue against your own position before you ask for it. He researched the case law himself and reported that fee shifting is "a maybe, and probably not much at best". He also reported that none of the money already spent comes back. That is his own case demolished in his own words, followed by "Correct me if I'm misreading this." An expert who has to talk you down first is spending your money doing it.

Attach your own guess to every question. "I would guess we don't need a third letter. Thoughts?" and "Yes?" and "How about you?" That turns an essay-length request into a yes or no, which is worth real money when the reader bills by the hour.

Give an explicit exit and pre-commit to taking it. "If your answer after all this is 'no way dude, way, way too expensive,' then that settles it. Politics from here on in." The expert can say no without also having to manage your reaction to it.

Separate what it buys from what it costs, and ask only for the cost. He lists the non-monetary returns himself, then says the price is the lawyer's question and the decision is his own.

Name your own bias and discount it out loud. "I'm (maybe) not so vain as to want my name in a citation... I can't say I hate the idea." And on the risk of being painted a crusader, "they'll paint me that way no matter what."

Credit their earlier advice by name. "Jake smartly (thanks!) kept our powder dry." "The financial hazards you've pointed out." It costs a clause and it tells them you were listening.

Scope the ask to the items that prove themselves, and say why. He cut the request to two records that the other side's own documents establish, so "no discovery fight necessary to establish either exists."

Signpost the optional parts. "Stop reading here and skip to the cases under my signature if you're feeling bored. If you want to know the why, read on." Long is fine when the reader is told what they may skip.

Sound like a person. Contractions, "my little robots", "$1100 filing fee?! OUCH", "no way dude". None of it costs precision, and a memo voice buys nothing.
