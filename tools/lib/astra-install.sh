#!/usr/bin/env bash
# astra-install.sh — the one place that decides WHERE an astra tool lands in a
# repo and what it records about itself. Every tool's install.sh sources this.
#
# WHY THIS EXISTS (Jonathan, 2026-08-18)
# --------------------------------------
# The first design copied tools into whatever directory each repo happened to
# use — 13_Scripts, scripts, tools, pdf, one repo's root — and then kept a
# central list in astra of where everything went. That list was built by
# matching FILENAMES across the workspace, which meant any repo's own
# rules.json or lib.sh was adopted as an astra install and overwritten by a
# post-commit hook. Ownership was inferred, and inference is a guess.
#
# Two corrections, both his:
#
#   "Why wouldn't you be writing someplace you know isn't going to be touched?
#    like .astra or whatever?"
#
# Everything lands in <repo>/.astra/<tool>/. Ownership stops being a guess and
# becomes a fact: if it is in there, it is ours, and nothing else is. The
# collision bug cannot occur rather than being guarded against.
#
#   "probably worth each .astra able to find where it was installed FROM and
#    check for updates?"
#
# So the direction of the relationship flips. Astra no longer pushes into
# repos it keeps a list of; each repo records where it was installed from and
# pulls. That removes the blast radius entirely — nothing reaches into another
# repo uninvited — and it survives the repo being cloned or moved, which a
# central list of absolute paths does not.
#
# Usage from a tool's install.sh:
#     . "$(dirname "$0")/../lib/astra-install.sh"
#     astra_target "$@"                 # parses --into, validates, sets $TARGET
#     astra_place check-prose check-prose.js rules.json
#
set -euo pipefail

ASTRA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

# Parse --into and refuse anywhere that is not a project checkout. Global
# installs were removed on 2026-08-18 and nothing here may recreate one.
astra_target() {
  TARGET=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --into) TARGET="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  [ -n "$TARGET" ] || { echo "usage: --into <repo>" >&2; exit 64; }
  [ -d "$TARGET" ] || { echo "no such directory: $TARGET" >&2; exit 66; }
  # -P resolves symlinks: js-hoa and js-speedway are symlinks into Dropbox.
  TARGET="$(cd "$TARGET" && pwd -P)"
  case "$TARGET" in
    "$HOME"|"$HOME/.claude"*|"$HOME/.agents"*|"$HOME/.config"*|"$HOME/Library"*)
      echo "REFUSING: $TARGET is a home/global location." >&2
      echo "  Astra tools install per-repo only." >&2
      exit 78 ;;
  esac
  export TARGET
}

# Every function below delegates to astra_manifest.py, the one writer of a
# repo's install state (2026-10-04). Before that, this file, install-doctrine.sh
# and a dozen hand-rolled installers each wrote the manifest their own way, or
# not at all, and only one of them wired the updater hook.
ASTRA_MANIFEST_PY="$ASTRA_ROOT/tools/lib/astra_manifest.py"

# Copy a tool's files into <repo>/.astra/<tool>/ and record them.
#     astra_place check-prose check-prose.js rules.json
astra_place() {
  local tool="$1"; shift
  local pairs=() f
  for f in "$@"; do pairs+=("tools/$tool/$f:.astra/$tool/$f"); done
  python3 "$ASTRA_MANIFEST_PY" place "$TARGET" "$tool" "${pairs[@]}"
  python3 "$ASTRA_MANIFEST_PY" finish "$TARGET"
  echo "installed $tool -> $TARGET/.astra/$tool"
}

# Copy files to explicit places in the repo and record them. Each argument is
# <path relative to astra>:<path relative to the repo>. For a skill under
# .claude/skills/ or anything else that cannot live in .astra/.
#     astra_place_at asd-ste100 agents-and-prompts/skills/asd-ste100/SKILL.md:.claude/skills/asd-ste100/SKILL.md
astra_place_at() {
  local tool="$1"; shift
  python3 "$ASTRA_MANIFEST_PY" place "$TARGET" "$tool" "$@"
  python3 "$ASTRA_MANIFEST_PY" finish "$TARGET"
  echo "installed $tool -> $TARGET"
}

# Remove a tool's recorded files and its manifest entry. Once the entry is gone,
# no automatic update can bring the tool back. Removing the last tool also
# removes the updater, its hooks and its ignore rule.
astra_remove() {
  python3 "$ASTRA_MANIFEST_PY" unplace "$TARGET" "$1"
  python3 "$ASTRA_MANIFEST_PY" finish "$TARGET"
}
