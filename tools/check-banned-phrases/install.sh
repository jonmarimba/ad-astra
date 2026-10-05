#!/usr/bin/env bash
# astra-scope: repo
# install.sh — the banned-phrases checker with its own copy of the list, in <repo>/.astra/check-banned-phrases/.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/astra-install.sh"
astra_target "$@"
astra_place_at check-banned-phrases "tools/check-banned-phrases/check-banned-phrases.sh:.astra/check-banned-phrases/check-banned-phrases.sh" "agents-and-prompts/doctrine/banned-phrases.txt:.astra/check-banned-phrases/banned-phrases.txt"
