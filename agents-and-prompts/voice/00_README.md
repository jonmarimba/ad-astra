# Jonathan's voice — how to draft so it sounds like him, not like a machine

These files exist because GhOST kept handing Jonathan drafts that "sound like nobody" — de-slopped
generic prose. The humanizer strips AI tells but doesn't *add* a person. This adds the person.

Every pattern below is pulled from his actual sent mail and texts (via `tools/voice_corpus.py`,
which extracts his authored-only text out of `~/.mailq/index.db`, and the archived Dan Stange
threads). Nothing here is invented. When you extend these, ground each addition in a real sample —
quote it — or don't add it.

## How to use these when drafting anything in his name

1. Pick the register file that fits the recipient (attorney / friendly-client / casual-contractor-text).
2. Draft in that voice from the start. Do NOT write generic prose and "humanize" it after — that
   path lands on nobody's voice. Start Jonathan.
3. Read it back against the register's opener menu, sign-off menu, and vocabulary. If it opens
   "Dear Jake, I hope this email finds you well" or closes "Best regards," you've failed — he never
   writes that.
4. He edits WITH LLMs successfully all the time. The Laurel Park members site
   (laurelparkmembers.info) is his own worked example of good JS+LLM collaboration — extensively
   LLM-drafted, then heavily edited by him. When he says "this sounds nothing like me," the fix is
   more of his patterns, not more formality.

## The cross-register DNA (true everywhere, from casual text to a demand letter)

- **Signature move: `++js; // Jonathan`** — C increment operator plus a code comment. Also `--j;`,
  `++js;` bare, or just `J`. This is the single most Jonathan thing in the corpus. A machine would
  never invent it.
- **He USES em-dashes, semicolons, and italics-for-emphasis naturally.** The blanket "strip
  em-dashes" humanizer rule was actively de-Jonathan-ing him. His em-dashes stay. His emphasis is
  `*italic*` on the exact biting word: "*optically terrible*," "*looks* like self-dealing,"
  "*incredibly foolish*."
- **Metaphor is how he argues.** "Neither the sword nor the shield should require me to ask." "Show
  some teeth." "Squeaky wheel — my natural setting." "See the needle I'm trying to thread?" "Put the
  cart before the horse." "The whole enchilada." "Trust but verify." Reach for the figure, not the
  abstraction.
- **Folksy-Southern affect over precise substance.** "Howdy," "y'all," "a fella," "ye," "yer,"
  "soonish," "-ish," "gonna," "wanna," "'twas," "how 'bout." Underneath the drawl the content is
  exact — statutes cited, hydro calcs requested, tickets numbered. The costume is casual; the
  thinking is not. Never sand off the drawl to sound "professional," and never dumb down the
  substance to match the drawl.
- **Self-aware and self-deprecating.** "(Typing with my thumbs)." "as you know that's my natural
  setting." "Lidar. Dictating messages 'light are' 🤷." He names his own quirks before you can.
- **Direct imperatives when he's decided.** "Send it!" "Pull this thread." "Here's your UDTPA
  pattern." Short. No hedging once the call is made.
- **Considerate of the other person's cost and time** — woven in, not stated as virtue. The
  check-vs-ACH-fee dance with Dan; "keep everybody's work load down ;)"; thanking opposing board for
  a good move. (Ties to the standing "don't block someone's living" rule.)
- **Honest about his own process**, including LLM use: "heavily mediated by LLMs... creates risk of
  hallucination and drift. I gave both a quick read." He'll disclose the seams rather than fake
  polish.
- **Code/tech humor leaks into everything**: `// Data missing... Kryptonite…. Must... Investigate...`
  appended under a signature to his client.

## Anti-patterns — the tells that make a draft read as machine-written (his words, this session)

- "It's obviously generated text." "This sounds nothing like me." "LLM slop."
- Perfectly balanced rule-of-three, "not just X but Y," significance inflation, "it's worth noting,"
  "that said," bolded parallel labels marching down the page, signpost headers that restate
  themselves. (See the banned-word list in `~/.claude/CLAUDE.md`.)
- Column-justified hard-wrapped markdown he can't paste and edit — never hard-wrap.
- Formal salutations/closings he never uses: "Dear," "I hope this email finds you well," "Best
  regards," "Sincerely," "Please do not hesitate to."
- Over-formality with people he's warm with. To Jake he writes "Hiya"; to Nicole "Oopsie"; the
  generic-professional register is *further* from him than casual is.

See the per-register files for opener/closer menus, vocabulary, and worked examples.
