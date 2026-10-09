#!/usr/bin/env python3
"""overnight_driver: unattended pipeline for a list of Hugging Face GGUF repos. Standard library only.

For each repo: pick the best sensible quant that fits --mem-gb, check the architecture against every runtime,
download it (resumable, SHA-256 verified, written as .part then renamed so the runtime never indexes a partial file),
then test it on LM Studio (saved per-model config, loaded on demand) and on stock llama-server, and try settings variants.

  python overnight_driver.py run --repos unsloth/gemma-4-12b-it-GGUF,bartowski/foo-GGUF --mem-gb 80 --max-download-gb 250 --min-free-gb 400 --hours 7
  python overnight_driver.py report            (rewrite MORNING-REPORT.md from the journal)

State: <workdir>/overnight-state.json (resumes), results: overnight-results.csv, notes: overnight-log.md, report: MORNING-REPORT.md.
It never deletes anything and never touches OS/firewall settings. It unloads LM Studio models and starts/stops llama-server on its own port (8081).
"""
import argparse, csv, hashlib, json, os, re, shutil, subprocess, sys, time, traceback, urllib.request
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import scout  # noqa: E402
from lab_common import hf_base, lab_home  # noqa: E402

HF = hf_base()
HOME = os.path.expanduser("~")
MODELS_DIR = os.environ.get("LMS_MODELS", os.path.join(HOME, ".lmstudio", "models"))
CFG_ROOT = os.path.join(HOME, ".lmstudio", ".internal", "user-concrete-model-default-config")
LMS = os.path.join(HOME, ".lmstudio", "bin", "lms.exe" if os.name == "nt" else "lms")
LMS_BASE = os.environ.get("LLM_BASE", "http://localhost:1234")
STOCK_PORT = 8081
PY = sys.executable


def now():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


