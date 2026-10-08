#!/usr/bin/env bash
# TIER: slow — installs a real Homebrew into a mktemp directory and pulls real bottles over the network
# test-real-brew.sh — astra's Homebrew use, run against a REAL Homebrew installed in a mktemp directory.
#
# The throwaway machine in test-machine-lifecycle.sh uses a stand-in brew, which can only encode what we
# already know about brew. Two behaviors it did not have cost a real machine three formulae (a failed
# `brew uninstall` autoremoved unrelated orphans) and would have corrupted a formula list (an
# "==> Auto-updating" banner on stdout). This installs the genuine article under a temp directory,
# removes the real Homebrew from PATH, and checks the verbs astra's tools use, so those assumptions are
# facts about brew and not about a fake. The formulae are real ones that pour in any prefix (jq, uv,
# exiftool): bottles tied to /opt/homebrew (poppler, gettext, ffmpeg...) cannot be installed elsewhere.
#
# It needs the network (GitHub, ghcr.io) and says so loudly when it has none; it is a failure, not a skip.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
. "$ASTRA_ROOT/tools/tests/fakeworld/realbrew.sh"
need git "xcode-select --install"; need curl "ships with macOS"
curl -sfI -m 10 https://github.com >/dev/null 2>&1 || { fail "no network: this test installs a real Homebrew from github.com"; finish; exit 1; }
[ -x /opt/homebrew/bin/brew ] || { fail "needs a Homebrew on this machine to borrow its portable Ruby: /opt/homebrew/bin/brew"; finish; exit 1; }

D="$SB/hb"; mkdir -p "$D"
realbrew_build "$D" || { fail "could not install Homebrew into $D"; finish; exit 1; }
BREW="$RB_PREFIX/bin/brew"
export ASTRA_PATH; ASTRA_PATH="$(realbrew_path)"
rb() { realbrew_run "$@"; }

echo "== a real Homebrew, in a temp directory, and the real one is out of the way"
assert_eq "$RB_PREFIX" "$(rb --prefix | sed 's#^/private##')" "brew's prefix is the temp directory"
assert_eq "$BREW" "$(env PATH="$ASTRA_PATH" sh -c 'command -v brew')" "the temp brew is the one PATH finds"
assert_eq "" "$(env PATH="$ASTRA_PATH" sh -c 'command -v ffmpeg axe periphery' 2>/dev/null)" "nothing installed under /opt/homebrew is visible"

echo "== the verbs astra's tools use, against the real thing"
rb install jq > "$SB/i1.out" 2>&1; assert_eq 0 "$?" "brew install jq"
assert_eq 1 "$(realbrew_installed jq && echo 1)" "jq is in the temp Cellar"
assert_eq 1 "$(realbrew_installed oniguruma && echo 1)" "and so is its dependency"
assert_eq "jq-1.8" "$("$RB_PREFIX/bin/jq" --version | cut -c1-6)" "the installed jq runs"
rb install jq > "$SB/i2.out" 2>&1; assert_eq 0 "$?" "installing again exits 0, as the fake assumes"
assert_contains "$SB/i2.out" "already installed" "and says so"
rb upgrade jq > "$SB/u1.out" 2>&1; assert_eq 0 "$?" "upgrading a current formula exits 0"
assert_contains "$SB/u1.out" "already installed" "and says so"
rb upgrade no-such-formula-xyz > /dev/null 2>&1; assert_eq 1 "$?" "upgrading something that does not exist exits 1"
rb uninstall no-such-formula-xyz > /dev/null 2>&1; assert_eq 1 "$?" "so does uninstalling it"
# `bundle list` output, with auto-update ON: the case that printed a banner on the real machine
printf 'brew "jq"\nbrew "uv"\nbrew "exiftool"\n' > "$SB/Brewfile"
env $(realbrew_env | sed 's/HOMEBREW_NO_AUTO_UPDATE=1//') PATH="$ASTRA_PATH" "$BREW" bundle list --formula --file="$SB/Brewfile" > "$SB/bl.out" 2>/dev/null
assert_eq "exiftool jq uv" "$(grep -E '^[A-Za-z0-9][A-Za-z0-9._@+/-]*$' "$SB/bl.out" | sort | tr '\n' ' ' | sed 's/ $//')" "bundle list names the formulae (the banner filter keeps exactly the names)"

echo "== astra's brewfile_upgrade, on the real brew"
. "$ASTRA_ROOT/tools/lib/deps-common.sh"
export HOME="$RB_HOME" HOMEBREW_CACHE="$D/cache" HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_AVOID_NESTED_SANDBOXING=1
PATH="$ASTRA_PATH"
brewfile_upgrade "$SB/Brewfile" > "$SB/bu1.out" 2>&1; assert_eq 0 "$?" "brewfile_upgrade installs a Brewfile on an empty brew"
for f in jq uv exiftool; do assert_eq 1 "$(realbrew_installed $f && echo 1)" "$f arrived"; done
brewfile_upgrade "$SB/Brewfile" > "$SB/bu2.out" 2>&1; assert_eq 0 "$?" "running it again succeeds (everything current)"

echo "== an unrelated orphan survives an upgrade and an uninstall, because of the guard"
# Make a real orphan: a formula installed only as a dependency, with nothing left that needs it.
rb uninstall --ignore-dependencies jq > /dev/null 2>&1
assert_eq 1 "$(realbrew_installed oniguruma && echo 1)" "oniguruma is now an orphaned dependency (nothing needs it)"
. "$ASTRA_ROOT/tools/lib/uninstall-common.sh"
UNINSTALL_DEPS=1; BREW_BIN="$BREW"
uc_brew uv "test" > "$SB/uc.out" 2>&1
assert_eq "" "$(realbrew_installed uv && echo 1)" "uninstall --deps removed uv"
assert_eq 1 "$(realbrew_installed oniguruma && echo 1)" "and left the unrelated orphan alone"
# RED control: the same uninstall WITHOUT the guard removes it, which is the damage that happened on the real machine
env -u HOMEBREW_NO_AUTOREMOVE $(realbrew_env) PATH="$ASTRA_PATH" "$BREW" install uv > /dev/null 2>&1
env -u HOMEBREW_NO_AUTOREMOVE $(realbrew_env) PATH="$ASTRA_PATH" "$BREW" uninstall uv > "$SB/raw.out" 2>&1
assert_contains "$SB/raw.out" "Autoremoving" "RED: a bare brew uninstall autoremoves unneeded formulae"
assert_eq "" "$(realbrew_installed oniguruma && echo 1)" "RED: and it took the unrelated orphan with it, so the guard is what protected it"

echo "== the real Homebrew on this machine was never used"
assert_eq "" "$(grep -l "$D" /opt/homebrew/var/log/* 2>/dev/null)" "(nothing in the real Homebrew's logs mentions the temp prefix)"
finish
