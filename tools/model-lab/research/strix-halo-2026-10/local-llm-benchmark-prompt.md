# Reusable prompt: find and benchmark the best local LLMs for my hardware

Fill in the placeholders in the first block, then paste everything below the line into an AI coding agent that has shell access and (ideally) a real browser tool. Everything is written so it works on any hardware.

---

## Fill these in

```
HARDWARE:        {{HARDWARE}}
                 e.g. "AMD Ryzen AI Max+ 395, 128 GB LPDDR5X-8000, Windows 11, ~96 GB GPU carve-out"
                 e.g. "Apple M4 Max, 128 GB unified, macOS"
                 e.g. "2x RTX 3090 24 GB + 64 GB DDR5, Ubuntu 24.04"
RUNTIME:         {{RUNTIME}}          e.g. LM Studio / llama.cpp server / Ollama / vLLM / MLX
USE_CASE:        {{USE_CASE}}         e.g. "headless agentic coding via Qwen Code / OpenCode, one client at a time"
ACCESS:          {{ACCESS}}           e.g. "remote over Tailscale, nobody at the machine" or "local, I can reboot it"
DISK_BUDGET:     {{DISK_BUDGET}}      e.g. "up to 500 GB of downloads"
SPEED_VS_QUALITY:{{PREFERENCE}}       e.g. "want a fast tier and a smarter/slower tier"
MUST_AVOID:      {{MUST_AVOID}}       e.g. "models that get stuck in repetition/tool-call loops"
```

## Your task

Find a handful of local models that work for USE_CASE on HARDWARE, benchmark them yourself on this machine, and keep a running findings log (`findings-log.md`) as you go. Recommend a fast tier and a smarter tier. Use the real hardware; do not rely on spec sheets or other people's numbers except as hypotheses to test.

### Ground rules (lessons learned the hard way)

1. **Ask no questions you can answer yourself.** Inspect the machine (RAM, VRAM or unified-memory split, GPU, drivers, runtime version, installed models, free disk) before planning. Make sensible defaults and state them in the log.
2. **Safety.** Never hard-delete files; write a "delete candidates" list in the log instead. Do not change OS, firmware, driver or security settings; give the user exact steps. If the machine is remote and unattended, do NOT load models that approach the GPU memory limit (on some systems an overflow freezes the whole box and needs a physical reset). Note those as "untested, try with physical access".
3. **Log everything.** Every result, every mistake, every retraction goes in `findings-log.md` with the settings used. If a result later turns out to be invalid, add a RETRACTION entry; do not silently overwrite.
4. **Background long jobs.** Run downloads and benchmarks in the background, one GPU job at a time, and report as results arrive. Do not sit in sleep loops.

### Step 1: understand the hardware ceiling

- Token generation is usually **memory-bandwidth bound**: tokens/s is roughly bandwidth (GB/s) divided by the GB of weights read per token. Only the *active* parameters of a mixture-of-experts (MoE) model are read per token, so MoE models with a few billion active parameters are far faster than dense models of the same size. Dense models above ~14B will be slow on bandwidth-limited machines.
- Work out the usable GPU memory, leave room for the KV cache, and decide the largest model size that fits.
- Prompt processing (prefill) is separate from generation and matters a lot for agentic work, where prompts are often 20k+ tokens.

### Step 2: research candidates (use a real browser tool, not blocked scrapers)

- Search for others' measurements on the same or similar hardware (community wikis, GitHub discussions and issues for the runtime, hardware review blogs). Treat them as hypotheses and note whether each claim was measured or just advice.
- Use the Hugging Face JSON API for listings, which is much more reliable than the website:
  - `https://huggingface.co/api/models?filter=gguf&sort=trendingScore&limit=60`
  - `https://huggingface.co/api/models?search=<name>&filter=gguf&sort=downloads&direction=-1`
  - `https://huggingface.co/api/models/<org>/<repo>/tree/main` (exact file names, sizes and the LFS SHA-256 in `lfs.oid`)
