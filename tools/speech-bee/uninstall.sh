#!/usr/bin/env bash
# uninstall.sh — dis-integrate speech-bee: remove the downloaded whisper model
# (~/.cache/whisper/ggml-base.en.bin). Optional deps: whisper-cpp + ffmpeg. TTS uses macOS `say`
# (nothing installed).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/uninstall-common.sh"
uc_parse "$@"
echo "speech-bee dis-integrate:"
uc_rm_state "${SPEECH_BEE_MODEL:-$HOME/.cache/whisper/ggml-base.en.bin}" "downloaded whisper model"
uc_brew whisper-cpp "whisper-cli STT backend"
uc_brew ffmpeg "general-purpose media tool used by many workflows"
echo "done."
