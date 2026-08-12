#!/usr/bin/env bash
# harness-settings.sh — APPLY or UNDO the "Harness settings — SYNTHESIS (real coding, not vibe)"
# recommendations across Claude Code, Codex, and Qwen. Source: the Fable+Sol synthesis note.
#
# Design: apply() ALWAYS backs up every config to a timestamped dir FIRST, then edits in place
# (jq for the JSON configs, tomlkit for Codex TOML — format/comment preserving). undo() restores
# the most recent backup verbatim, so a bad apply is always fully reversible. Nothing here runs
# unless you run it — it edits YOUR live configs, so review, then `apply`, then `undo` if you dislike it.
#
# Usage: harness-settings.sh apply | undo | status | diff
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CLAUDE="$HOME/.claude/settings.json"
CODEX="$HOME/.codex/config.toml"
QWEN="$HOME/.qwen/settings.json"
BACKUP_ROOT="${HARNESS_BACKUP_ROOT:-$HOME/.harness-settings-backups}"

# Claude deny-list (irreversible) + allow-list (safe verbs) — additive, deduped, never clobbering.
CLAUDE_DENY='["Bash(git commit:*)","Bash(git push:*)","Bash(git reset --hard:*)","Bash(rm -rf:*)","Read(.env)","Read(**/.env)","Read(~/.ssh/**)","Read(~/.aws/**)"]'
CLAUDE_ALLOW='["Bash(rg:*)","Bash(git status:*)","Bash(git diff:*)","Bash(git log:*)","Bash(ls:*)"]'

apply() {
  command -v jq >/dev/null || { echo "need jq (run install.sh)"; exit 1; }
  python3 -c "import tomlkit" 2>/dev/null || { echo "need python tomlkit (run install.sh)"; exit 1; }
  # timestamp passed in (date is fine in a normal shell); one backup dir per apply
  local ts bdir; ts="$(date +%Y%m%d-%H%M%S)"; bdir="$BACKUP_ROOT/$ts"; mkdir -p "$bdir"
  [ -f "$CLAUDE" ] && cp "$CLAUDE" "$bdir/claude_settings.json"
  [ -f "$CODEX" ]  && cp "$CODEX"  "$bdir/codex_config.toml"
  [ -f "$QWEN" ]   && cp "$QWEN"   "$bdir/qwen_settings.json"
  echo "$ts" > "$BACKUP_ROOT/latest"
  echo "backed up -> $bdir"

  if [ -f "$CLAUDE" ]; then
    local tmp; tmp="$(mktemp)"
    jq --argjson deny "$CLAUDE_DENY" --argjson allow "$CLAUDE_ALLOW" '
      .model = "opus"
      | .effortLevel = "xhigh"
      | .outputStyle = "Default"
      | .autoMemoryEnabled = false
      | .permissions = (.permissions // {})
      | .permissions.deny  = (((.permissions.deny  // []) + $deny)  | unique)
      | .permissions.allow = (((.permissions.allow // []) + $allow) | unique)
    ' "$CLAUDE" > "$tmp" && mv "$tmp" "$CLAUDE"
    echo "claude: model=opus effort=xhigh outputStyle=Default autoMemory=off; deny/allow merged"
  fi

  if [ -f "$QWEN" ]; then
    local tmp; tmp="$(mktemp)"
    jq '.thinking = "high" | (if has("telemetry") then .telemetry.enabled = false else . end)' \
      "$QWEN" > "$tmp" && mv "$tmp" "$QWEN"
    echo "qwen: thinking=high, telemetry off. (Trim QWEN.md — it was ~103k tokens; do that by hand.)"
  fi

  if [ -f "$CODEX" ]; then
    python3 "$HERE/toml_set.py" "$CODEX" \
      model_reasoning_effort=xhigh \
      plan_mode_reasoning_effort=xhigh \
      model_verbosity=low \
      personality=none \
      approval_policy=on-request \
      sandbox_mode=workspace-write \
      sandbox_workspace_write.network_access=false \
      features.hooks=true \
      features.memories=false
    echo "codex: effort=xhigh verbosity=low personality=none approval=on-request sandbox=workspace-write net=off hooks=on memories=off"
  fi
  echo "DONE. Review; 'harness-settings.sh undo' restores the backup above."
}

undo() {
  local ts bdir; ts="$(cat "$BACKUP_ROOT/latest" 2>/dev/null || true)"
  [ -z "$ts" ] && { echo "no backup to undo"; exit 1; }
  bdir="$BACKUP_ROOT/$ts"
  [ -f "$bdir/claude_settings.json" ] && cp "$bdir/claude_settings.json" "$CLAUDE" && echo "restored claude"
  [ -f "$bdir/codex_config.toml" ]    && cp "$bdir/codex_config.toml"    "$CODEX"  && echo "restored codex"
  [ -f "$bdir/qwen_settings.json" ]   && cp "$bdir/qwen_settings.json"   "$QWEN"   && echo "restored qwen"
  echo "undone from $bdir"
}

status() {
  echo "== claude =="; jq -r '{model,effortLevel,outputStyle,autoMemoryEnabled,deny:(.permissions.deny//[]|length),allow:(.permissions.allow//[]|length)}' "$CLAUDE" 2>/dev/null
  echo "== codex =="; grep -E '^(model_reasoning_effort|plan_mode_reasoning_effort|model_verbosity|personality|approval_policy|sandbox_mode)' "$CODEX" 2>/dev/null
  grep -E 'network_access|hooks|memories' "$CODEX" 2>/dev/null
  echo "== qwen =="; jq -r '{thinking}' "$QWEN" 2>/dev/null
  echo "latest backup: $(cat "$BACKUP_ROOT/latest" 2>/dev/null || echo none)"
}

case "${1:-}" in
  apply) apply ;;
  undo)  undo ;;
  status) status ;;
  *) echo "usage: $0 apply|undo|status"; exit 1 ;;
esac
