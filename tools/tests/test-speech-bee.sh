#!/usr/bin/env bash
# test-speech-bee.sh — a real round trip through the shipped engines: `say` synthesizes a
# sentence to AIFF, ffmpeg converts, whisper.cpp transcribes it back, and the words must
# survive. No mocks anywhere in this file.
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
BEE="$HERE/../speech-bee/speech-bee"
need ffmpeg "brew install ffmpeg"
need whisper-cli "brew install whisper-cpp"
need say "macOS"
MODEL="${SPEECH_BEE_MODEL:-$HOME/.cache/whisper/ggml-base.en.bin}"
[ -f "$MODEL" ] || { fail "whisper model missing at $MODEL (speech-bee bootstrap) — loud fail, not a skip"; finish; exit 1; }

# ---- tts: by effect, a real audio file ----
assert_rc 0 "tts writes an audio file" "$BEE" tts "the quick brown fox jumps over the lazy dog" --out "$SB/fox.aiff"
assert_file "$SB/fox.aiff" "aiff exists"
[ "$(stat -f%z "$SB/fox.aiff")" -gt 10000 ] && pass "aiff has real audio in it (>10KB)" || fail "aiff suspiciously small"

# ---- stt: the round trip. Words in, words out. ----
txt="$("$BEE" stt "$SB/fox.aiff" 2>/dev/null | tr '[:upper:]' '[:lower:]')"
for w in quick brown fox lazy dog; do
  case "$txt" in *"$w"*) pass "round-trip kept '$w'";; *) fail "round-trip lost '$w' (got: $txt)";; esac
done

# ---- stdin form of tts ----
echo "hello from stdin" | "$BEE" tts - --out "$SB/stdin.aiff"
assert_file "$SB/stdin.aiff" "tts reads text from stdin with '-'"

# ---- RED controls ----
printf 'this is not audio' > "$SB/garbage.bin"
red "stt on non-audio bytes must fail" "$BEE" stt "$SB/garbage.bin"
red "stt with a missing model must fail" env SPEECH_BEE_MODEL="$SB/no-model.bin" "$BEE" stt "$SB/fox.aiff"
red "unknown STT engine must fail" env SPEECH_BEE_STT=elvish "$BEE" stt "$SB/fox.aiff"
red "no arguments must fail with usage" "$BEE"

finish
