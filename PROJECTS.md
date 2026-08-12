# @astra — projects backlog (GhOST coding work)

Captured 2026-08-12 from a batch of @ghost/@astra note asks. This is the visible tracker for the "standardize our little tools into @astra" effort. Priority: **P1** = do next / time-sensitive, **P2** = core standardization, **P3** = larger/optional. JS authorized the work and said: *do it after the notes tasks; if I need confirmation, message the Google Voice number and he'll confirm.*

## Cross-cutting standard (applies to every tool moved into @astra)
Each tool that lands in @astra gets: (1) a **Brewfile** + **install script** for its dependencies; (2) **commit-hook add / subtract** scripts that don't conflict with other tools' hooks; (3) portable, agent-agnostic design (no hardcoded paths/identity — config-driven), per the toolkit rule. Don't clobber existing hooks or templates.

## P1 — time-sensitive / next
- [ ] **Dan communication sequence (Speedway drainage)** — Dan has ghosted; JS needs a documented approach. Steps: (a) pull the *during-rain* + *next-day* videos/stills, add punch-list items based on them; (b) prep a documentation packet to send via **email + Dropbox transfer**; (c) **call Dan** with notes in hand to hash it out; (d) decide what to actually send based on that call (or on no-answer). Afternoon calendar event: "Dan. Postcard. Arborist…" (1–2pm today). See `Dan-comms-prep` doc.
- [x] **Call-recording → transcription tool** — BUILT: `tools/speech-bee` (whisper.cpp STT + `say` TTS, engine-swappable, round-trip tested). Record in Audio Hijack → `speech-bee stt`.  ~~ — record the Dan call via **Audio Hijack**, then transcribe. Build the **speech-bee** STT (Apple SpeechAnalyzer/SpeechTranscriber, stdin/stdout, engine-swappable) as the transcription engine. This call is the first real use.
- [x] **vllm + Firecrawl research** — DONE (real findings in tech-to-try; Firecrawl ⭐ self-host = web-budget fix; vllm = Strix-box serving engine).  ~~ — JS flagged both as missed multiple passes. Real research passes (web budget spent → use Safari MCP).

## P2 — core tool standardization into @astra
- [x] **Copy XO's pdf-sidecars into @astra** — DONE: `tools/pdf-sidecars` w/ hook add (setup.sh) + subtract (hook-subtract.sh) + Brewfile + install.  ~~ — XO made a separate repo; JS wants it in @astra instead. Copy it in, add per-tool commit-hook add/subtract + Brewfile + install scripts. *(JS: do after other notes tasks; GV-confirm if needed. Andrew also has @astra access.)*
- [ ] **Marked 3 migration of the export toolchain** — move export code to @astra; migrate the legal template to Marked 3 as the default export template; drop the mouse-grabbing part of PDF export; add a **CLI flag to select a template**; add import/export of Marked 2 ↔ Marked 3 templates; auto-import (or better, reference-in-place) any on-disk @astra template named by the flag that isn't in the running Marked 3, **without clobbering** existing templates; guard against version-conflicting same-name templates (disk @astra vs running app).
- [x] **Generic "any robot can message me" tool** — BUILT: `tools/botline` (send/recv/dispatch/register/list), imsg-based, `@bot`-or-reply-to-last routing, monotonic-id watermark, schd dispatch timer registered. Brewfile+install+README. Routing tested.
- [x] **Harness add/undo script** — BUILT+TESTED: `tools/harness-settings` (apply/undo/status, backup-based, jq+tomlkit, verified on config copies).  ~~ — one script to APPLY and UNDO all the harness-settings recommendations per CLI (Claude/Codex/Qwen). Put in @astra tools.
- [~] **Model-sync system** — PARTIAL: `tools/ollama-watch` built (notifies via botline when ollama adds a frontier model; daily schd check registered). STILL TODO: sync model availability across OpenCode/qwen router + both laptops, auto-pull frontier models (needs router config + M5 reachable).  ~~orig:~~ — sync ollama model availability across OpenCode/qwen ("the router thing") and across both laptops; auto-add frontier-quality new ollama models (GLM 5.x, Kimi K-class); **notify JS** when ollama adds such a model. Reconcile litellm vs the existing router setup first (conflict or integrate?).
- [ ] **Graphify exportable hooks + Maharam trial** — build exportable hooks for graphify, put in @astra (Andrew + JS access); trial graphify+obsidian on a Maharam branch. Symlink any Maharam graphify-obsidian into JS's obsidian "chokepoint."

## P3 — larger / open-ended
- [ ] **Design toolchain** — Figma + code CLIs, for both print (HOA postcard) and UI (HOA / Maharam / kicker apps). Start a folder + branch in @astra. (Feeds off the Apple design skill.)
- [ ] **Hooks technical spec** — write the agent-hooks research (Claude/Qwen/Codex shared shell-hook convention; OpenCode/Pi TS-plugin family) as a technical spec/proposal in the kicker planning repo.
- [ ] **Humanizer on HOA site branch** — install the humanizer skill, run it on a **branch** of the HOA/POA site, report what it does + own opinion.
- [ ] **Consolidate STT/TTS notes** — re-synthesize all TTS/STT into one note, delete the rest (try-items already lifted into tech-to-try).

## Done tonight
- [x] Migrated tech-to-try → @astra (canonical, exclusive), reorganized by category + priority for kicker, symlinked into Obsidian vault, pointer stub in GhOST repo.
- [x] Added all of tonight's "add to tech to try" items (Exo, Firecrawl, ACP adapters, MCP-merging near top, Herdr near top, SetApp picks, dead-code synthesis, STT/TTS "speech-bee", Obsidian plugins, etc.).
- [x] Reminders set: Thu 8/13 2pm (sync laptops + commit-hooks into legal repos); Thu 8/13 3pm (tech-to-try review).
- [x] RH/temp sensor purchase-options doc + linked into the Dan calendar event.
