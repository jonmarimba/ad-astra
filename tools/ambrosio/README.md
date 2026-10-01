# ambrosio

Named for Alessandra Ambrosio — the job is finding JS HOT MODELS, the pun is the point. So JS never weekly-searches "what's hot": the tool watches HF trending (filtered to the frontier watchlist, official labs only) plus a standing want-list. It auto-pulls the best NEW and genuinely worth-his-time model onto the headroom host's LM Studio and lets OmniRoute discover it (already a provider_node). Then it **botline-pings JS "come play."**

"Hot" means real signal, not merely "downloaded and didn't error." Two checks gate a pull specifically because that distinction got tested live and failed once. The first is a popularity floor (HuggingFace's own `downloads` count on each candidate repo, used as a tiebreaker). The second is a redundancy check against what's already loaded on the host, so a same-family retread doesn't burn a notification.

```sh
ambrosio check [--dry-run]   # whole loop; silent if host down or nothing new
ambrosio status              # host up/down + loaded models + seen count + want-list + current trending candidates
```

The tool is **reachability-gated**: it does nothing but a fast 6s probe while the host (M5) is unreachable. That is cheap enough to run every 4 hours. The cadence was daily; it changed because the M5 isn't always on the tailnet and daily was too sparse a retry window. Config `~/.ambrosio/config`: `HOST`/`SSH_TARGET`, `WATCHLIST`, `SIZE_CAP_GB`, `MAX_PER_RUN`, `MIN_PARAMS_B`, `LMS_BIN`, `LMS_FORMAT`.

The **want-list** lives at `~/.ambrosio/wantlist.txt`, one model family term per line. Tried first every run, ahead of the reactive trending scan, through the identical resolve/size-check/pull path — no separate code, same treatment. An explicit want-list entry always goes through, even if it shares a family with something already loaded (the redundancy check only gates the reactive scan). An entry stays in the file until it pulls successfully or is removed. The list is durable across the host being asleep for a while, not a queue that silently drains.

These behaviors are **verified live, repeatedly, against the real M5**: trending detection and family-term dedup, plus the junk-fork/reputable-org filter. The same live verification covers the live HuggingFace size check against the real cap, the reachability gate, the redundancy check, and the downloads tiebreaker. It covers `expose_model` writing real entries into both qwen's `settings.json` and OpenCode's `opencode.jsonc`, and botline notify. It covers a real completion through a delivered model via both qwen (tmux) and OpenCode (`opencode models`). Full sandboxed test coverage exists across `test-ambrosio.sh`, `test-ambrosio-wantlist.sh`, `test-ambrosio-tui.sh`, and `test-ambrosio-quality.sh` (46 assertions total). With the live verification above, nothing about the pull leg is unverified anymore.

The **known gap** is the redundancy check: a blunt heuristic (leading-letters family prefix of the search term, checked as a substring against the loaded-models list). It catches the exact failure mode that motivated it (same family, different version, nothing new) but isn't a real capability comparison. It doesn't know whether a same-family newer release is actually better, only that something with the same name prefix already exists.

## Front door (2026-08-22)

`ambrosio check` is the single entry point for "is there a hot model I can play with." It covers three surfaces:

- **Local** — pull new MLX quants onto the headroom host's LM Studio. Requires that host to be awake; skipped with a log line when it is not.
- **Ollama library** — `ollama-watch check`, which notifies when a new frontier family appears on ollama.com.
- **Cloud catalog** — `omniroute-model-sync`, which wires new ollamacloud models into qwen and OpenCode.

The cloud surfaces run whether or not the headroom host is reachable. Before this, a sleeping host made the whole command inert. The ollama subscription then went unchecked from here even though two other schd jobs covered it.

They remain SEPARATE TOOLS with their own tests and their own state. Ambrosio calls them at injectable seams (`OLLAMA_WATCH_BIN`, `OMNIROUTE_SYNC_BIN`); it does not absorb them. That separation is deliberate. `omniroute-model-sync` was built after an `omniroute setup-qwen` run silently wiped qwen's hand-curated model list, so the two must never write each other's config.

Output follows the schd convention: silent when nothing happened, loud when something did. A missing or failing surface is reported rather than skipped. A front door that quietly stops watching something is worse than the separate jobs it replaced. Set `CLOUD="0"` in the config for local-only behaviour.

Tests: `tools/tests/test-ambrosio-frontdoor.sh`.

### Cadence, after consolidation

The two cloud surfaces used to carry their own schd jobs — `ollama-watch` every 24h and `omniroute-model-sync` every 6h. Both were removed on 2026-08-22 once `check` started driving them, so each surface runs exactly once per pass instead of twice.

Ambrosio's own job runs every 4 hours, which makes both cloud surfaces MORE frequent than before rather than less. The library watch goes from daily to four-hourly, and the catalog sync goes from six-hourly to four-hourly. There is no latency regression anywhere in the consolidation, which is why it was safe to do rather than something to weigh.

