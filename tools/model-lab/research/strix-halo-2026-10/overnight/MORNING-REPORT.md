# Morning report (2026-10-06 10:14:53)

Downloaded tonight: 261 GB. Models processed: 11.

## Per model

| repo | quant | GB | verdict | notes |
|---|---|---|---|---|
| unsloth/gemma-4-26B-A4B-it-qat-GGUF | UD-Q4_K_XL | 14.2 | tested |  |
| bartowski/Kwaipilot_KAT-Coder-V2.5-Dev-GGUF | Q5_K_L | 25.3 | tested |  |
| ornith-ai/Ornith-1.0-35B-GGUF | Q6_K | 28.5 | tested |  |
| bartowski/endless-frontier_BigBang-v1-GGUF | Q5_K_L | 25.8 | tested |  |
| FINAL-Bench/POCKET-35B-GGUF | Q4_K_M | 21.2 | tested |  |
| unsloth/Muse-Glimmer-30B-GGUF | UD-Q5_K_XL | 21.8 | tested |  |
| ibm-granite/granite-4.2-30b-GGUF | Q6_K | 24.0 | tested |  |
| unsloth/gemma-4-31B-it-qat-GGUF | UD-Q4_K_XL | 17.3 | tested |  |
| bartowski/FrogNano-4B-2609-GGUF | Q6_K_S | 3.6 | tested |  |
| unsloth/Qwen3.8-Flash-Next-GGUF | UD-Q2_K_XL | 78.9 | tested |  |
| ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF | IQ1_M | 58.4 | skipped: budget (disk/time) |  |

## All measurements (overnight-results.csv)

