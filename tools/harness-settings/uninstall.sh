#!/usr/bin/env bash
# uninstall.sh — harness-settings EDITS your agent config files rather than installing a tool, so
# "uninstall" means REVERT those edits — which only you can safely decide. This prints the files it
# touched and where the backups are, WITHOUT auto-restoring (a wrong restore is worse than none) and
# WITHOUT deleting backups (they are how you revert). --deps removes jq + tomlkit.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/uninstall-common.sh"
uc_parse "$@"
BK="${HARNESS_BACKUP_ROOT:-$HOME/.harness-settings-backups}"
echo "harness-settings dis-integrate:"
uc_warn "harness-settings edited these files — revert them from a backup if you want the old values:" \
        "$HOME/.claude/settings.json" "$HOME/.codex/config.toml" "$HOME/.qwen/settings.json"
if [ -d "$BK" ]; then
  latest="$(ls -1t "$BK" 2>/dev/null | head -1)"
  echo "  backups live at: $BK  (newest: ${latest:-none})"
  echo "  to restore, e.g.:  cp \"$BK/$latest/settings.json\" \"$HOME/.claude/settings.json\""
else
  echo "  (no backup dir at $BK — nothing to restore from)"
fi
echo "  KEEPING backups (deleting them would destroy your ability to revert)."
uc_brew jq "widely-used JSON processor"
if [ "${UNINSTALL_DEPS:-0}" = 1 ]; then
  uc_warn "removing pip user package 'tomlkit'"
  "${PYTHON_BIN:-python3}" -m pip uninstall -y tomlkit || echo "  (tomlkit uninstall failed or already gone)"
else
  echo "  KEEPING pip package 'tomlkit'. Remove with --deps, or: python3 -m pip uninstall tomlkit"
fi
uc_keep "python@3.12" "foundational Python runtime"
echo "done."
