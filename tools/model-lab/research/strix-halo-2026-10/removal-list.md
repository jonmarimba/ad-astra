# Models to remove from this box (and where to get them back)

Why each is not a good fit for a Strix Halo (128 GB, ~96 GB GPU memory on Windows, ~256 GB/s) running headless agentic coding. Evidence is in `findings-log.md`. Hugging Face URLs are built from the local folder names (publisher/repo), so double-check one before relying on it. Nothing here has been deleted. `launchers\remove-models.ps1` does a dry run by default and deletes only when you pass `-Execute`.

| Local folder (under `%USERPROFILE%\.lmstudio\models\`) | Size | Get it back | Why it is not good here |
|---|---|---|---|
| `lmstudio-community\NVIDIA-Nemotron-3-Super-120B-A12B-GGUF` | ~86 GB | https://huggingface.co/lmstudio-community/NVIDIA-Nemotron-3-Super-120B-A12B-GGUF | 12B active parameters: 22 tok/s decode and 69 s to first token on a 23k prompt, far slower than the other 120B-class options |
| `kingjones777\DeepSeek-V4-Flash-180B-ROCmFP4-STRIX_LEAN-GGUF` | ~96 GB | https://huggingface.co/kingjones777/DeepSeek-V4-Flash-180B-ROCmFP4-STRIX_LEAN-GGUF | Custom ROCmFPX format needs a patched llama.cpp fork; does not run in LM Studio; fills the entire GPU memory |
| `otheru\DeepSeek-V4-Flash-Strix-Halo-GGUF` (includes the DSpark draft) | ~102 GB | https://huggingface.co/otheru/DeepSeek-V4-Flash-Strix-Halo-GGUF | Same custom-engine problem; the DSpark draft failed to load in LM Studio |
| `lmstudio-community\Hermes-4-70B-GGUF` | ~42.5 GB | https://huggingface.co/lmstudio-community/Hermes-4-70B-GGUF | Dense 70B reads ~40 GB per token: about 5 tok/s by bandwidth math (untested) |
| `kingjones777\Qwen3.8-27B-Uncensored-ROCmFP4-STRIX-MTP-GGUF` | ~26 GB | https://huggingface.co/kingjones777/Qwen3.8-27B-Uncensored-ROCmFP4-STRIX-MTP-GGUF | Custom ROCmFP4 format and MTP head that LM Studio cannot load |
| `lmstudio-community\Qwen3-Coder-30B-A3B-Instruct-GGUF` | ~18.6 GB | https://huggingface.co/lmstudio-community/Qwen3-Coder-30B-A3B-Instruct-GGUF | Loops in agent runs (3 of 6 hard-task runs): fixes the code, then re-runs the tests 10+ times without stopping |
| `logic65\Qwen3.8-Whittle-MoE-27B-A17.8B-GGUF` | ~19 GB | https://huggingface.co/logic65/Qwen3.8-Whittle-MoE-27B-A17.8B-GGUF | Failed to load (HTTP 400); 17.8B active parameters would be slow anyway |
| `lmstudio-community\Qwen3.8-27B-GGUF\Qwen3.8-27B-Q8_0.gguf` (file only; the Q6_K and vision file stay) | ~29 GB | https://huggingface.co/lmstudio-community/Qwen3.8-27B-GGUF | Q6_K tested equal quality and decodes faster (Q8 is bandwidth-heavier for the same result) |
| `ales27pm\lumen-qwen3-bootstrap-gguf` | ~1.1 GB | https://huggingface.co/ales27pm/lumen-qwen3-bootstrap-gguf | Small bootstrap model; not useful for this workload |
| `jukofyork\Qwen3-Coder-Instruct-DRAFT-0.75B-GGUF` | ~0.5 GB | https://huggingface.co/jukofyork/Qwen3-Coder-Instruct-DRAFT-0.75B-GGUF | Draft model for the Qwen3-Coder family (which is rejected); drafts slow MoE models |
| `jukofyork\GLM-4.5-DRAFT-0.6B-v3.0-GGUF` | ~0.4 GB | https://huggingface.co/jukofyork/GLM-4.5-DRAFT-0.6B-v3.0-GGUF | Draft for the older GLM-4.5 family; not used |
| `mrchuy\Qwen3.8-27B-DFlash-drafter-bootstrap-GGUF` | ~1.7 GB | https://huggingface.co/mrchuy/Qwen3.8-27B-DFlash-drafter-bootstrap-GGUF | DFlash drafting is unreliable in LM Studio (open bug reports); the dense 27B is better served by MTP |
| `peculiar-ragdoll\Tiel-Coder-35B-A3B-GGUF-MTP\Tiel-Coder-35B-A3B-MTP-UD-Q6_K_XL.gguf.corrupt` (file only) | ~35 GB | not needed | Corrupt partial download from a race; the verified good copy sits next to it |

Total: about 458 GB decimal (the script prints GiB: 426.5 GiB).

**Running the script:** this PC's PowerShell execution policy blocks unsigned scripts. Either run `powershell -ExecutionPolicy Bypass -File .\launchers
emove-models.ps1` (dry run) and add `-Execute` to delete, or paste the file's contents into a PowerShell window. Changing the policy is your call; I did not touch it.

## Round 2 (tested 2026-10-05): both fail to load, so remove. KEEP the avar6 IQ2_XXS GLM file (user decision). Use `remove-models-round2.bat`

| Local folder | Size | Get it back | Notes |
|---|---|---|---|
| `avar6\GLM-5.3-Flash-BF16-gguf` (IQ2_XXS 2.32bpw + vision file) | ~94 GB | https://huggingface.co/avar6/GLM-5.3-Flash-BF16-gguf | **DECISION 2026-10-05: KEEP** (to re-test after a llama.cpp GLM5-Next MTP follow-up lands). The only GLM quant small enough to fit the 96 GB GPU memory. Tested on stock llama.cpp: 19 tok/s decode and an 8.8-minute cold start on a 20k prompt, so not usable for agentic coding right now. Keep only if you want to re-test once llama.cpp PR 29928 (GLM5-Next optimisation) merges |
| `lausannequants\GLM-5.3-Flash-GGUF` (UD-IQ1_M + vision file) | ~99 GB | https://huggingface.co/lausannequants/GLM-5.3-Flash-GGUF | **TESTED: fails to load** (`unknown model architecture: 'glm5next'`): converted for an early GLM branch with a different architecture name than the merged llama.cpp support (`glm5-next`). Unusable in any current build; the unsloth UD-IQ1_M is the compatible 1-bit version if you ever want it. Remove |
| `IFM\K2-Horizon-MoVA-36B-A4B-GGUF` (BF16) | ~75 GB | https://huggingface.co/IFM/K2-Horizon-MoVA-36B-A4B-GGUF | **TESTED: fails to load** (`unknown model architecture: 'k2-horizon'`) in stock llama.cpp b11424 (and LM Studio's runtime); needs a custom fork. Remove |

## Keep

Tiel-Coder-35B-A3B Q6_K_XL, gpt-oss-120b, Qwen3.5-122B-A10B IQ4_XS, Qwen3.6-35B-A3B MTP Q6_K, Qwen-AgentWorld-35B-A3B Q6_K, Qwen3.8-27B Q6_K (with its vision file), Ornith-1.5-35B-A3B Q4_K_M.
