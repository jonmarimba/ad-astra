#!/usr/bin/env bash
# astra-scope: repo
# install.sh — the convoq wrapper in <repo>/.astra/convoq/. The search engine stays in astra (vendor/authsec-bridge), because it indexes this machine's transcripts.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/astra-install.sh"
astra_target "$@"
astra_place_at convoq "tools/convoq/convoq:.astra/convoq/convoq"
