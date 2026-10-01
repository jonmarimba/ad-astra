#!/usr/bin/env bash
# install.sh — periphery (Swift dead-code scanner). Which-first: never a second copy.
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
# periphery is machine-wide (a brew formula), so --into <repo> is ACCEPTED and ignored
# rather than rejected: template.py invokes every member as `install.sh --into <repo>`,
# and a member that chokes on the contract breaks the template (adversarial round: the
# mirror-image on uninstall left swift-ios half-removed and the manifest lying).
while [ $# -gt 0 ]; do case "$1" in --into) shift 2 ;; *) shift ;; esac; done
if p="$(command -v periphery 2>/dev/null)"; then
  echo "already installed: periphery -> $p $( [ -L "$p" ] && echo "-> $(readlink "$p")" )"
else
  brew bundle --file="$HERE/Brewfile"
fi
periphery version
