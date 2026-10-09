# model-lab

model-lab finds, downloads, and measures local language models for one machine's hardware. It is the slow, manual sibling of ambrosio. Ambrosio watches for hot models every day and pulls a few. model-lab asks a harder question. Which recent, popular models fit this memory? Which of those run at a useful speed, and which finish real agent work without looping? Answering that takes hours, so you run it by hand, about once a month.

It runs on macOS, Linux, and Windows. It needs Python 3.8 or newer and nothing else from pip. It runs from this checkout and installs nothing.

## Start

On macOS or Linux, run `tools/model-lab/model-lab`. On Windows, run `tools\model-lab\model-lab.cmd`, or `py -3 tools\model-lab\model_lab.py`. The examples below use `model-lab` for all of these.

First describe the machine. A profile holds four values. They are the memory for the weights, the memory bandwidth, the model format, and the address of the model server to measure. Run `model-lab profile detect` to see what the machine has. Then save a profile:

```
model-lab profile set strix --mem-gb 85 --bandwidth 256 --server http://localhost:1234
```

The memory figure is the memory for the weights alone: usable GPU or unified memory, minus room for the context cache and the operating system. The bandwidth comes from the chip's published specification. Profiles are per hardware, so one machine can scout for another. A Windows box can run `model-lab profile set m5 --mem-gb 100 --bandwidth 614 --format mlx` and then `model-lab --profile m5 scout`.

## The commands

- `model-lab --profile strix scout` lists hot, recent Hugging Face models that fit the profile. It shows the best quantization that fits, the real parameter count, and a rough speed ceiling. It also flags unknown publishers, risky formats, and architectures that failed before. It needs only the network and takes a minute or two. Add `--json` for a machine-readable queue.
- `model-lab smoke <model>` loads a model on the server and prints the load time, the first-token time, and the tokens per second. Add `--long` for a 24,000-token test of cold and cached first-token time.
- `model-lab bench agent --model <model>` runs a multi-turn tool-calling task with a real code check. It counts fixes, loops, and edits to the tests. The model's code runs on this machine, in a temporary folder with a 20-second limit.
- `model-lab bench cache --model <model>` compares cold, cached, and new-prefix first-token times.
- `model-lab overnight run --repos a/b-GGUF,c/d-GGUF --stock-exe <llama-server> --mem-gb 85` is the unattended pipeline. For each repository it picks a quantization and checks that the runtimes know the architecture. Then it downloads the file with a resume and a SHA-256 check, tests it, and writes `MORNING-REPORT.md`. It never deletes files. Use `--max-download-gb` and `--min-free-gb` to set the budgets, and one `--workdir` per batch.
- `model-lab watch --workdir <dir> --driver-cmd-file <json>` restarts a stalled overnight run.
- `model-lab arch gemma4 --runtime <dir>` shows which runtimes know an architecture, so an unsupported model is skipped before the download.
- `model-lab seen add <term>` hides models you already tested from future scouts.
- `model-lab wantlist --from queue.json` prints family terms for ambrosio. Add `--ambrosio` to append them to `~/.ambrosio/wantlist.txt`, or `--append-to <file>` for another file.

## How it fits with ambrosio

Ambrosio's job is the daily watch. It pulls MLX models onto the always-on Mac and tells you when something is worth trying. Its size limit is a fixed number, not a measurement of the hardware. model-lab supplies what ambrosio lacks: it knows what fits and what runs well. The two stay separate tools. The handoff is the want-list. After a monthly run, `model-lab wantlist --from queue.json --ambrosio` adds the models that fit and are worth trying, and ambrosio pulls them on its normal pass.

## Where it keeps things

Everything lives in `~/.model-lab`, or in the folder named by `MODEL_LAB_HOME`. That folder holds the profiles, the list of tested models, the smoke-test history, and the default overnight run folder. Nothing is written inside the checkout. Set `MODEL_LAB_HF_BASE` to point at a Hugging Face mirror, and `LLM_BASE` to override the server address for one run.

## The research behind it

`research/strix-halo-2026-10/` holds the record of the first run of this method. The machine was an AMD Ryzen AI Max+ 395 box with 128 GB of memory, tested on 5 and 6 October 2026. The record has the findings log, the open items, and the overnight reports. It also has the raw result tables and the reusable prompts that an agent can follow to repeat the research. An agent session on the Windows box wrote them. Treat the findings as that session's measurements on that machine. The reusable prompts are the best place to learn the method.

## Tests

`python test_model_lab.py` runs the test suite. It starts a stub Hugging Face server and a stub model server on the local machine, so it needs no network and no real model. The same file runs on Windows. `bash test-model-lab.sh` runs it inside astra's slow tier.
