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

# ---- ponytail: real fetch into a temp repo, idempotent second run ----
REPO="$SB/repo"; mkdir -p "$REPO"
assert_rc 0 "ponytail installs into a repo" "$HERE/../ponytail/install-into-repo.sh" "$REPO"
assert_file "$REPO/.claude/skills/ponytail/SKILL.md" "ponytail skill landed"
assert_file "$REPO/.claude/skills/ponytail-audit/SKILL.md" "ponytail-audit skill landed"
assert_contains "$REPO/.claude/skills/ponytail/SKILL.md" "name:" "skill has frontmatter (not an error page)"
out="$("$HERE/../ponytail/install-into-repo.sh" "$REPO" 2>&1)"
printf '%s\n' "$out" | grep -c "already installed" | grep -q "^2$" && pass "second run: both skills detected, nothing re-fetched" || fail "ponytail re-run not idempotent"

# ---- RED controls ----
red "ponytail without a repo arg must fail" 1 "usage: install-into-repo.sh" "$HERE/../ponytail/install-into-repo.sh"

finish
