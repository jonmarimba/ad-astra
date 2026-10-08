# idle-nag

A spoken nudge for when Claude has gone quiet and is waiting on you: 25 seconds after a turn ends, if you have not come back, the Mac says "Dude. Look over here." Submitting a prompt cancels it. It stays silent while the display is asleep, so remote-controlling from bed with the screen off does not set it talking.

It used to be wired into `~/.claude/settings.json` on one Mac, which made it apply to every session on that machine. It now lives here and installs per repo.

## Turn it on

For every session in one repo, run this inside the repo:

```
<astra checkout>/tools/astra add idle-nag
```

That places the scripts in `.astra/idle-nag/` and registers a Stop hook and a UserPromptSubmit hook in the repo's `.claude/settings.json`. Hook settings are read when a session starts, so start a new session (or run `/hooks`) to pick it up.

For one session at a time instead, install the session variant, which places the same scripts and registers no repo hooks, then opt each session in when you launch it:

```
<astra checkout>/tools/astra add idle-nag-session
claude --settings .astra/idle-nag-session/session-settings.json
```

## Turn it off

```
<astra checkout>/tools/astra remove idle-nag          # or idle-nag-session
```

This removes the scripts and only the two hook entries it added. Any other hooks in the repo's settings stay. Nothing brings it back on an automatic update.

## Knobs

Set these in the environment Claude Code runs in: `IDLE_NAG_DELAY` (seconds, default 25), `IDLE_NAG_PHRASE`, `IDLE_NAG_VOICE` (default `Aman`, the English (India) voice), `IDLE_NAG_SAY` (the command that speaks, default `say`), and `IDLE_NAG_REQUIRE_DISPLAY` (default 1; set 0 to speak with the display asleep).
