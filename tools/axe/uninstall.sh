#!/usr/bin/env bash
# uninstall.sh — dis-integrate axe (the AXe iOS-simulator accessibility CLI). It keeps no state and
# writes nothing into any repo, so the only artifact is the brew formula from cameroncooke's tap.
# Like every machine-scope tool it keeps the formula unless --deps is given, because other repos on
# this machine may be driving the simulator with it.
#
# --into <repo> is accepted for uniformity with install.sh and ignored: there is nothing in the repo.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/uninstall-common.sh"
# Pull --into <repo> out FIRST: the shared uc_parse rejects unknown flags.
REST=(); want_into=0
for a in "$@"; do
  if [ "$want_into" = 1 ]; then want_into=0; continue; fi
  if [ "$a" = "--into" ]; then want_into=1; continue; fi
  REST+=("$a")
done
uc_parse ${REST[@]+"${REST[@]}"}
echo "axe dis-integrate:"
echo "  axe keeps no global state and writes nothing into a repo."
uc_brew cameroncooke/axe/axe "AXe, the simulator accessibility CLI the ios-ui-driving skill drives"
echo "done."
