# speech-bee

Swappable STT/TTS "bee": audio→text, text→audio, same stdin/stdout contract regardless of engine. For kicker2's voice side-channel and for transcribing recorded calls.

```sh
./install.sh                          # whisper-cpp + ffmpeg + fetch base.en model
speech-bee stt call.aiff              # transcription → stdout
speech-bee tts "hello" --out hi.aiff  # or: echo hi | speech-bee tts -
speech-bee bootstrap small.en         # better/larger model (base.en is the default)
```
Engines now: **STT** = whisper.cpp (`whisper-cli`); **TTS** = macOS `say` (AVSpeechSynthesizer, on-device). Override with `SPEECH_BEE_STT` / `SPEECH_BEE_TTS` / `SPEECH_BEE_MODEL`.

**Next backend:** Apple **SpeechAnalyzer/SpeechTranscriber** (macOS 26+, on-device, benchmarks above Whisper Large v3 Turbo, ~2-3× faster) as a Swift helper behind the same `stt` verb — for jargon (JIRA IDs, tool names) it may still need a correction pass or legacy SFSpeechRecognizer custom-vocabulary.

## Recording a call (Audio Hijack → speech-bee)
1. In **Audio Hijack**, build a session: Application/Input blocks for the call app + your mic → a **Recorder** block (AIFF or WAV). Start it before the call.
2. After the call: `speech-bee stt ~/Music/Audio\ Hijack/<recording>.aiff > transcript.txt`
3. For the Dan call, save to `js-speedway/09_Sedona/20260812_Dan_call_transcript.md`.
