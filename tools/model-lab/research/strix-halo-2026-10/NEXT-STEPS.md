# Next steps and open items

Written 2026-10-05 so nothing gets lost. Full results are in `findings-log.md`; the reusable research prompt is `local-llm-benchmark-prompt.md`.

## Where things stand

- Recommended models (see "FINAL RECOMMENDATIONS" in findings-log.md): fast default **Tiel-Coder-35B-A3B Q6_K_XL**; smartest **gpt-oss-120b**; bigger direct-answer **Qwen3.5-122B-A10B IQ4_XS**; avoid **Qwen3-Coder-30B** (loops).
- LM Studio server address for clients: `http://<strix-tailscale-address>:1234/v1` (Tailscale) or `http://localhost:1234/v1` on the box. Since 2026-10-06 the server listens on 0.0.0.0 (all interfaces) with auto-start on launch; it has no password, so the network boundary is what protects it. Use any dummy API key.
- A stock llama.cpp build is installed for experiments: `llama.cpp-b11424-vulkan\bin\llama-server.exe` (official ggml-org release, SHA-256 verified).

## LM Studio's server (restored after the experiment)

The experiment temporarily stopped LM Studio's server and then restarted it (confirmed running on <strix-tailscale-address>:1234). If it is ever down, restore it with:

```
"%USERPROFILE%\.lmstudio\bin\lms.exe" server start --bind 0.0.0.0 --port 1234
```

## DONE: stock llama.cpp vs LM Studio's bundled runtime (results: findings-log.md Update 33)

