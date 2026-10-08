#!/usr/bin/env bash
# test-installers-which-first.sh — the anti-double-copy contract, run for real: on a machine
# where the tools exist, every installer must detect them ("already installed") and invoke
# NO package manager for them. This is the exact regression that bit on 2026-08-12 (a
# Brewfile that would have installed brew copies of npm-installed claude/codex).
# NOT covered here: the absent-tool branch (would really install software on this machine)
# and pdf-sidecars/install.sh (unconditionally runs `uv tool install marker-pdf` — a
# mutating step with no which-first gate; run it by hand, not from a test).
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
need claude "npm install -g @anthropic-ai/claude-code"
need codex "npm install -g @openai/codex"
need qwen "brew install qwen-code"
need periphery "brew install periphery"

# ---- convocation: all three agents detected, zero installs, no shadow copies ----
out="$("$HERE/../convocation/install.sh" 2>&1)"; rc=$?
assert_eq "0" "$rc" "convocation install exits 0"
for b in claude codex qwen; do
  printf '%s\n' "$out" | grep -q "already installed: $b" && pass "convocation: $b detected, not reinstalled" || fail "convocation: no 'already installed' for $b"
done
printf '%s\n' "$out" | grep -q "installing" && fail "convocation: an install step ran despite tools being present" || pass "convocation: no package manager invoked"
printf '%s\n' "$out" | grep -q "WARNING" && fail "convocation: shadow copies present on this machine (resolve!)" || pass "convocation: exactly one copy of each agent"

# ---- periphery: detected, brew not invoked ----
out="$("$HERE/../periphery/install.sh" 2>&1)"; rc=$?
assert_eq "0" "$rc" "periphery install exits 0"
printf '%s\n' "$out" | grep -q "already installed: periphery" && pass "periphery detected, brew bundle skipped" || fail "periphery: no 'already installed' line"

# ---- ponytail: installs the vendored skills into a temp repo, idempotent second run ----
# This block called ponytail/install-into-repo.sh, which the 2026-10-04 move to the shared
# astra_place pattern removed, so it failed with rc=127 ("not found") ever since. The skills
# are vendored now and nothing is fetched, so idempotent means the second run succeeds and
# leaves every installed byte as it was.
REPO="$SB/repo"; mkdir -p "$REPO"; git -C "$REPO" init -q
assert_rc 0 "ponytail installs into a repo" "$HERE/../ponytail/install.sh" --into "$REPO"
assert_file "$REPO/.claude/skills/ponytail/SKILL.md" "ponytail skill landed"
assert_file "$REPO/.claude/skills/ponytail-audit/SKILL.md" "ponytail-audit skill landed"
assert_contains "$REPO/.claude/skills/ponytail/SKILL.md" "name:" "skill has frontmatter (not an error page)"
before="$(cd "$REPO" && find .claude -type f -exec shasum {} + | sort)"
assert_rc 0 "ponytail re-run succeeds" "$HERE/../ponytail/install.sh" --into "$REPO"
after="$(cd "$REPO" && find .claude -type f -exec shasum {} + | sort)"
assert_eq "$before" "$after" "second run leaves every installed file byte-identical"

# ---- RED controls ----
red "ponytail without --into must fail" 64 "usage: --into" "$HERE/../ponytail/install.sh"

finish
