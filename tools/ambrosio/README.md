# ambrosio

Named for Alessandra Ambrosio — the job is finding JS HOT MODELS, the pun is the point. So JS never weekly-searches "what's hot": watches HF trending (filtered to the frontier watchlist, official labs only) plus a standing want-list, auto-pulls the best NEW and genuinely worth-his-time model onto the headroom host's LM Studio, lets OmniRoute discover it (already a provider_node), and **botline-pings JS "come play."**

"Hot" means real signal, not just "downloaded and didn't error." Two checks gate a pull specifically because that distinction got tested live and failed once: a popularity floor (HuggingFace's own `downloads` count on each candidate repo, used as a tiebreaker) and a redundancy check against what's already loaded on the host, so a same-family retread doesn't burn a notification.

```sh
ambrosio check [--dry-run]   # whole loop; silent if host down or nothing new
ambrosio status              # host up/down + loaded models + seen count + want-list + current trending candidates
```

**Reachability-gated:** does nothing but a fast 6s probe while the host (M5) is unreachable — cheap enough to run every 4 hours (was daily; changed because the M5 isn't always on the tailnet and daily was too sparse a retry window). Config `~/.ambrosio/config`: `HOST`/`SSH_TARGET`, `WATCHLIST`, `SIZE_CAP_GB`, `MAX_PER_RUN`, `MIN_PARAMS_B`, `LMS_BIN`, `LMS_FORMAT`.

**Want-list:** `~/.ambrosio/wantlist.txt`, one model family term per line. Tried first every run, ahead of the reactive trending scan, through the identical resolve/size-check/pull path — no separate code, same treatment. An explicit want-list entry always goes through, even if it shares a family with something already loaded (the redundancy check only gates the reactive scan). Stays in the file until it pulls successfully or is removed — durable across the host being asleep for a while, not a queue that silently drains.

**Verified live, repeatedly, against the real M5:** trending detection and family-term dedup, the junk-fork/reputable-org filter, the live HuggingFace size check against the real cap, the reachability gate, the redundancy check, the downloads tiebreaker, `expose_model` writing real entries into both qwen's `settings.json` and OpenCode's `opencode.jsonc`, botline notify, and a real completion through a delivered model via both qwen (tmux) and OpenCode (`opencode models`). Full sandboxed test coverage across `test-ambrosio.sh`, `test-ambrosio-wantlist.sh`, `test-ambrosio-tui.sh`, and `test-ambrosio-quality.sh` (46 assertions total) plus the live verification above — nothing about the pull leg is unverified anymore.

**Known gap:** the redundancy check is a blunt heuristic (leading-letters family prefix of the search term, checked as a substring against the loaded-models list) — it catches the exact failure mode that motivated it (same family, different version, nothing new) but isn't a real capability comparison. It doesn't know whether a same-family newer release is actually better, only that something with the same name prefix already exists.
