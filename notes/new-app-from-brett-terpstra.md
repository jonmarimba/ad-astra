New app from Brett Terpstra:

TerminalWidget lets you send output from commands, scripts, APIs, and Shortcuts directly to widgets across macOS, iOS, and iPadOS with rich formatting, progress bars, sparklines, and image support. It is available as a universal app on the App Store for $19.99.

I don’t know what I’m going to use this for, but I know I want to use it.

@ghost oooooh kicker dashboard.

New app from Brett Terpstra:

TerminalWidget lets you send output from commands, scripts, APIs, and Shortcuts directly to widgets across macOS, iOS, and iPadOS with rich formatting, progress bars, sparklines, and image support. It is available as a universal app on the App Store for $19.99.

I don’t know what I’m going to use this for, but I know I want to use it.

@ghost oooooh kicker dashboard.

***GhOST reply, 2026-08-04 20:31:***

*It's real and well-received — featured on Daring Fireball, listed on Product Hunt, brettterpstra.com's own intro post. $19.99 one-time (not subscription — matches your general preference). CLI (terminal-widget, symlinked from the app bundle) is scriptable from day one: --target NAME picks the widget, --text/--progress/--chart/--image push content, --icon/--fg/--bg/--font/--title style it, chart formats include sparkline/graph/area/matrix. Meant to be driven by cron/launchd/CI/Shortcuts — exactly the shape of an schd job. Kicker dashboard idea is genuinely solid: a launchd/schd job every N seconds/minutes running `kicker ps` (or a parsed summary of it — node count, any `!attention:` flags, live vs done states) piped into `terminal-widget --target kicker --text -`, mirrored to your phone via iCloud sync (slight delay noted for iOS). Could go further with --progress for something like 'how many nodes are attention-needed vs total' or a sparkline of node count over time. Straightforward to prototype: one schd command-type job wrapping a kicker ps summary script.*

New app from Brett Terpstra:

TerminalWidget lets you send output from commands, scripts, APIs, and Shortcuts directly to widgets across macOS, iOS, and iPadOS with rich formatting, progress bars, sparklines, and image support. It is available as a universal app on the App Store for $19.99.

I don’t know what I’m going to use this for, but I know I want to use it.

@ghost oooooh kicker dashboard.

***GhOST reply, 2026-08-04 20:31:***

*It's real and well-received — featured on Daring Fireball, listed on Product Hunt, brettterpstra.com's own intro post. $19.99 one-time (not subscription — matches your general preference). CLI (terminal-widget, symlinked from the app bundle) is scriptable from day one: --target NAME picks the widget, --text/--progress/--chart/--image push content, --icon/--fg/--bg/--font/--title style it, chart formats include sparkline/graph/area/matrix. Meant to be driven by cron/launchd/CI/Shortcuts — exactly the shape of an schd job. Kicker dashboard idea is genuinely solid: a launchd/schd job every N seconds/minutes running `kicker ps` (or a parsed summary of it — node count, any `!attention:` flags, live vs done states) piped into `terminal-widget --target kicker --text -`, mirrored to your phone via iCloud sync (slight delay noted for iOS). Could go further with --progress for something like 'how many nodes are attention-needed vs total' or a sparkline of node count over time. Straightforward to prototype: one schd command-type job wrapping a kicker ps summary script.*

@astra