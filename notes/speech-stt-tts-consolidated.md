**Speech — STT + TTS (consolidated)**

One note for everything speech — consolidated 2026-08-12 from &quotSpeech - to - text" + &quotMeetily — STT/TTS recommendations" (both deleted per JS). Try-items live in the @astra tech-to-try list.

**The kicker2 ask (original)**

Voice on either end of the side-channel between hosts; the iOS app as a voice host for a conversation; keep tmux as transport with a swappable &quotbee" on the end to pipe STT/TTS through; engine replaceable (Whisper ↔ Apple's tools), start with Apple.

**What's BUILT (2026-08-12): speech-bee**

* **@astra tools/speech-bee** — the swappable bee, exactly the stdin/stdout contract from the ask: **speech-bee stt file** → text; **speech-bee tts &quottext"** → audio. Engines now: whisper.cpp (base.en) + macOS say; SPEECH\_BEE\_STT/TTS/MODEL env-swappable; Apple SpeechAnalyzer Swift backend is the planned drop-in.
* **Proven on real material**: transcribed 5 Dan Stange voicemails + the recorded 8/12 Dan callback (evidence-grade after a proper-noun pass), phone-band audio.
* **Three-way engine shootout on the same audio**: whisper base.en ≈ Apple Phone-app ≈ Google Voice — near-identical, all three fumble the same proper nouns (&quotSedona Waterproofing"). whisper uniquely tags non-speech events ("(phone ringing)"). Upgrade path: speech-bee bootstrap small.en.
* Recording chain: Audio Hijack → tmp/audioTranscriptionInbox → speech-bee. WAV 16-bit/16kHz/mono = zero-conversion path.

**Engine picks (the standing recommendations)**

* **Apple SpeechAnalyzer/SpeechTranscriber** (macOS 26+, also iOS) — best on-device STT: beats Whisper Large v3 Turbo, ~2-3× faster. Gap: no custom vocabulary yet (jargon needs legacy SFSpeechRecognizer or a correction pass). The eventual speech-bee default.
* **Local STT alternates**: whisper.cpp / faster-whisper (CLI), MacWhisper (GUI), Parakeet (fast engine).
* **Meetily** (Zackriya-Solutions, meetily.ai) — privacy-first local Descript replacement: Rust, local Whisper/Parakeet, speaker diarization, Ollama summaries. The meeting-assistant slot.
* **Max-accuracy cloud STT**: ElevenLabs Scribe v2 — what Descript used (your screenshots showed Automatic / Scribe v2 / Rev AI v2/v3). Accuracy leader on names/technical terms.
* **TTS**: local — Kokoro or Piper (genuinely good now), macOS say for quick jobs (AVSpeechSynthesizer, what speech-bee uses); max quality — ElevenLabs Multilingual v2 (Descript's voice; its avatar was Kling v2).
* **How to choose**: accuracy → ElevenLabs Scribe v2. Privacy/local → Meetily or MacWhisper/Parakeet, accept a small accuracy loss. Descript sourced both directions from ElevenLabs.