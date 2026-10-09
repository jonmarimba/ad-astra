# Strix Halo model findings log

Machine: Ryzen AI Max+ 395, Radeon 8060S, 128 GB LPDDR5X-8000 (~256 GB/s), Windows 11, ~96 GB GPU carve-out. LM Studio 0.4.25, llama.cpp Vulkan 2.51.0.
Use case: headless coding via Qwen Code / OpenCode from a remote Mac over Tailscale, one client, no loops. Want a fast tier and a smarter/slower tier.
Server: bound to Tailscale IP <strix-tailscale-address>:1234 (OpenAI-compatible at /v1).

## Method
- `lms load <model> --gpu max -c <ctx> -y`, then OpenAI-style request, stats from LM Studio's /api/v0 endpoint.
- Defaults otherwise: 4 slots (use --parallel 1 going forward), f16 KV, no per-model overrides on tested models.
- Short test: 38-97 token prompt, 300 tokens out. Long test: ~21k-token prompt.

## Results: short prompt (decode tok/s)
| Model | tok/s | Note |
|---|---|---|
| Qwen3-Coder-30B-A3B Q4_K_M | 81.8 | fast; coding benchmark by others: 5/10 |
| Ornith-1.5-35B-A3B Q4_K_M | 70.1 | |
| gpt-oss-120b MXFP4 | 50.0 | coding benchmark by others: 9/10 |
| Nemotron-3-Super 120B-A12B Q4_K_M | 23.3 | |
| Qwen3.8-27B Q8 (dense) | 7.9 | 10-12 with MTP on |
| Qwen3.8-Whittle-MoE | failed | HTTP 400; has saved per-model config (numExperts 8, DFlash drafter) |

Qwen3.8-27B Q8 with MTP: unsupported for the kingjones777 "strix-mtp" file (no supported bundled head).
Backend: ROCm 2.40.0 slower than Vulkan 2.51.0 (Coder-30B 67 vs 82; gpt-oss 46 vs 50). Vulkan restored.

## Results: ~21k-token prompt, cold (no cache)
| Model | prefill tok/s | time to first token | decode tok/s |
|---|---|---|---|
| Qwen3-Coder-30B-A3B | 546 | 41.1 s | 45.1 |
| gpt-oss-120b | 614 | 33.6 s | 41.4 |

## Memory
gpt-oss-120b: ~61 GB in GPU memory. OS-visible RAM climbs to its 31.6 GB ceiling during load and stays there; likely file cache, unconfirmed.

## External evidence (others' measurements, not mine)
- 23-model coding benchmark on a 128 GB Strix Halo (soothill.io): gpt-oss-120b 9/10; Qwen AgentWorld 35B-A3B Q6_K 8/10 at 7.2 s/task; Qwen3.8-27B Q6_K MTP 8/10; Qwen3.5-122B-A10B 7/10 ~21 tok/s; Qwen3-Coder-30B only 5/10.
- Qwen model card sampling (thinking): temp 1.0, top_p 0.95, top_k 20, min_p 0. Avoid low temperature/greedy in agent loops.

## In flight
- Downloads (all from unsloth / lmstudio-community): Qwen-AgentWorld-35B-A3B UD-Q6_K (29 GB), Qwen3.8-27B Q6_K (22 GB), Qwen3.5-122B-A10B-MTP UD-IQ4_XS (~62 GB).
- Cache-reuse experiment (cold vs same-prefix vs new-prefix TTFT) on gpt-oss-120b and Coder-30B, parallel=1, ctx 64k.
- Nemotron and Qwen3.8-27B long-prompt reruns (earlier failures were caused by my server restart / partial download).

## Settings changed (nothing persistent except)
- LM Studio server rebound to Tailscale IP only.

## Update 1 (long prompt, cold, ~23k tokens)
| Model | prefill tok/s | TTFT | decode tok/s |
|---|---|---|---|
| Nemotron-3-Super 120B-A12B Q4_K_M | 336 | 69.3 s | 22.2 |
Verdict so far: Nemotron is too slow for interactive agentic coding (nearly 70 s before first token on a 23k prompt).
Qwen3.8-27B long run errored: LM Studio indexed the partially downloaded Q6_K file. Retest after download completes.

## Notes
- Per-model settings live in ~/.lmstudio/.internal/user-concrete-model-default-config/<publisher>/<model>.gguf.json (keys: contextLength, cpuThreadPoolSize, contextCheckpoints, speculativeDecoding.*, argumentsOverride).
- LM Studio default n_slots = 4 with unified KV; using --parallel 1 for the single-client case.
- Delete candidates (not deleted; user removes via LM Studio My Models): qwen3.8-27b Q8_0 (29 GB) once Q6 verified; anything failing tests.
- Downloads: AgentWorld Q6_K and Qwen3.8-27B Q6_K in progress (~33 MB/s combined); Qwen3.5-122B UD-IQ4_XS queued behind them.

## Candidate discovery (Hugging Face API, by trending/downloads/recency)
Download queue order: AgentWorld Q6_K -> Qwen3.8-27B Q6_K (parallel), then Qwen3.5-122B UD-IQ4_XS (62 GB), Qwen3.6-35B-A3B-MTP UD-Q6_K (30 GB), Tiel-Coder-35B-A3B-MTP UD-Q6_K_XL (32 GB).
- peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF-MTP: 1.59M downloads, 247 likes, uploaded 2026-08-24, MIT, agentic-coding finetune of Ornith 1.5 35B-A3B with MTP. Queued.
- unsloth/Qwen3.8-Flash-Next-GGUF: 1.4M downloads. UD-IQ4_XS is ~94 GB (too big for 96 GB carve with context). Needs smaller quant; reports say it needs unmerged llama.cpp PRs for good MTP.
- ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF: coding variant, expert-pruned, 351k downloads, uploaded 2026-09-26. Only IQ1_M folder seen (very low bit); candidate, not queued.
- empero-ai/Qwen3.8-35B-A3B-Distill-GGUF: 558k downloads, 2026-09-16. Candidate.
- unsloth/gemma-4-26B-A4B-it-GGUF: 521k downloads, different family. Candidate.
- bytkim/Qwen3.8-27B-pi-GGUF: coding/tool-use/MTP, only 10k downloads, 2026-09-29. Low trust, skip for now.

## Update 2: prompt-cache reuse (KEY FINDING)
gpt-oss-120b, parallel=1, ctx=65536, ~20.6k-token prompt:
- cold: 33.7 s to first token
- same prefix, new question: 0.3 s to first token (cache hit)
- different prefix: 33.6 s (cache miss)
- decode: 42.4 tok/s
Implication: for agentic coding the cold first turn costs ~34 s, then turns that keep the prompt prefix byte-stable are near-instant. Qwen Code / OpenCode must not rewrite the system prompt or tool list between turns, or every turn pays full prefill.

