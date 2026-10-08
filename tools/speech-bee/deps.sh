#!/usr/bin/env bash
# deps.sh — install or upgrade whisper-cpp and ffmpeg, and make sure the default whisper model is present.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/deps-common.sh"
brewfile_upgrade "$HERE/Brewfile"
"$HERE/speech-bee" bootstrap base.en
