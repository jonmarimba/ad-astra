# ollama-watch

Texts Jonathan (via botline) when **ollama.com/library gains a new frontier-tier model family**, so he knows to try it. One slice of the model-sync ask.

```sh
ollama-watch check            # fetch, diff vs snapshot, notify on new frontier models
ollama-watch check --dry-run  # show what it'd notify, send nothing
ollama-watch list             # current library set
```
First `check` seeds silently. Config `~/.ollama-watch/config` — `WATCHLIST` is the space-separated name-substrings that count as frontier (glm, kimi, deepseek, qwen3, minimax, gpt-oss, …); edit freely. Notifies through `botline send --from ollama-watch` (falls back to raw `imsg`). Run on a timer (daily is plenty).

NOT yet built (the rest of model-sync): syncing model availability across OpenCode/qwen ("the router thing") and across both laptops, and auto-pulling frontier models. Those need the router config + both machines reachable — see PROJECTS.md.