Summary: stock llama-server is faster for Tiel and gpt-oss (cold start 20-25% shorter, decode up to ~10-20% faster with MTP on Tiel) with no loss in agent reliability. Launch scripts are in `launchers\`. LM Studio's server was restarted after the tests.

### Original plan (kept for reference)

Compare on Tiel-Coder (and gpt-oss-120b): baseline flags, `-ub 1024 -b 2048`, `-ub 256`, `--cache-reuse 256`. Baseline LM Studio numbers for Tiel: decode 61-64 tok/s (74 on a long prompt), 24k prompt 31 s cold / 2.0 s cached. Results land in `raw-results\results_llamaserver.csv` (scripts: `scripts\bench_ls.ps1`). Things to decide afterwards:
- [ ] Is stock llama-server meaningfully faster or better-behaved than LM Studio? (If not, stay on LM Studio.)
- [ ] Does tool calling behave the same with `--jinja` (run the hard agent task, 5 trials, 0 loops)?
- [ ] Note: stock llama.cpp reports ~112 GB of Vulkan-addressable memory on this box (more than the 96 GB carve-out). Models up to ~100 GB might load; do that only with physical access (a memory overflow can freeze Windows).

## Fleet plan (needs your answers)

Proposed: Strix box always-on host; a gateway (Olla, or LiteLLM) bound to the Tailscale IP as the single endpoint; M5 Max as an optional fast backend (MLX/oMLX); M4 Pro and Mac mini as small or overflow backends; Tailscale-only binds plus API keys.
- [ ] How much RAM does the Mac mini have?
- [ ] Can Claude reach the Macs over SSH/Tailscale, or will you set those up?
- [ ] Decide gateway: Olla (simple, health-check failover) or LiteLLM (API keys, session pinning).
- [ ] Set up the gateway on the Strix box, route the three Strix models through it, point Qwen Code / OpenCode at the one address.
- [ ] Add the M5 Max as a warm backend; test sleep/wake behaviour (unverified: Wake-on-LAN, caffeinate, clamshell).
- [ ] Remember failover loses the prefix cache (one re-prefill, 30-75 s on a 24k prompt), so run the same model on both machines if you want smooth failover.

## Housekeeping (nothing was deleted by Claude)

- [ ] Remove the corrupt 35 GB file `Tiel-Coder-35B-A3B-MTP-UD-Q6_K_XL.gguf.corrupt` from `.lmstudio\models\peculiar-ragdoll\Tiel-Coder-35B-A3B-GGUF-MTP\`.
- [ ] Optional disk space: Qwen3.8-27B Q8_0 (29 GB; the Q6 is equal quality and faster), Nemotron-3-Super (86 GB), Hermes-4-70B (42 GB).
- [ ] The `scripts\` folder points at <strix-tailscale-address>:1234; edit the address before reuse on another machine.

## Ideas not yet tried

- Very large models (DeepSeek-V4-Flash 180B, GLM-5.3-Flash, K2-Horizon): only with physical access.
- Qwen3.8-Flash-Next (smaller quants), Gemma-4-26B-A4B, ISTA Flash-Next-Coder.
- Qwen Code / OpenCode with real project tasks (my harness is a small synthetic task).
- Check Qwen's recommended sampling (temp 1.0, top_p 0.95, top_k 20 for thinking mode) against what the clients send by default.

## New open items from the llama.cpp experiment
- [ ] Decide: switch the daily driver to stock llama-server (launchers/start-tiel-coder.ps1), or stay on LM Studio.
- [ ] If switching: try llama-swap (or Olla) to load models on demand on one port.
- [ ] Test Qwen3.5-122B, Qwen3.6 and AgentWorld on the stock build with -ub 1024 -b 2048.
- [ ] Test prompts near 128k tokens (cold prefill will take minutes; prefix caching is what makes it usable).


## TODO: model cleanup (reclaim disk). The authoritative list with Hugging Face URLs and reasons is `removal-list.md`; a dry-run-by-default script is `launchers\remove-models.ps1`.

(older summary:) Nothing here has been deleted; remove them yourself in LM Studio > My Models (trash icon), or from `%USERPROFILE%\.lmstudio\models`

Sizes are approximate. "Why" is based on this research (tests are in findings-log.md).

### Safe to remove (tested bad, unusable here, or redundant)
- [ ] `peculiar-ragdoll\...\Tiel-Coder-35B-A3B-MTP-UD-Q6_K_XL.gguf.corrupt`: 35 GB. Corrupt partial download.
- [ ] `nvidia/nemotron-3-super` (Nemotron-3-Super 120B-A12B): 86 GB. Slow (22 tok/s, 69 s to first token on a 23k prompt).
- [ ] `kingjones777/DeepSeek-V4-Flash-180B-ROCmFP4-STRIX_LEAN`: 96 GB. Needs a custom ROCmFPX engine fork; does not run in LM Studio.
- [ ] `otheru/DeepSeek-V4-Flash-Strix-Halo-GGUF` (ROCmFPx 2.58bpw): 91.5 GB, plus its DSpark draft: 10.9 GB. Same custom-engine problem; the draft failed to load.
- [ ] `nousresearch/hermes-4-70b` (dense 70B): 42.5 GB. Untested, but a dense 70B is bandwidth-limited to roughly 5 tok/s here.
- [ ] `qwen3.8-27b-uncensored-rocmfp4-strix-mtp` (kingjones777): 25.5 GB. Failed to load in LM Studio (custom ROCmFP4 format and MTP head).
- [ ] `qwen3-coder-30b-a3b-instruct` (Qwen3-Coder-30B-A3B Q4_K_M): 18.6 GB. Loops in agent runs (never stops after success).
- [ ] `qwen3.8-whittle-moe-27b-a17.8b`: 18.3 GB. Failed to load (HTTP 400); 17.8B active parameters is slow anyway.
- [ ] `lmstudio-community/Qwen3.8-27B-GGUF/Qwen3.8-27B-Q8_0.gguf`: 29 GB. The Q6_K tested equal and runs faster.
- [ ] Small drafters, about 3.7 GB total: `lumen-qwen3-bootstrap` (1.1 GB), `qwen3-coder-instruct-draft-0.75b` (0.47 GB), `glm-4.5-draft-0.6b-v3.0` (0.43 GB), `Qwen3.8-27B-DFlash-bootstrap` (1.7 GB). DFlash/DSpark drafting is unreliable in LM Studio and drafts hurt MoE models.
- Subtotal of the above: about 457 GB.

### Decide after the GLM-5.3-Flash test (running)
- [ ] `avar6/GLM-5.3-Flash-BF16-gguf` IQ2_XXS (2.32bpw): 86 GB + mmproj 1.1 GB. Keep only if it runs well on stock llama.cpp.
- [ ] `lausannequants/GLM-5.3-Flash-GGUF` UD-IQ1_M: about 91 GB + mmproj 1.1 GB. A 1-bit quant of the same model; likely redundant if the IQ2_XXS works, and probably lower quality.

### Untested, your call
- [ ] `IFM/K2-Horizon-MoVA-36B-A4B` (BF16): 74.9 GB. Not tested; BF16 weights make it heavy for the bandwidth (about 8 GB read per token).

### Keep (tested good)
Tiel-Coder-35B-A3B Q6_K_XL (32 GB), gpt-oss-120b (63 GB), Qwen3.5-122B-A10B IQ4_XS (62 GB; shows in LM Studio as `ud`), Qwen3.6-35B-A3B MTP Q6_K (30 GB), Qwen-AgentWorld-35B-A3B Q6_K (29 GB), Qwen3.8-27B Q6_K (22 GB), Ornith-1.5-35B-A3B Q4_K_M (21 GB).

## DONE 2026-10-05: removal list executed by the user
13 items removed (C: free space went from 842 GB to 1,268 GB, about 426 GB reclaimed). LM Studio now lists 10 LLMs: the 7 keepers (Tiel-Coder, gpt-oss-120b, Qwen3.5-122B shown as `ud`, Qwen3.6-35B MTP, AgentWorld, Qwen3.8-27B Q6_K, Ornith) plus the 3 held items (two GLM-5.3-Flash files, K2-Horizon). Still open: decide on those 3 (GLM: re-test after llama.cpp PR 29928 merges; K2-Horizon untested).

## llama.cpp PR #29928 (GLM-5.3-Flash MTP + optimize), tried 2026-10-05
Built from source (w64devkit + Vulkan SDK; build script `C:\Users\Jonathan\llama-build\build-pr29928.ps1`, binary in `C:\Users\Jonathan\llama-build\llama.cpp-pr29928\build\bin\`). Result: no speedup (524 s cold start on a 20k prompt, 19.9 tok/s, same as stock) and MTP does not work yet ("GLM5-Next NextN graph not implemented yet"). Re-test when the MTP follow-up merges; until then GLM-5.3-Flash is not usable for agentic coding here. `C:\Users\Jonathan\llama-build\tools` (unneeded portable toolchain, ~235 MB) can be deleted.

## Decisions recorded 2026-10-05
- GLM-5.3-Flash `avar6` IQ2_XXS (~86 GiB): **KEEP** (user decision), for re-testing once llama.cpp lands working MTP / prefill improvements for GLM5-Next.
- Still undecided: `lausannequants` GLM-5.3-Flash UD-IQ1_M (~91 GiB, likely redundant 1-bit quant of the same model) and K2-Horizon BF16 (~75 GiB, untested).

## Update: the two held models were tested and both fail to load
K2-Horizon (unknown architecture 'k2-horizon', needs a fork) and lausannequants GLM IQ1_M (old architecture name 'glm5next'). Recommended: run `remove-models-round2.bat` (about 175 GB). Still keeping the avar6 GLM IQ2_XXS.

## DONE 2026-10-05: LM Studio optimized (see findings-log.md Update 41)
Saved per-model default configs for all 7 keepers (BOM-free JSON; context 131072, 1 slot, ubatch 1024/batch 2048 (27B: 512), flash attention, mmap off; MTP on only for the 27B) and a 24-hour idle timeout. Remaining decision: run stock llama.cpp directly or stay on tuned LM Studio (summary in Update 41). If switching, the "click to run" automation is: one launcher per model (launchers\*.ps1/.cmd), plus a small menu, plus llama-swap for on-demand loading (untested).

## DONE 2026-10-06: light smoke tests
`smoke\` has `llm_smoke.py` (standard-library Python) and double-click launchers: one per model, `RUN ALL`, and a `--long` variant. Live streaming output plus a `smoke-results.csv` history. See `smoke\README.md`.

## DONE 2026-10-06: server listens on all interfaces
LM Studio saved config (`.lmstudio\.internal\http-server-config.json`): `networkInterface` 0.0.0.0 and `autoStartOnLaunch` true (it was false, which is why the server stayed down after an app restart). Backup: `http-server-config.json.bak-before-0000`. Verified reachable on 127.0.0.1, localhost and <strix-tailscale-address>. The llama.cpp launchers in `launchers\` now bind 0.0.0.0 too. Windows Firewall was not touched.

## DONE 2026-10-06: reusable prompts and toolkit
- `local-llm-benchmark-prompt-v2.md`: full runbook (fresh or refresh mode; Windows/AMD, Linux, macOS incl. MLX/oMLX; apple-specific parts marked unverified).
- `overnight-agent-prompt.md`: unattended overnight agent (find, download, benchmark, tune, morning report) with hard budgets and safety rules.
- `toolkit\`: `scout.py` (hot-model finder), `llm_smoke.py`, `llm_bench.py` (cache + agent tests), `seen-models.txt`, README. Tested on this machine: scout, agent (Tiel: 2/2 fixed, 0 loops) and cache.
- [ ] First real use on the Mac: set MEM_GB and BANDWIDTH_GBS for that chip, run `scout.py --format mlx` and `--format gguf`, and verify the Apple-specific notes in the v2 prompt (wired-memory limit, MLX/oMLX behaviour).

## 2026-10-06: overnight batches 1 and 2 (22 repos, 475 GB downloaded) and what to do next
Results: `findings-log.md` Updates 44 to 47, `overnight/MORNING-REPORT.md`, `overnight2/MORNING-REPORT.md`.

### Updated recommendation (replaces "stay on LM Studio")
- On 12 of 14 models tested on both engines, stock llama.cpp finished the same hard agent task 1.3 to 8x faster than LM Studio with equal fix rates (fast MoE models 2 to 5x). The PR #29928 source build matched stock, so it is not worth maintaining. **Recommended: switch the daily driver to stock llama.cpp (b11433 at `C:\Users\Jonathan\llama-build\stock-latest\bin`)**, one model per port, with llama-swap if you want on-demand loading. Keep LM Studio as the GUI/model manager. Confirm with a real Qwen Code or OpenCode session before relying on it (my harness is a synthetic task).
- Tiers: fast = POCKET-35B, Nemotron-3.5-Lightning, Ling-3.0-tiny (verify with more trials), Ornith-35B / KAT-Coder / BigBang; smart/slow = Qwen3.8-Flash-Next UD-Q2_K_XL (stock only, 28 tok/s, 31 s per task) and gemma-4-31B; tiny = FrogNano-4B.
- [ ] Decide: switch (see above) or stay on LM Studio.
- [ ] Repeat the top 5 to 6 models with 15+ hard trials and a second, different hard task to catch intermittent loops (Nemotron-3-Nano-Omni and Ornith-9B each looped on some runs).
- [ ] Test Step-3.7-Flash and the ISTA IQ1_M Flash-Next Coder (58 GB, skipped for budget) on stock only.

### Mac proof tomorrow (nothing has touched the Macs yet)
1. On the Mac: install llama.cpp (Homebrew `brew install llama.cpp`) and/or oMLX; note chip, unified memory and bandwidth.
2. Copy the `toolkit\` folder; run `python scout.py --mem-gb <usable GB> --bandwidth <GB/s> --format gguf` and `--format mlx` to build the queue.
3. Run `overnight_driver.py run ... --stock-exe <llama-server on the Mac>` (leave `--lmstudio-runtime` off if there is no LM Studio; check the driver handles that; if not, patch it) with `watchdog.py` (now works on macOS/Linux: uses `ps`/`kill`).
4. Check what breaks and fix the toolkit (path separators, Windows-only assumptions such as `taskkill`/PowerShell calls in the driver, `Name='python.exe'` kill patterns used by hand).
5. Success = a morning report with at least 3 models tested, no loops reported falsely, and the prompt needing no edits beyond the placeholders.

### Removal candidates from tonight's tests (nothing deleted; I do not delete files)
Reject for this use, safe to remove (paths under `%USERPROFILE%\.lmstudio\models`; sizes approximate):
- granite-4.2-30b Q6_K (24 GB, ibm-granite/granite-4.2-30b-GGUF): 9 tok/s dense, 2/5 on the task.
- Muse-Glimmer-30B UD-Q5_K_XL (22 GB, unsloth/Muse-Glimmer-30B-GGUF): 10 tok/s dense.
- Nemotron-3-Nano-Omni-30B-A3B UD-Q5_K_S (25 GB, unsloth/NVIDIA-Nemotron-3-Nano-Omni-30B-A3B-Reasoning-GGUF): loops.
- Mellum2-12B-A2.5B Q8_0 (13 GB, JetBrains/Mellum2-12B-A2.5B-Instruct-GGUF-Q8_0): 0 to 2 of 5.
- Spark-X2.5-4B Q4_K_M (2.6 GB, XHToken/Spark-X2.5-4B-GGUF): 1 to 2 of 5.
- clef-flash Q5_K_M (7 GB, bartowski/Cloudflare_clef-flash-GGUF): not a chat model for llama-server.
- Optional (keep only if you want a slow tier): gemma-4-12b Q6_K (9.8 GB), gemma-4-31B-it-qat (17 GB), Step-3.7-Flash UD-IQ3_XXS (74 GB, 10-minute cold prefill).

### Pre-Mac check done on the Strix box (2026-10-06 19:01)
`overnight_driver.py run` with only `--stock-exe` (no `--lmstudio-runtime`, as it will be on a Mac) worked end to end: arch check, download, stock tests, agent trials, morning report (`overnight3-nolms\`). It reproduced Ling-3.0-tiny: 140.9 tok/s, 5/5 hard, 8 s. Note: `--hours` below about 0.5 makes the driver skip every model for budget (use 1 or more). Still unproven: the POSIX paths on macOS itself (`watchdog.py` ps/kill branch, `lms` absence, path separators), Metal instead of Vulkan, and oMLX.
