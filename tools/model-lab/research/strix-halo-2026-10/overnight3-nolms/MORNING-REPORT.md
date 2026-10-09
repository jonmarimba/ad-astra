# Morning report (2026-10-06 19:04:06)

Downloaded tonight: 6 GB. Models processed: 1.

## Per model

| repo | quant | GB | verdict | notes |
|---|---|---|---|---|
| bartowski/Ling-3.0-tiny-GGUF | Q5_K_L | 5.9 | tested |  |

## All measurements (overnight-results.csv)

| repo | engine | variant | status | load s | tok/s | cold s | cached s | hard fixed | loops | secs/task | notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| bartowski/Ling-3.0-tiny-GGUF | stock | ub1024 | ok |  | 140.9 | 79.9 | 7.0 |  |  |  |  |
| bartowski/Ling-3.0-tiny-GGUF | stock | ub1024 | agent |  |  |  |  | 5/5 | 0 | 8 |  |
