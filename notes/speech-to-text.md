**Speech - to - text**

@ghost - when we get to kicker2, I’d like to be able to put speech on either end of the conversation in my side channel between hosts. So, the iOS app should be able to act as some kind of host for a conversation via voice. Would like as much as possible to continue to live in tmux (transport) and only have something like a ‘bee’ on the end or something we can pipe into or out of for speech - to - text and text - to - speech.

I think the guts of kicker may be more cross platform (iOs app not withstanding), so maybe some part of this needs to be something where you can replace the engine easily from (e.g.) whisper or whatever to Apple’s apparently fantastic tools in both directions. We’d probably start with Apple and then add others.

**GhOST reply, 2026-08-06 11:53:**

Your instinct on Apple's tools checks out — genuinely current-best, not just &quotgood enough on-device." macOS 26 replaced the old SFSpeechRecognizer with a new SpeechAnalyzer/SpeechTranscriber API:

fully on-device, proprietary Apple model, benchmarked as the most accurate on-device speech engine tested — beating every Whisper model including Whisper Large V3 Turbo, while running ~2-3x faster. Only gap:

it doesn't yet have SFSpeechRecognizer's old Custom Vocabulary feature (registering domain-specific keywords), so if kicker2 needs to reliably transcribe jargon (JIRA ticket IDs, tool names, &quotkicker," &quotbees," etc.) you may need to fall back to legacy SFSpeechRecognizer for that specific need, or build a post-transcription correction pass.

For TTS, AVSpeechSynthesizer is the match — private, low-latency, on-device, no cloud round-trip. Concrete shape for kicker2 given your &quottmux as transport, replaceable engine" framing: this is a clean fit for exactly the &quotbee" pattern — a small standalone CLI (&quotspeech-bee" or similar) that does two things:

* reads audio in, calls SpeechAnalyzer, writes transcribed text to stdout;
* reads text from stdin, calls AVSpeechSynthesizer, plays/writes audio out.

Both directions swappable behind the same stdin/stdout contract — start wired to Apple's APIs since they're free, private, and currently best-in-class, but the interface itself doesn't care whether the backend is Apple, Whisper, or something else later.

That keeps kicker's cross-platform ambition intact (the bee itself would need a non-Apple backend on Linux nodes, but the protocol between hosts stays engine-agnostic) while giving you the best available option on the Mac side today with zero API cost and no cloud dependency. For the iOS-app-as-host-for-a-voice-conversation idea specifically:

both SpeechAnalyzer and AVSpeechSynthesizer are iOS APIs too (not Mac-only), so the same bee logic could run natively in the iOS app rather than needing a separate bridge — worth designing the bee's interface to be portable to Swift-on-iOS from the start rather than assuming it only lives on a Mac.

@ghost re-synthesize / consolidate all TTS and STT in one note. Delete all other related notes. Place the stuff to try in a section of my tech to try list.

@astra the result