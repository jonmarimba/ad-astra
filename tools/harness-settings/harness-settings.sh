#!/usr/bin/env bash
# harness-settings.sh — APPLY or UNDO the "Harness settings — SYNTHESIS (real coding, not vibe)"
# recommendations across Claude Code, Codex, and Qwen. Source: the Fable+Sol synthesis note.
#
# Design: apply() ALWAYS backs up every config to a timestamped dir FIRST, then edits in place
# (jq for the JSON configs, tomlkit for Codex TOML — format/comment preserving). undo() restores
# the most recent backup verbatim, so a bad apply is always fully reversible. Nothing here runs
# unless you run it — it edits YOUR live configs, so review, then `apply`, then `undo` if you dislike it.
#
# Usage: harness-settings.sh apply|undo|status [--scope global|project] [--path DIR]
#   --scope defaults to "project". Undo/status use the SAME scope to find their backup/files —
#   pass the same --scope you applied with, or you'll look at the wrong file.
#   --path targets a project DIR without needing to cd into it first (Jonathan, 2026-08-15:
#   "most people will not run things from where they want them installed... make them all
#   like that unless you have a good reason not to"). Only meaningful with --scope project;
#   defaults to the current directory's git root (or cwd, if not in a repo) when omitted.
#
# GLOBAL vs PROJECT (added 2026-08-15, Jonathan: "add an option for global vs project, default
# to project, warn the user what happens at project level that's different from global level"):
# researched live against each brand's real docs/precedence rules, not assumed — the three
# brands do NOT behave the same way, which is exactly why this matters:
#   - Claude Code: permission `allow`/`deny` rules MERGE (union) across EVERY scope — a
#     project-level .claude/settings.json can only ADD restrictions, it can never remove or
#     override a deny rule that already exists in your GLOBAL ~/.claude/settings.json. So at
#     --scope project, Claude's deny rules here are additive on top of whatever's already
#     global, not an independent, undo-able-per-project layer the way the other two are.
#   - Codex: a project .codex/config.toml genuinely OVERRIDES the global one for the keys
#     this script sets (approval_policy, sandbox_mode, etc.) — a real, independent, per-
#     project layer.
#   - Qwen: plain override too — project settings.json fully overrides the global one.
# Still always undoable either way (see design note above) — this is about SCOPE (which
# project(s) get the change), not about reversibility (everything here reverses regardless).
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Most people won't run this from inside the repo they want it applied to — they'll
# expect an explicit target arg (Jonathan, 2026-08-15: "Make them all like that unless
# you have a good reason not to"). --path overrides where "project" scope resolves to;
# without it, falls back to the old cwd-derived behavior (git root, else cwd) so nothing
# breaks for anyone already running it from inside the target repo.
SCOPE="project"
TARGET_PATH=""
ARGS=()
NEXT=""
for a in "$@"; do
  case "$a" in
    --scope=*) SCOPE="${a#--scope=}" ;;
    --scope) NEXT="scope" ;;
    --path=*) TARGET_PATH="${a#--path=}" ;;
    --path) NEXT="path" ;;
    *)
      case "$NEXT" in
        scope) SCOPE="$a"; NEXT="" ;;
        path)  TARGET_PATH="$a"; NEXT="" ;;
        *) ARGS+=("$a") ;;
      esac
      ;;
  esac
done
case "$SCOPE" in
  global|project) ;;
  *) echo "harness-settings.sh: --scope must be 'global' or 'project', got '$SCOPE'" >&2; exit 64 ;;
esac
set -- "${ARGS[@]:-}"

if [ "$SCOPE" = "project" ]; then
  if [ -n "$TARGET_PATH" ]; then
    [ -d "$TARGET_PATH" ] || { echo "harness-settings.sh: --path '$TARGET_PATH' is not a directory" >&2; exit 1; }
    # Grouped explicitly — an ungrouped `A && B || C && D` chain does NOT short-circuit
    # the way it looks like it should: `&& pwd` tacked on the end runs regardless of
    # whether the OR already succeeded, so a ONE-LINER version of this silently printed
    # BOTH git rev-parse's output AND pwd's, corrupting PROJECT_ROOT with an embedded
    # newline (found live testing this exact line, 2026-08-15).
    PROJECT_ROOT="$(cd "$TARGET_PATH" && { git rev-parse --show-toplevel 2>/dev/null || pwd; })"
  else
    PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
  CLAUDE="$PROJECT_ROOT/.claude/settings.json"
  CODEX="$PROJECT_ROOT/.codex/config.toml"
  QWEN="$PROJECT_ROOT/.qwen/settings.json"
else
  CLAUDE="$HOME/.claude/settings.json"
  CODEX="$HOME/.codex/config.toml"
  QWEN="$HOME/.qwen/settings.json"
fi
BACKUP_ROOT="${HARNESS_BACKUP_ROOT:-$HOME/.harness-settings-backups}/$SCOPE"

