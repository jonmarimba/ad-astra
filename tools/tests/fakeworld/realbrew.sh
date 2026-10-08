#!/usr/bin/env bash
# fakeworld/realbrew.sh — a REAL Homebrew, installed into a mktemp directory and used from there.
# Source this file; it defines functions only.
#
#   realbrew_build <dir>     install Homebrew into <dir>/homebrew the documented way for any directory:
#                            git clone https://github.com/Homebrew/brew. Nothing is installed in it yet.
#   realbrew_path            the PATH to use: the current PATH minus the real Homebrew directories, plus the
#                            temp prefix's bin and sbin first. Formulae then come from the real network,
#                            exactly as `brew install` normally pulls them, and land only under <dir>.
#   realbrew_run <args>      run the temp brew
#   realbrew_installed <f>   true when the formula is in the temp Cellar
#   realbrew_version <f>     its installed version
#
# The real Homebrew is never touched: the temp brew has its own prefix, Cellar, taps and cache, and HOME is a
# directory under <dir>. Bottles install in another prefix only when they are relocatable; anything else builds
# from source, so tests should pick small, relocatable formulae.
#
# HOMEBREW_AVOID_NESTED_SANDBOXING: when this runs inside another macOS sandbox (an agent's shell, say),
# Homebrew refuses to nest its build sandbox ("Inherited sandbox permits writes to .../bin/brew") and fails
# every install. This is Homebrew's own switch for exactly that case: an unprivileged user, a prefix outside
# the default one.

realbrew_build() {
  RB_DIR="$1"; RB_PREFIX="$RB_DIR/homebrew"; RB_HOME="$RB_DIR/home"
  mkdir -p "$RB_HOME"
  git clone --depth 1 -q https://github.com/Homebrew/brew "$RB_PREFIX" || return 1
  return 0
}

realbrew_path() {  # current PATH, minus the real Homebrew, plus the temp one first
  local out="$RB_PREFIX/bin:$RB_PREFIX/sbin" d IFS=:
  for d in $PATH; do
    case "$d" in /opt/homebrew|/opt/homebrew/*|/usr/local/bin|/usr/local/sbin|/usr/local/opt/*) continue ;; esac   # all of the real Homebrew, opt/ and cellar paths included
    out="$out:$d"
  done
  echo "$out"
}

# the environment brew needs inside the world: its own HOME and cache, no analytics or hints
realbrew_env() {
  echo "HOME=$RB_HOME HOMEBREW_CACHE=$RB_DIR/cache HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_EMOJI=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_AVOID_NESTED_SANDBOXING=1"
}

realbrew_run() {
  env $(realbrew_env) PATH="$(realbrew_path)" "$RB_PREFIX/bin/brew" "$@"
}

realbrew_installed() { [ -d "$RB_PREFIX/Cellar/$1" ] && [ -n "$(ls "$RB_PREFIX/Cellar/$1" 2>/dev/null)" ]; }
realbrew_version() { ls "$RB_PREFIX/Cellar/$1" 2>/dev/null | sort | tail -n 1; }