- Rank candidates by **download count, recency/newness, publisher trust, and size-vs-memory fit**. Prefer known publishers (the model's own org, unsloth, bartowski, lmstudio-community). Be cautious with obscure uploaders; high downloads and likes and a month or more of age help.
- Also try close "cousins" of promising models even if they are not on any list.
- Check what the runtime actually supports (speculative decoding modes, known bugs on this GPU backend) before testing it.

### Step 3: download safely

- Use **one writer per file**. Never launch a second resume of a file another process may still be writing: two writers corrupted a 32 GB file.
- **Verify by SHA-256, not by file size.** Compare against the LFS `oid` from the repo tree API. A size-only "done" marker fired falsely twice (one curl exit after 11 of 30 GB; one oversize corrupt file).
- If a file fails verification, rename it (e.g. `.corrupt`) so the runtime ignores it and re-download to a fresh name. Do not leave partial `.gguf` files where the runtime can index them; it will try to load them and report confusing errors.
- Check the exact model key the runtime assigned (for example `lms ls`); `name@quant` forms may not be valid load keys.

### Step 4: benchmark, in this order

Run each model with full GPU offload, a single slot (parallel 1), and a stated context size. Record runtime version and sampling settings.

1. **Short-prompt speed**: decode tokens/s on a ~100-token prompt, 300-token reply, run twice.
2. **Long-prompt speed and prefix-cache test** at ~20-25k prompt tokens: time-to-first-token (a) cold, (b) same prefix with a different final question (cache hit), (c) a different prefix (cache miss). This single test predicts how an agent feels in practice.
3. **Repetition test**: four long coding generations (~3000 tokens) at each model's recommended sampling; score the fraction of repeated 8-word sequences. This only catches single-turn degeneration.
4. **Agentic tool-calling tests, the real loop detector.** Build a small harness against the OpenAI-compatible endpoint with tools `list_files`, `read_file`, `write_file`, `run_tests`:
   - *Easy task*: one bug in one file.
   - *Hard task*: three independent bugs in one module, tests read-only (flag any attempt to edit tests), up to ~16 turns. Execute the model's edited code for real to score it.
   - Record: fixed yes/no, turns, tool calls, invalid tool arguments, the **longest run of identical consecutive tool calls** (>=4 counts as a loop), wall time.
   - **Run 5 trials per finalist.** Sampling is random and one model passed once and looped on the next run.
   - Save every tool-call sequence to a file so you can read what a loop actually looked like.
5. **Speculative decoding / MTP** where supported: measure it on one dense and one MoE model. In my runs it helped dense models (+20-75%) and slowed small-active-parameter MoE models.
6. **Context size**: repeat the long-prompt test at 2x the context to see if a bigger window costs speed.
7. **Backend comparison** (for example Vulkan vs ROCm vs CUDA vs Metal) on one MoE and one dense model.

### Harness pitfalls that produced wrong results (check yours)

- Windows PowerShell writes UTF-8 files **with a byte-order mark**; a Python `exec(open(f).read())` then fails with `U+FEFF`, so every model "fails". Read with `utf-8-sig` or write without BOM. Validate the scorer against a known-correct solution *and* a known-buggy one before trusting any result.
- Do not make benchmark scripts wait on each other by scanning process command lines; they matched each other and deadlocked. Chain jobs sequentially in one wrapper, or gate on result files.
- If a tool is missing from your harness (no file-listing tool), a model that guesses a wrong path can loop forever. That looked like a model flaw but was a harness flaw. Give agents the same tools real clients provide.
- Restarting or rebinding the model server mid-benchmark silently breaks the running jobs.
- Do not match error text on the word "error" in shell wrappers; PowerShell prints "NativeCommandError" for harmless stderr.
- Reasoning-first models spend many tokens thinking; judge them by time-per-task, not tokens/s alone.

### Step 5: final report

Write the recommendations at the end of `findings-log.md`:

- A table: fast default, fast alternates, smartest, bigger/direct-answer option, slow-and-careful option, and models to **avoid** with the reason.
- For every model: decode tokens/s, cold and cached time-to-first-token at ~24k, agent trials (fixed/loops/avg seconds), file size, and download source.
- Recommended runtime settings (context, parallel, KV cache type, speculative decoding on/off per model type, sampling).
- Client tips: keep the system prompt and tool list byte-stable so the prefix cache hits; give the model list/glob tools; cap turns client-side as a safety net.
- A "not tested and why" section and a "delete candidates" list with paths and sizes.
- Notify me (push/notification if available) at real milestones only: a key finding, a model verified, something broken, the final shortlist.

Begin by inspecting HARDWARE and stating your plan in two or three sentences, then start working.
