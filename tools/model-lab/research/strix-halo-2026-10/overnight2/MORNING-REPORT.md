# Morning report (2026-10-06 18:08:13)

Downloaded tonight: 214 GB. Models processed: 11.

## Per model

| repo | quant | GB | verdict | notes |
|---|---|---|---|---|
| ggml-org/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF | Q4_0 | 18.9 | tested |  |
| ggml-org/NVIDIA-Nemotron-3-Nano-30B-A3B-GGUF | Q4_K_M | 22.4 | tested |  |
| JetBrains/Mellum2-12B-A2.5B-Instruct-GGUF-Q8_0 | Q8_0 | 12.9 | tested |  |
| unsloth/NVIDIA-Nemotron-3-Nano-Omni-30B-A3B-Reasoning-GGUF | UD-Q5_K_S | 24.8 | tested |  |
| abenzerps/Apodex-1.1-mini-GGUF | Q6_K | 29.2 | tested |  |
| unsloth/gemma-4-12b-it-GGUF | Q6_K | 9.8 | tested |  |
| ornith-ai/Ornith-1.0-9B-GGUF | Q6_K | 7.4 | tested |  |
| XHToken/Spark-X2.5-4B-GGUF | Q4_K_M | 2.6 | tested |  |
| bartowski/Ling-3.0-tiny-GGUF | Q5_K_L | 5.9 | tested |  |
| bartowski/Cloudflare_clef-flash-GGUF | Q5_K_M | 7.0 | tested |  |
| unsloth/Step-3.7-Flash-GGUF | UD-IQ3_XXS | 73.6 | tested |  |

## All measurements (overnight-results.csv)

