# ⚠️ update.sh overwrites global configs — Drew's machine only

`update.sh` ends with `cp AGENTS.md ~/.claude/CLAUDE.md` and `cp AGENTS.md ~/.codex/AGENTS.md` — a full REPLACE, not a merge. On Drew's machine that's the point. On Jonathan's machines it would destroy the global CLAUDE.md (house rules, TCC/Automator pattern, all standing corrections) and the codex AGENTS.md.

If Jonathan wants Drew's components loaded here, the safe form is an `@`-import LINE added to the existing global file, never a copy over it. (Noted by GhOST 2026-08-12 on first read of the restructure.)
