# ambrosio

Food of the gods, delivered — so JS never weekly-searches "what's hot." Watches HF trending (filtered to the frontier watchlist, official labs only), auto-pulls the best new model onto the headroom host's LM Studio, lets OmniRoute discover it (already a provider_node), and **botline-pings JS "come play."**

```sh
ambrosio check [--dry-run]   # whole loop; silent if host down or nothing new
ambrosio status              # host up/down + loaded models + current trending-frontier candidates
```
**Reachability-gated:** does nothing while the host (M5 in the bag, or the Strix box pre-install) is unreachable. Config `~/.ambrosio/config`: `HOST`/`SSH_TARGET` (repoint from M5 → Strix box later), `WATCHLIST`, `SIZE_CAP_GB`, `OMNIROUTE_NODE`.

**Verified:** HF trending detection (surfaces DeepSeek-V4-Flash, Nemotron 3.5 Lightning, GLM-5.2…), the junk-fork filter, the reachability gate, botline notify.
**UNVERIFIED until a host is awake:** the pull leg — `ssh HOST 'lms get <id>'`. `lms get` may want an LM-Studio-catalog name rather than a raw HF repo id; confirm the exact id form on the first live run (M5 awake) and adjust the resolution if needed. Size cap (`SIZE_CAP_GB`) is a config knob to wire into a pre-pull size check once tested on the host.
