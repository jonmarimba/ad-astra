#!/usr/bin/env bash
# deps.sh — the software the ios-simulator server needs on this machine: idb-companion (the daemon)
# and fb-idb (the `idb` CLI the server spawns). `astra upgrade` runs it; install.sh runs it first.
# Without both, the config installs fine and every interaction tool dies with `spawn idb ENOENT`
# (found live in pot-mhm, 2026-09-01). pipx installs to ~/.local/bin, which GUI-spawned servers may
# not have on PATH, so the CLI is also linked into Homebrew's bin.
set -euo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
command -v brew >/dev/null || { echo "ios-simulator: FAIL: brew missing" >&2; exit 69; }
if ! command -v idb_companion >/dev/null; then
  echo "ios-simulator: installing idb-companion (interaction tools need it)"
  brew install facebook/fb/idb-companion || { echo "ios-simulator: FAIL: brew install facebook/fb/idb-companion" >&2; exit 69; }
fi
if ! command -v idb >/dev/null; then
  command -v pipx >/dev/null || { echo "ios-simulator: FAIL: pipx missing. brew install pipx" >&2; exit 69; }
  echo "ios-simulator: installing fb-idb (the idb CLI the server spawns)"
  pipx install fb-idb || { echo "ios-simulator: FAIL: pipx install fb-idb" >&2; exit 69; }
else
  pipx upgrade fb-idb >/dev/null 2>&1 || true
fi
BREW_BIN_DIR="$(brew --prefix)/bin"   # /opt/homebrew on Apple Silicon, /usr/local on Intel
[ -x "$BREW_BIN_DIR/idb" ] || ln -sf "$(command -v idb)" "$BREW_BIN_DIR/idb"
