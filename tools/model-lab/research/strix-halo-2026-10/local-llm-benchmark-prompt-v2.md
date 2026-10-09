# Runbook prompt (v2): find, tune and verify the best local LLM setup for a machine

Paste everything below the divider into an AI coding agent that has shell access, a real browser tool, and permission to download. It can be run on a new machine, or re-run months later when new models and runtimes appear ("refresh" mode, which builds on the previous findings instead of starting over). Written from a real 24-hour run on an AMD Strix Halo box; the Apple Silicon parts are marked where they are unverified.

---

## Fill these in

```
HARDWARE:      {{HARDWARE}}     e.g. "MacBook Pro M5 Max, 128 GB unified, macOS 26" / "Mac Studio M4 Max 128 GB" / "AMD Ryzen AI Max+ 395 128 GB, Windows 11"
MODE:          {{MODE}}         "fresh" or "refresh"
PRIOR_FINDINGS:{{PRIOR_FINDINGS}}  (refresh only) path to the previous findings-log.md / NEXT-STEPS.md / removal-list.md
USE_CASE:      {{USE_CASE}}     e.g. "headless agentic coding from Qwen Code and OpenCode, one client at a time, no repetition loops"
CLIENTS:       {{CLIENTS}}      the tools that will call the server (they decide tool-calling needs and prompt sizes)
ACCESS:        {{ACCESS}}       "nobody at the machine, remote over Tailscale" or "I can reboot it"
DISK_BUDGET:   {{DISK_BUDGET}}  e.g. "up to 500 GB of downloads"
PREFERENCES:   {{PREFERENCES}}  e.g. "a fast tier and a smarter/slower tier"
TOOLKIT:       {{TOOLKIT}}      folder holding llm_smoke.py and llm_bench.py (see "Toolkit" below)
```

## Your job

Work out which local models and settings give the best real-world experience for USE_CASE on HARDWARE, prove it with measurements on this machine, and leave behind a log, a recommendation, and everything needed to repeat it. Do the work; do not stop to ask questions you can answer by inspecting the machine or reading the web. Report at milestones only.

## Operating rules

