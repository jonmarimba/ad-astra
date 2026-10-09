# claude-usage-meters

This tool puts usage meters around the Claude Code prompt for every session in one repo.

Above the prompt, one row shows three numbers:

```
Context 229k    NCR tok 277k    Last hour 84k
```

- `Context` is the number of tokens in the live context window, as of the last response.
- `NCR tok` is the number of non-cache-read tokens that this session and its subagents used today, since local midnight. Non-cache-read tokens are uncached input, cache writes, and output.
- `Last hour` is the same count over the last 60 minutes.

Below the prompt, the status line shows the name of the current folder and two bars:

```
√ my-repo
Session ███████████████░░░░░  75% left · resets Thu Jan 1 12:00am    Week    ██░░░░░░░░░░░░░░░░░░   9% left · resets Thu Jan 1 12:00am
```

- `Session` is the 5-hour subscription limit, and `Week` is the 7-day limit.
- Each bar shows the percent that is left, and the bar is green, yellow, or red as the limit gets near.
- A terminal narrower than 136 columns shows each bar on its own line.
- Before the first response, each bar shows `no data yet`.

## Turn it on

Run this command inside the repo:

```
<astra checkout>/tools/astra add claude-usage-meters
```

The command makes these changes in the repo, and nowhere else:

- It places the status-line script at `.astra/claude-usage-meters/statusline.sh`. The repo's post-commit hook keeps the script current.
- It writes the `statusLine` entry into `.claude/settings.json`.
- It writes the `usage-meters` plugin into `.claude/settings.json`, as a marketplace entry for `github drewster99/claude-usage-meters` and an enable flag.

Start Claude Code in the repo. When Claude Code asks to install the `usage-meters` marketplace and plugin, accept. Claude Code then fetches the plugin from GitHub.

If the repo already has its own `statusLine`, the install stops and changes nothing. Remove that entry first, or run the install again with `ASTRA_FORCE=1` to replace it.

## Requirements

- The status line needs `jq`. Install it with `brew install jq`.
- The plugin needs macOS with `/usr/bin/python3`, which comes with the Command Line Tools.
- The plugin needs a Claude Code version that supports function-hook mods.

## Turn it off

```
<astra checkout>/tools/astra remove claude-usage-meters
```

This command removes the script and the three settings entries that the install wrote. Other entries in `.claude/settings.json` stay. If you changed one of the three entries after the install, that entry stays too, and the command tells you. Nothing brings the tool back on an automatic update.
