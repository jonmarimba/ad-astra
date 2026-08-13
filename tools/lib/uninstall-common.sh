#!/usr/bin/env bash
# uninstall-common.sh — shared dis-integration helpers for @astra tools. Source it from a tool's
# uninstall.sh:  . "$(dirname "$0")/../lib/uninstall-common.sh"
#
# The contract (Jonathan, 2026-08-13): "anything installing needs to uninstall, too — but not
# necessarily the brew stuff; that should be an option. Uninstall dis-integrates and OPTIONALLY
# uninstalls deps with big loud warnings."
#
#   plain uninstall            → remove the tool's OWN local state (config/caches/symlinks). Deps
#                                are LEFT ALONE; the tool prints the exact command to remove each.
#   uninstall --deps           → also remove the shared deps, each behind a loud banner, because a
#                                brew formula / uv tool is very likely used by OTHER tools too.
#
# Shared-dep removal runs through $BREW_BIN / $UV_BIN seams so a test can point them at a stub and
# assert what WOULD be removed without touching the real toolchain — same seam pattern as install.
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"
BREW_BIN="${BREW_BIN:-brew}"
UV_BIN="${UV_BIN:-uv}"
UNINSTALL_DEPS=0

_uc_hr(){ printf '  %s\n' "============================================================"; }
uc_warn(){ _uc_hr; for line in "$@"; do printf '  ⚠️  %s\n' "$line"; done; _uc_hr; }

uc_parse(){ # read flags an uninstaller shares; call once with "$@"
  for a in "$@"; do case "$a" in
    --deps) UNINSTALL_DEPS=1 ;;
    --help|-h) echo "usage: uninstall.sh [--deps]   (--deps also removes shared brew/uv deps, loudly)"; exit 0 ;;
    --*) echo "unknown flag '$a'" >&2; exit 64 ;;
  esac; done
}

uc_rm_state(){ # usage: uc_rm_state <path> "<human description>"
  if [ -e "$1" ]; then echo "  removing $2: $1"; rm -rf "$1"
  else echo "  (nothing to remove: no $2 at $1)"; fi
}

uc_rm_symlink(){ # remove a symlink ONLY if it points into this tool — never a real file
  if [ -L "$1" ]; then echo "  removing symlink: $1 -> $(readlink "$1")"; rm -f "$1"
  elif [ -e "$1" ]; then echo "  KEEPING $1 (not a symlink — left untouched)"
  else echo "  (no symlink at $1)"; fi
}

uc_brew(){ # usage: uc_brew <formula> "<why it's shared / what may break>"
  if [ "$UNINSTALL_DEPS" = 1 ]; then
    uc_warn "removing shared brew dep '$1'" "$2" "Other tools on this machine may rely on it."
    "$BREW_BIN" uninstall "$1" || echo "  ($BREW_BIN uninstall $1 failed or it was already gone)"
  else
    echo "  KEEPING shared dep '$1' (brew). To remove it too, re-run with --deps, or:  $BREW_BIN uninstall $1"
  fi
}

uc_keep(){ # a dep we NEVER auto-remove even with --deps (foundational runtimes, or the user's own
           # primary tools). usage: uc_keep <name> "<what it is / why kept>"
  echo "  NOT removing '$1' — $2. Left in place; remove by hand only if you are certain."
}

uc_uv_tool(){ # usage: uc_uv_tool <tool> "<why it's shared>"
  if [ "$UNINSTALL_DEPS" = 1 ]; then
    uc_warn "removing shared uv tool '$1'" "$2" "Other tools on this machine may rely on it."
    "$UV_BIN" tool uninstall "$1" || echo "  ($UV_BIN tool uninstall $1 failed or it was already gone)"
  else
    echo "  KEEPING shared uv tool '$1'. To remove it too, re-run with --deps, or:  $UV_BIN tool uninstall $1"
  fi
}