1. **Log as you go** in `findings-log.md` (what you measured, with settings and versions). When a result later proves wrong, add a RETRACTION entry; never silently overwrite.
2. **Safety.** Never hard-delete files: write a delete list (path, size, Hugging Face URL, reason) and, if asked, a dry-run-by-default script for the user to run. Do not change OS, firmware, driver, security or firewall settings; give exact steps instead (for example, `sudo sysctl iogpu.wired_limit_mb=N` on macOS is the user's to run). If ACCESS is remote, do not load models that approach the GPU-memory limit: an overflow can freeze the machine and nobody can reset it.
3. **Run long jobs in the background** (downloads, builds, benchmarks), one GPU job at a time, watching with a monitor instead of sleeping. Verify a job actually started (log file exists) before walking away.
4. **Verify the verifier.** Before trusting a harness, run it on a known-good and a known-bad case. Repeat anything stochastic (agent tests: 5 trials per finalist). Do not generalize from one run.
5. **Prefer measured over reported.** Others' benchmarks are hypotheses; mark each claim "measured by me", "measured by someone else (who, when)", or "advice".
6. **Notify the user** (push notification if available) only for real milestones: key finding, shortlist ready, something broken.

## Phase 0: inventory (and, in refresh mode, what changed)

- Hardware facts: chip and memory (macOS `system_profiler SPHardwareDataType`, `sysctl hw.memsize`, `sysctl iogpu.wired_limit_mb`; Windows `Get-CimInstance Win32_*`, Adrenalin/BIOS GPU memory; Linux `lspci`, `rocm-smi`/`nvidia-smi`), free disk, power mode (laptops: test on AC, note thermal throttling), network (Tailscale IP, firewall).
- What is installed: LM Studio (version, runtime/engine versions, models folder), llama.cpp (stock `llama-server`), Ollama, MLX tools (`mlx-lm`, oMLX), Python, git, compilers/CMake.
- Models already on disk, and which runtimes can load them.
- **Refresh mode:** read PRIOR_FINDINGS first. List the previous keepers, rejects, and "revisit when X lands" items (open pull requests, unsupported architectures). Then research only what is new since the previous run's date: new models, new runtime releases, merged fixes. Re-run the previous keepers against the new runtime versions to catch regressions, and compare with the old CSVs.

## Phase 1: ceiling math (decide what is even worth testing)

- Generation is usually memory-bandwidth bound: tokens/s is roughly bandwidth divided by the GB of weights read per token. Only the active parameters of a mixture-of-experts model count; dense models above ~14B are slow on most unified-memory machines.
- Work out usable GPU memory: Windows AMD = the configured carve-out (and what Vulkan reports as addressable); Linux = GTT limit; NVIDIA = VRAM; **Apple = a default cap on GPU-wired memory (reportedly about 75% of RAM, verify) that a sysctl can raise until reboot**. Leave room for KV cache, the OS, and anything else running.
- Prefill (prompt processing) is separate from decoding and dominates agentic coding, where prompts are 20k+ tokens. Prefix caching decides whether turns after the first are fast. Measure both.

## Phase 2: research (use the real browser tool, not scrapers)

- Same or similar hardware: community wikis, GitHub discussions/issues for each runtime, hardware-review blogs. For Apple: the llama.cpp Apple Silicon benchmark discussion, mlx-community on Hugging Face, the oMLX repository and its issues. Check open bugs for your GPU/backend combination before depending on a feature (MTP, speculative decoding, ROCm, Metal).
- Hugging Face JSON API (far more reliable than the site): `https://huggingface.co/api/models?filter=gguf&sort=trendingScore&limit=60`, `...?search=<name>&filter=gguf&sort=downloads&direction=-1`, `https://huggingface.co/api/models/<org>/<repo>/tree/main[/<folder>]` for exact file names, sizes and the LFS SHA-256 (`lfs.oid`). For Apple, search `mlx-community` and the `mlx` library filter as well as GGUF.
- Rank candidates by downloads, recency, publisher trust (the model's own org, unsloth, bartowski, lmstudio-community, mlx-community; be wary of unknown uploaders), and size versus memory. Include close variants and "cousins" of promising models even if not on any list.
- Survey the engines worth trying on this hardware: the primary runtime (LM Studio), stock llama.cpp, and on Mac MLX (mlx-lm, oMLX, LM Studio's MLX engine). Skip vLLM/SGLang/Ollama unless the hardware or concurrency changes the case.
- Before downloading a huge file, check the runtime supports its architecture: Hugging Face reports each GGUF repo's architecture in the API (`gguf.architecture`) and every runtime embeds the names it supports, so `toolkit/archcheck.py <arch> --runtime <dir>` answers it for free (it showed LM Studio's runtime already supported `qwen4exp` and `glm5-next`, but nobody's supported `inkling` or the early-branch name `glm5next`).
- Windows release zips of llama.cpp are attached to the numbered build tags (b11433 and so on), not always to the newest `vX.Y.Z` tag: take the newest release that has the asset and verify the SHA-256 digest GitHub publishes.
- Test every model that works on both engines and tune each separately; do not stop at the first model count you pick, budgets are the limit.

## Phase 3: download safely

- One writer per file. Never resume a file another process may still be writing.
- **Verify by SHA-256 against the repo's LFS hash, not by size.** Size-only checks passed a corrupt file and a truncated one.
- Keep partial downloads out of the runtime's models folder (it indexes them and tries to load them); rename failed files so they are ignored.
- Find the model key the runtime assigned (for example `lms ls`) and test that key loads.

## Phase 4: baseline in the primary runtime

For every candidate, with the runtime's defaults first, using the toolkit:
1. Speed and load: `llm_smoke.py` (load time, first token, tokens/s).
2. Prefix cache: `llm_bench.py cache` (cold vs same-prefix vs new-prefix first token at ~24k tokens).
3. Agent reliability: `llm_bench.py agent` (easy task, then hard task with 5 trials). Provide a file-listing tool; without one, a wrong path guess can look like a model that loops.
4. Record which models load at all, and why not when they fail (architecture, format, memory).

## Phase 5: tune the primary runtime

- **LM Studio per-model defaults** live in `~/.lmstudio/.internal/user-concrete-model-default-config/<publisher>/<model>/<file>.gguf.json` (hub-listed models use `<key>.json`). They apply to loads triggered by a client request (just-in-time loading), not to `lms load`. **Write them as UTF-8 without a byte-order mark, or LM Studio silently ignores them.** Useful fields: `llm.load.contextLength`, `llm.load.numParallelSessions`, `llm.load.llama.physicalBatchSize` (ubatch), `llm.load.llama.evalBatchSize`, `llm.load.llama.flashAttention`, `llm.load.llama.tryMmap`, `llm.load.llama.keepModelInMemory`, `llm.load.llama.speculativeDecoding.draftMtp/draftMaxTokens/draftMinTokens/draftMinContinueProbability`. Confirm each change with `lms ps` (context, parallel slots) and a measurement.
- Server: bind address (`0.0.0.0` or the Tailscale IP), `autoStartOnLaunch` true, and the idle-unload timeout in `~/.lmstudio/settings.json` (`jitModelTTL.ttlSeconds`; the default 20 minutes unloads models and loses the cache). Back files up before editing.
- Sweep per model, one change at a time: ubatch (256/512/1024/2048), flash attention, parallel 1, context, mmap. Expect model-specific results (a bigger ubatch helped most MoE models and hurt a dense one).
- Speculative decoding: test MTP on one dense and one MoE model; in our runs it helped dense models and slowed small-active-parameter MoE models. Separate draft models and DFlash/DSpark were unreliable.

## Phase 6: try the alternatives head-to-head

- **Stock llama.cpp**: download the official release asset for the platform (Windows Vulkan/CUDA, macOS arm64 Metal, Linux), verify the digest GitHub publishes, and run `llama-server` with `-ngl 999 -fa on --jinja -np 1 -ub 1024 -b 2048` (flag names change between builds; read `--help`). Test with and without MTP. Compare to the tuned primary runtime on the same models with the same toolkit tests, including the agent trials (`--jinja` tool-calling parity). Note what you give up (UI, on-demand loading, one server per model unless you add a swapper such as llama-swap).
- **Source or pull-request builds** when a feature or fix is not yet released: Windows with w64devkit (GCC, CMake, Ninja) plus the Vulkan SDK; macOS with Xcode command-line tools and CMake (Metal is on by default); Linux per the docs. `git fetch --depth 1 origin pull/<N>/head` gets just the tip.
- **On Mac, MLX**: install `mlx-lm` and/or oMLX, use MLX-format models (mlx-community), start the server, then compare the same models against the GGUF/llama.cpp path: first-token time at 24k tokens (cold and cached; oMLX has a RAM and SSD prefix cache), decode tokens/s, memory use, tool-calling behaviour, and the agent trials. Check oMLX's current requirements (it reportedly demands an API key for non-local binds) and open issues. Also try LM Studio's own MLX engine if present.
- Decide per runtime whether the gain is worth the operational cost; state the numbers and your recommendation, then let the user decide.

## Phase 7: reliability for the real clients

- Agent tests: easy and hard task, tool calling on, 5 trials per finalist, report fixed rate, loop rate (an identical tool call repeated 4 or more times in a row), average seconds and turns. Read the call logs of any loop to see what repeated.
- Use each model card's recommended sampling for the real setup. Make sure the client keeps the system prompt and tool list byte-stable between turns so the prefix cache keeps hitting.
- Single-turn repetition tests and long-context tests are secondary; the multi-turn tool loop is what exposes real failures.

## Phase 8: operations and, optionally, a fleet

- Auto-start on boot/login, pinned models and long idle timeout, restore commands written down, a smoke-test launcher per model (`llm_smoke.py`), and a CSV history so regressions show up after updates.
- Several machines: one stable endpoint with a router that health-checks backends (Olla, LiteLLM, llama-swap are options); run the same model on two machines if you want failover without a different model's behaviour; do not pool memory across machines over a network. On Mac: `caffeinate`, `pmset`, a `launchd` job for the server, Tailscale MagicDNS names; verify sleep and clamshell behaviour yourself.

## Deliverables (in one folder, plus copies of the scripts and raw CSVs)

1. `findings-log.md`: running log, final recommendations table (fast default, fast alternates, smartest, bigger, slow-and-careful, and models to avoid with reasons), "not tested and why".
2. Recommended settings per model (and per runtime), written into the runtime's saved per-model configs and verified.
3. `NEXT-STEPS.md` with checkboxes: open decisions, re-test triggers (for example "re-test when pull request N merges"), housekeeping.
4. `removal-list.md`: every model not worth keeping with path, size, Hugging Face URL, one-line reason, plus a dry-run-by-default script for the user to run.
5. In refresh mode, a "Changes since last run" section at the top of the log.

## Toolkit (reuse; do not rewrite)

- `overnight_driver.py`: runs the whole per-model pipeline (check, download, both engines, variants, agent trials, report) for a repo list; `archcheck.py`: which runtimes support which architectures.
- `scout.py`: finds hot, recent Hugging Face models that fit `--mem-gb` and ranks them with a rough speed ceiling from `--bandwidth`; hides what is in `seen-models.txt`; `--json` for agents. Use it for Phase 2.

- `llm_smoke.py`: streams a short reply and prints load time, first-token time and live tokens/s; `--all` tests every configured model and appends to `smoke-results.csv`; `--long` adds the 24k-token cache test. Edit its `MODELS` table for the machine.
- `llm_bench.py cache --model KEY`: cold vs cached vs new-prefix first-token time at ~24k tokens.
- `llm_bench.py agent --model KEY --task easy|hard --trials 5`: multi-turn tool-calling test with a real code check, loop detection, and edit-the-tests detection.
- Both read `LLM_BASE` (default `http://localhost:1234`) and use only the Python standard library.

## Pitfalls we hit (check for each)

- PowerShell `Set-Content -Encoding utf8` adds a BOM: LM Studio ignored a config file, and a Python `exec` of a BOM-prefixed file failed every test.
- Benchmark scripts that wait for "other benchmarks" by scanning process command lines match each other and deadlock; chain jobs in one wrapper or gate on result files.
- Restarting or rebinding the model server mid-benchmark breaks running jobs; PowerShell prints "NativeCommandError" for harmless stderr (do not match on the word "error").
- `lms load` ignores saved per-model defaults; server-triggered loads honour them.
- Fixed `sleep` waits get blocked; use a monitor with an until-loop. Check a monitor's baseline so you do not miss results written before it started.
- An old community quant can use an architecture name current runtimes reject; a hub-listed model's config file is named by its key, not its file path.
- A model that "loops" in a test may be a harness gap (no list tool, wrong scorer). Prove the harness first.

## Unattended runs

For an overnight/refresh run on an already-working machine, use `overnight-agent-prompt.md` (it drives `scout.py` and the tests inside hard budgets and writes a morning report).

## Start

Begin with Phase 0 on HARDWARE (and, if MODE is refresh, read PRIOR_FINDINGS), state your plan in a few sentences, then work through the phases, logging as you go.
