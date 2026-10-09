#!/usr/bin/env python3
"""scout: find hot, recent models on Hugging Face that should fit this machine. Standard library only.

  python scout.py --mem-gb 85 --bandwidth 256                 hot GGUF models; best quant that fits 85 GB; speed ceiling at 256 GB/s
  python scout.py --mem-gb 85 --bandwidth 256 --format mlx    Apple MLX models
  python scout.py --mem-gb 85 --bandwidth 256 --json > queue.json   for an agent to consume
  python scout.py --mem-gb 85 --seen seen-models.txt --show-seen    include models you already tested (marked)

--mem-gb is the memory you can give the WEIGHTS (usable GPU memory minus room for KV cache and the OS).
--bandwidth is the memory bandwidth in GB/s. The speed figure is a rough ceiling (about 0.6x bandwidth / bytes read per token),
calibrated on one box: it is a way to rank candidates, not a promise.
Flags: RISK words mean a custom/early format may not load in stock runtimes; VARIANT means an abliterated/uncensored/merged re-upload.
"""
import argparse, json, math, mmap, os, re, sys, time, urllib.error, urllib.parse, urllib.request
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lab_common import hf_base  # noqa: E402

HF = hf_base()
TRUSTED = {"unsloth", "bartowski", "lmstudio-community", "ggml-org", "mlx-community", "qwen", "openai", "google", "meta-llama", "mistralai",
           "deepseek-ai", "zai-org", "nvidia", "microsoft", "ibm-granite", "allenai", "huggingfacetb", "ornith-ai", "xiaomimimo", "moonshotai"}
VARIANT_WORDS = ["abliterat", "uncensor", "heretic", "obliterat", "jailbreak", "distill", "merge", "fable", "cold-fusion", "roleplay"]
RISK_WORDS = ["rocmfp", "dflash", "dspark", "turboquant", "glm5next", "k2-horizon", "apex", "gsq", "-rco", "ternary", "bonsai", "reap", "pruned", "ds4", "eagle", "ultra"]
SKIP_TAGS = {"text-to-image", "image-generation", "comfyui", "diffusers", "automatic-speech-recognition", "voice-activity-detection", "text-to-speech",
             "feature-extraction", "image-to-image", "audio", "text-to-video", "speaker-diarization", "image-editing", "lora"}
OK_PIPELINES = {"text-generation", "image-text-to-text", "conversational", None}


def get(url, tries=3):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "scout/1.0"})
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 429:
                time.sleep(5 * (i + 1)); continue
            if e.code in (401, 403, 404):
                return None
        except Exception:
            time.sleep(2)
    return None


def list_repos(fmt, sort, limit, search=None):
    flt = "gguf" if fmt == "gguf" else "mlx"
    q = "%s/api/models?filter=%s&sort=%s&limit=%d" % (HF, flt, sort, limit)
    if sort in ("downloads", "createdAt", "lastModified", "likes"):
        q += "&direction=-1"
    if search:
        q += "&search=" + urllib.parse.quote(search)
    return get(q) or []


def runtime_files(paths):
    """Binary files of a runtime (llama-server, llama.dll, libllama.so/dylib, ...) to scan for supported architecture names."""
    out = []
    for p in paths or []:
        if os.path.isdir(p):
            for root, _, files in os.walk(p):
                for f in files:
                    if f.lower().endswith((".dll", ".exe", ".so", ".dylib")) or f.lower().startswith(("llama-server", "llama-cli")):
                        fp = os.path.join(root, f)
                        if os.path.getsize(fp) > 1_000_000:
                            out.append(fp)
        elif os.path.isfile(p):
            out.append(p)
    return out


def arch_supported(arch, files):
    """True/False if the architecture name is embedded in any runtime binary; None when no runtime was given."""
    if not files or not arch:
        return None
    needle = arch.encode()
    for fp in files:
        try:
            with open(fp, "rb") as fh, mmap.mmap(fh.fileno(), 0, access=mmap.ACCESS_READ) as mm:
                if mm.find(needle) != -1:
                    return True
        except (OSError, ValueError):
            continue
    return False


def params_from_name(name):
    n = name.replace("_", "-")
    total = active = None
    m = re.search(r"(\d+)x(\d+(?:\.\d+)?)b", n, re.I)            # 8x7B style
    if m:
        total = float(m.group(1)) * float(m.group(2))
    m2 = re.search(r"(?<![\d.])(\d+(?:\.\d+)?)\s*b(?![a-z])", n, re.I)
    if m2 and total is None:
        total = float(m2.group(1))
    ma = re.search(r"[-_ ]a(\d+(?:\.\d+)?)b", n, re.I)
    if ma:
        active = float(ma.group(1))
    return total, active


