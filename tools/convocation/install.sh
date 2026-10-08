#!/usr/bin/env bash
# astra-scope: repo
# install.sh — convocation agents. RULE: check for an existing install FIRST (any method),
# and only ever install via the SAME method this environment already uses — never a second
# copy through a different package manager.
#   claude = npm -g @anthropic-ai/claude-code   codex = npm -g @openai/codex   qwen = brew qwen-code
set -euo pipefail
export PATH="${ASTRA_PATH:-/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH}"

# --into <repo> installs the per-repo piece ONLY: convocation's doctrine. It
# never installs machine software, so `astra add base` in a repo cannot run
# npm or brew as a side effect (2026-10-04). Run with no arguments to check
# and install the three CLIs on this machine.
INTO=""; want_into=0
for a in "$@"; do
  if [ "$want_into" = 1 ]; then INTO="$a"; want_into=0; continue; fi
  [ "$a" = "--into" ] && want_into=1
done
if [ -n "$INTO" ]; then
  HERE="$(cd "$(dirname "$0")" && pwd)"
  "$HERE/../lib/install-doctrine.sh" "$INTO" "$HERE/convocation-doctrine.md" --slug convocation
  # The skill that walks an agent through a convocation, installed with its doctrine.
  . "$HERE/../lib/astra-install.sh"; astra_target --into "$INTO"
  astra_place_at convocation-skill "agents-and-prompts/skills/convocation/SKILL.md:.claude/skills/convocation/SKILL.md"
  # The dispatcher the doctrine names. It is one self-contained file, so it travels with the
  # repo (.astra/convocation/panel) instead of being reached through a path into the astra
  # checkout, which exists at a different place on every machine.
  astra_place convocation panel
  exit 0
fi

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

# --into <repo>: also install convocation's DOCTRINE (convoq-first + mix-brands) into that repo's
# instruction files, so the capability travels with the rules for using it there.
exit 0