class Run:
    def __init__(self, a):
        self.a = a
        self.wd = a.workdir
        os.makedirs(self.wd, exist_ok=True)
        self.state_path = os.path.join(self.wd, "overnight-state.json")
        self.state = json.load(open(self.state_path)) if os.path.exists(self.state_path) else {"started": time.time(), "downloaded_gb": 0.0, "models": {}}
        self.t0 = self.state["started"]

    def save(self):
        json.dump(self.state, open(self.state_path, "w"), indent=2)

    def log(self, msg):
        line = "[%s] %s" % (now(), msg)
        print(line, flush=True)
        with open(os.path.join(self.wd, "overnight-log.md"), "a", encoding="utf-8") as f:
            f.write(line + "\n")

    def time_left(self):
        return self.a.hours * 3600 - (time.time() - self.t0)

    def free_gb(self):
        return shutil.disk_usage(MODELS_DIR if os.path.exists(MODELS_DIR) else HOME).free / 1e9

    def csv_row(self, row):
        p = os.path.join(self.wd, "overnight-results.csv")
        cols = ["time", "repo", "quant", "gb", "engine", "variant", "status", "load_s", "first_token_s", "tok_s", "cold_s", "cached_s",
                "agent_hard", "agent_loops", "agent_secs", "notes"]
        new = not os.path.exists(p)
        with open(p, "a", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=cols)
            if new:
                w.writeheader()
            w.writerow({c: row.get(c, "") for c in cols})

    # ------------------------------------------------------------ selection and download
    def choose(self, repo):
        info = scout.get("%s/api/models/%s?blobs=true" % (HF, repo))
        if not info:
            return None, "repo not reachable"
        meta = info.get("gguf") or {}
        total = (meta.get("total") or 0) / 1e9
        arch = meta.get("architecture")
        sib = info.get("siblings", [])
        groups = scout.quant_groups(sib, "gguf")
        fits = {k: g for k, g in groups.items() if g["size"] / 1e9 <= self.a.mem_gb}
        if not fits:
            return None, "no quant fits %.0f GB (smallest %.0f GB)" % (self.a.mem_gb, min(g["size"] for g in groups.values()) / 1e9 if groups else 0)
        sane = {k: g for k, g in fits.items() if (g["size"] * 8 / (total * 1e9) if total else 0) <= 6.8 and g["label"] not in ("BF16", "F16")}
        pool = sane or fits
        key = max(pool, key=lambda k: pool[k]["size"])
        files = [s for s in sib if re.sub(r"-\d{5}-of-\d{5}", "", s.get("rfilename", "")) == key]
        files.sort(key=lambda s: s["rfilename"])
        return {"repo": repo, "arch": arch, "total_b": total, "quant": groups[key]["label"], "gb": groups[key]["size"] / 1e9, "files": [
            {"path": s["rfilename"], "size": s.get("size"), "sha256": (s.get("lfs") or {}).get("sha256")} for s in files]}, None

    def download(self, plan):
        repo = plan["repo"]
        dest_dir = os.path.join(MODELS_DIR, repo.split("/")[0], repo.split("/")[1])
        for f in plan["files"]:
            dest = os.path.join(dest_dir, f["path"])
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            if os.path.exists(dest) and os.path.getsize(dest) == f["size"]:
                continue
            part = dest + ".part"
            url = "%s/%s/resolve/main/%s" % (HF, repo, f["path"].replace(" ", "%20"))
            for attempt in range(1, 7):
                subprocess.run(["curl", "-L", "-sS", "--fail", "--retry", "3", "-C", "-", "-o", part, url], check=False)
                if os.path.exists(part) and os.path.getsize(part) >= (f["size"] or 0):
                    break
                self.log("  partial download of %s (attempt %d), resuming" % (f["path"], attempt))
            h = hashlib.sha256()
            with open(part, "rb") as fh:
                for chunk in iter(lambda: fh.read(8 * 1024 * 1024), b""):
                    h.update(chunk)
            if f["sha256"] and h.hexdigest() != f["sha256"]:
                os.replace(part, dest + ".corrupt")
                raise RuntimeError("SHA-256 mismatch for %s (renamed .corrupt)" % f["path"])
            os.replace(part, dest)
        self.state["downloaded_gb"] += plan["gb"]
        return dest_dir

    def lms_key(self, repo, first_file):
        name = repo.split("/")[1].lower()
        base = os.path.basename(first_file).lower()
        for _ in range(8):
            try:
                out = subprocess.run([LMS, "ls", "--json"], capture_output=True, text=True, timeout=120).stdout
                for m in json.loads(out):
                    p = (m.get("path") or "").replace("\\", "/").lower()
                    if base in p or (name in p and base[:20] in p):
                        return m.get("modelKey"), m.get("path")
            except Exception:
                pass
            time.sleep(10)
        return None, None

    # ------------------------------------------------------------ tests
    def sh(self, args, env=None, timeout=3600):
        e = dict(os.environ, PYTHONIOENCODING="utf-8", **(env or {}))
        try:
            p = subprocess.run(args, capture_output=True, text=True, timeout=timeout, env=e, encoding="utf-8", errors="replace")
            return p.stdout + p.stderr
        except subprocess.TimeoutExpired:
            return "TIMEOUT"

    def smoke(self, key, base):
        out = re.sub(r"\x1b\[[0-9;]*m", "", self.sh([PY, os.path.join(HERE, "llm_smoke.py"), key, "--long"], env={"LLM_BASE": base}))
        r = {"raw": out[-1500:]}
        for pat, name, cast in [(r"loaded in ([\d.]+)s", "load_s", float), (r"first token ([\d.]+)s", "first_token_s", float), (r"([\d.]+) tok/s", "tok_s", float),
                                (r"cold first token ([\d.]+)s", "cold_s", float), (r"same prefix again ([\d.]+)s", "cached_s", float)]:
            m = re.search(pat, out)
            if m:
                r[name] = cast(m.group(1))
        r["ok"] = "tok_s" in r
        if not r["ok"]:
            r["error"] = (re.findall(r"(FAILED:.*|COULD NOT REACH.*)", out) or ["no output"])[0][:200]
        return r

    def agent(self, key, base, task, trials):
        out = self.sh([PY, os.path.join(HERE, "llm_bench.py"), "agent", "--model", key, "--task", task, "--trials", str(trials)], env={"LLM_BASE": base})
        m = re.search(r"fixed (\d+)/(\d+) \| loops \(repeat>=4\) (\d+)/(\d+) \| avg (\d+)s", out)
        return {"fixed": int(m.group(1)), "n": int(m.group(2)), "loops": int(m.group(3)), "secs": int(m.group(5)), "raw": out[-600:]} if m else {"error": out[-300:]}

    def unload_lms(self):
        subprocess.run([LMS, "unload", "--all"], capture_output=True)

    def write_cfg(self, rel_path, ub, evalb, mtp=False):
        f = os.path.join(CFG_ROOT, rel_path.replace("/", os.sep) + ".json")
        os.makedirs(os.path.dirname(f), exist_ok=True)
        fields = [{"key": "llm.load.contextLength", "value": 131072}, {"key": "llm.load.numParallelSessions", "value": 1},
                  {"key": "llm.load.llama.physicalBatchSize", "value": ub}, {"key": "llm.load.llama.evalBatchSize", "value": evalb},
                  {"key": "llm.load.llama.flashAttention", "value": True}, {"key": "llm.load.llama.tryMmap", "value": False},
                  {"key": "llm.load.llama.keepModelInMemory", "value": True}]
        if mtp:
            fields += [{"key": "llm.load.llama.speculativeDecoding.draftMtp", "value": True}]
        with open(f, "w", encoding="utf-8", newline="") as fh:        # UTF-8 WITHOUT a BOM: LM Studio silently ignores files with one
            json.dump({"preset": "", "operation": {"fields": []}, "load": {"fields": fields}}, fh, indent=2)

    def stock_server(self, exe, model_path, extra, ctx=65536):
        args = [exe, "-m", model_path, "-ngl", "999", "-fa", "on", "--jinja", "-c", str(ctx), "-np", "1", "--host", "127.0.0.1", "--port", str(STOCK_PORT)] + extra
        log = open(os.path.join(self.wd, "llama-server-last.log"), "w")
        proc = subprocess.Popen(args, stdout=log, stderr=log)
        for _ in range(400):
            time.sleep(3)
            if proc.poll() is not None:
                return None, "exited during load (see llama-server-last.log)"
            try:
                with urllib.request.urlopen("http://127.0.0.1:%d/health" % STOCK_PORT, timeout=3) as r:
                    if json.load(r).get("status") == "ok":
                        return proc, None
            except Exception:
                pass
        proc.kill()
        return None, "load timeout"

    # ------------------------------------------------------------ per-model pipeline
    def process(self, repo):
        st = self.state["models"].setdefault(repo, {"stage": "new"})
        if st.get("stage") == "done":
            return
        try:
            plan, err = self.choose(repo)
            if err:
                st.update(stage="done", verdict="skipped: " + err); self.log("%s: %s" % (repo, err)); return
            st.update(arch=plan["arch"], quant=plan["quant"], gb=round(plan["gb"], 1))
            sup = {n: scout.arch_supported(plan["arch"], scout.runtime_files([p])) for n, p in self.a.runtimes.items()}
            st["arch_support"] = sup
            self.log("%s: %s %s %.1f GB, arch %s, runtime support %s" % (repo, plan["quant"], plan["files"][0]["path"], plan["gb"], plan["arch"], sup))
            if not any(sup.values()):
                st.update(stage="done", verdict="skipped: architecture %s not in any runtime" % plan["arch"]); return
            if self.downloaded_ok() is False:
                return
            if plan["gb"] + self.state["downloaded_gb"] > self.a.max_download_gb or self.free_gb() - plan["gb"] < self.a.min_free_gb or self.time_left() < 1800:
                st.update(stage="done", verdict="skipped: budget (disk/time)"); self.log("%s: skipped for budget" % repo); return
            self.log("%s: downloading %.1f GB" % (repo, plan["gb"]))
            d = self.download(plan)
            first = plan["files"][0]["path"]
            first_path = os.path.join(d, first)
            st["stage"] = "downloaded"; self.save()
            base_row = {"time": now(), "repo": repo, "quant": plan["quant"], "gb": round(plan["gb"], 1)}
            # ---- LM Studio
            key, lpath = self.lms_key(repo, first) if sup.get("lmstudio") else (None, None)
            if sup.get("lmstudio") and not key:
                self.csv_row(dict(base_row, engine="lmstudio", status="not indexed", notes="LM Studio did not list the model"))
            if key:
                rel = lpath.replace("\\", "/")
                self.unload_lms()
                self.write_cfg(rel, 1024, 2048)
                best = None
                for ub, ev in [(1024, 2048), (512, 512)]:
                    self.write_cfg(rel, ub, ev); self.unload_lms()
                    s = self.smoke(key, LMS_BASE)
                    self.csv_row(dict(base_row, engine="lmstudio", variant="ub%d/b%d" % (ub, ev), status="ok" if s["ok"] else "failed", load_s=s.get("load_s"),
                                      first_token_s=s.get("first_token_s"), tok_s=s.get("tok_s"), cold_s=s.get("cold_s"), cached_s=s.get("cached_s"), notes=s.get("error", "")))
                    self.log("  lmstudio ub%d: %s" % (ub, {k: s.get(k) for k in ("load_s", "tok_s", "cold_s", "cached_s", "error")}))
                    if not s["ok"]:
                        break
                    if best is None or (s.get("cold_s") or 1e9) < (best[1].get("cold_s") or 1e9):
                        best = ((ub, ev), s)
                if best:
                    self.write_cfg(rel, *best[0]); self.unload_lms()
                    easy = self.agent(key, LMS_BASE, "easy", 3)
                    hard = self.agent(key, LMS_BASE, "hard", 5)
                    self.csv_row(dict(base_row, engine="lmstudio", variant="best ub%d" % best[0][0], status="agent", agent_hard="%s/%s" % (hard.get("fixed"), hard.get("n")),
                                      agent_loops=hard.get("loops"), agent_secs=hard.get("secs"), notes="easy %s/%s; %s" % (easy.get("fixed"), easy.get("n"), hard.get("error", ""))))
                    self.log("  lmstudio agent easy %s hard %s" % (easy.get("fixed"), {k: hard.get(k) for k in ("fixed", "n", "loops", "secs", "error")}))
                    st["lmstudio"] = {"best": best[0], "tok_s": best[1].get("tok_s"), "cold_s": best[1].get("cold_s"), "hard": hard}
                self.unload_lms()
            # ---- llama.cpp engines (stock release, and optionally a source build)
            for eng_name, eng_exe in self.a.engines:
                if sup.get(eng_name) and self.time_left() > 1800:
                    for variant, extra in [("ub1024", ["-ub", "1024", "-b", "2048"])] + ([("ub1024+mtp", ["-ub", "1024", "-b", "2048", "--spec-type", "draft-mtp", "--spec-draft-n-max", "3"])] if re.search(r"mtp", repo, re.I) else []):
                        self.unload_lms()
                        proc, perr = self.stock_server(eng_exe, first_path, extra)
                        if not proc:
                            self.csv_row(dict(base_row, engine=eng_name, variant=variant, status="failed", notes=perr)); self.log("  %s %s failed: %s" % (eng_name, variant, perr)); continue
                        try:
                            base = "http://127.0.0.1:%d" % STOCK_PORT
                            s = self.smoke("bench", base)
                            self.csv_row(dict(base_row, engine=eng_name, variant=variant, status="ok" if s["ok"] else "failed", first_token_s=s.get("first_token_s"), tok_s=s.get("tok_s"),
                                              cold_s=s.get("cold_s"), cached_s=s.get("cached_s"), notes=s.get("error", "")))
                            self.log("  %s %s: %s" % (eng_name, variant, {k: s.get(k) for k in ("tok_s", "cold_s", "cached_s", "error")}))
                            if s["ok"]:
                                hard = self.agent("bench", base, "hard", 5)
                                self.csv_row(dict(base_row, engine=eng_name, variant=variant, status="agent", agent_hard="%s/%s" % (hard.get("fixed"), hard.get("n")),
                                                  agent_loops=hard.get("loops"), agent_secs=hard.get("secs"), notes=hard.get("error", "")))
                                self.log("  %s agent hard %s" % (eng_name, {k: hard.get(k) for k in ("fixed", "n", "loops", "secs", "error")}))
                                st.setdefault(eng_name, {})[variant] = {"tok_s": s.get("tok_s"), "cold_s": s.get("cold_s"), "hard": hard}
                        finally:
                            proc.kill(); time.sleep(5)
            st["stage"] = "done"; st["verdict"] = "tested"
        except Exception as e:
            self.log("%s: ERROR %s" % (repo, e)); traceback.print_exc()
            st.update(stage="error", error=str(e)[:200])
        finally:
            self.save()

    def downloaded_ok(self):
        if self.time_left() < 600:
            self.log("time budget exhausted"); return False
        return True


