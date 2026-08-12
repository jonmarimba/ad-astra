#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
command -v brew >/dev/null && brew bundle --file="$HERE/Brewfile" || echo "ensure whisper-cpp + ffmpeg present"
"$HERE/speech-bee" bootstrap base.en
echo "speech-bee ready."