## Update 3: research agent on speculative decoding / cache (sources: LM Studio bug tracker, llama.cpp discussions; claims are others' reports unless marked tested)
- Risk: llama.cpp #27306 (2026-08-18, open): on gfx1151 Vulkan, MTP (--spec-type draft-mtp) can crash with GPU device-lost mid-prompt on long prompts; non-MTP survived 125k tokens. MTP with --parallel >1 corrupts output across slots (#28286). Keep parallel=1. Batch/ubatch 1024 reportedly avoids it (not exposed in LM Studio as far as known).
- LM Studio DFlash/DSpark drafters: open failure reports (#2181, #2394). Treat as unreliable. Simple draft needs identical vocab; weak drafts can slow generation.
- Measured by others (dense Qwen3.8-27B Q4_K_XL, ROCm): MTP n=2 22 tok/s, n=12 59 tok/s cold; with ngram-mod real code 29-40 tok/s. ROCm ~2x Vulkan generation on that model. LM Studio cannot combine MTP+ngram-mod yet (#2409).
- No data found for speculative decoding on MoE on Strix Halo; one CUDA report shows MTP cost 38% on a Flash-Next MoE.
- Cache: hybrid-recurrent Qwen models (Qwen3.8, Qwen3.5-122B, AgentWorld-family) cannot trim state, so prefix edits force re-prefill; per-model contextCheckpoints setting exists (a config of yours uses 32). gpt-oss (plain attention) cache works great (Update 2).
- argumentsOverride JSON format: not publicly documented. Method: set it in the UI and read the saved per-model JSON.
- Compatible draft files found: unsloth MTP sidecar mtp-Qwen3.8-27B-Q4_0.gguf (1.4 GB, already in the unsloth repo MTP folder); z-lab DFlash2 for Qwen3.8-27B; no MTP for Coder-30B or gpt-oss-120b; gpt-oss EAGLE3 files are safetensors (not usable).

## Plan changes
1. Test cache behavior (cold/cached/new-prefix) on hybrid models (Qwen3.8-27B Q6, AgentWorld) with contextCheckpoints set, not just gpt-oss.
2. Test ROCm vs Vulkan on dense Qwen3.8-27B Q6 (others report ROCm ~2x for dense; my MoE test favored Vulkan).
3. MTP only with parallel=1, ctx modest, and watch for GPU resets.

## Update 4: cache reuse, Qwen3-Coder-30B-A3B (parallel=1, ctx 64k, ~22.5k-token prompt)
- cold 40.7 s, same prefix 0.9 s, new prefix 40.7 s, decode 44.9 tok/s. Plain-attention models cache well.
- Loop test started (gpt-oss-120b temp1.0/top_p1.0; Coder-30B 0.7/0.8/20; Ornith 1.0/0.95/20).

## Update 5: loop test (4 long coding generations each, max 3000 tokens; score = fraction of repeated 8-word sequences, 0 = none)
| Model | sampling | repetition scores | finish |
|---|---|---|---|
| gpt-oss-120b | temp 1.0, top_p 1.0 | 0.020, 0.015, 0.014, 0.004 | length x4 |
| Qwen3-Coder-30B-A3B | temp 0.7, top_p 0.8, top_k 20 | 0.019, 0.008, 0.075, 0.015 | length, stop, stop, length |
| Ornith-1.5-35B-A3B | temp 1.0, top_p 0.95, top_k 20 | 0, 0, 0.068, 0 | length x4 |
No loops detected at these settings (length finishes = long answers hitting the cap, not repetition). Caveat: single-turn tests, not multi-turn tool use.

## Ops note
Benchmark scripts had a self-inflicted deadlock (wait-for-other-benchmark checks matched each other's command lines). Fixed by running one sequential chain: Qwen3.8-27B Q6 plain, Qwen3.8-27B Q6 MTP, AgentWorld plain, AgentWorld loop test.

## Update 6: loop test, Qwen-AgentWorld-35B-A3B UD-Q6_K (unsloth), temp 1.0 / top_p 0.95 / top_k 20
repetition scores 0.015, 0.058, 0.026, 0.008; finish = length x4. No loops detected (single-turn).
Model key note: `lms load qwen/qwen3.8-27b` loads the selected variant (Q6_K); `@q6_k` suffix is not a valid load key.

## Update 7: downloads
- Qwen3.5-122B-A10B-MTP UD-IQ4_XS (unsloth, 61.9 GB, 3 shards, sizes verified) complete; LM Studio key is 'ud'. Queued: plain+cache test, then loop test.

## Update 8: Qwen3.8-27B Q6_K (lmstudio-community), Vulkan 2.51, parallel 1, ctx 64k, no MTP, temp 0.7/top_p 0.8/top_k 20
- decode: 10.0 / 10.0 tok/s (short), 9.3 (long)
- ~24.3k-token prompt: cold TTFT 100.0 s (~243 tok/s prefill), same-prefix 4.2 s, new prefix 99.6 s
- Output is reasoning-first (reasoning content before the answer), so effective time to answer is longer than decode speed suggests.
Verdict: dense 27B is the slow tier. High accuracy per others' coding benchmark (8/10) but about 10 tok/s and 100 s cold prefill. Hybrid cache works (4.2 s) but is less sharp than plain-attention models (0.3-0.9 s). MTP test pending.

## Update 9: Qwen3.8-27B Q6_K with MTP (bundled head; draft min 2, max 4, continue-prob 0.75), Vulkan 2.51, parallel 1
- decode: 12.1 / 13.0 tok/s short (plain 10.0), 16.4 long-prompt (plain 9.3) => +21-30% short, +76% on repetitive code
- ~24.3k prompt: cold TTFT 104.1 s (plain 100.0), cached 5.4 s (plain 4.2), new prefix 103.8 s
- No GPU reset or crash; output start identical to plain run (spot check only, not a full quality test).
Verdict: MTP is a modest win on the dense model and cheap to keep on; prefill is ~4% slower. Still the slow tier.

## Ops note 2
A 'download done' marker for Qwen3.6-35B-A3B-MTP fired early (curl exit 18, file only 11.5 of 30 GB). Resumed with size-verified retry loops for Qwen3.6 and Tiel-Coder. Benchmarks are gated on those verified markers. 122B shards were byte-verified and are fine.

## Update 10: Qwen-AgentWorld-35B-A3B UD-Q6_K (unsloth), Vulkan 2.51, parallel 1, ctx 64k, no MTP, temp 0.7/top_p 0.8/top_k 20
- decode: 53.4 / 54.2 tok/s short, 47.9 long
- ~24.3k-token prompt: cold TTFT 30.1 s (~807 tok/s prefill), same prefix 1.5 s, new prefix 30.2 s
- Loop test (Update 6): no loops.
- Output is reasoning-first ("Thinking Process:..."), so answer latency = reasoning tokens / decode speed.
Verdict: strongest fast-tier candidate so far. Others' coding benchmark: 8/10 at 7.2 s/task. Faster prefill than gpt-oss-120b (614 tok/s) and the cache works on this hybrid model (1.5 s).

## Update 11: Qwen3.5-122B-A10B UD-IQ4_XS (unsloth MTP repo, 61.9 GB), Vulkan 2.51, parallel 1, ctx 64k, no MTP flag, temp 0.7/top_p 0.8/top_k 20
- decode: 33.8 / 32.2 tok/s short, 32.7 long (others reported ~21 tok/s)
- ~24.3k-token prompt: cold TTFT 76.1 s (~319 tok/s prefill), same prefix 4.2 s, new prefix 76.1 s
- Output starts directly with code (not reasoning-first), so answer latency is lower than the 27B or AgentWorld at similar tok/s.
- Loop test pending.
Verdict: strong "smart, slower" candidate, much faster decode than the dense 27B (33 vs 10) with a bigger model. Others' coding score 7/10 (gpt-oss-120b 9/10 at ~50 tok/s remains the accuracy leader).

## Update 12: loop test, Qwen3.5-122B-A10B IQ4_XS, temp 1.0 / top_p 0.95 / top_k 20
repetition scores 0, 0.01, 0, 0.002; finish = length x4. No loops detected (single-turn).

## Update 13: multi-turn tool-calling harness (bench_agent.ps1)
Task: fake repo, one failing test (discount computed wrong). Tools: read_file, write_file, run_tests (the model's edited code is executed in Python to verify the fix). Max 12 turns, temp 0.7/top_p 0.8/top_k 20, ctx 64k, parallel 1.
Scores: valid tool-call arguments, longest run of identical consecutive tool calls (loop signal), fixed yes/no, wall time.
- AgentWorld-35B-A3B Q6 (smoke test): 5 turns, 4 tool calls, 0 invalid args, 0 identical repeats, FIXED, 28 s total.
Caveat: this task is easy (one bug); a harder multi-bug task would separate models better. Queued for: gpt-oss-120b, Qwen3.5-122B, Coder-30B, Ornith, Qwen3.6-35B, Qwen3.8-27B+MTP.

## Update 14: Qwen3.6-35B-A3B UD-Q6_K (unsloth MTP repo, 30 GB), Vulkan 2.51, parallel 1, ctx 64k, no MTP flag, temp 0.7/top_p 0.8/top_k 20
- decode: 65.7 / 74.6 tok/s short, 76.0 long
- ~24.3k-token prompt: cold TTFT 32.1 s (~757 tok/s prefill), same prefix 2.1 s, new prefix 32.2 s
- Reasoning-first output ("Here's a thinking process...").
Verdict: fastest quality-tier model so far (vs AgentWorld 53 tok/s, same size/arch family). Others' coding benchmark: Qwen3.6-35B-A3B 6/10 vs AgentWorld 8/10, so AgentWorld is likely the better coder at lower speed. MTP and loop tests pending.

## Update 15: Qwen3.6-35B-A3B Q6_K with MTP (draft min 2, max 4, continue-prob 0.75)
- decode: 50.4 / 68.4 tok/s short (plain 65.7 / 74.6), 56.6 long (plain 76.0); prefill unchanged (cold 32.1 s, cached 2.1 s)
=> MTP is SLOWER on this MoE (-23%, -8%, -26%). Confirms the expectation: speculative decoding helps dense models (Qwen3.8-27B: +21-30%) but hurts small-active-param MoEs.
Recommendation: MTP on for dense 27B only; off for all A3B/MoE models.

## Update 16: loop test, Qwen3.6-35B-A3B Q6_K (no MTP), temp 1.0 / top_p 0.95 / top_k 20
repetition scores 0.032, 0.027, 0, 0.003; finish = length x4. No loops detected (single-turn).

## Ops note 3: Tiel-Coder download race (not yet usable)
My resume script raced the original download (two/three writers on one file); the file grew to 35.2 GB vs expected 32,233,201,504 bytes, and a size-only completion marker fired falsely. Extra writers killed. Checking SHA-256 of the first 32,233,201,504 bytes against the published LFS hash (ebf721ae...b085e). If it does not match, re-download to a fresh filename. Tiel is excluded from benchmarks until verified. Lesson: verify with SHA-256, not size. Other downloads loaded and produced coherent output; hash-verify them when the GPU is idle.

## Ops note 4: Tiel-Coder corrupt, re-downloading
SHA-256 of the first 32.2 GB did NOT match the published hash. Corrupt file renamed to Tiel-Coder-35B-A3B-MTP-UD-Q6_K_XL.gguf.corrupt (not deleted; ~35 GB; remove manually when convenient). Fresh single-writer download running with SHA-256 verification (tiel.verified / tiel.failed markers).

## Update 17: agent test (easy), first results
- AgentWorld: fixed, 5 turns, 20 s, 0 invalid, 0 repeats.
- gpt-oss-120b: NOT fixed; 12 turns, 12 tool calls, one tool call repeated 10x in a row (loop). Unclear whether harness (tool-message format / sampling 0.7/0.8/20 vs OpenAI's recommended temp 1.0) or model. Diagnostic runs queued: default+logging, +tool name field, +temp 1.0/top_p 1.0, both. This is exactly the failure the user wants to avoid, so it needs a root cause.

## Update 18: EASY agent task, complete (one bug, tools: read/write/run_tests; temp 0.7/top_p 0.8/top_k 20; ctx 64k; parallel 1)
| Model | turns | tool calls | invalid args | max identical repeat | fixed | seconds |
|---|---|---|---|---|---|---|
| Qwen3-Coder-30B-A3B Q4_K_M | 5 | 4 | 0 | 0 | yes | 8 |
| Qwen3.6-35B-A3B Q6_K | 5 | 4 | 0 | 0 | yes | 10 |
| Ornith-1.5-35B-A3B Q4_K_M | 6 | 5 | 0 | 0 | yes | 14 |
| Qwen-AgentWorld-35B-A3B Q6_K | 5 | 4 | 0 | 0 | yes | 20 |
| Qwen3.5-122B-A10B IQ4_XS | 6 | 5 | 0 | 0 | yes | 25 |
| Qwen3.8-27B Q6_K + MTP | 5 | 5 | 0 | 0 | yes | 27 |
| gpt-oss-120b MXFP4 | 12 | 12 | 0 | 10 | NO | 16 |
gpt-oss-120b looped (same tool call 10x). Diagnostics queued (default+logging, tool-name field, temp 1.0, both). Easy task does not separate the six passers; hard task (3 bugs, iterate on failing output) is running next.

## Update 19: Tiel-Coder-35B-A3B-MTP UD-Q6_K_XL (peculiar-ragdoll)
Re-downloaded with a single writer; SHA-256 matches the published hash (ebf721ae...b085e), size exactly 32,233,201,504. LM Studio key: tiel-coder-35b-a3b-mtp. Queued: plain speed/cache, loop test, easy + hard agent tasks (after the gpt-oss diagnostics). Corrupt earlier copy remains as ...gguf.corrupt (35 GB; user may remove).

## RETRACTION (hard agent task)
Results labelled hard-* in results_agent2.csv (hard-agentworld: not fixed/repeat 6; hard-gptoss120b: not fixed; and other hard-* rows written before the fix) are INVALID. Cause: my scoring driver exec'd test files written by PowerShell with a UTF-8 BOM, causing a SyntaxError on every run, so no model could pass and models saw tracebacks (which also explains repeated run_tests calls). Fixed (driver reads utf-8-sig) and validated against a known-correct solution (4 passed). Clean reruns queued as hard2-* labels for all seven models; hard-tiel35b runs after the fix and is valid. The easy task is unaffected (runs the file directly); its results stand.

## Update 20: why gpt-oss looped (easy task)
Call log: run_tests, read_file('pricing.py') [wrong path -> error], then run_tests x10 with no edit and no retry of the read. Default settings reproduce it (dbg-a). Hypotheses: (1) reasoning_content not passed back between tool turns (gpt-oss reasons before each call), (2) recovery from a tool error is weak, (3) OpenAI-recommended sampling (temp 1.0). Diagnostics b (tool name), c (temp 1.0), d (both) queued; added e/f (keep reasoning, +temp 1.0). The easy harness has no list_files tool, so a wrong path guess is unrecoverable; the hard task provides list_files.

## Update 21: gpt-oss-120b easy-task diagnostics a-d (all identical)
a default / b +tool-name field / c temp 1.0, top_p 1.0 / d both: each = 12 turns, 12 tool calls, one call repeated 10x, not fixed, ~16 s.
Ruled out: tool-message `name` field, sampling temperature. Remaining hypotheses: reasoning_content not passed back (e, f queued) and no file-listing tool in the easy task (hard task has list_files; clean hard2-gptoss120b rerun queued).
Interim verdict: gpt-oss-120b is risky for agentic tool loops in my harness; do not choose it as the daily agent model without a passing e/f or hard2 result.

## Update 22: Tiel-Coder-35B-A3B-MTP UD-Q6_K_XL (peculiar-ragdoll, hash-verified), Vulkan 2.51, parallel 1, ctx 64k, no MTP flag, temp 0.7/top_p 0.8/top_k 20
- decode: 61.3 / 63.7 tok/s short, 74.4 long
- ~24.5k-token prompt: cold TTFT 31.3 s (~782 tok/s prefill), same prefix 2.0 s, new prefix 31.4 s
- Output starts directly with code (not reasoning-first), so answer latency is lower than AgentWorld / Qwen3.6 at similar speed.
Verdict: strong fast-tier candidate; coding-tuned and direct. Loop and agent tests queued.

## Update 23: clean hard-task reruns (3 bugs, list_files available) and a nondeterminism warning
- hard2-agentworld: fixed, 6 turns, 28 s, 0 repeats.
- hard2-gptoss120b: fixed, 7 turns, 16 s, 0 repeats (so the easy-task loop is a path-recovery weakness, not general tool-calling failure).
- hard2-qwen35-122b: fixed, 6 turns, 42 s, 0 repeats.
- hard2-coder30b: fixed_all=True but 16 turns, one call repeated 10x (kept re-running tests after succeeding); its earlier run was clean (9 turns, repeat 3). => results are NONDETERMINISTIC; single runs are not enough.
- Post-fix single runs (valid): Ornith fixed 5 turns/16 s; Qwen3.6-35B fixed 5 turns/16 s; Qwen3.8-27B+MTP fixed 5 turns/41 s; Tiel-Coder fixed 5 turns/15 s.
Plan: 5 trials per model on the hard task (bench_trials.ps1; 3 for the slow 27B), measuring pass rate and loop rate (max identical repeat >= 4). Runs after gpt-oss e/f.

## Update 24: gpt-oss easy-task diagnostics e/f
e (keep reasoning) and f (keep reasoning + temp 1.0): both identical to a-d: 12 turns, repeat 10, not fixed. Ruled out: tool 
ame field, temperature, reasoning passback (caveat: LM Studio may not return a reasoning_content field, so e/f may not have changed the messages). Remaining explanation: no list_files in the easy task, so a wrong path guess is unrecoverable (hard task with list_files passes). Added -ListTool option; g/h run the easy task with list_files, queued after the trials.

## Update 25: five-trial hard agent task (3 bugs, list_files available, temp 0.7/top_p 0.8/top_k 20, ctx 64k)
| Model | fixed | loops (max identical repeat >= 4) | avg seconds | avg turns |
|---|---|---|---|---|
| Tiel-Coder-35B-A3B Q6_K_XL | 5/5 | 0/5 | 18 | 5 |
| Qwen-AgentWorld-35B-A3B Q6_K | 5/5 | 0/5 | 44 | 6 |
| Qwen3.6-35B-A3B Q6_K | 5/5 | 0/5 | 16 | 5 |
| Ornith-1.5-35B-A3B Q4_K_M | 5/5 | 0/5 | 16 | 5.2 |
| Qwen3-Coder-30B-A3B Q4_K_M | 5/5 | 2/5 (repeat 10-11 after fixing; kept re-running tests) | 20 | 10.8 |
| Qwen3.5-122B-A10B IQ4_XS | 5/5 | 0/5 | 35 | 6 |
| gpt-oss-120b MXFP4 | 5/5 | 0/5 | 15 | 6.4 |
| Qwen3.8-27B Q6_K + MTP (3 trials) | 3/3 | 0/3 | 40 | 5 |

## Update 26: Qwen3-Coder-30B-A3B loop pattern (hard task, trials 4 and 5, plus an earlier rerun)
After a correct write_file fix it calls run_tests 10-11 times in a row (output says "4 passed" each time) and never emits a final answer; it hits the 16-turn cap. Loop rate across 6 hard-task runs: 3/6 (earlier rerun + trials 4,5); all runs fixed the code. Failure mode = no termination after success, not wrong code.
Verdict: reject Qwen3-Coder-30B-A3B for unattended agentic use despite being fastest per task (~10 s) when it does terminate.

## Update 27: five-trial hard task complete
All eight models finished (table above). Clean (no loops): gpt-oss-120b, Qwen3.6-35B, Ornith-35B, Tiel-Coder-35B, Qwen3.5-122B, AgentWorld-35B, Qwen3.8-27B+MTP (3 trials). Loops: Qwen3-Coder-30B (2/5; never terminates after fixing). Queued: ctx 131072 speed/cache runs for Tiel, gpt-oss, Qwen3.5-122B, Qwen3.6 (after gpt-oss list-tool tests g/h).

## Update 28: gpt-oss easy-task root cause CONFIRMED
With a list_files tool added to the easy task: g = fixed, 6 turns, 5 calls, 10 s; h = fixed, 6 turns, 5 calls, 9 s; 0 identical repeats. Without it, all six variants (a-f) looped 10x. Root cause: the harness gave no way to recover from a wrong-path guess; not a sampling, message-format, or reasoning-passback problem. gpt-oss-120b is reliable for agentic coding when the client provides a file-listing/glob tool (Qwen Code and OpenCode both do).
Retracts the interim verdict in Update 21 ("risky for agentic loops").

## Update 29: 128k context (ctx 131072) vs 64k, ~24k-token prompt, parallel 1
| Model | decode short | cold TTFT | cached TTFT | decode long |
|---|---|---|---|---|
| Tiel-Coder-35B Q6_K_XL | 59-67 | 31.3 s | 2.1 s | 74.4 |
| gpt-oss-120b | 50.6 | 33.3 s | 0.3 s | 41.3 |
| Qwen3.5-122B IQ4_XS | 34.9 | 75.7 s | 4.3 s | 33.1 |
| Qwen3.6-35B Q6_K | 68-78 | 32.1 s | 2.1 s | 70.0 |
Identical to 64k results: allocating a 128k window costs no measured speed at a 24k prompt. Not tested: prompts approaching 128k (prefill would then take many minutes cold; prefix caching is what makes it usable).

## FINAL RECOMMENDATIONS (for headless coding via Qwen Code / OpenCode over Tailscale, one client)
LM Studio server: http://<strix-tailscale-address>:1234/v1 (bound to the Tailscale IP only). Runtime: llama.cpp Vulkan 2.51.0. Settings for all: full GPU offload, parallel 1, context 131072 (64k also fine), f16 KV, default flash attention. MTP: ON only for dense Qwen3.8-27B; OFF for all A3B/MoE models (it slows them).

1. FAST DEFAULT: Tiel-Coder-35B-A3B Q6_K_XL (key tiel-coder-35b-a3b-mtp). 59-74 tok/s, answers directly (no reasoning preamble), 5/5 hard agent trials, 0 loops, 18 s per task, hash-verified file. 24k prompt: 31 s cold, 2 s cached.
2. FAST ALTERNATES: Qwen3.6-35B-A3B Q6_K (66-78 tok/s, reasons first, 5/5, 0 loops, 16 s) and your existing Ornith-1.5-35B-A3B Q4_K_M (70 tok/s, 5/5, 0 loops, 16 s).
3. SMARTEST: gpt-oss-120b MXFP4 (50 tok/s, 5/5, 0 loops, 15 s/task, cached prefix 0.3 s, top score 9/10 in an outside coding benchmark). Needs a client with a file-listing tool (Qwen Code/OpenCode have one).
4. BIG DIRECT-ANSWER: Qwen3.5-122B-A10B IQ4_XS (33-35 tok/s, 5/5, 0 loops, 35 s/task, 76 s cold on 24k). Qwen-AgentWorld-35B-A3B Q6_K (53 tok/s, 5/5, 0 loops, but 44 s/task: reasons first).
5. SLOW/CAREFUL: Qwen3.8-27B Q6_K + MTP (12-16 tok/s, 3/3, 0 loops, 40 s/task). Use only if you want a dense model.
AVOID: Qwen3-Coder-30B-A3B (loops 3 of 6 hard runs: never stops after fixing); Nemotron-3-Super 120B (22 tok/s, 69 s to first token on 23k prompt); dense 70B (Hermes-4) untested but ~5 tok/s by bandwidth math.
Agent-client tips: keep the system prompt and tool list byte-stable between turns so the prefix cache hits (cached first token 0.3-4 s vs 30-76 s cold); give the model a list/glob tool; cap turns client-side as a safety net; Qwen's card recommends temp 1.0/top_p 0.95/top_k 20 for thinking mode (my agent trials used 0.7/0.8/20 and showed no loops for the recommended models).

## Not tested (and why)
Very large downloads (DeepSeek-V4-Flash 180B ~96 GB, GLM-5.3-Flash ~94-99 GB, K2-Horizon 75 GB, Whittle-MoE load error): loading near the 96 GB GPU carve risks a Windows memory-overflow freeze; the user is remote and a freeze needs a physical reset. Try these when someone is at the machine/KVM. Qwen3.8-Flash-Next (UD-IQ4_XS ~94 GB too big; smaller quants/Coder variants unverified), Gemma-4-26B-A4B, ISTA Flash-Next-Coder: candidates for a later round.

## Housekeeping for the user (nothing deleted by me)
- Corrupt partial: peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF-MTP/Tiel-Coder-35B-A3B-MTP-UD-Q6_K_XL.gguf.corrupt (35 GB) can be removed.
- Candidates to remove if space is wanted (not tested/low value): Qwen3.8-27B Q8_0 (29 GB, Q6 is equal quality and faster), Nemotron-3-Super (86 GB), Hermes-4-70B (42 GB).
- Downloaded and kept: Tiel-Coder Q6_K_XL (32 GB), Qwen3.6-35B-A3B MTP Q6_K (30 GB), Qwen-AgentWorld Q6_K (29 GB), Qwen3.8-27B Q6_K (22 GB), Qwen3.5-122B IQ4_XS (62 GB).

## Update 30: other inference engines (research agent; sources: kyuz0 toolboxes, strixhalo.wiki, llama.cpp issues, Lemonade/Ollama issue trackers; mostly others' reports, not measured here)
- No engine found that beats llama.cpp for single-client agentic coding on Strix Halo. Only upgrade worth trying: current stock llama.cpp `llama-server` (Vulkan) instead of LM Studio's bundled runtime (newer speculative modes, batch/--cache-reuse flags LM Studio hides). Untested here.
- ROCm/HIP on gfx1151 has open correctness reports (llama.cpp #25992: cross-request responses, garbled output, broken tool calls; #29092: recurrent-state leak on Qwen3.5/3.6/3.8, unresolved). Vulkan reported clean. Matches my own result that ROCm was slower on MoE models. Keep Vulkan.
- vLLM: Linux only, built for concurrency (published numbers are batched throughput), needs AWQ/BF16 not GGUF. Skip. Ollama: many open gfx1151 bugs. Lemonade/Jan: wrappers over llama.cpp. SGLang, ik_llama.cpp (no ROCm/Vulkan), mistral.rs: no usable gfx1151 evidence.
- Windows vs Linux: Linux adds vLLM, experimental forks, ~120 GB GPU memory; stock llama.cpp Vulkan works on Windows.

## Update 31: fleet architecture research (agent; repo activity checked 2026-10-05; unverified items flagged)
Measured by others (Linux Strix Halo, llama.cpp build 9193, 2026-05-16, kyuz0): Qwen3.6-35B-A3B Q4 ~1100 pp / ~60 tg; gpt-oss-120b ~720 / ~57; Qwen3.5-122B-A10B Q5 ~309-337 / ~22 (Vulkan RADV best for generation). My Windows numbers are in line (Tiel 61-74 tg; gpt-oss 50; 122B IQ4_XS 34).
Apple (llama.cpp 7B Q4_0 benchmark, 2026-08): M4 Pro 273 GB/s ~440 pp / ~51 tg; M5 Max 614 GB/s ~3220 pp / ~120 tg (dense 7B; M5 Max ~7x prefill, ~2.4x decode vs M4 Pro). No Mac mini row found.
Gateway options: Olla (github.com/thushan/olla; active; priority routing, failover, health checks, auto model discovery, conversation pinning for KV reuse; no auto-registration; small project), LiteLLM proxy (priority tiers, cooldowns, session_affinity, virtual keys; heavier), llama-swap (per-host model swapping, not multi-machine), LM Studio LM Link (Tailscale-based device sharing, not a failover gateway). vllm-router: poor fit. Open WebUI Pipelines: stale.
Pooling across machines (exo: MLX/Mac-first, fast mode needs Thunderbolt 5 RDMA; llama.cpp RPC: "fragile and insecure"): not recommended over Tailscale; run different models on different machines instead.
Mac serving: oMLX (MLX server with RAM+SSD prefix KV cache, Anthropic/OpenAI APIs, requires an API key for non-local binds) is the strongest prefix-cache option on Mac. macOS gives the GPU ~75% of RAM by default (64 GB -> ~48 GB; 128 GB -> ~96 GB).
Proposed layout: Strix always-on (gpt-oss-120b, Tiel-Coder, Qwen3.5-122B) + Olla (or LiteLLM) gateway bound to the Tailscale IP; M5 Max as an optional high-priority fast-model backend (35B-A3B via oMLX/MLX); M4 Pro and Mac mini as small always-on or overflow backends; health checks add/drop laptops automatically; keep the same model on two machines so a failover costs only one re-prefill; bind to Tailscale only + API keys + ACLs. Unverified: Wake-on-LAN/caffeinate/clamshell behavior, LM Link offline behavior, LM Studio behind a gateway, MLX vs llama.cpp speed for these exact MoE models, cross-machine draft models (not practical).

## Update 32: stock llama.cpp b11424 (official ggml-org Vulkan x64 release, SHA-256 verified) vs LM Studio runtime, Tiel-Coder Q6_K_XL, ctx 64k, parallel 1
Flags common to all: -ngl 999 -fa on -lm none (this build replaced --no-mmap with -lm none) --jinja -np 1. llama-server reports ~112 GB of Vulkan-addressable memory on this box (more than the 96 GB carve-out).
| Variant | cold prefill tok/s | cold TTFT (24.5k tokens) | cached TTFT | decode short | decode long |
|---|---|---|---|---|---|
| LM Studio runtime (reference) | 782 | 31.3 s | 2.0 s | 61-64 | 74 |
| A baseline | 972 | 25.0 s | 1.7 s | 54-56 | 48 |
| B -ub 1024 -b 2048 | 1086 | 22.4 s | 2.2 s | 56 | 48 |
| C -ub 256 | 776 | 31.3 s | 1.4 s | 55 | 48 |
| D --cache-reuse 256 | 980 | 24.8 s | 1.7 s | 56 | 49 |
Takeaways so far: larger ubatch speeds prefill (-ub 1024 -b 2048: 28% faster cold start than LM Studio), -ub 256 matches LM Studio's speed (LM Studio likely uses a small ubatch), --cache-reuse made no difference, decode is ~12% lower than LM Studio's (unexplained; follow-up variants E-H queued: -fa auto, mmap, 12 threads, -ub 2048). The decode_long gap (48 vs 74) may partly be a measurement difference. gpt-oss run pending.

### Update 32b: gpt-oss-120b on stock llama.cpp b11424 (baseline flags)
decode 55.1/55.5 tok/s (LM Studio 50.0/50.6), cold prefill 762 tok/s (LM Studio 614), cold TTFT 27.0 s on 20.6k tokens (LM Studio 33.3 s), cached 0.2 s (0.3), decode long 45.7 (41.3). Stock build is ~10% faster decode and ~24% faster prefill on gpt-oss; Tiel decoded ~12% slower than in LM Studio (hypothesis: LM Studio uses Tiel's bundled MTP head by default; variants I (draft-mtp) and J (ngram-mod) queued).

### Update 32c: Tiel on stock llama.cpp, follow-up variants (all with -ub 1024 -b 2048 unless noted)
| Variant | cold prefill | cold TTFT | cached TTFT | decode short | decode long |
|---|---|---|---|---|---|
| E -fa auto | 1088 | 22.3 s | 2.2 s | 55 | 48 |
| F -lm mmap | 1086 | 22.4 s | 2.2 s | 55 | 48.5 |
| G -t 12 | 1084 | 22.4 s | 2.2 s | 55 | 48 |
| H -ub 2048 -b 4096 | 933 | 26.0 s | 3.6 s | 55 | 48 |
| I --spec-type draft-mtp (n-max 3) | 994 | 24.4 s | 3.0 s | 65-77 | 86 |
Flash attention mode, load mode, and thread count made no difference; -ub 1024 -b 2048 is the sweet spot (256 and 2048 both slower). MTP on this model raises decode ~18-39% over no-MTP and beats LM Studio's 61-64 / 74, supporting the hypothesis that LM Studio was already using Tiel's bundled MTP head. Caveat: earlier research reports Vulkan MTP crashes/divergence on this GPU, so agent trials with MTP are queued (K), plus gpt-oss with -ub 1024 (L).

### Update 32d: variant J
J --spec-type ngram-mod: decode 43.1 / 55.5 tok/s short, 20.8 long (slower than no speculation: 55 / 48); prefill unchanged (1084, 22.4 s). N-gram drafting hurts this model; MTP (I) is the only speculative mode worth using on Tiel.

### Update 32e: Tiel on stock llama.cpp b11424 with MTP, hard agent task, 5 trials (flags: -ngl 999 -fa on -lm none --jinja -np 1 -c 65536 -ub 1024 -b 2048 --spec-type draft-mtp --spec-draft-n-max 3)
5/5 fixed, 0/5 loops, 16-22 s, 5 turns each, 0 invalid tool calls. Speed on the same run: decode 69-70 tok/s short, 80 long; cold 24.4 s / cached 3.0 s on 24.5k tokens. MTP + --jinja tool calling is stable on this build for this model.
### Update 32f: gpt-oss-120b on stock llama.cpp with -ub 1024 -b 2048
cold prefill 799 tok/s, cold TTFT 25.7 s (20.6k tokens; default batch 27.0 s; LM Studio 33.3 s), cached 0.2 s, decode 54.8-54.9 short, 46.0 long. Hard-agent trial 1 fixed (7 turns, 23 s); remaining trials pending.

## Update 33: STOCK llama.cpp vs LM Studio runtime, conclusions
Stock llama.cpp b11424 (official ggml-org Vulkan x64 release, SHA-256 verified) with -ngl 999 -fa on -lm none --jinja -np 1 -ub 1024 -b 2048:
| Model | metric | LM Studio runtime | stock llama-server |
|---|---|---|---|
| Tiel-Coder Q6_K_XL | cold first token, 24.5k tokens | 31.3 s | 22.4 s (24.4 s with MTP) |
| Tiel-Coder Q6_K_XL | decode | 61-64 tok/s (long 74) | 55 without MTP; 65-77 (long 80-86) with MTP |
| Tiel-Coder Q6_K_XL | hard agent task | 5/5, 0 loops, 18 s | with MTP: 5/5, 0 loops, 16-22 s |
| gpt-oss-120b | cold first token, 20.6k tokens | 33.3 s | 25.7 s |
| gpt-oss-120b | decode | 50 tok/s (long 41) | 55 tok/s (long 46) |
| gpt-oss-120b | hard agent task | 5/5, 0 loops, 15 s | 5/5, 0 loops, 15-23 s (7 turns) |
Cached-prefix first token was about the same in both (0.2-3 s). No effect from: flash attention auto vs on, load mode (none vs mmap), 12 threads, --cache-reuse 256. Worse: -ub 256 and -ub 2048; ngram-mod speculation slowed Tiel (43 tok/s, long 21).
Verdict: stock llama.cpp is faster for both models (cold start 20-25% shorter, decode up to ~10-20% faster, MTP working) with no loss in agent reliability. Cost: no LM Studio UI/JIT loading; one llama-server per model (a swapper such as llama-swap can load on demand; untested here). Worth switching for a dedicated headless box.
Recommended flags: -ngl 999 -fa on -lm none --jinja -np 1 -c 131072 -ub 1024 -b 2048; add --spec-type draft-mtp --spec-draft-n-max 3 for Tiel only. Launch scripts: launchers/start-tiel-coder.ps1 and launchers/start-gpt-oss-120b.ps1.
Not tested: Qwen3.5-122B and Qwen3.6/AgentWorld on the stock build; llama-swap; multi-model on-demand loading; prompts near 128k.

## CORRECTION (Update 33b): LM Studio did not use MTP on Tiel
My earlier hypothesis (Update 32d/32e) that LM Studio used Tiel's bundled MTP head by default is contradicted by LM Studio's own server logs: 'creating MTP draft context' appears only for the Qwen3.8-27B loads where MTP was explicitly enabled, never for Tiel. LM Studio's faster non-MTP Tiel decode (61-64 vs stock 55) is therefore unexplained (different llama.cpp build?). Test running: Tiel in LM Studio with --speculative-draft-mtp (label tiel-lmstudio-mtp-n3).

## Update 34: Tiel with MTP inside LM Studio, and GLM-5.3-Flash support
- Tiel in LM Studio with --speculative-draft-mtp (min 2, max 3, continue-prob 0.75): loads fine, but decode 50.9 / 55.6 tok/s short and 66.2 long, SLOWER than LM Studio without MTP (61-64, 74). Stock llama.cpp with MTP (n-max 3, default p-min) got 65-77 / 80-86. So LM Studio's MTP path did not help Tiel (possible causes: my continue-probability 0.75 setting, or LM Studio's older runtime). Untested: LM Studio MTP with p-min 0.
- GLM-5.3-Flash (glm5-next, 320B hybrid MoE; your files: avar6 IQ2_XXS 86 GB, lausannequants UD-IQ1_M 91 GB): LM Studio's bundled runtime fails with 'unknown model architecture: glm5next' (log, 2026-09-17). llama.cpp release notes (v0.6.0, 2026-10-05) list GLM-5.3-Flash support (PR 27773, merged) and a fix for graph reallocation in k-pool models (PR 29958, merged). PR 29928 (GLM5Next MTP and graph optimization) is still open. The stock b11424 build I downloaded should load these files; test below. LM Studio stays on the old runtime until it bumps llama.cpp.
- Test plan: GLM-5.3-Flash IQ2_XXS on stock llama-server, ctx 32768, default ubatch, text only (no mmproj); speed + 24k cache test + 3 hard agent trials. Risk note: an 86 GB model plus buffers nears the 96 GB GPU carve-out; an 86 GB model (Nemotron) previously ran fine.

## Update 35: which GLM-5.3-Flash quants can fit this box (file sizes from the Hugging Face API; "GB" = decimal)
unsloth/GLM-5.3-Flash-GGUF (1.08M downloads, 2026-08-26), 320B total: UD-IQ1_M 97.6 GB; UD-IQ2_XXS 101.9 GB; UD-Q2_K_XL 118.1 GB; UD-IQ3_XXS 120.3 GB (all plus a ~1.1 GB vision file).
This Windows box: 96 GiB (~103 GB) GPU carve-out; stock llama.cpp Vulkan reports ~112 GiB (~120 GB) addressable, ~106 GiB free. So UD-Q2_K_XL and UD-IQ3_XXS (suggested by a web answer for "128 GB Strix Halo") do NOT fit here with any context; they only fit on Linux with ~120 GB of GTT and almost no headroom. UD-IQ2_XXS is borderline; UD-IQ1_M fits but is 1-bit. The avar6 IQ2_XXS (2.32bpw, 86 GiB on disk) is the one that fits comfortably, and is the one under test.
The same answer called upstream support a "draft pull request": outdated. GLM-5.3-Flash support (PR 27773) is merged and listed in the llama.cpp v0.6.0 notes; only GLM5Next MTP (PR 29928) is still open.

## Update 36: GLM-5.3-Flash IQ2_XXS (avar6, 2.32bpw, ~86 GiB) on stock llama.cpp b11424, Vulkan, ctx 32768, parallel 1, -fa on -lm none --jinja, default ubatch
- Loads and runs (stock build supports glm5next; LM Studio's bundled runtime did not).
- decode: 19.4 / 19.9 tok/s short, 17.5 long.
- 20.7k-token prompt: cold first token 525.7 s (~39 tok/s prefill, falling as context grows: 150 tok/s at 2k tokens, ~67 average at 10k), cached prefix 23.2 s, new prefix 525.9 s.
Verdict: unusable for agentic coding as-is: an 8.8-minute cold start on a 20k prompt, and only ~20 tok/s decode, versus 22-30 s cold starts and 55-75 tok/s for the models on the keep list. The hybrid sparse-attention indexer is likely the bottleneck on Vulkan; llama.cpp PR 29928 ("GLM5Next MTP, optimize") is still open and may improve it. Re-test after it merges. Agent trials (3) running to confirm tool-calling behaviour.

### Update 36b: GLM-5.3-Flash IQ2_XXS agent trials (stock llama.cpp b11424, hard task, 3 trials)
3/3 fixed, 0 loops, 0 invalid tool calls, 46 / 70 / 60 s, 5 turns each. Tool calling is correct and stable; the problem is purely speed on long prompts (see Update 36). The agent task's prompts are small (~1k tokens), which is why these finished in about a minute. LM Studio's server confirmed restored on <strix-tailscale-address>:1234 after the test.

## Update 37: cleanup done
User ran remove-models.bat. C: free 842 -> 1,268 GB. 10 LLMs remain in LM Studio (7 keepers + GLM-5.3-Flash x2 + K2-Horizon, held).

## Update 38: building llama.cpp PR #29928 (GLM5Next MTP + optimize) from source
Open PR by pwilkin, branch glm5nextmtp, tip 16c62f4 ("glm5-next: crop the MTP graph to the output rows instead of pruning it"), +160/-8 in 3 files. Built with w64devkit (GCC 16.2, CMake, Ninja from the user's Downloads folder) and the installed Vulkan SDK, nothing installed system-wide: C:\Users\Jonathan\llama-build\llama.cpp-pr29928\build\bin\llama-server.exe (build script: C:\Users\Jonathan\llama-build\build-pr29928.ps1). Sees Vulkan0: Radeon 8060S. Note: GCC build vs the official clang release, so a small CPU-side difference is possible; the GPU path is shader-based. First launch failed silently because the PowerShell execution policy blocks -File; launching through -Command works.
Test queued: the same 20.7k-token GLM-5.3-Flash IQ2_XXS test (default flags, then --spec-type draft-mtp). Baseline to beat (stock b11424): cold first token 525.7 s, decode 19-20 tok/s.

### Update 38b: GLM-5.3-Flash IQ2_XXS on the PR #29928 build (default flags, ctx 32768, parallel 1)
decode 19.9 / 19.9 tok/s short, 17.4 long; 20.7k-token prompt: cold first token 524.4 s (~39 tok/s prefill), cached 23.3 s, new prefix 523.4 s. Identical to stock b11424 (525.7 s, 19.4-19.9 tok/s). The PR's graph optimization does not improve long-prompt prefill or plain decode for this model on Vulkan. MTP variant (--spec-type draft-mtp) pending.

### Update 38c: GLM-5.3-Flash MTP on the PR #29928 build: not functional yet
`--spec-type draft-mtp` fails at context creation: "GLM5-Next NextN graph not implemented yet" (llama_init_from_model), then "failed to create MTP context". The PR's own source comment says the trunk/MTP graph split is a TODO "in the MTP follow up". Conclusion: this PR (tip 16c62f4) delivers neither a prefill speedup nor working MTP for GLM-5.3-Flash on Vulkan. GLM-5.3-Flash stays at 19-20 tok/s and a ~525 s cold start on a 20k prompt. Re-test when the MTP follow-up lands; rebuild with C:\Users\Jonathan\llama-build\build-pr29928.ps1 (change the fetched ref). LM Studio server confirmed restored.

## Update 39: decisions
User chose to keep the GLM-5.3-Flash avar6 IQ2_XXS file for later re-testing. lausannequants GLM IQ1_M and K2-Horizon remain undecided. Cleanup of 13 listed models was executed by the user earlier (C: free 842 -> 1,268 GB).

## Update 40: the two held models, tested
- IFM K2-Horizon-MoVA-36B-A4B (BF16, ~75 GB) on stock llama.cpp b11424: load fails, "unknown model architecture: 'k2-horizon'". Needs a custom fork; not usable in LM Studio either.
- lausannequants GLM-5.3-Flash UD-IQ1_M (~91 GiB): load fails, "unknown model architecture: 'glm5next'". The file uses the early-branch architecture name; merged llama.cpp support is 'glm5-next' (the avar6 IQ2_XXS file uses that and works). Unusable in any current build.
Both are removal candidates (remove-models-round2.bat). Their sizes were never the problem. LM Studio's server confirmed restored after the tests.

## Update 41: LM Studio optimized (saved per-model default configs), and the head-to-head with the compiled llama.cpp
How the configs work: per-model defaults live in ~/.lmstudio/.internal/user-concrete-model-default-config/<publisher>/<model>/<file>.gguf.json (hub models like openai/gpt-oss-120b and qwen/qwen3.8-27b use <key>.json). They apply to loads triggered by a client request (JIT) but NOT to `lms load` from the command line. PITFALL: the file must be UTF-8 WITHOUT a byte-order mark; with a BOM LM Studio silently ignores it (PowerShell's Set-Content -Encoding utf8 adds one). Real field names (found in the app code): llm.load.contextLength, llm.load.numParallelSessions, llm.load.llama.physicalBatchSize (ubatch), llm.load.llama.evalBatchSize, llm.load.llama.flashAttention, llm.load.llama.tryMmap, llm.load.llama.keepModelInMemory, llm.load.llama.speculativeDecoding.draftMtp/draftMaxTokens/draftMinTokens/draftMinContinueProbability; sampling defaults live under llm.prediction.* (temperature, topKSampling, topPSampling, repeatPenalty, presencePenalty; value formats not verified, so not set).
Settings applied to all 7 keepers: context 131072, 1 parallel slot, ubatch 1024, batch 2048, flash attention on, mmap off, keep model in memory. Qwen3.8-27B: MTP on (draft 2-4 tokens, p 0.75) and ubatch/batch 512 (ub 1024 made its prefill worse: 119.6 s cold / 9.8 s cached vs 104.1 s / 5.3 s). Global: jitModelTTL in ~/.lmstudio/settings.json raised 1200 s -> 86400 s (backup: settings.json.bak-before-ttl) so models are not unloaded after 20 idle minutes.
Measured results (24k-token prompt; cold / cached first token; decode short, long):
| Model | LM Studio before | LM Studio tuned | Stock llama.cpp b11424 |
|---|---|---|---|
| Tiel-Coder Q6_K_XL | 31.3 s / 2.0 s; 61-64, 74 | 27.1 s / 2.6 s; 60-69, 69 | 22.4 s / 2.2 s; 55, 48 (with MTP: 24.4 s / 3.0 s; 65-77, 80-86) |
| gpt-oss-120b | 33.3 s / 0.3 s; 50, 41 | 31.7 s / 0.3 s; 49, 41 | 25.7 s / 0.2 s; 55, 46 |
| Qwen3.5-122B IQ4_XS | 75.7 s / 4.3 s; 35, 33 | 65.8 s / 5.5 s; 31-36, 35 | not tested |
| Qwen3.6-35B Q6_K | 32.1 s / 2.1 s; 66-78, 70 | 27.7 s / 2.6 s; 66-77, 77 | not tested |
| AgentWorld-35B Q6_K | 30.1 s / 1.5 s; 53, 48 | 25.9 s / 2.1 s; 53, 48 | not tested |
| Qwen3.8-27B Q6_K + MTP | 104 s / 5.4 s; 12-13, 16 | 104 s / 5.3 s; 14-15, 17.5 | not tested |
Conclusions: tuning cuts LM Studio's cold start 12-17% with no loss of decode speed, at a small cost (+0.5-0.8 s) on cached first token for the Qwen-family models. Stock llama.cpp is still ahead: cold start ~17-19% shorter than tuned LM Studio (Tiel 22.4 vs 27.1 s; gpt-oss 25.7 vs 31.7 s), gpt-oss decode ~10% faster, and Tiel gains +10-25% decode from MTP that LM Studio's MTP path cannot match (LM Studio MTP made Tiel slower). Agent reliability was equal wherever both were tested (Tiel, gpt-oss: 5/5, 0 loops). The gap is the runtime build, not a missing setting.

## Update 42: server now listens on 0.0.0.0
User decision (network boundary handled elsewhere). LM Studio: networkInterface 0.0.0.0, autoStartOnLaunch true, verified on 127.0.0.1/localhost/Tailscale IP. No authentication on the API; Windows Firewall untouched. The earlier benchmark scripts still target <strix-tailscale-address> and still work.

## Update 43: portable toolkit and reusable prompts written
scout.py (Hugging Face hot-model finder with fit/speed/risk flags, uses real GGUF metadata for parameters and architecture), llm_bench.py (cache + agent tests; verified: Tiel hard task 2/2 fixed, 0 loops, 29 s; cache test cold 26.6 s), llm_smoke.py, v2 runbook prompt, overnight agent prompt. Not yet exercised: Apple Silicon sections, scout --format mlx, an unattended overnight run.

## Update 44 (overnight batch 1, 2026-10-06 02:07 to ~09:30; models 1-10 of 11)

Source: `overnight/overnight-results.csv`, `overnight/overnight-log.md`. Hard task = 5 trials, loop = same tool call 4+ times in a row. All rows: 0 loops unless stated.

| Model (quant) | Engine | tok/s | cold prefill s | cached s | hard fixed | s/task |
|---|---|---|---|---|---|---|
| Gemma-4-26B-A4B qat (UD-Q4_K_XL) | LM Studio | 72.7 | 94.7 | 4.9 | 5/5 | 78 |
| | stock | 77.8 | 93.8 | 4.1 | 5/5 | 36 |
| KAT-Coder-V2.5-Dev (Q5_K_L) | LM Studio | 60.4 | 91.8 | 4.0 | 5/5 | 95 |
| | stock | 60.2 | 22.1 | 2.2 | 5/5 | 19 |
| Ornith-1.0-35B (Q6_K) | LM Studio | 61.3 | 26.1 | 4.0 | 5/5 | 95 |
| | stock | 64.7 | 22.2 | 2.2 | 5/5 | 18 |
| BigBang-v1 (Q5_K_L) | LM Studio | 62.3 (ub512) | 29.1 | 3.9 | 5/5 | 85 |
| | stock | 61.9 | 21.0 | 2.2 | 5/5 | 20 |
| POCKET-35B (Q4_K_M) | LM Studio | 72.6 (ub512) | 26.3 | 3.4 | 5/5 | 89 |
| | stock | 73.9 | 21.7 | 2.2 | 5/5 | 16 |
| Muse-Glimmer-30B (UD-Q5_K_XL) | LM Studio | 10.2 | 87.7 | 4.3 | not completed | |
| | stock | 10.4 | 71.8 | 2.1 | 5/5 | 133 |
| granite-4.2-30b (Q6_K) | LM Studio | 9.3 | 344.8 | 2.9 | 2/5 | 283 |
| | stock | 9.4 | 243.9 | 0.6 | killed by me | |
| gemma-4-31B-it-qat (UD-Q4_K_XL) | LM Studio | 12.6 | 399.7 | 12.5 | 5/5 | 261 |
| | stock | 12.7 | 404.2 | 14.1 | 5/5 | 147 |
| FrogNano-4B (Q6_K_S) | LM Studio | 79.8 | 25.8 | 5.0 | 5/5 | 30 |
| | stock | 54.0 | 21.7 | 2.3 | 5/5 | 24 |

Findings
- **Stock llama.cpp (b11433) cut agent time per task 2 to 5x vs LM Studio on the same weights** for the fast MoE models (KAT-Coder 95 to 19 s, Ornith 95 to 18, BigBang 85 to 20, POCKET 89 to 16, Gemma-4 78 to 36), with the same 5/5 fix rate and no loops. Single-request decode speed is about the same on both engines. So the difference is in multi-turn behaviour, not raw speed. Mechanism not proven: prefix-cache reuse or batch handling in LM Studio during tool-call turns is the leading suspect. This is now strong enough to change the stay-on-LM-Studio recommendation (see NEXT-STEPS).
- **Dense 30B+ models are not usable for the fast tier**: Muse-Glimmer-30B, granite-4.2-30b and gemma-4-31B decode at 9 to 13 tok/s on both engines (memory-bandwidth bound) and have cold prefills of 70 to 520 s. Only gemma-4-31B and Muse-Glimmer completed the hard task (147 s and 133 s per task on stock). granite fixed only 2/5. Reject all three for coding agents; gemma-4-31B is the only slow-tier candidate.
- **Fastest per task: POCKET-35B on stock** (73.9 tok/s, 16 s/task), then Ornith and KAT-Coder. FrogNano-4B (3.6 GB) fixed 5/5 at 24 to 30 s/task: a good tiny tier.
- **Suspect measurements**: (1) at ubatch 512, KAT-Coder and Ornith on LM Studio showed cold and cached prefill times swapped (cached slower than cold). Looks like the cache not being reused on the second request, or the cold run being warm from the earlier load. Needs a direct retest; ubatch 1024 stays the default. (2) BigBang ub1024 on LM Studio read 43.4 tok/s vs 62.3 at ub512: likely first-load disturbance, not real. (3) The first Gemma-4 cold prefill (95 s) is repeated on LM Studio and stock but KAT/Ornith/BigBang/POCKET run 21 to 29 s cold on stock, so Gemma-4's slow prefill is probably quant/arch specific (PR #27952 MMQ hypothesis still untested).
- **Harness notes**: the driver recorded killed agent runs as empty results; killing a bench child sometimes did not stop the run (granite LM Studio and gemma-31B kept going and reported real results). Process-match patterns must be narrow (`Name='python.exe'` and `llm_bench.py agent`); a broad pattern also matched my own shell.
- Driver now supports a third engine (`--src-exe`, e.g. the PR #29928 source build) via a loop over `self.a.engines`; backup `toolkit/overnight_driver.py.bak-before-3engines`.

## Update 45 (batch 1 finished 10:14; Qwen3.8-Flash-Next result)

- **unsloth/Qwen3.8-Flash-Next-GGUF UD-Q2_K_XL (78.9 GB, qwen4exp)**: LM Studio refused to load it (HTTP 400, probably its memory guardrail at 78.9 GB of an ~80 GB budget). **Stock llama.cpp loaded it**: 28.3 tok/s, cold prefill 54.8 s, cached 4.6 s, hard task 5/5, 0 loops, **31 s per task**. Best candidate so far for the "smarter, slower" tier (it is far larger than the 26 to 35B models), and it only runs on stock llama.cpp here.
- The IQ1_M Qwen3.8-Flash-Next Coder (58.4 GB) was skipped by the driver for budget; retry later.
- Batch 1 totals: 11 repos processed, 261 GB downloaded. Full table: `overnight/MORNING-REPORT.md`.
- Batch 2 started 10:15 in `overnight2/` with three engines (LM Studio, stock b11433, PR #29928 source build). Repos: Nemotron-3.5-Lightning-30B-A3B (ggml-org), Nemotron-3-Nano-30B-A3B, Mellum2-12B-A2.5B (JetBrains, coding MoE), Nemotron-3-Nano-Omni-30B-A3B, Apodex-1.1-mini, gemma-4-12b, Ornith-1.0-9B, Spark-X2.5-4B, Ling-3.0-tiny, Cloudflare clef-flash (stock-only arch), Step-3.7-Flash (UD-IQ3_XXS 73.6 GB).
- `toolkit/watchdog.py` now has macOS/Linux branches (ps/kill) for the Mac proof; `--dry` verified on Windows.

## CORRECTION (Update 46, 11:05): first "cold prefill" after a download is inflated
Nemotron-3-Nano-30B-A3B on LM Studio: first load cold 219.1 s, second load (ubatch 512) cold 18.6 s. The first run reads a just-downloaded file into memory during the timed request. The same effect explains the 90 s cold values on the first LM Studio runs of Gemma-4-26B-A4B and KAT-Coder in Update 44 (the second Gemma load stayed at 97 s, so Gemma-4 may still have its own slowness; KAT-Coder ub512 gave 27.5 s). Rule: read the second load as the real cold prefill, or warm the file with one throwaway request before timing. The PR #27952 / quant-type theory for prefill is not supported by these numbers. The agent-time gap (stock 2 to 5x faster on fast MoE models) does not depend on this and stands; Nemotron-3.5-Lightning showed a smaller gap (35 s LM Studio vs 19 s stock).

## Update 47 (batch 2 finished 18:08; 3 engines: LM Studio / stock b11433 / PR #29928 source build)

Hard task, 5 trials. Format: fixed/loops/seconds per task. tok/s are decode speeds (stock ~ src unless noted).

| Model (quant) | tok/s | LM Studio | stock | src | verdict |
|---|---|---|---|---|---|
| Ling-3.0-tiny (Q5_K_L, 5.9 GB) | 136 to 142 | 5/0/25 | 5/0/8 | 5/0/10 | **promote (fast tier)**; cold prefill 81 to 88 s on every engine and both loads (real), cached 6 to 9 s |
| Nemotron-3.5-Lightning-30B-A3B (Q4_0) | 69 | 5/0/35 | 5/0/19 | 5/0/21 | **promote**; best cold prefill (13 to 16 s) |
| Nemotron-3-Nano-30B-A3B (Q4_K_M) | 64 to 65 | 5/0/219 | 5/0/28 | 5/0/29 | keep as alternate; LM Studio 8x slower per task than stock |
| Apodex-1.1-mini (Q6_K) | 64 (stock), 85 (LMS ub1024) | 5/0/122 | 4/0/21 | 5/0/28 | alternate |
| Ornith-1.0-9B (Q6_K) | 31 to 32 | 5/1/82 | 5/0/49 | 5/0/43 | alternate (dense, slower) |
| gemma-4-12b (Q6_K) | 22 | 5/0/105 | 5/0/82 | 5/0/92 | slow tier; gemma4 prefill 165 to 171 s on all 3 engines |
| Nemotron-3-Nano-Omni-30B-A3B (UD-Q5_K_S) | 62 to 74 | 5/2/366 | 5/2/76 | 5/0/44 | reject (loops on 2 of 3 engines) |
| Mellum2-12B-A2.5B (Q8_0) | 84 to 86 | 2/0/26 | 0/0/9 | 1/0/13 | reject (not capable enough for this task) |
| Spark-X2.5-4B (Q4_K_M) | 74 to 75 | 1/0/51 | 2/0/32 | 1/0/28 | reject |
| clef-flash (Q5_K_M) | n/a | unsupported | server error | server error | reject: "context does not support logits computation" (not a chat model for llama-server) |
| Step-3.7-Flash (UD-IQ3_XXS, 73.6 GB) | 22.1 | 3/0/161 | not run | not run | LM Studio only (time budget); cold prefill 599 s at ub512 (104 s on first load). Retest on stock if wanted |

Findings
- **Stock llama.cpp beats LM Studio on agent time again** (Nemotron-3-Nano 219 to 28 s, Apodex 122 to 21 s, Ling-tiny 25 to 8 s, Ornith-9B 82 to 49 s). The PR #29928 source build matches stock everywhere (decode, prefill, agent time): no benefit seen from it on these models, so PR #27952 did not make a measurable difference in this suite (and the shader string scan earlier was not conclusive). Not worth maintaining a source build.
- **gemma4 architecture has a genuinely slow prefill** here (Gemma-4-26B-A4B about 95 s, gemma-4-12b 165 to 171 s, 31B 400 to 520 s) on all three engines. Real, not a first-load artifact (second loads match). Avoid gemma4 for long-prompt agent work. Ling-3.0-tiny (bailingmoe3) also has an 81 to 88 s cold prefill but its agent task still finished in 8 to 25 s, because the cache absorbs it.
- **Intermittent loops exist**: Nemotron-3-Nano-Omni looped on 2 of 3 engines, Ornith-9B once on LM Studio only. A single 5-trial run can miss them; repeat promising models with more trials before trusting them for unattended use.
- **Harness**: Spark/Mellum/Step showed that the "hard" task can discriminate models (0 to 3 of 5), but it is one task. A second, different hard task would make the ranking more robust.
- Disk now: 937 GB free of 1.9 TB (970 GB used by models).

## Candidate tiers for this machine (as of Update 47)
- **Fast tier (stock llama.cpp, ub1024):** POCKET-35B (73.9 tok/s, 16 s), Nemotron-3.5-Lightning (69 tok/s, 19 s), Ling-3.0-tiny (140 tok/s, 8 s), Ornith-35B / KAT-Coder / BigBang (18 to 20 s).
- **Smart/slow tier:** Qwen3.8-Flash-Next UD-Q2_K_XL (28 tok/s, 31 s per task, stock only), gemma-4-31B (12.7 tok/s, 147 s).
- **Tiny tier:** FrogNano-4B (24 to 30 s, 5/5).

## Update 48 (validation, 18:09 to 18:47): 15 hard trials each on stock llama.cpp b11433, ub1024/b2048, ctx 65536
`validation/validation-results.csv`, script `toolkit/validate_top.py`.

| Model | fixed | loops | s per task |
|---|---|---|---|
| Ling-3.0-tiny Q5_K_L | 15/15 | 0 | 8 |
| POCKET-35B Q4_K_M | 15/15 | 0 | 18 |
| Nemotron-3.5-Lightning-30B-A3B Q4_0 | 15/15 | 0 | 18 |
| Ornith-1.0-35B Q6_K | 15/15 | 0 | 18 |
| KAT-Coder-V2.5-Dev Q5_K_L | 15/15 | 0 | 18 |
| BigBang-v1 Q5_K_L | 15/15 | 0 | 22 |
| FrogNano-4B Q6_K_S | 14/15 | 0 | 24 |
| Qwen3.8-Flash-Next UD-Q2_K_XL (78.9 GB) | 15/15 | 0 | 32 |

Conclusions: all but FrogNano passed 15 of 15 with no loops, so the 5-trial results held up. Caveat: it is still one synthetic hard task; a real Qwen Code or OpenCode session on a real project is the test that remains. Recommended lineup for the box (stock llama.cpp): fast = POCKET-35B or Nemotron-3.5-Lightning (best prefill) or Ling-3.0-tiny (fastest), smart = Qwen3.8-Flash-Next UD-Q2_K_XL, tiny = FrogNano-4B (14/15).
