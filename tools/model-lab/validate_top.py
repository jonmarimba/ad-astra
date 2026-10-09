#!/usr/bin/env python3
"""validate_top: re-test chosen models on stock llama-server with many more hard-task trials (catches intermittent loops).
  python validate_top.py --exe <llama-server> --models-dir <dir with .gguf files> --names pocket,ling-3.0-tiny --trials 15 --workdir <dir>
Each name is a case-insensitive substring of a .gguf path (first shard of split files is used). Standard library only."""
import argparse, csv, glob, json, os, re, subprocess, sys, time, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__))
PORT = 8081

def find(models_dir, name):
    hits = [p for p in glob.glob(os.path.join(models_dir, "**", "*.gguf"), recursive=True)
            if name.lower() in p.lower() and "mmproj" not in p.lower() and not p.endswith(".part")]
    hits = [p for p in hits if not re.search(r"-0000[2-9]-of-", p)]
    return sorted(hits)[0] if hits else None

def serve(exe, path, log, ctx=65536):
    args = [exe, "-m", path, "-ngl", "999", "-fa", "on", "--jinja", "-c", str(ctx), "-np", "1", "--host", "127.0.0.1", "--port", str(PORT), "-ub", "1024", "-b", "2048"]
    proc = subprocess.Popen(args, stdout=open(log, "w"), stderr=subprocess.STDOUT)
    for _ in range(400):
        time.sleep(3)
        if proc.poll() is not None:
            return None
        try:
            with urllib.request.urlopen("http://127.0.0.1:%d/health" % PORT, timeout=3) as r:
                if json.load(r).get("status") == "ok":
                    return proc
        except Exception:
            pass
    proc.kill()
    return None

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--exe", required=True); ap.add_argument("--models-dir", required=True)
    ap.add_argument("--names", required=True); ap.add_argument("--trials", type=int, default=15)
    ap.add_argument("--workdir", required=True)
    a = ap.parse_args()
    os.makedirs(a.workdir, exist_ok=True)
    out_csv = os.path.join(a.workdir, "validation-results.csv")
    if not os.path.exists(out_csv):
        csv.writer(open(out_csv, "w", newline="")).writerow(["time", "name", "path", "fixed", "n", "loops", "avg_s", "note"])
    for name in [n.strip() for n in a.names.split(",") if n.strip()]:
        path = find(a.models_dir, name)
        row = [time.strftime("%Y-%m-%d %H:%M:%S"), name, path or "", "", "", "", "", ""]
        if not path:
            row[-1] = "model file not found"
        else:
            proc = serve(a.exe, path, os.path.join(a.workdir, "validate-server.log"))
            if not proc:
                row[-1] = "server failed to load"
            else:
                try:
                    env = dict(os.environ, LLM_BASE="http://127.0.0.1:%d" % PORT)
                    out = subprocess.run([sys.executable, os.path.join(HERE, "llm_bench.py"), "agent", "--model", "bench", "--task", "hard", "--trials", str(a.trials)],
                                         capture_output=True, text=True, env=env, timeout=7200).stdout
                    m = re.search(r"fixed (\d+)/(\d+) \| loops \(repeat>=4\) (\d+)/(\d+) \| avg (\d+)s", out)
                    if m:
                        row[3:7] = [m.group(1), m.group(2), m.group(3), m.group(5)]
                    else:
                        row[-1] = out[-200:].replace("\n", " ")
                except subprocess.TimeoutExpired:
                    row[-1] = "timeout"
                finally:
                    proc.kill(); time.sleep(5)
        csv.writer(open(out_csv, "a", newline="")).writerow(row)
        print(row, flush=True)
    print("validation finished", flush=True)

if __name__ == "__main__":
    main()
