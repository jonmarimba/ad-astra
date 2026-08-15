# Handlebars — one standing TCC-grant tower, reprogrammed by editing a script outside the bundle

*"I can ride my bike with no handlebars."* wrap-in-app's design (2026-08-12: `.app` references the script by absolute path, the script never lives inside the bundle) has a property beyond "fix the mail wrapper": granting a `.app` bundle a macOS TCC permission grants *that code-signed identity*, not *a task*. Since the app's hash — and therefore its grant — survives any edit to the script it calls, one wrapper granted **every** TCC permission it will ever plausibly need becomes a standing tower: mint it once, reprogram what it does forever by editing `handlebars.sh`, never touch the app, never re-grant.

## Install

```
cd tools/handlebars
./install.sh        # brew bundle (ffmpeg) + build Handlebars.app via wrap-in-app
./handlebars.sh     # see which TCC domains are granted (all 8 will say BLOCKED on a fresh install)
```

Then grant each domain one at a time in System Settings, following the pane paths the output prints.

## What this is

- `handlebars.sh` — the payload. Edit this freely; the grant survives (per wrap-in-app's core guarantee).
- `Handlebars.app` — the granted identity. **Never edit this directly** (a wrap-in-app re-run over it, or any change to the bundle itself, changes its hash and silently kills every grant it holds — reread as EPERM with no prompt, exactly the original TCC disease).
- `handlebars_launch.sh` — the schd/launchd-facing shim (swallows the app's stdout-eating, restores poke-on-output).
- `install.sh` / `uninstall.sh` — standard @astra tool lifecycle. install.sh will not rebuild an existing .app (that would kill its grants).
- `Brewfile` — declares ffmpeg (needed for mic + camera probes; the other 6 checks use pure macOS tools).

## ONE grant at a time — never a batch skeleton key

Jonathan, 2026-08-14: *"we do one at a time in the script. And coordinate where I grant access in the seat with your direction."* Followed immediately by the point of that constraint: grant everything at once and *"then you have a skeleton key to the system."* This is the actual design, not "grant every pane up front":

1. GhOST (or whoever's driving) picks ONE domain the task at hand actually needs — say, Screen Recording.
2. GhOST tells Jonathan exactly which System Settings pane to open: Privacy & Security → Screen Recording → add `Handlebars.app`.
3. Jonathan does it himself, in the seat, watching it happen — never done unattended, never batched.
4. Run `handlebars.sh screen` (or the matching domain arg) to confirm that ONE grant took, before moving on.

Run `handlebars.sh` with no argument to see current state across all 8 wired domains (Full Disk Access, Screen Recording, Automation/Notes, Contacts, Calendar, Accessibility, Microphone, Camera) — read-only, checks only what's already been granted, never prompts for anything new. Each BLOCKED line prints the exact System Settings pane to visit. Mic and Camera probes need ffmpeg; without it they report SKIP instead of BLOCKED.

Once granted, the identity IS broad by construction (that's what makes reprogramming via `handlebars.sh` valuable) — the discipline is entirely in how deliberately each individual grant gets added, never in pretending the tower stays narrow after the fact.

## The discipline this demands (the brakes, not the bars)

A wrapper this broad is exactly as dangerous as it is convenient — same escalation shape as "my reach is global, my power is pure." Treat every edit to `handlebars.sh` as a real capability change:

- Log what changed and why (git commit message, minimum).
- Never let a scheduled/unattended run carry a destructive or irreversible action without the same explicit-permission discipline that applies everywhere else in this repo (sending messages, deleting data, spending money — see the outer system prompt's action categories).
- The tower makes it EASY to skip asking. That ease is the risk, not a reason the rule doesn't apply.

## Why not one wrapper per task (the old pattern)

The HOA/ingest wrappers are narrowly granted (FDA only, one job each) — the deliberately safer default, and still the right call for anything that doesn't need this breadth. Handlebars exists for the case where you genuinely want one standing, broadly-capable identity you reprogram on the fly (interactive one-offs, "I need Automation + Screen Recording for ten minutes today, something else tomorrow") rather than minting a new narrowly-scoped wrapper — and re-granting FDA — every time the need shifts.

## Test

None yet — the payload is currently a read-only proof-of-reach template with no real behavior to assert on. When `handlebars.sh` grows a real task, it inherits `tools/tests/lib.sh`'s rules like everything else here: real effect, RED-capable, no silent skip.
