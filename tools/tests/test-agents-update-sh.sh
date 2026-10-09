#!/usr/bin/env bash
# test-agents-update-sh.sh — agents-and-prompts/update.sh regenerates AGENTS.md in place and does NOT
# touch the user's global ~/.claude/CLAUDE.md or ~/.codex/AGENTS.md unless asked with --to-home
# (it used to overwrite both on every `make`, which broke the rule that astra never installs globally).
#
# The real script runs from a COPY of agents-and-prompts in a sandbox with HOME redirected.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

export HOME="$SB/home"; mkdir -p "$HOME/.claude" "$HOME/.codex"
printf 'MY OWN GLOBAL FILE\n' > "$HOME/.claude/CLAUDE.md"
printf 'MY OWN CODEX FILE\n' > "$HOME/.codex/AGENTS.md"
cp -R "$ASTRA_ROOT/agents-and-prompts" "$SB/ap"
UP="$SB/ap/update.sh"

echo "== the default run"
bash "$UP" > "$SB/default.out" 2>&1
assert_eq 0 "$?" "update.sh succeeds"
assert_contains "$SB/ap/AGENTS.md" "@$SB/ap/components/" "it writes AGENTS.md with references into the copy it ran in"
assert_eq "MY OWN GLOBAL FILE" "$(cat "$HOME/.claude/CLAUDE.md")" "RED: ~/.claude/CLAUDE.md is untouched"
assert_eq "MY OWN CODEX FILE" "$(cat "$HOME/.codex/AGENTS.md")" "RED: ~/.codex/AGENTS.md is untouched"

echo "== --to-home"
bash "$UP" --to-home > "$SB/home.out" 2>&1
assert_eq 0 "$?" "update.sh --to-home succeeds"
assert_contains "$HOME/.claude/CLAUDE.md" "Important references" "the global file now holds the references"
assert_eq "MY OWN GLOBAL FILE" "$(cat "$HOME/.claude/CLAUDE.md.before-update")" "and the previous content was saved first"
assert_eq "MY OWN CODEX FILE" "$(cat "$HOME/.codex/AGENTS.md.before-update")" "for the Codex file too"

echo "== a typo'd flag"
bash "$UP" --to-hom > "$SB/typo.out" 2>&1
assert_eq 64 "$?" "RED: an unknown flag exits 64 and writes nothing global"
finish
