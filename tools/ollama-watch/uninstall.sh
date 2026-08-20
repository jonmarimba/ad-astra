#!/usr/bin/env bash
# uninstall.sh — dis-integrate ollama-watch: remove its state dir (~/.ollama-watch: seen.txt).
# It installs no deps of its own (it talks to an existing ollama), so there is nothing under --deps.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/uninstall-common.sh"
uc_parse "$@"
echo "ollama-watch dis-integrate:"
uc_rm_state "${OLLAMA_WATCH_HOME:-$HOME/.ollama-watch}" "ollama-watch state dir (seen list)"
echo "  (ollama-watch installs no deps of its own — nothing for --deps to remove.)"
echo "done."