warn_scope() {
  echo "SCOPE: $SCOPE"
  if [ "$SCOPE" = "project" ]; then
    echo "  claude: deny/allow rules here ADD to your global ~/.claude/settings.json rules —"
    echo "          Claude merges permission rules across scopes, this can't remove or"
    echo "          override anything already denied globally, only add more."
    echo "  codex:  $CODEX fully overrides your global ~/.codex/config.toml for this project."
    echo "  qwen:   $QWEN fully overrides your global ~/.qwen/settings.json for this project."
    echo "  (files created here if they don't exist yet — that's the point of --scope project)"
  else
    echo "  applies to your GLOBAL configs — every project, all three brands."
  fi
}

# Claude deny-list (irreversible) + allow-list (safe verbs) — additive, deduped, never clobbering.
CLAUDE_DENY='["Bash(git commit:*)","Bash(git push:*)","Bash(git reset --hard:*)","Bash(rm -rf:*)","Read(.env)","Read(**/.env)","Read(~/.ssh/**)","Read(~/.aws/**)"]'
CLAUDE_ALLOW='["Bash(rg:*)","Bash(git status:*)","Bash(git diff:*)","Bash(git log:*)","Bash(ls:*)"]'

LAST_APPLIED="$BACKUP_ROOT/last-applied"  # snapshot of each file exactly as WE last left it

# check_drift <file> <last-applied-snapshot> <label>
# Software-dev-101 config hygiene (Jonathan, 2026-08-15 — should've been in the first pass):
# a backup lets you undo OUR edit, but says nothing about whether the file already held
# something that ISN'T an earlier version of our own output — a user's own hand-written
# config, or a hand-edit made to OUR output since the last time this script touched it (e.g.
# they changed effortLevel back, or someone ran `apply` after a code update changed what we
# set). We don't implement real merge — instead: detect the divergence, show exactly what
# differs, and tell the user to merge by hand rather than silently steamrolling their edit.
check_drift() {
  local file="$1" snapshot="$2" label="$3"
  [ -f "$snapshot" ] || return 0  # no prior apply on record — nothing to compare against
  [ -f "$file" ] || return 0
  if ! diff -q "$snapshot" "$file" >/dev/null 2>&1; then
    echo "NOTE: $label ($file) differs from what harness-settings last set — hand-edited"
    echo "  since the last apply, or changed by something else. This script does NOT merge;"
    echo "  it will overwrite the keys it manages. Diff (last-applied -> current, before this"
    echo "  run's edit):"
    diff -u "$snapshot" "$file" | sed 's/^/    /'
    echo "  Consider merging your changes back in by hand after this apply, or reviewing"
    echo "  the backup at $bdir before trusting the new state."
  fi
}