| repo | engine | variant | status | load s | tok/s | cold s | cached s | hard fixed | loops | secs/task | notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| ggml-org/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF | lmstudio | ub1024/b2048 | ok | 8.9 | 68.7 | 16.1 | 3.4 |  |  |  |  |
| ggml-org/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF | lmstudio | ub512/b512 | ok | 12.5 | 68.7 | 26.7 | 3.0 |  |  |  |  |
| ggml-org/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF | lmstudio | best ub1024 | agent |  |  |  |  | 5/5 | 0 | 35 | easy 0/3;  |
| ggml-org/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF | stock | ub1024 | ok |  | 69.0 | 13.5 | 1.5 |  |  |  |  |
| ggml-org/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF | stock | ub1024 | agent |  |  |  |  | 5/5 | 0 | 19 |  |
| ggml-org/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF | src | ub1024 | ok |  | 68.9 | 15.0 | 2.0 |  |  |  |  |
| ggml-org/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF | src | ub1024 | agent |  |  |  |  | 5/5 | 0 | 21 |  |
| ggml-org/NVIDIA-Nemotron-3-Nano-30B-A3B-GGUF | lmstudio | ub1024/b2048 | ok | 10.4 | 63.7 | 219.1 | 3.5 |  |  |  |  |
| ggml-org/NVIDIA-Nemotron-3-Nano-30B-A3B-GGUF | lmstudio | ub512/b512 | ok | 13.9 | 63.6 | 18.6 | 3.1 |  |  |  |  |
| ggml-org/NVIDIA-Nemotron-3-Nano-30B-A3B-GGUF | lmstudio | best ub512 | agent |  |  |  |  | 5/5 | 0 | 219 | easy 0/3;  |
| ggml-org/NVIDIA-Nemotron-3-Nano-30B-A3B-GGUF | stock | ub1024 | ok |  | 64.2 | 14.1 | 1.6 |  |  |  |  |
| ggml-org/NVIDIA-Nemotron-3-Nano-30B-A3B-GGUF | stock | ub1024 | agent |  |  |  |  | 5/5 | 0 | 28 |  |
| ggml-org/NVIDIA-Nemotron-3-Nano-30B-A3B-GGUF | src | ub1024 | ok |  | 65.2 | 15.1 | 2.1 |  |  |  |  |
| ggml-org/NVIDIA-Nemotron-3-Nano-30B-A3B-GGUF | src | ub1024 | agent |  |  |  |  | 5/5 | 0 | 29 |  |
| JetBrains/Mellum2-12B-A2.5B-Instruct-GGUF-Q8_0 | lmstudio | ub1024/b2048 | ok | 6.6 | 83.9 | 19.0 | 2.7 |  |  |  |  |
| JetBrains/Mellum2-12B-A2.5B-Instruct-GGUF-Q8_0 | lmstudio | ub512/b512 | ok | 6.2 | 84.2 | 17.7 | 2.7 |  |  |  |  |
| JetBrains/Mellum2-12B-A2.5B-Instruct-GGUF-Q8_0 | lmstudio | best ub512 | agent |  |  |  |  | 2/5 | 0 | 26 | easy 0/3;  |
| JetBrains/Mellum2-12B-A2.5B-Instruct-GGUF-Q8_0 | stock | ub1024 | ok |  | 86.4 | 16.4 | 0.6 |  |  |  |  |
| JetBrains/Mellum2-12B-A2.5B-Instruct-GGUF-Q8_0 | stock | ub1024 | agent |  |  |  |  | 0/5 | 0 | 9 |  |
| JetBrains/Mellum2-12B-A2.5B-Instruct-GGUF-Q8_0 | src | ub1024 | ok |  | 86.0 | 17.1 | 1.2 |  |  |  |  |
| JetBrains/Mellum2-12B-A2.5B-Instruct-GGUF-Q8_0 | src | ub1024 | agent |  |  |  |  | 1/5 | 0 | 13 |  |
| unsloth/NVIDIA-Nemotron-3-Nano-Omni-30B-A3B-Reasoning-GGUF | lmstudio | ub1024/b2048 | ok | 13.7 | 73.7 | 49.0 | 3.4 |  |  |  |  |
| unsloth/NVIDIA-Nemotron-3-Nano-Omni-30B-A3B-Reasoning-GGUF | lmstudio | ub512/b512 | ok | 15.8 | 59.6 | 18.4 | 3.1 |  |  |  |  |
| unsloth/NVIDIA-Nemotron-3-Nano-Omni-30B-A3B-Reasoning-GGUF | lmstudio | best ub512 | agent |  |  |  |  | 5/5 | 2 | 366 | easy 0/3;  |
| unsloth/NVIDIA-Nemotron-3-Nano-Omni-30B-A3B-Reasoning-GGUF | stock | ub1024 | ok |  | 62.3 | 13.5 | 1.5 |  |  |  |  |
| unsloth/NVIDIA-Nemotron-3-Nano-Omni-30B-A3B-Reasoning-GGUF | stock | ub1024 | agent |  |  |  |  | 5/5 | 2 | 76 |  |
| unsloth/NVIDIA-Nemotron-3-Nano-Omni-30B-A3B-Reasoning-GGUF | src | ub1024 | ok |  | 62.8 | 14.6 | 2.0 |  |  |  |  |
| unsloth/NVIDIA-Nemotron-3-Nano-Omni-30B-A3B-Reasoning-GGUF | src | ub1024 | agent |  |  |  |  | 5/5 | 0 | 44 |  |
| abenzerps/Apodex-1.1-mini-GGUF | lmstudio | ub1024/b2048 | ok | 16.4 | 85.2 | 28.0 | 185.5 |  |  |  |  |
| abenzerps/Apodex-1.1-mini-GGUF | lmstudio | ub512/b512 | ok | 18.3 | 67.1 | 32.1 | 4.0 |  |  |  |  |
| abenzerps/Apodex-1.1-mini-GGUF | lmstudio | best ub1024 | agent |  |  |  |  | 5/5 | 0 | 122 | easy 0/3;  |
| abenzerps/Apodex-1.1-mini-GGUF | stock | ub1024 | ok |  | 63.7 | 22.1 | 2.2 |  |  |  |  |
| abenzerps/Apodex-1.1-mini-GGUF | stock | ub1024 | agent |  |  |  |  | 4/5 | 0 | 21 |  |
| abenzerps/Apodex-1.1-mini-GGUF | src | ub1024 | ok |  | 64.7 | 24.7 | 2.9 |  |  |  |  |
| abenzerps/Apodex-1.1-mini-GGUF | src | ub1024 | agent |  |  |  |  | 5/5 | 0 | 28 |  |
| unsloth/gemma-4-12b-it-GGUF | lmstudio | ub1024/b2048 | ok | 9.6 | 21.7 | 165.9 | 6.2 |  |  |  |  |
| unsloth/gemma-4-12b-it-GGUF | lmstudio | ub512/b512 | ok | 7.3 | 22.1 | 166.8 | 13.2 |  |  |  |  |
| unsloth/gemma-4-12b-it-GGUF | lmstudio | best ub1024 | agent |  |  |  |  | 5/5 | 0 | 105 | easy 0/3;  |
| unsloth/gemma-4-12b-it-GGUF | stock | ub1024 | ok |  | 22.4 | 165.1 | 5.5 |  |  |  |  |
| unsloth/gemma-4-12b-it-GGUF | stock | ub1024 | agent |  |  |  |  | 5/5 | 0 | 82 |  |
| unsloth/gemma-4-12b-it-GGUF | src | ub1024 | ok |  | 22.3 | 170.6 | 9.0 |  |  |  |  |
| unsloth/gemma-4-12b-it-GGUF | src | ub1024 | agent |  |  |  |  | 5/5 | 0 | 92 |  |
| ornith-ai/Ornith-1.0-9B-GGUF | lmstudio | ub1024/b2048 | ok | 6.1 | 31.2 | 33.0 | 4.5 |  |  |  |  |
| ornith-ai/Ornith-1.0-9B-GGUF | lmstudio | ub512/b512 | ok | 6.1 | 31.3 | 29.2 | 3.4 |  |  |  |  |
| ornith-ai/Ornith-1.0-9B-GGUF | lmstudio | best ub512 | agent |  |  |  |  | 5/5 | 1 | 82 | easy 0/3;  |
| ornith-ai/Ornith-1.0-9B-GGUF | stock | ub1024 | ok |  | 31.8 | 31.5 | 2.8 |  |  |  |  |
| ornith-ai/Ornith-1.0-9B-GGUF | stock | ub1024 | agent |  |  |  |  | 5/5 | 0 | 49 |  |
| ornith-ai/Ornith-1.0-9B-GGUF | src | ub1024 | ok |  | 31.8 | 32.0 | 3.3 |  |  |  |  |
| ornith-ai/Ornith-1.0-9B-GGUF | src | ub1024 | agent |  |  |  |  | 5/5 | 0 | 43 |  |
| XHToken/Spark-X2.5-4B-GGUF | lmstudio | ub1024/b2048 | ok | 4.4 | 74.5 | 24.1 | 2.9 |  |  |  |  |
| XHToken/Spark-X2.5-4B-GGUF | lmstudio | ub512/b512 | ok | 4.1 | 74.4 | 19.9 | 2.9 |  |  |  |  |
| XHToken/Spark-X2.5-4B-GGUF | lmstudio | best ub512 | agent |  |  |  |  | 1/5 | 0 | 51 | easy 0/3;  |
| XHToken/Spark-X2.5-4B-GGUF | stock | ub1024 | ok |  | 75.1 | 22.1 | 0.8 |  |  |  |  |
| XHToken/Spark-X2.5-4B-GGUF | stock | ub1024 | agent |  |  |  |  | 2/5 | 0 | 32 |  |
| XHToken/Spark-X2.5-4B-GGUF | src | ub1024 | ok |  | 75.2 | 23.1 | 1.5 |  |  |  |  |
| XHToken/Spark-X2.5-4B-GGUF | src | ub1024 | agent |  |  |  |  | 1/5 | 0 | 28 |  |
| bartowski/Ling-3.0-tiny-GGUF | lmstudio | ub1024/b2048 | ok | 7.8 | 135.8 | 84.0 | 8.9 |  |  |  |  |
| bartowski/Ling-3.0-tiny-GGUF | lmstudio | ub512/b512 | ok | 4.5 | 136.4 | 88.0 | 5.8 |  |  |  |  |
| bartowski/Ling-3.0-tiny-GGUF | lmstudio | best ub1024 | agent |  |  |  |  | 5/5 | 0 | 25 | easy 0/3;  |
| bartowski/Ling-3.0-tiny-GGUF | stock | ub1024 | ok |  | 138.9 | 81.0 | 6.8 |  |  |  |  |
| bartowski/Ling-3.0-tiny-GGUF | stock | ub1024 | agent |  |  |  |  | 5/5 | 0 | 8 |  |
| bartowski/Ling-3.0-tiny-GGUF | src | ub1024 | ok |  | 141.9 | 82.5 | 7.1 |  |  |  |  |
| bartowski/Ling-3.0-tiny-GGUF | src | ub1024 | agent |  |  |  |  | 5/5 | 0 | 10 |  |
| bartowski/Cloudflare_clef-flash-GGUF | stock | ub1024 | failed |  |  |  |  |  |  |  | COULD NOT REACH THE SERVER at http://127.0.0.1:8081 (HTTP Error 500: Internal Server Error). Is LM Studio's server running? |
| bartowski/Cloudflare_clef-flash-GGUF | src | ub1024 | failed |  |  |  |  |  |  |  | COULD NOT REACH THE SERVER at http://127.0.0.1:8081 (HTTP Error 500: Internal Server Error). Is LM Studio's server running? |
| unsloth/Step-3.7-Flash-GGUF | lmstudio | ub1024/b2048 | ok | 34.4 | 22.1 | 103.8 | 3.5 |  |  |  |  |
| unsloth/Step-3.7-Flash-GGUF | lmstudio | ub512/b512 | ok | 33.4 | 22.1 | 598.9 | 3.6 |  |  |  |  |
| unsloth/Step-3.7-Flash-GGUF | lmstudio | best ub1024 | agent |  |  |  |  | 3/5 | 0 | 161 | easy None/None;  |