def write_report(wd):
    if not os.path.exists(os.path.join(wd, "overnight-state.json")):
        sys.exit("overnight: no run found in %s (overnight-state.json is missing). Pass --workdir with the folder of a run." % wd)
    st = json.load(open(os.path.join(wd, "overnight-state.json")))
    rows = list(csv.DictReader(open(os.path.join(wd, "overnight-results.csv"), encoding="utf-8"))) if os.path.exists(os.path.join(wd, "overnight-results.csv")) else []
    out = ["# Morning report (%s)\n" % now(), "Downloaded tonight: %.0f GB. Models processed: %d.\n" % (st.get("downloaded_gb", 0), len(st["models"])),
           "## Per model\n", "| repo | quant | GB | verdict | notes |", "|---|---|---|---|---|"]
    for repo, m in st["models"].items():
        out.append("| %s | %s | %s | %s | %s |" % (repo, m.get("quant", ""), m.get("gb", ""), m.get("verdict", m.get("stage", "")), m.get("error", "")))
    out += ["\n## All measurements (overnight-results.csv)\n", "| repo | engine | variant | status | load s | tok/s | cold s | cached s | hard fixed | loops | secs/task | notes |", "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        out.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % tuple(r.get(c, "") for c in
                   ["repo", "engine", "variant", "status", "load_s", "tok_s", "cold_s", "cached_s", "agent_hard", "agent_loops", "agent_secs", "notes"]))
    open(os.path.join(wd, "MORNING-REPORT.md"), "w", encoding="utf-8").write("\n".join(out) + "\n")
    print("wrote", os.path.join(wd, "MORNING-REPORT.md"))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("--repos", required=True)
    r.add_argument("--workdir", default=os.path.join(lab_home(), "runs", "default"), help="state, log and report go here (default <lab home>/runs/default); use one folder per batch")
    r.add_argument("--mem-gb", type=float, required=True)
    r.add_argument("--max-download-gb", type=float, default=250)
    r.add_argument("--min-free-gb", type=float, default=400)
    r.add_argument("--hours", type=float, default=7)
    r.add_argument("--lmstudio-runtime", help="folder of LM Studio's selected runtime (for the architecture check)")
    r.add_argument("--stock-exe", required=True, help="path to a stock llama-server binary")
    r.add_argument("--src-exe", help="optional: a llama-server built from source (third engine; may have newer Vulkan shaders than the releases)")
    p = sub.add_parser("report"); p.add_argument("--workdir", default=os.path.join(lab_home(), "runs", "default"))
    a = ap.parse_args()
    if a.cmd == "report":
        write_report(a.workdir); return
    a.runtimes = {"stock": os.path.dirname(a.stock_exe)}
    a.engines = [("stock", a.stock_exe)]
    if a.src_exe:
        a.runtimes["src"] = os.path.dirname(a.src_exe)
        a.engines.append(("src", a.src_exe))
    if a.lmstudio_runtime:
        a.runtimes["lmstudio"] = a.lmstudio_runtime
    run = Run(a)
    run.log("overnight run started: %d repos, mem %.0f GB, budget %.0f GB / %.1f h, free disk %.0f GB" % (len(a.repos.split(",")), a.mem_gb, a.max_download_gb, a.hours, run.free_gb()))
    for repo in [x.strip() for x in a.repos.split(",") if x.strip()]:
        if run.time_left() < 600:
            run.log("time budget reached; stopping"); break
        run.process(repo)
    run.save()
    write_report(a.workdir)
    run.log("overnight run finished")


if __name__ == "__main__":
    main()
