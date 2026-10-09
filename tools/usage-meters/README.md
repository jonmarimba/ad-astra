# usage-meters

This tool puts usage meters around the prompt of Claude Code, Qwen Code, and Codex for every session in one repo.

## What each agent shows

### Claude Code

Above the prompt, the `astra-usage-meters` plugin shows one row:

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

### Qwen Code

Below the prompt, the status line shows two lines:

```
√ my-repo
Context 134k    NCR tok 26k this session
```

- `Context` is the number of tokens in the context window, as of the last response.
- `NCR tok` is the number of non-cache-read tokens that this session used. Qwen Code reports each request's prompt with its cached part included, so the count is prompt tokens minus cached tokens plus completion tokens.
- Qwen Code reports no subscription limits, so this status line has no bars.

### Codex

Codex cannot run a status-line command, so the tool selects Codex's own items. They are the project, the context used, the 5-hour limit, the weekly limit, and the used tokens. Codex shows an item only when it has data for it.

## Turn it on

Run this command inside the repo:

```
<astra checkout>/tools/astra add usage-meters
```

The command makes these changes in the repo, and nowhere else:

- It places both status-line scripts in `.astra/usage-meters/`.
- It places the Claude Code plugin in `.claude/skills/astra-usage-meters/`. Claude Code loads a plugin from that folder with no install step.
- It writes `statusLine` into `.claude/settings.json`, `ui.statusLine` into `.qwen/settings.json`, and `tui.status_line` into `.codex/config.toml`.

The manifest records every file and entry. The repo's post-commit hook keeps the files current.

Each agent reads these settings only when you start it in the repo folder. Claude Code and Codex read them only after you trust the folder.

If the repo already sets one of these entries to its own value, the install stops and changes nothing. Remove that entry first, or run the install again with `ASTRA_FORCE=1` to replace it.

## The plugin source

Astra keeps its own copy of the plugin source in `claude-plugin/`. The copy came from `github drewster99/claude-usage-meters` at commit 0f7a3cc. Its name, its state key, and its cache folder (`~/Library/Caches/astra-usage-meters/`) differ from the GitHub plugin, so the two can run side by side. Run its tests with this command:

```
/usr/bin/python3 -m unittest discover -s tools/usage-meters/claude-plugin/bin
```

## Requirements

- The status lines need `jq`. Install it with `brew install jq`.
- The Claude Code plugin needs macOS with `/usr/bin/python3`, which comes with the Command Line Tools.
- The Claude Code plugin needs a Claude Code version that supports function-hook mods.

## Turn it off

```
<astra checkout>/tools/astra remove usage-meters
```

This command removes the files and the three entries that the install wrote. Other entries in those config files stay. If you changed one of the three entries after the install, that entry stays too, and the command tells you. Nothing brings the tool back on an automatic update.
