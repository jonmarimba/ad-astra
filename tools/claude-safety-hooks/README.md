# claude-safety-hooks

Two PreToolUse/Bash hooks for Claude Code, extracted from a repo where they were built the hard way — each one exists because the failure it blocks actually happened, cost real data or a real live session, and a rule written down in prose did not hold on its own.

## What's here

- **`no-silent-truncation.sh`** — blocks piping a search over protected data (mail, notes, screenshots, messages, transcripts, whatever a repo's own indexers cover) through `head`, `tail`, `sed -n`, or an explicit `--limit`. An arbitrary truncation on a search silently drops real data with no error — a missing result and a nonexistent one look identical. Configured per-repo via a `.watchlist` file (substrings, one per line) naming the tools that actually search protected data in that repo; the hook itself carries no repo-specific tool names.
- **`no-killing-other-claudes.sh`** — blocks `kill`/`pkill`/`killall` from ever terminating a live `claude` process. Any machine running more than one Claude Code session at once (multiple terminal windows, a multi-agent setup, unrelated work in another repo) has this exposure, and "this looks like a stale duplicate" is not evidence — it has killed a session someone was actively using. Fails closed: `pkill`/`killall` are always refused, and `kill` is refused unless every target is a literal PID that resolves via `ps` to something that is NOT running `claude`.

Both are read-only about intent — they refuse a dangerous shape of command, they never execute anything themselves, and both have `git commit`/`tag`/`merge`/`notes` explicitly exempted so a commit message *describing* the guarded behavior doesn't trip the guard on its own commit.

## Install

```sh
./install.sh --into /path/to/target-repo [--reap-hint "text naming your repo's scoped reap mechanism, if any"]
```

This copies both hooks into `<target>/.claude/hooks/`, seeds a starter `no-silent-truncation.watchlist` (only if one doesn't already exist — re-running never clobbers a tuned watchlist), and merges the `PreToolUse`/`Bash` wiring into `<target>/.claude/settings.local.json` via `jq`, additively — any other hooks already registered on that matcher are left alone, and re-running doesn't duplicate entries. Requires `jq`.

**After installing, edit `<target>/.claude/hooks/no-silent-truncation.watchlist`** to name the tools in that repo that search protected data. The file ships with commented-out examples; it does nothing until you uncomment or add your own.

## Uninstall

```sh
./uninstall.sh --into /path/to/target-repo [--keep-watchlist]
```

Removes the two hook scripts and just their two `PreToolUse`/`Bash` entries (nothing else registered there). The watchlist is deleted by default since it may carry repo-specific tuning that shouldn't quietly survive; `--keep-watchlist` preserves it.

## Maintaining

Fix the hook logic here, in `js-db-ad-astra`, and re-run `install.sh` into every repo that has it — that's the update path, same as every other tool in this toolbox. Don't patch an installed copy in place; the fix won't propagate and the next `install.sh` run would overwrite it anyway (the watchlist is the one file that's deliberately exempt from that, since it's config, not code).

## Origin

Written for a personal-assistant Claude Code deployment after real, named incidents: a diary reconstruction silently lost a device's worth of activity to a `sed -n` line range for hours before a human caught it, and a live, in-use Claude session was killed on the model's own pattern-matching judgment after a genuine split-brain outage had already been resolved. Both hooks fail closed rather than trying to prove a command is dangerous before blocking it — they require proof a command is *safe* before allowing it through.
