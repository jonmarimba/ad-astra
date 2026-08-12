# botline

Generic two-way text bridge: **any local bot can text Jonathan, and his replies route back to the bot that messaged him.** Built on `imsg` — no GhOST dependency, portable (point the config at any recipient).

## A bot's whole integration (minimal setup)
```sh
botline send --from mybot "the thing I want to tell you"   # → texts JS as "[mybot] the thing…"
botline recv --as mybot                                    # ← prints (and clears) JS's replies to mybot
```

## How replies route
JS replies in his Messages thread. The **dispatcher** (`botline dispatch`, run on a timer) reads new inbound and routes:
- reply starting `@mybot ...` → that bot's inbox
- any other reply → the **last bot that messaged him** (reply-to-last)

Each bot polls `botline recv --as <bot>`. State in `~/.botline/` (per-bot `inbox/`, monotonic-id watermark so nothing is missed or double-routed; first `dispatch` seeds to "now" so the existing thread isn't replayed).

## Setup
```sh
./install.sh
# then run the dispatcher on a timer (GhOST schd, cron, or launchd), every ~2 min:
botline dispatch
```
Config `~/.botline/config`: `JS_NUMBER` + `JS_CHAT_ID` (from `imsg chats --json`) — not hardcoded, so it works for any recipient/thread.