| repo | engine | variant | status | load s | tok/s | cold s | cached s | hard fixed | loops | secs/task | notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| unsloth/gemma-4-26B-A4B-it-qat-GGUF | lmstudio | ub1024/b2048 | ok | 11.5 | 72.7 | 94.7 | 4.9 |  |  |  |  |
| unsloth/gemma-4-26B-A4B-it-qat-GGUF | lmstudio | ub512/b512 | ok | 8.1 | 73.2 | 97.2 | 4.5 |  |  |  |  |
| unsloth/gemma-4-26B-A4B-it-qat-GGUF | lmstudio | best ub1024 | agent |  |  |  |  | 5/5 | 0 | 78 | easy 0/3;  |
| unsloth/gemma-4-26B-A4B-it-qat-GGUF | stock | ub1024 | ok |  | 77.8 | 93.8 | 4.1 |  |  |  |  |
| unsloth/gemma-4-26B-A4B-it-qat-GGUF | stock | ub1024 | agent |  |  |  |  | 5/5 | 0 | 36 |  |
| bartowski/Kwaipilot_KAT-Coder-V2.5-Dev-GGUF | lmstudio | ub1024/b2048 | ok | 58.9 | 60.4 | 91.8 | 4.0 |  |  |  |  |
| bartowski/Kwaipilot_KAT-Coder-V2.5-Dev-GGUF | lmstudio | ub512/b512 | ok | 16.7 | 60.6 | 27.5 | 118.0 |  |  |  |  |
| bartowski/Kwaipilot_KAT-Coder-V2.5-Dev-GGUF | lmstudio | best ub512 | agent |  |  |  |  | 5/5 | 0 | 95 | easy 0/3;  |
| bartowski/Kwaipilot_KAT-Coder-V2.5-Dev-GGUF | stock | ub1024 | ok |  | 60.2 | 22.1 | 2.2 |  |  |  |  |
| bartowski/Kwaipilot_KAT-Coder-V2.5-Dev-GGUF | stock | ub1024 | agent |  |  |  |  | 5/5 | 0 | 19 |  |
| ornith-ai/Ornith-1.0-35B-GGUF | lmstudio | ub1024/b2048 | ok | 15.0 | 61.3 | 26.1 | 4.0 |  |  |  |  |
| ornith-ai/Ornith-1.0-35B-GGUF | lmstudio | ub512/b512 | ok | 14.9 | 61.5 | 29.7 | 93.1 |  |  |  |  |
| ornith-ai/Ornith-1.0-35B-GGUF | lmstudio | best ub1024 | agent |  |  |  |  | 5/5 | 0 | 95 | easy 0/3;  |
| ornith-ai/Ornith-1.0-35B-GGUF | stock | ub1024 | ok |  | 64.7 | 22.2 | 2.2 |  |  |  |  |
| ornith-ai/Ornith-1.0-35B-GGUF | stock | ub1024 | agent |  |  |  |  | 5/5 | 0 | 18 |  |
| bartowski/endless-frontier_BigBang-v1-GGUF | lmstudio | ub1024/b2048 | ok | 14.4 | 43.4 | 68.6 | 37.5 |  |  |  |  |
| bartowski/endless-frontier_BigBang-v1-GGUF | lmstudio | ub512/b512 | ok | 18.4 | 62.3 | 29.1 | 3.9 |  |  |  |  |
| bartowski/endless-frontier_BigBang-v1-GGUF | lmstudio | best ub512 | agent |  |  |  |  | 5/5 | 0 | 85 | easy 0/3;  |
| bartowski/endless-frontier_BigBang-v1-GGUF | stock | ub1024 | ok |  | 61.9 | 21.0 | 2.2 |  |  |  |  |
| bartowski/endless-frontier_BigBang-v1-GGUF | stock | ub1024 | agent |  |  |  |  | 5/5 | 0 | 20 |  |
| FINAL-Bench/POCKET-35B-GGUF | lmstudio | ub1024/b2048 | ok | 9.8 | 73.4 | 25.1 | 32.9 |  |  |  |  |
| FINAL-Bench/POCKET-35B-GGUF | lmstudio | ub512/b512 | ok | 23.2 | 72.6 | 26.3 | 3.4 |  |  |  |  |
| FINAL-Bench/POCKET-35B-GGUF | lmstudio | best ub1024 | agent |  |  |  |  | 5/5 | 0 | 89 | easy 0/3;  |
| FINAL-Bench/POCKET-35B-GGUF | stock | ub1024 | ok |  | 73.9 | 21.7 | 2.2 |  |  |  |  |
| FINAL-Bench/POCKET-35B-GGUF | stock | ub1024 | agent |  |  |  |  | 5/5 | 0 | 16 |  |
| unsloth/Muse-Glimmer-30B-GGUF | lmstudio | ub1024/b2048 | ok | 63.6 | 10.2 | 87.7 | 4.3 |  |  |  |  |
| unsloth/Muse-Glimmer-30B-GGUF | lmstudio | ub512/b512 | ok | 17.0 | 10.0 | 73.2 | 4.1 |  |  |  |  |
| unsloth/Muse-Glimmer-30B-GGUF | lmstudio | best ub512 | agent |  |  |  |  | None/None |  |  | easy 0/3;  |
| unsloth/Muse-Glimmer-30B-GGUF | stock | ub1024 | ok |  | 10.4 | 71.8 | 2.1 |  |  |  |  |
| unsloth/Muse-Glimmer-30B-GGUF | stock | ub1024 | agent |  |  |  |  | 5/5 | 0 | 133 |  |
| ibm-granite/granite-4.2-30b-GGUF | lmstudio | ub1024/b2048 | ok | 16.7 | 9.3 | 344.8 | 2.9 |  |  |  |  |
| ibm-granite/granite-4.2-30b-GGUF | lmstudio | ub512/b512 | ok | 20.4 | 9.3 | 214.4 | 98.4 |  |  |  |  |
| ibm-granite/granite-4.2-30b-GGUF | lmstudio | best ub512 | agent |  |  |  |  | 2/5 | 0 | 283 | easy None/None;  |
| ibm-granite/granite-4.2-30b-GGUF | stock | ub1024 | ok |  | 9.4 | 243.9 | 0.6 |  |  |  |  |
| ibm-granite/granite-4.2-30b-GGUF | stock | ub1024 | agent |  |  |  |  | None/None |  |  |  |
| unsloth/gemma-4-31B-it-qat-GGUF | lmstudio | ub1024/b2048 | ok | 10.6 | 12.6 | 399.7 | 12.5 |  |  |  |  |
| unsloth/gemma-4-31B-it-qat-GGUF | lmstudio | ub512/b512 | ok | 10.0 | 12.5 | 521.4 | 11.5 |  |  |  |  |
| unsloth/gemma-4-31B-it-qat-GGUF | lmstudio | best ub1024 | agent |  |  |  |  | 5/5 | 0 | 261 | easy None/None;  |
| unsloth/gemma-4-31B-it-qat-GGUF | stock | ub1024 | ok |  | 12.7 | 404.2 | 14.1 |  |  |  |  |
| unsloth/gemma-4-31B-it-qat-GGUF | stock | ub1024 | agent |  |  |  |  | 5/5 | 0 | 147 |  |
| bartowski/FrogNano-4B-2609-GGUF | lmstudio | ub1024/b2048 | ok | 6.0 | 79.8 | 25.8 | 5.0 |  |  |  |  |
| bartowski/FrogNano-4B-2609-GGUF | lmstudio | ub512/b512 | ok | 5.7 | 72.8 | 25.1 | 7.4 |  |  |  |  |
| bartowski/FrogNano-4B-2609-GGUF | lmstudio | best ub512 | agent |  |  |  |  | 5/5 | 0 | 30 | easy 0/3;  |
| bartowski/FrogNano-4B-2609-GGUF | stock | ub1024 | ok |  | 54.0 | 21.7 | 2.3 |  |  |  |  |
| bartowski/FrogNano-4B-2609-GGUF | stock | ub1024 | agent |  |  |  |  | 5/5 | 0 | 24 |  |
| unsloth/Qwen3.8-Flash-Next-GGUF | lmstudio | ub1024/b2048 | failed |  |  |  |  |  |  |  | COULD NOT REACH THE SERVER at http://localhost:1234 (HTTP Error 400: Bad Request). Is LM Studio's server running? |
| unsloth/Qwen3.8-Flash-Next-GGUF | stock | ub1024 | ok |  | 28.3 | 54.8 | 4.6 |  |  |  |  |
| unsloth/Qwen3.8-Flash-Next-GGUF | stock | ub1024 | agent |  |  |  |  | 5/5 | 0 | 31 |  |
