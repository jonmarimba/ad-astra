# harness-settings

Apply / undo the "Harness settings — SYNTHESIS (real coding, not vibe)" recommendations (Fable+Sol) across **Claude Code**, **Codex**, and **Qwen**, reversibly.

## Use
```sh
./install.sh                 # jq + python tomlkit
./harness-settings.sh apply  # backs up every config first, then applies
./harness-settings.sh status # show what's in effect + latest backup
./harness-settings.sh undo   # restore the most recent backup verbatim
```
Backups: `~/.harness-settings-backups/<timestamp>/`. Every `apply` makes a fresh one; `undo` restores the latest. It edits YOUR live configs — review, apply, undo if you dislike it.

## What it sets (and why)
**Claude** (`~/.claude/settings.json`, jq): `model=opus`, `effortLevel=xhigh`, `outputStyle=Default` (Proactive is the vibe knob), `autoMemoryEnabled=false` (auto-memory accretes stale assumptions). Permissions **merged additively** (never clobbered): deny `git commit/push`, `git reset --hard`, `rm -rf`, `.env`/`~/.ssh`/`~/.aws` reads; allow `rg`, `git status/diff/log`, `ls`.

**Codex** (`~/.codex/config.toml`, tomlkit, format-preserving): `model_reasoning_effort` + `plan_mode_reasoning_effort=xhigh`, `model_verbosity=low`, `personality=none` (anti-cheerleader), `approval_policy=on-request`, `sandbox_mode=workspace-write`, `[sandbox_workspace_write] network_access=false`, `[features] hooks=true, memories=false`.

**Qwen** (`~/.qwen/settings.json`, jq): `thinking=high`, telemetry off. Also: **trim `QWEN.md` by hand** — it was ~103k tokens, which buries any rule you add.

## NOT set (deliberate — per the synthesis)
Adaptive-thinking env vars (`CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING`, `MAX_THINKING_TOKENS`) — ineffective on 4.7+ and interact badly with effort settings. The Stop-hook `agent-verify` gate is the real anti-vibe mechanism but is repo-specific, so it's not auto-wired here.
