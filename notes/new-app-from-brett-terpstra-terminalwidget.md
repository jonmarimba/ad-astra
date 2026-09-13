**New app from Brett Terpstra — TerminalWidget**

TerminalWidget sends output from commands, scripts, APIs, and Shortcuts directly to widgets across macOS, iOS, and iPadOS, with rich formatting, progress bars, sparklines, and image support. Universal app on the App Store, $19.99.

I don't know what I'll use it for, but I want to. @ghost — oooooh, kicker dashboard.

Real and well-received (Daring Fireball, Product Hunt, Brett's own intro post). $19.99 one-time, not a subscription — matches your preference.

* The CLI (terminal-widget, symlinked from the app bundle) is scriptable from day one: --target NAME picks the widget; --text/--progress/--chart/--image push content; --icon/--fg/--bg/--font/--title style it; chart formats include sparkline, graph, area, matrix. It's meant to be driven by cron/launchd/Shortcuts — exactly the shape of an schd job.
* **The kicker-dashboard idea is solid:** a launchd/schd job every N minutes running &quotkicker ps" (or a parsed summary — node count, any !attention: flags, live vs done) piped into &quotterminal-widget --target kicker --text -", mirrored to your phone via iCloud (slight iOS delay). You could go further with --progress for attention-needed vs total, or a sparkline of node count over time. Straightforward to prototype: one schd command-type job wrapping a kicker-ps summary script.

@astra

**GhOST reply, 2026-08-17 — confirming prior research above is current.**

The kicker-dashboard idea via terminal-widget is still viable. One schd command job wrapping a kicker-ps summary piped into terminal-widget --target kicker --text -. Ready to prototype whenever you want it.

@ghost - Move this nearer the top of the list. I think having this show me my Jenkins for MHM would be useful and once we get kicker back up, some kind of activity graph of busy bots?

**GhOST reply, 2026-08-19:**

Moved up — it now sits in section A of tech-to-try alongside the other three you promoted, because it answers a problem you raised in a different note and did not connect to this one.

**In the TickTick note you said the real objection to keeping your TODO with me is that you cannot see it.** That is not a task-manager problem, it is a display problem, and TerminalWidget is the display. Your TODO lives in a markdown file that a script can already parse; TerminalWidget puts the output of any script into a widget on the Mac desktop and on the phone. So the answer to “should I move to TickTick” is no — you do not need a second task system, you need the one you have to be visible. That reframes a $36-a-year cloud subscription as a $19.99 one-time purchase you already wanted.

**Three widgets are worth building, in the order I would build them.**

**The TODO widget is first**, because it removes the only real argument against the current system. An schd command job every fifteen minutes runs the staleness check you already have, plus a count of open items, and pushes the two or three most urgent lines. The overdue items are the ones worth surfacing, not the full list — a widget that shows forty things shows nothing.

**The Maharam Jenkins widget is second and probably the one you will use most**, since it is the thing you currently check by opening a browser. Last build result per job, with a progress bar while one is running. Jenkins has a JSON API, so this is a curl and a parse.

**The kicker activity graph is third**, for the honest reason that kicker is not back up yet. When it is, terminal-widget takes a sparkline directly, so busy-bot count over time is one flag, and the more useful version is a progress bar of nodes needing attention against total.

Two things to know before buying. The phone mirroring goes through iCloud, so the widget on your phone lags the Mac by a little — fine for a build status, wrong for anything you would page on. And it is $19.99 once, on the App Store, universal across Mac, iPhone and iPad, which matches how you prefer to buy software.

Say the word and I will build the TODO one first, since it is the only prerequisite-free item of the three.