#!/usr/bin/env bash
# install.sh — convocation agents. RULE: check for an existing install FIRST (any method),
# and only ever install via the SAME method this environment already uses — never a second
# copy through a different package manager.
#   claude = npm -g @anthropic-ai/claude-code   codex = npm -g @openai/codex   qwen = brew qwen-code
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"

have() {  # present anywhere on PATH? report where + how it resolves, and skip install
  local p; p="$(command -v "$1" 2>/dev/null)" || return 1
  echo "already installed: $1 -> $p $( [ -L "$p" ] && echo "-> $(readlink "$p")" )"
}

have claude || { echo "installing claude via npm (the method used here)"; npm install -g @anthropic-ai/claude-code; }
have codex  || { echo "installing codex via npm (the method used here)";  npm install -g @openai/codex; }
have qwen   || { echo "installing qwen via brew (the method used here)";  brew install qwen-code; }

echo "--- final state (one copy each, no shadowing) ---"
for b in claude codex qwen; do
  hits=0
  for d in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin" "$HOME/bin" "$HOME/.bun/bin" "$HOME/.cargo/bin"; do
    [ -e "$d/$b" ] && { echo "  $d/$b"; hits=$((hits+1)); }
  done
  [ "$hits" -gt 1 ] && echo "  WARNING: $b has $hits copies — resolve before scheduling anything that calls it"
done
# the [ -gt 1 ] test being false on the loop's last iteration must not become the script's
# exit code (a clean single-copy state read as failure — caught by test-installers-which-first)
exit 0
