#!/usr/bin/env bash
# uninstall.sh — convocation installs the AGENT CLIs claude/codex/qwen. Those are your primary
# tools, NOT incidental deps, so this NEVER removes them (even with --deps) — it prints how, if you
# truly want to. convocation itself creates no state to dis-integrate.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/uninstall-common.sh"
# Pull --into <repo> out FIRST — the shared uc_parse rejects unknown flags, so it must not see it.
INTO=""; REST=(); want_into=0
for a in "$@"; do
  if [ "$want_into" = 1 ]; then INTO="$a"; want_into=0; continue; fi
  if [ "$a" = "--into" ]; then want_into=1; continue; fi
  REST+=("$a")
done
uc_parse ${REST[@]+"${REST[@]}"}
echo "convocation dis-integrate:"
echo "  convocation keeps no state of its own."
uc_keep claude "your Claude Code agent CLI (npm -g @anthropic-ai/claude-code)"
uc_keep codex  "your Codex agent CLI (npm -g @openai/codex)"
uc_keep qwen   "your Qwen agent CLI (brew qwen-code)"
if [ "${UNINSTALL_DEPS:-0}" = 1 ]; then
  uc_warn "You passed --deps, but convocation refuses to remove agent CLIs." \
          "If you really mean it:  npm rm -g @anthropic-ai/claude-code @openai/codex ; brew uninstall qwen-code"
fi
if [ -n "$INTO" ]; then
  "$HERE/../lib/uninstall-doctrine.sh" "$INTO" --slug convocation
fi
echo "done."
