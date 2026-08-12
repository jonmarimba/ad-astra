#!/usr/bin/env bash
# install.sh — convocation agents, matching how this environment actually installs them:
#   claude  = npm -g @anthropic-ai/claude-code   (npm prefix /opt/homebrew → /opt/homebrew/bin/claude)
#   codex   = npm -g @openai/codex
#   qwen    = brew qwen-code
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
command -v brew >/dev/null && brew bundle --file="$HERE/Brewfile"
command -v claude >/dev/null || npm install -g @anthropic-ai/claude-code
command -v codex  >/dev/null || npm install -g @openai/codex
for b in /opt/homebrew/bin/claude /opt/homebrew/bin/codex /opt/homebrew/bin/qwen; do
  [ -x "$b" ] && echo "ok: $b" || echo "MISSING: $b"
done
