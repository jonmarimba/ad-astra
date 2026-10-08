#!/usr/bin/env bash
# test-tool-kinds.sh — every directory under tools/ declares what kind of tool it is, and keeps the
# promises that kind makes.
#
# Three kinds, because three different things can happen when someone asks for a tool:
#   repo, repo-config   install.sh (`# astra-scope: repo` or `repo-config` in its first five lines)
#                       plus an uninstall.sh that undoes it inside a repo.
#   machine             install.sh (`# astra-scope: machine`) plus an uninstall.sh. It changes the
#                       machine, so a repo install never runs it and its uninstall keeps shared
#                       software unless told otherwise.
#   run-in-place        no install.sh; a RUN-IN-PLACE file whose one line says why nothing needs
#                       installing. The tool runs from the checkout.
# A tool that is none of these, or that claims to install and has no way to undo it, fails here.
# Found 2026-10-08: axe had no uninstaller, drew-kit's installer had a different name from every
# other tool's, and eight tools declared nothing at all, so nothing could say which were meant to be
# scripts and which had lost their installer.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$ASTRA_ROOT/tools" || exit 1

# `check <dir>` prints a problem, or nothing when the directory is in order.
check() {
  local t="$1" scope
  # lib, tests and the template data are infrastructure, not tools.
  case "$t" in lib|tests|tool-templates) return ;; esac
  if [ -f "$t/install.sh" ]; then
    [ ! -f "$t/RUN-IN-PLACE" ] || { echo "$t: has both install.sh and RUN-IN-PLACE"; return; }
    scope="$(head -n 5 "$t/install.sh" | sed -n 's/^# astra-scope: *//p' | head -n 1)"
    case "$scope" in
      repo|repo-config|machine) ;;
      *) echo "$t: install.sh declares scope '${scope:-nothing}'; want repo, repo-config or machine"; return ;;
    esac
    [ -f "$t/uninstall.sh" ] || echo "$t: install.sh but no uninstall.sh"
    # A machine tool owns software, so it has a deps.sh for `astra upgrade` to refresh, or it says why
    # not with a `# no-deps:` line.
    if [ "$scope" = machine ] && [ ! -f "$t/deps.sh" ] && ! head -n 6 "$t/install.sh" | grep -q '^# no-deps:'; then
      echo "$t: machine scope but no deps.sh and no '# no-deps: <why>' line"
    fi
    if [ -f "$t/deps.sh" ]; then
      [ -x "$t/deps.sh" ] || echo "$t: deps.sh is not executable"
      # deps.sh refreshes software and nothing else; these are the things an upgrade must never do
      if grep -nE 'launchd-install|launchctl|wrap-in-app|astra_place|--into' "$t/deps.sh" | grep -v '^[0-9]*:[[:space:]]*#' | grep -q .; then
        echo "$t: deps.sh touches a daemon, a wrapper app or a repo; an upgrade may only refresh software"
      fi
    fi
  elif [ -f "$t/RUN-IN-PLACE" ]; then
    [ -s "$t/RUN-IN-PLACE" ] || echo "$t: RUN-IN-PLACE is empty; say why nothing needs installing"
    [ ! -f "$t/uninstall.sh" ] || echo "$t: RUN-IN-PLACE but also an uninstall.sh"
  else
    echo "$t: no install.sh and no RUN-IN-PLACE; declare which kind of tool this is"
  fi
}

echo "== RED controls: the check must see each kind of mistake"
P="$SB/tools"; mkdir -p "$P"
cd "$P" || exit 1
mkdir undeclared; mkdir noundo; printf '#!/bin/sh\n# astra-scope: repo\n' > noundo/install.sh
mkdir badscope; printf '#!/bin/sh\n# astra-scope: sometimes\n' > badscope/install.sh; : > badscope/uninstall.sh
mkdir both; printf '#!/bin/sh\n# astra-scope: repo\n' > both/install.sh; : > both/uninstall.sh; echo why > both/RUN-IN-PLACE
mkdir emptyreason; : > emptyreason/RUN-IN-PLACE
mkdir good; printf '#!/bin/sh\n# astra-scope: machine\n' > good/install.sh; : > good/uninstall.sh; printf '#!/bin/sh\n' > good/deps.sh; chmod +x good/deps.sh
mkdir script; echo "runs from the checkout" > script/RUN-IN-PLACE
mkdir nodeps; printf '#!/bin/sh\n# astra-scope: machine\n' > nodeps/install.sh; : > nodeps/uninstall.sh
mkdir whynot; printf '#!/bin/sh\n# astra-scope: machine\n# no-deps: it owns no software\n' > whynot/install.sh; : > whynot/uninstall.sh
mkdir daemondeps; printf '#!/bin/sh\n# astra-scope: machine\n' > daemondeps/install.sh; : > daemondeps/uninstall.sh
printf '#!/bin/sh\n"$(dirname "$0")/xcode-mcp-front" launchd-install\n' > daemondeps/deps.sh; chmod +x daemondeps/deps.sh
mkdir notexec; printf '#!/bin/sh\n# astra-scope: machine\n' > notexec/install.sh; : > notexec/uninstall.sh; : > notexec/deps.sh
for t in undeclared noundo badscope both emptyreason nodeps daemondeps notexec; do
  assert_nonempty "$(check "$t")" "RED: '$t' is reported"
done
assert_empty "$(check good)" "a declared machine tool with an uninstaller passes"
assert_empty "$(check script)" "a run-in-place tool with a reason passes"
assert_empty "$(check whynot)" "a machine tool that says why it has no deps.sh passes"

echo "== every tool in the tree"
cd "$ASTRA_ROOT/tools" || exit 1
problems=""
for d in */; do problems="$problems$(check "${d%/}")"$'\n'; done
problems="$(printf '%s' "$problems" | sed '/^$/d')"
assert_empty "$problems" "every directory under tools/ is a declared kind and keeps its promises"
[ -z "$problems" ] || printf '%s\n' "$problems" | sed 's/^/        /'
finish
