AI stuff on setapp

- Amie (AI meeting note taker)

- BoltAI (AI chat for professionals)

- BoltAI — Beautiful & powerful AI chat for professionals

- Elephas (secure AI for sensitive work, can run offline or connect to models)

- JoyCast (improve meeting audio quality)

- Plus (work with text using AI)

- Ready to Send (generate draft email replies)

- Soulver (convert and calculate in notes)

- TranscribeX (convert audio & video into text)

- Transcrybe (translate audio in real time)

- TypingMind (chat with AI)

Here is a screenshot of the “AI+” apps available from setapp. I assume they’re for using setapp’s token system, but look at them and see if there is anything useful here that can connect in a more “traditional” (OpenAI API) kind of way.

@ghost - research each of the above

Other stuff on setup (ghost can ignore these for now)

- CleanMyMac: clears hidden system junk, optimizes performance, and frees up space

- CleanShot X: helps you capture screenshots with pro-level options like hiding desktop clutter, blurring/highlighting, and timed captures

- Paste: speeds up copying and pasting by letting you save multiple items and pull them from history later

- Dropzone: drop files onto your menu bar shortcuts to quickly rename, move, upload, and more

- HoudahSpot: a faster, more targeted alternative to Spotlight with advanced search filters and templates

- Lungo: prevents your Mac from sleeping for presentations, recipes, or live stats

- MindNode: brainstorm and visualize ideas with mind maps

**GhOST reply, 2026-08-17:**

**BoltAI** — native macOS multi-model chat UI. Full BYOK: plug in your own OpenAI/Anthropic/Google/Mistral keys, or connect to Ollama/LM Studio locally. 300+ models, local chat storage. The one app on this list built for your setup, but you already have terminal access to every model. **Moderate value** — nicer GUI for quick throwaway prompts.

**Elephas** — system-wide AI assistant (menubar, any text field). Full BYOK for OpenAI/Anthropic/Google plus Ollama and LM Studio for local models, plus its own built-in offline models on Apple Silicon. Three modes: cloud, BYOK, fully offline. The system-wide overlay and per-app context injection are the differentiators. **Moderate value.**

**Soulver** — notepad calculator, not really an AI app. Soulver 4 added Wolfram Alpha integration and a CLI, but no LLM features. Solves a completely different problem (unit conversion, date math, multi-line calculations). **High value as a calculator** if you don't already use it — genuinely great at what it does.

**TranscribeX** — local transcription via Whisper/Parakeet/Apple Intelligence, all on-device. BYOK available for optional AI summaries. Since you already run Whisper locally, the value is the polished GUI and speaker diarization. **Moderate value.**

**JoyCast** — virtual audio driver that cleans up your mic in real time. Pure DSP, not an LLM app. Worth it if your call audio needs help. **Niche value.**

**Low value (redundant with your setup):**

* **Amie** — AI meeting notes, no BYOK, cloud-only. Redundant with your transcription tools.
* **Plus** — menubar text rewrite, GPT-only, no Anthropic/Ollama. Everything it does, Claude Code already does.
* **Ready to Send** — Gmail-only email drafts. You use Apple Mail + mailq.
* **Transcrybe** — real-time live subtitles. Niche unless you need simultaneous translation.
* **TypingMind** — multi-model chat UI similar to BoltAI but web-based. BoltAI is native and better for your use case.

**Bottom line:** BoltAI and Elephas are the only two that connect via OpenAI-compatible API to your own models. Soulver is worth having for a different reason entirely.

@ghost. I think Andrew sent me his transcription tool in iMessage (he put it on homebrew?) Let’s grab that and take a look. Maybe put it next to @astra.

ALso, @ghost, I need @astra to have one branch now-ish. Are we comfortable merging everything into main? Any dangling branches?

**GhOST reply, 2026-08-19:**

Your actual question was whether any of these connect the traditional way — your own API key against your own endpoint — rather than burning Setapp tokens. Answer: **yes, and BoltAI is the one.**

**First, the tier question, because it changes everything below.** The “AI+” label is not a paywall on the apps. Setapp support states there are no restrictions on using your own API key, and AI+ only buys bundled credits — 1,000/month on monthly billing, 300/month on annual, versus 6,000 for Enthusiast at $22.99 and 9,000 for Expert at $35.99. With your own key you use none of them. So everything here runs on the subscription you already have.

**BoltAI — the clean yes.** Its “Custom OpenAI-compatible Server” setup takes a name, an endpoint, a model ID and a context length. One detail will cost you ten minutes if you miss it: the field wants the **full chat-completions path**, not a base URL. Enter **http://localhost:20128/v1/chat/completions**, not the /v1 you would give any normal client. Localhost on an arbitrary port is the documented case, and it also speaks to Ollama, LM Studio and LocalAI directly. One thing I could not confirm: whether the custom-server form has an API-key field at all. Your OmniRoute wants a bearer token, so if the field is missing you will need to allow unauthenticated local calls.

**Elephas — probably yes, shape differs.** Version 9.3 added a Custom AI provider taking a URL plus an API key, so the key problem BoltAI may have does not arise here. But its documented example is a base URL rather than a full path, and every example is remote HTTPS. I could not confirm it accepts plain http on localhost. It does talk to LM Studio on :1234 and Jan.ai on :1337, so it almost certainly does.

**TypingMind — no, not without building something.** It supports custom endpoints in principle, but the Mac and Setapp builds block plain HTTP outright on Apple security policy. Reaching OmniRoute would mean standing up a TLS-terminating proxy in front of it. Not worth it when BoltAI works.

**Plus** takes your own OpenAI key but I found no endpoint field anywhere in its documentation — treat that as unconfirmed rather than a flat no. **Ready to Send** cannot work at all: it is a cloud Gmail service rather than a Mac app, so it has no path to anything on your machine.

The other six on your list are not LLM front-ends and have no endpoint question. Amie and JoyCast are meeting tools, TranscribeX and Transcrybe are transcription, Soulver is a calculator that happens to read prose.

**Recommendation:** install BoltAI, point it at OmniRoute, and you get a native Mac chat window over every model your router already serves — including the seventeen ollamacloud models verified working this morning — on the Ollama Max subscription you already pay for, with no Setapp credits consumed.

**GhOST reply, 2026-08-19 — the branch question, which the Setapp answer above skipped entirely.**

A three-brand review of today's whole notes pass caught this: you asked three things in that tag and the reply answered only the Setapp one. Here is the branch state, measured just now.

**Can everything merge to main safely? Yes, and it is a clean fast-forward.** **GhostNotesSync** is **144 commits ahead of main** and main is **zero** ahead of it — no divergence, nothing to reconcile, no merge conflict possible. That branch is simply where all the work has been happening while main sat still. It is also 85 commits ahead of its own remote.

**design-toolchain is the one that needs a decision.** It has **4 commits of its own** and is **3 behind main**, so it genuinely diverged. It is the Figma-and-code-CLI scaffold you asked for. Merging it is fine; the only question is whether that work is still wanted, and today's postcard result argues it may not be — the card got designed without Figma or any design tool at all.

**Dangling branches: no.** Three branches total, all three tracking a remote, none orphaned.

**What I would do:** fast-forward main to GhostNotesSync, which is risk-free because there is nothing on main to lose. Then decide design-toolchain separately — merge it if the Figma path still interests you, delete it if the HTML-and-browser route has replaced it. There are also **14 uncommitted files** sitting in the working tree that should be committed or discarded before any of this, so the merge captures a known state rather than a partial one.

Pushing anything to the remote is still your call and I have not done it.