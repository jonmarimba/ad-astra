#!/usr/bin/env python3
"""watchdog: keeps an unattended overnight_driver.py run from getting stuck. Standard library only.

  python watchdog.py --workdir <overnight dir> --driver-cmd-file <json list of the driver command> [--stall-min 75] [--dry]

Every minute it checks that the driver is alive and that its log (overnight-log.md) is still moving:
  * log silent for --stall-min: kill the stuck child (llm_smoke / llm_bench / the stock llama-server on port 8081) so the driver moves on;
  * still silent 10 minutes later: kill the driver itself;
  * driver gone and the log does not say 'overnight run finished': restart it (it resumes from overnight-state.json), at most 4 times.
Everything it does is written to watchdog.log. It never deletes files. Download time counts as silence, so keep --stall-min above the longest download (79 GB at 33 MB/s is about 45 minutes).
"""
import argparse, json, os, subprocess, sys, time
from datetime import datetime


def procs():
    """List of {ProcessId, Name, CommandLine} for every process. Windows: PowerShell CIM; macOS/Linux: ps."""
    if os.name == "nt":
        ps = "Get-CimInstance Win32_Process | Select-Object ProcessId,Name,CommandLine | ConvertTo-Json -Compress"
        out = subprocess.run(["powershell", "-NoProfile", "-Command", ps], capture_output=True, text=True).stdout
        try:
            data = json.loads(out)
        except ValueError:
            return []
        return data if isinstance(data, list) else [data]
    out = subprocess.run(["ps", "-axo", "pid=,command="], capture_output=True, text=True).stdout
    rows = []
    for line in out.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and parts[0].isdigit():
            rows.append({"ProcessId": int(parts[0]), "Name": parts[1].split()[0], "CommandLine": parts[1]})
    return rows


def kill(pid):
    if os.name == "nt":
        subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], capture_output=True)
    else:
        try:
            os.kill(int(pid), 9)
        except OSError:
            pass


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--workdir", required=True)
    ap.add_argument("--driver-cmd-file", required=True)
    ap.add_argument("--stall-min", type=float, default=75)
    ap.add_argument("--dry", action="store_true", help="print what it sees once and exit")
    a = ap.parse_args()
    log_path = os.path.join(a.workdir, "overnight-log.md")
    wlog = os.path.join(a.workdir, "watchdog.log")
    cmd = json.load(open(a.driver_cmd_file))
    restarts, killed_child_at = 0, None

    def say(m):
        line = "[%s] %s" % (datetime.now().strftime("%Y-%m-%d %H:%M:%S"), m)
        print(line, flush=True)
        if not a.dry:
            open(wlog, "a", encoding="utf-8").write(line + "\n")

    while True:
        plist = procs()
        driver = [p for p in plist if p.get("CommandLine") and "overnight_driver.py" in p["CommandLine"] and "run" in p["CommandLine"] and "watchdog" not in p["CommandLine"] and p["ProcessId"] != os.getpid()]
        text = open(log_path, encoding="utf-8", errors="replace").read() if os.path.exists(log_path) else ""
        finished = "overnight run finished" in text
        age = (time.time() - os.path.getmtime(log_path)) / 60 if os.path.exists(log_path) else 9999
        if a.dry:
            print("driver processes:", [p["ProcessId"] for p in driver], "| log age %.1f min | finished=%s" % (age, finished)); return
        if finished:
            say("driver finished; watchdog exiting"); return
        if not driver:
            if restarts >= 4:
                say("driver is gone and 4 restarts were used; giving up"); return
            restarts += 1
            say("driver not running; restarting it (resume), restart #%d" % restarts)
            subprocess.Popen(cmd, stdout=open(os.path.join(a.workdir, "driver-console.txt"), "a"), stderr=subprocess.STDOUT)
            killed_child_at = None
        elif age > a.stall_min:
            if killed_child_at is None:
                kids = [p for p in plist if p.get("CommandLine") and ("llm_smoke.py" in p["CommandLine"] or "llm_bench.py" in p["CommandLine"] or ("llama-server" in p["CommandLine"] and "8081" in p["CommandLine"]))]
                say("log silent for %.0f min; killing stuck children %s" % (age, [k["ProcessId"] for k in kids]))
                for k in kids:
                    kill(k["ProcessId"])
                killed_child_at = time.time()
            elif time.time() - killed_child_at > 600:
                say("still silent 10 min after killing children; killing the driver (it will be restarted)")
                for d in driver:
                    kill(d["ProcessId"])
                killed_child_at = None
        else:
            killed_child_at = None
        time.sleep(60)


if __name__ == "__main__":
    main()
