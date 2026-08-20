#!/usr/bin/env bash
# uninstall.sh — dis-integrate frame-review. It's stateless (frames go wherever --outdir points;
# nothing global is created), so the only thing to optionally remove is its one dep, ffmpeg.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/uninstall-common.sh"
uc_parse "$@"
echo "frame-review dis-integrate:"
echo "  frame-review keeps no global state — output lives only where you pointed --outdir."
uc_brew ffmpeg "ffmpeg is a general-purpose media tool used by many workflows"
echo "done."