apply() {
  command -v jq >/dev/null || { echo "need jq (run install.sh)"; exit 1; }
  python3 -c "import tomlkit" 2>/dev/null || { echo "need python tomlkit (run install.sh)"; exit 1; }
  warn_scope
  if [ "$SCOPE" = "project" ]; then
    # Project files usually don't exist yet — that's the point of scoping here. Global
    # files are left alone if missing (don't invent a global config nobody has).
    [ -f "$CLAUDE" ] || { mkdir -p "$(dirname "$CLAUDE")"; echo '{}' > "$CLAUDE"; }
    [ -f "$QWEN" ]   || { mkdir -p "$(dirname "$QWEN")";   echo '{}' > "$QWEN"; }
    [ -f "$CODEX" ]  || { mkdir -p "$(dirname "$CODEX")";  : > "$CODEX"; }
  fi
  # timestamp passed in (date is fine in a normal shell); one backup dir per apply
  local ts bdir; ts="$(date +%Y%m%d-%H%M%S)"; bdir="$BACKUP_ROOT/$ts"; mkdir -p "$bdir" "$LAST_APPLIED"
  [ -f "$CLAUDE" ] && cp "$CLAUDE" "$bdir/claude_settings.json"
  [ -f "$CODEX" ]  && cp "$CODEX"  "$bdir/codex_config.toml"
  [ -f "$QWEN" ]   && cp "$QWEN"   "$bdir/qwen_settings.json"
  echo "$ts" > "$BACKUP_ROOT/latest"
  echo "backed up -> $bdir"

  check_drift "$CLAUDE" "$LAST_APPLIED/claude_settings.json" "claude settings"
  check_drift "$QWEN"   "$LAST_APPLIED/qwen_settings.json"   "qwen settings"
  check_drift "$CODEX"  "$LAST_APPLIED/codex_config.toml"    "codex config"

  # success lines are printed ONLY after the edit is proven landed — a failed jq/toml edit
  # claiming success would leave the safety deny-rules unapplied while reporting them live
  local failed=0
  if [ -f "$CLAUDE" ]; then
    local tmp; tmp="$(mktemp)"
    if jq --argjson deny "$CLAUDE_DENY" --argjson allow "$CLAUDE_ALLOW" '
      .model = "opus"
      | .effortLevel = "xhigh"
      | .outputStyle = "Default"
      | .autoMemoryEnabled = false
      | .permissions = (.permissions // {})
      | .permissions.deny  = (((.permissions.deny  // []) + $deny)  | unique)
      | .permissions.allow = (((.permissions.allow // []) + $allow) | unique)
    ' "$CLAUDE" > "$tmp" && mv "$tmp" "$CLAUDE"; then
      echo "claude: model=opus effort=xhigh outputStyle=Default autoMemory=off; deny/allow merged"
      cp "$CLAUDE" "$LAST_APPLIED/claude_settings.json"
    else
      echo "claude: EDIT FAILED — config NOT changed (bad JSON?)" >&2; rm -f "$tmp"; failed=1
    fi
  fi

  if [ -f "$QWEN" ]; then
    local tmp; tmp="$(mktemp)"
    if jq '.thinking = "high" | (if has("telemetry") then .telemetry.enabled = false else . end)' \
      "$QWEN" > "$tmp" && mv "$tmp" "$QWEN"; then
      # MEASURE, don't assert. This line used to say "Trim QWEN.md — it was ~103k tokens"
      # unconditionally. That was true on 2026-08-15 and false by 2026-08-19, when the file was
      # ~5k tokens, so the tool spent four days telling him to redo work he had already done.
      # A hardcoded observation is a stale artifact being read as live state; measure it instead.
      qwen_md="$(dirname "$QWEN")/QWEN.md"
      if [ -f "$qwen_md" ]; then
        qmd_chars="$(wc -c < "$qwen_md" | tr -d ' ')"
        qmd_tok=$(( qmd_chars / 4 ))
        if [ "$qmd_tok" -gt 20000 ]; then
          echo "qwen: thinking=high, telemetry off. (QWEN.md is roughly $qmd_tok tokens — big enough to be worth trimming by hand.)"
        else
          echo "qwen: thinking=high, telemetry off. (QWEN.md ~$qmd_tok tokens — fine, nothing to trim.)"
        fi
      else
        echo "qwen: thinking=high, telemetry off."
      fi
      cp "$QWEN" "$LAST_APPLIED/qwen_settings.json"
    else
      echo "qwen: EDIT FAILED — config NOT changed (bad JSON?)" >&2; rm -f "$tmp"; failed=1
    fi
  fi

  if [ -f "$CODEX" ]; then
    if python3 "$HERE/toml_set.py" "$CODEX" \
      model_reasoning_effort=xhigh \
      plan_mode_reasoning_effort=xhigh \
      model_verbosity=low \
      personality=none \
      approval_policy=on-request \
      sandbox_mode=workspace-write \
      sandbox_workspace_write.network_access=false \
      features.hooks=true \
      features.memories=false; then
      echo "codex: effort=xhigh verbosity=low personality=none approval=on-request sandbox=workspace-write net=off hooks=on memories=off"
      cp "$CODEX" "$LAST_APPLIED/codex_config.toml"
    else
      echo "codex: EDIT FAILED — config NOT changed" >&2; failed=1
    fi
  fi
  if [ "$failed" -eq 0 ]; then
    echo "DONE. Review; 'harness-settings.sh undo' restores the backup above."
  else
    echo "INCOMPLETE — one or more configs were NOT changed (see errors above); backup at $bdir" >&2
    exit 1
  fi
}

undo() {
  echo "SCOPE: $SCOPE"
  local ts bdir; ts="$(cat "$BACKUP_ROOT/latest" 2>/dev/null || true)"
  [ -z "$ts" ] && { echo "no backup to undo"; exit 1; }
  bdir="$BACKUP_ROOT/$ts"
  # Clear the last-applied snapshots too — after an undo, "what we last set" is no longer
  # true (we just reverted it), so the next apply's drift check should have nothing stale
  # to compare against, not a snapshot describing a state that no longer exists.
  rm -rf "${BACKUP_ROOT:?}/last-applied"
  [ -f "$bdir/claude_settings.json" ] && cp "$bdir/claude_settings.json" "$CLAUDE" && echo "restored claude"
  [ -f "$bdir/codex_config.toml" ]    && cp "$bdir/codex_config.toml"    "$CODEX"  && echo "restored codex"
  [ -f "$bdir/qwen_settings.json" ]   && cp "$bdir/qwen_settings.json"   "$QWEN"   && echo "restored qwen"
  echo "undone from $bdir"
}

status() {
  warn_scope
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
  *) echo "usage: $0 apply|undo|status [--scope global|project] [--path DIR]  (--scope default: project; --path default: cwd's git root, else cwd)"; exit 1 ;;
esac
