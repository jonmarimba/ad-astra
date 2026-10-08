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
# A missing model is NOT a precondition failure: the tool fetches its own on first use (that
# is what astra is for), so the first real `stt` below heals this machine if it needs to.
# This used to fail the whole file with "model missing — loud fail, not a skip", which made a
# clean machine's first test run red for a dependency the tool could fetch itself.

# ---- self-healing, hermetic: a fake model hub served from a local directory ----
mkdir -p "$SB/hub" "$SB/heal"; printf 'not a real model' > "$SB/hub/ggml-tiny.bin"
printf 'x' > "$SB/in.aiff"
env SPEECH_BEE_MODEL="$SB/heal/ggml-tiny.bin" SPEECH_BEE_MODEL_URL_BASE="file://$SB/hub" "$BEE" stt "$SB/in.aiff" >/dev/null 2>"$SB/heal.err"
assert_file "$SB/heal/ggml-tiny.bin" "stt fetched the missing model on first use"
assert_contains "$SB/heal.err" "fetching ggml-tiny.bin" "and said it was fetching"
red "a failed model download stops with the URL" 1 "model download failed" \
  env SPEECH_BEE_MODEL="$SB/heal2/ggml-tiny.bin" SPEECH_BEE_MODEL_URL_BASE="file://$SB/nowhere" "$BEE" stt "$SB/in.aiff"
assert_no_file "$SB/heal2/ggml-tiny.bin.part" "a failed download leaves no partial file"
red "SPEECH_BEE_NO_FETCH keeps the old refusal" 1 "no model at" \
  env SPEECH_BEE_MODEL="$SB/heal3/ggml-tiny.bin" SPEECH_BEE_MODEL_URL_BASE="file://$SB/hub" SPEECH_BEE_NO_FETCH=1 "$BEE" stt "$SB/in.aiff"
assert_no_file "$SB/heal3/ggml-tiny.bin" "and fetched nothing"

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
red "stt on non-audio bytes must fail" 1 "ffmpeg convert failed" "$BEE" stt "$SB/garbage.bin"
red "stt with a missing model must fail" 1 "no model at" env SPEECH_BEE_MODEL="$SB/no-model.bin" "$BEE" stt "$SB/fox.aiff"
red "unknown STT engine must fail" 1 "unknown STT engine" env SPEECH_BEE_STT=elvish "$BEE" stt "$SB/fox.aiff"
red "no arguments must fail with usage" 1 "usage:" "$BEE"

finish
