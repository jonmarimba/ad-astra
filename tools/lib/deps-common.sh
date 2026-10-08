#!/usr/bin/env bash
# deps-common.sh — what every tool's deps.sh shares. Source it; it defines functions and runs nothing.
#
# A deps.sh brings a tool's software on THIS MACHINE up to date and does nothing else: it never writes
# into a repo and never touches a daemon, a schedule, or a signed app wrapper. Several installers also
# do those things (xcode-mcp-front reloads launchd jobs, agent-sync rewrites its schedule, handlebars
# builds an app whose permission grants a rebuild would destroy), which is why `astra upgrade` runs
# deps.sh and never install.sh.
export PATH="${ASTRA_PATH:-/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH}"
# Real brew autoremoves unneeded dependencies after any upgrade or uninstall, including orphans the machine's
# owner keeps and nothing here installed. No deps.sh may cause that, whichever way it calls brew.
export HOMEBREW_NO_AUTOREMOVE=1

# brewfile_upgrade <Brewfile>: install what the Brewfile lists, then upgrade those formulae.
brewfile_upgrade() {
  command -v brew >/dev/null || { echo "deps: FAIL: brew missing" >&2; return 69; }
  brew bundle --quiet --file="$1" || return $?
  local f
  # Two real-Homebrew habits, both found by running it: `bundle list` can print an "==> Auto-updating"
  # banner on stdout before the names, so keep only lines that look like a formula name; and `upgrade`
  # autoremoves unneeded dependencies, including ones nothing here installed (HOMEBREW_NO_AUTOREMOVE).
  for f in $(HOMEBREW_NO_AUTO_UPDATE=1 brew bundle list --formula --file="$1" 2>/dev/null | grep -E '^[A-Za-z0-9][A-Za-z0-9._@+/-]*$'); do
    HOMEBREW_NO_AUTOREMOVE=1 brew upgrade "$f" >/dev/null 2>&1 || true   # already current is not an error
  done
}
