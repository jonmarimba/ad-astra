#!/usr/bin/env bash
# test-panel.sh — panel fans one task file out to each requested agent binary, captures
# per-agent stdout/stderr, and FAILS LOUDLY when a requested agent can't run (a convocation
# missing a voice is not a convocation — silent-skip is the no-silent-pass class).
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
PANEL="$HERE/../convocation/panel"

mkdir -p "$SB/bin"
cat > "$SB/bin/fake-claude" <<'SHIM'
#!/usr/bin/env bash
# mimics `claude -p "prompt"`: prompt arrives as $2
echo "CLAUDE-ANSWER to: $2"
SHIM
cat > "$SB/bin/fake-codex" <<'SHIM'
#!/usr/bin/env bash
# mimics `codex exec --skip-git-repo-check "prompt"`: prompt arrives as $3
echo "CODEX-ANSWER to: $3"
SHIM
cat > "$SB/bin/fake-qwen" <<'SHIM'
#!/usr/bin/env bash
# mimics `qwen -m MODEL -y -p "prompt"`: prompt arrives as $5. It must echo the prompt back,
# because panel preflights qwen by asking it to reply READY and greps for it — a stub that
# echoed its model name instead failed that probe and took five unrelated assertions with it.
echo "QWEN-ANSWER to: $5"
SHIM
chmod +x "$SB/bin/"*

echo "What is the airspeed velocity of an unladen swallow?" > "$SB/task.md"

# ---- fan-out: each agent's real stdout lands in its own tagged file ----
export CLAUDE_BIN="$SB/bin/fake-claude" CODEX_BIN="$SB/bin/fake-codex" QWEN_BIN="$SB/bin/fake-qwen"
assert_rc 0 "fan-out to three agents succeeds" "$PANEL" "$SB/task.md" --out "$SB/out" --agents claude,codex,qwen --tag r1
assert_file "$SB/out/r1_claude.md" "claude output file written"
assert_file "$SB/out/r1_codex.md" "codex output file written"
assert_file "$SB/out/r1_qwen.md" "qwen output file written"
assert_contains "$SB/out/r1_claude.md" "CLAUDE-ANSWER to: What is the airspeed velocity" "claude got the task content as its prompt"
assert_contains "$SB/out/r1_codex.md" "CODEX-ANSWER to: What is the airspeed velocity" "codex invoked through its exec form"

# ---- isolation: agent stderr goes to the .err sidecar, not into the answer ----
cat > "$SB/bin/noisy" <<'SHIM'
#!/usr/bin/env bash
echo "the answer" ; echo "warning: noise" >&2
SHIM
chmod +x "$SB/bin/noisy"
CLAUDE_BIN="$SB/bin/noisy" "$PANEL" "$SB/task.md" --out "$SB/out2" --agents claude --tag r1 >/dev/null 2>&1
assert_not_contains "$SB/out2/r1_claude.md" "warning: noise" "stderr kept out of the answer file"
assert_contains "$SB/out2/r1_claude.md.err" "warning: noise" "stderr captured in the .err sidecar"

# ---- RED controls: a requested agent that can't run must be a loud failure ----
red "requested agent with missing binary must fail (no silent skip)" env CLAUDE_BIN="$SB/bin/does-not-exist" "$PANEL" "$SB/task.md" --out "$SB/out3" --agents claude --tag r1
red "unknown agent name must fail" "$PANEL" "$SB/task.md" --out "$SB/out4" --agents gemini --tag r1
# the sharp case: ONE good voice + one bad — a lazy implementation runs the good one and calls
# it success; a convocation must refuse to run short-handed, and launch NOTHING
red "good agent + unknown agent must fail (no short-handed round)" env CLAUDE_BIN="$SB/bin/fake-claude" "$PANEL" "$SB/task.md" --out "$SB/out6" --agents claude,gemini --tag r1
assert_no_file "$SB/out6/r1_claude.md" "no partial output written when the round was refused"
red "missing task file must fail" "$PANEL" "$SB/no-such-task.md" --out "$SB/out5"
# an agent binary that RUNS but crashes: 'done' + empty answer file + rc 0 was the mask
cat > "$SB/bin/crasher" <<'SHIM'
#!/usr/bin/env bash
echo "boom" >&2; exit 3
SHIM
chmod +x "$SB/bin/crasher"
red "agent that runs and crashes must fail the round" env CLAUDE_BIN="$SB/bin/crasher" "$PANEL" "$SB/task.md" --out "$SB/out7" --agents claude --tag r1
red "typo'd flag must error, not run with defaults (would overwrite the previous round)" env CLAUDE_BIN="$SB/bin/fake-claude" "$PANEL" "$SB/task.md" --out "$SB/out8" --agents claude --tga r2

finish