def quant_label(path):
    base = os.path.basename(path)
    m = re.search(r"(UD-)?(IQ\d_[A-Z]+|Q\d_K(?:_[A-Z]+)?|Q\d_\d|MXFP4(?:_MOE)?|NVFP4|BF16|F16|Q8_0)", base, re.I)
    if m:
        return m.group(0).upper()
    m = re.search(r"(\d)\s*-?bit", path, re.I)
    return "%sbit" % m.group(1) if m else "?"


def quant_groups(siblings, fmt):
    groups = {}
    for s in siblings:
        f, size = s.get("rfilename", ""), s.get("size") or 0
        if fmt == "gguf":
            if not f.endswith(".gguf") or "mmproj" in f.lower() or "imatrix" in f.lower() or f.lower().startswith("mtp/"):
                continue
            key = re.sub(r"-\d{5}-of-\d{5}", "", f)
            groups.setdefault(key, {"size": 0, "files": 0, "label": quant_label(f)})
            groups[key]["size"] += size; groups[key]["files"] += 1
        else:
            if not f.endswith(".safetensors"):
                continue
            groups.setdefault("weights", {"size": 0, "files": 0, "label": quant_label(f)})
            groups["weights"]["size"] += size; groups["weights"]["files"] += 1
    return groups


def analyse(repo, fmt, mem_gb, bw, min_age_days, max_age_days):
    rid = repo["id"]
    created = repo.get("createdAt", "")
    try:
        age = (datetime.now(timezone.utc) - datetime.fromisoformat(created.replace("Z", "+00:00"))).days
    except ValueError:
        age = 9999
    if age > max_age_days or age < min_age_days:
        return None
    tags = set(repo.get("tags", []))
    if tags & SKIP_TAGS or repo.get("pipeline_tag") not in OK_PIPELINES:
        return None
    total, active = params_from_name(rid.split("/")[-1])
    info = get("%s/api/models/%s?blobs=true" % (HF, rid))
    if not info:
        return None
    meta = info.get("gguf") or {}
    arch = meta.get("architecture")
    if meta.get("total"):
        total = meta["total"] / 1e9               # the real parameter count, from the file metadata
    elif (info.get("safetensors") or {}).get("total"):
        total = info["safetensors"]["total"] / 1e9
    groups = quant_groups(info.get("siblings", []), fmt)
    if not groups:
        return None
    fits = {k: g for k, g in groups.items() if g["size"] / 1e9 <= mem_gb}
    best_key = None
    if fits:
        def bpw(g):
            return g["size"] * 8 / (total * 1e9) if total else None
        # prefer the largest quant that fits but stays at or below ~6.8 bits per weight; BF16/F16/Q8 only if nothing smaller fits
        sane = {k: g for k, g in fits.items() if (bpw(g) or 0) <= 6.8 and g["label"] not in ("BF16", "F16")}
        pool = sane or fits
        best_key = max(pool, key=lambda k: pool[k]["size"])
    best = fits[best_key] if best_key else None
    small = min(groups.values(), key=lambda g: g["size"])
    est = None
    if best and total and active:
        bytes_per_param = best["size"] / (total * 1e9)
        read_gb = active * 1e9 * bytes_per_param / 1e9
        est = 0.6 * bw / read_gb if read_gb > 0 and bw else None
    elif best and total and bw and arch and ("moe" in arch.lower() or "exp" in arch.lower()):
        est = 0.6 * bw / (0.10 * total * (best["size"] / (total * 1e9)))   # MoE with unknown active params: assume ~10% active (a guess, shown with ?)
    elif best and total and bw and not active:
        est = 0.6 * bw / (best["size"] / 1e9)       # treated as dense: a pessimistic ceiling
    if best and total and best["size"] < total * 1e9 * 0.2:                 # under 1.6 bits per weight: the file listing is probably incomplete
        best = None; best_key = None; est = None
    low = rid.lower()
    return {
        "repo": rid, "url": "%s/%s" % (HF, rid), "downloads": repo.get("downloads", 0), "likes": repo.get("likes", 0),
        "trending": repo.get("trendingScore"), "age_days": age, "trusted": rid.split("/")[0].lower() in TRUSTED,
        "variant": [w for w in VARIANT_WORDS if w in low], "risk": [w for w in RISK_WORDS if w in low],
        "params_b": total, "active_b": active, "moe": bool(active), "arch": arch, "est_dense": bool(est and not active),
        "fits": bool(best), "best_quant": best["label"] if best else None, "best_gb": round(best["size"] / 1e9, 1) if best else None,
        "best_path": best_key, "smallest_gb": round(small["size"] / 1e9, 1), "est_tok_s": round(est, 0) if est else None,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mem-gb", type=float, required=True, help="GB available for model weights")
    ap.add_argument("--bandwidth", type=float, default=0, help="memory bandwidth in GB/s (enables the speed ceiling)")
    ap.add_argument("--format", choices=["gguf", "mlx"], default="gguf")
    ap.add_argument("--days", type=int, default=120, help="only repos created in the last N days (newness)")
    ap.add_argument("--min-days", type=int, default=0, help="skip repos younger than N days (let early bugs settle)")
    ap.add_argument("--scan", type=int, default=60, help="how many repos to pull from each of trending and downloads")
    ap.add_argument("--limit", type=int, default=25, help="rows to print")
    ap.add_argument("--seen", help="file of names/substrings already tested (one per line)")
    ap.add_argument("--show-seen", action="store_true")
    ap.add_argument("--include-variants", action="store_true", help="keep abliterated/uncensored/merged re-uploads")
    ap.add_argument("--min-downloads", type=int, default=2000)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--runtime", action="append", help="runtime folder or binary to scan for supported architectures (repeatable); unsupported architectures are flagged")
    ap.add_argument("--search", help="comma list of extra keyword searches, e.g. coder,agent,moe,glm,kimi,minimax,devstral")
    ap.add_argument("--discover", action="store_true", help="also pull the newest and most-liked repos, not just trending/downloads")
    ap.add_argument("--bad-archs", default="glm5next,k2-horizon,deepseek4-dflash-draft", help="comma list of architectures that failed to load before; matching repos are flagged")
    a = ap.parse_args()

    seen = [l.strip().lower() for l in open(a.seen, encoding="utf-8")] if a.seen and os.path.exists(a.seen) else []
    repos = {}
    sorts = ["trendingScore", "downloads"] + (["createdAt", "likes", "lastModified"] if a.discover else [])
    for sort in sorts:
        for r in list_repos(a.format, sort, a.scan):
            repos.setdefault(r["id"], r)
    for term in [s.strip() for s in (a.search or "").split(",") if s.strip()]:
        for sort in ("downloads", "createdAt"):
            for r in list_repos(a.format, sort, max(20, a.scan // 2), term):
                repos.setdefault(r["id"], r)
    if not repos:
        sys.exit("scout: could not list any repositories from Hugging Face at %s. Check the network, or try again later (it rate-limits)." % HF)
    rt_files = runtime_files(a.runtime)
    cands = [r for r in repos.values() if r.get("downloads", 0) >= a.min_downloads]
    print("scanning %d repos (%d after the download floor)..." % (len(repos), len(cands)), file=sys.stderr)
    rows = []
    for r in cands:
        row = analyse(r, a.format, a.mem_gb, a.bandwidth, a.min_days, a.days)
        if not row:
            continue
        row["seen"] = any(s and s in row["repo"].lower() for s in seen)
        row["arch_ok"] = arch_supported(row["arch"], rt_files)
        row["bad_arch"] = bool(row["arch"]) and row["arch"].lower() in [b.strip().lower() for b in a.bad_archs.split(",") if b.strip()]
        if row["variant"] and not a.include_variants:
            continue
        if row["seen"] and not a.show_seen:
            continue
        rows.append(row)
    rows.sort(key=lambda x: (not x["fits"], x.get("arch_ok") is False, not x["trusted"], -(x["trending"] or 0), -x["downloads"]))
    rows = rows[: a.limit]
    if a.json:
        print(json.dumps(rows, indent=2)); return
    print("%-3s %-50s %-8s %-8s %-11s %6s %7s %8s %5s  %s" % ("#", "repo", "params", "quant", "arch", "GB", "tok/s~", "dl", "age", "notes"))
    for i, x in enumerate(rows, 1):
        p = ("%gB-A%gB" % (x["params_b"], x["active_b"])) if x["moe"] and x["params_b"] else ("%gB" % x["params_b"] if x["params_b"] else "?")
        notes = []
        if not x["fits"]: notes.append("TOO BIG (smallest %.0f GB)" % x["smallest_gb"])
        if not x["trusted"]: notes.append("unknown publisher")
        if x.get("bad_arch"): notes.append("ARCH FAILED BEFORE")
        if x.get("arch_ok") is False: notes.append("ARCH NOT IN RUNTIME")
        if x["risk"]: notes.append("RISK:" + ",".join(x["risk"]))
        if x["variant"]: notes.append("VARIANT")
        if x["seen"]: notes.append("tested")
        est = ("%.0f%s" % (x["est_tok_s"], "?" if x["est_dense"] else "")) if x["est_tok_s"] else "-"
        print("%-3d %-50s %-8s %-8s %-11s %6s %7s %8s %4sd  %s" % (i, x["repo"][:50], p, (x["best_quant"] or "-")[:8], (x["arch"] or "-")[:11], x["best_gb"] or "-", est,
              x["downloads"], x["age_days"], "; ".join(notes)))


if __name__ == "__main__":
    main()
