#!/usr/bin/env python3
"""model-lab: find, download and measure local language models for ONE machine's hardware.

The slow, manual sibling of ambrosio. Ambrosio watches for hot models every day and pulls a few. model-lab
asks a harder question: of everything popular and recent, what actually fits THIS memory, runs at a useful
speed, and finishes real agent work without looping? That takes hours, so you run it by hand, about monthly.

  model-lab profile detect                       what this machine has (RAM, chip)
  model-lab profile set strix --mem-gb 85 --bandwidth 256 --server http://localhost:1234
  model-lab --profile strix scout                hot recent models that fit, with a speed ceiling (fast, network only)
  model-lab smoke <model>                        load time, first token, tokens per second (--long: 24k-token cache test)
  model-lab bench agent --model <model>          a real multi-turn tool-calling task with loop detection
  model-lab overnight run --repos a/b-GGUF,...   unattended: download, test on each engine, write MORNING-REPORT.md
  model-lab watch ...                            restart a stalled overnight run
  model-lab arch gemma4 --runtime <dir>          which runtimes know an architecture
  model-lab seen add <term>                      hide models you already tested from scout
  model-lab wantlist --from queue.json           family terms for ambrosio's want-list

A PROFILE names one machine's hardware: the memory the weights may use, the memory bandwidth, the model format
(gguf or mlx) and where its model server listens. Profiles are per hardware, so a Windows box can scout for a
Mac: `model-lab profile set m5 --mem-gb 100 --bandwidth 614 --format mlx`, then `model-lab --profile m5 scout`.

Everything this tool remembers lives in $MODEL_LAB_HOME (default ~/.model-lab). It needs only Python 3.8 or newer.
"""
import argparse
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from lab_common import lab_home  # noqa: E402

PASS_THROUGH = {"scout": "scout.py", "smoke": "llm_smoke.py", "bench": "llm_bench.py", "overnight": "overnight_driver.py",
                "watch": "watchdog.py", "arch": "archcheck.py", "validate": "validate_top.py"}
NAME_OK = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]*$")


def die(msg, code=2):
    print("model-lab: " + msg, file=sys.stderr)
    sys.exit(code)


# ------------------------------------------------------------------------------------- profiles
def profiles_dir():
    return os.path.join(lab_home(), "profiles")


def profile_path(name):
    if not NAME_OK.match(name or ""):
        die("a profile name uses letters, digits, hyphens and underscores, and starts with a letter or digit: %r" % name)
    return os.path.join(profiles_dir(), name + ".json")


def load_profile(name, required):
    path = profile_path(name)
    if not os.path.exists(path):
        if required:
            die("no profile named %r. `model-lab profile list` shows the ones that exist." % name)
        return None
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def detect():
    """(ram_gb or None, chip description). Best effort, no third-party packages."""
    ram = None
    chip = os.environ.get("PROCESSOR_IDENTIFIER") or ""
    try:
        if sys.platform == "darwin":
            ram = int(subprocess.run(["sysctl", "-n", "hw.memsize"], capture_output=True, text=True).stdout.strip()) / 2 ** 30
            chip = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], capture_output=True, text=True).stdout.strip() or chip
        elif os.name == "nt":
            import ctypes

            class MemStatus(ctypes.Structure):
                _fields_ = [("length", ctypes.c_ulong), ("load", ctypes.c_ulong), ("total", ctypes.c_ulonglong), ("avail", ctypes.c_ulonglong),
                            ("tpf", ctypes.c_ulonglong), ("apf", ctypes.c_ulonglong), ("tv", ctypes.c_ulonglong), ("av", ctypes.c_ulonglong),
                            ("ave", ctypes.c_ulonglong)]
            st = MemStatus(); st.length = ctypes.sizeof(MemStatus)
            ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(st))
            ram = st.total / 2 ** 30
        else:
            with open("/proc/meminfo") as f:
                ram = int(f.readline().split()[1]) / 2 ** 20
            chip = chip or "linux"
    except Exception:
        pass
    return ram, chip


def cmd_profile(argv):
    ap = argparse.ArgumentParser(prog="model-lab profile", description="Name a machine's hardware once; the other commands read it.")
    sub = ap.add_subparsers(dest="verb", required=True)
    s = sub.add_parser("set", help="create or update a profile")
    s.add_argument("name")
    s.add_argument("--mem-gb", type=float, help="memory the model WEIGHTS may use: usable GPU/unified memory minus room for context and the OS")
    s.add_argument("--bandwidth", type=float, help="memory bandwidth in GB/s (enables scout's speed ceiling)")
    s.add_argument("--format", choices=["gguf", "mlx"], help="model format this hardware runs (default gguf)")
    s.add_argument("--server", help="the OpenAI-compatible server to measure, e.g. http://localhost:1234")
    s.add_argument("--note")
    sh = sub.add_parser("show", help="print a profile as JSON"); sh.add_argument("name", nargs="?")
    sub.add_parser("list", help="list profiles")
    sub.add_parser("detect", help="print this machine's RAM and chip; saves nothing")
    a = ap.parse_args(argv)
    if a.verb == "detect":
        ram, chip = detect()
        print("RAM:  %s" % ("%.0f GB" % ram if ram else "unknown"))
        print("chip: %s" % (chip or "unknown"))
        print("Set --mem-gb to the memory the weights can use (usable GPU or unified memory, minus room for the context and the OS).")
        print("Set --bandwidth from the chip's published memory bandwidth in GB/s.")
        return 0
    if a.verb == "list":
        d = profiles_dir()
        names = sorted(f[:-5] for f in os.listdir(d) if f.endswith(".json")) if os.path.isdir(d) else []
        if not names:
            print("no profiles yet. Create one: model-lab profile set NAME --mem-gb N --bandwidth GBPS")
        for n in names:
            p = load_profile(n, True)
            print("%-12s mem %s GB  bandwidth %s GB/s  %s  %s" % (n, p.get("mem_gb"), p.get("bandwidth_gbs"), p.get("format", "gguf"), p.get("server") or ""))
        return 0
    if a.verb == "show":
        print(json.dumps(load_profile(a.name or resolve_name(None), True), indent=2))
        return 0
    path = profile_path(a.name)
    cur = load_profile(a.name, False) or {"name": a.name, "bandwidth_gbs": 0, "format": "gguf"}
    if a.mem_gb is not None:
        if a.mem_gb <= 0:
            die("--mem-gb must be more than 0")
        cur["mem_gb"] = a.mem_gb
    if a.bandwidth is not None:
        if a.bandwidth < 0:
            die("--bandwidth cannot be negative")
        cur["bandwidth_gbs"] = a.bandwidth
    if a.format:
        cur["format"] = a.format
    if a.server:
        cur["server"] = a.server.rstrip("/")
    if a.note:
        cur["note"] = a.note
    if "mem_gb" not in cur:
        die("a new profile needs --mem-gb")
    os.makedirs(profiles_dir(), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(cur, f, indent=2)
    print("saved %s" % path)
    return 0


def resolve_name(cli_name):
    return cli_name or os.environ.get("MODEL_LAB_PROFILE") or "default"


def has_flag(args, flag):
    return any(x == flag or x.startswith(flag + "=") for x in args)


# --------------------------------------------------------------------------------------- seen
def seen_path():
    return os.path.join(lab_home(), "seen-models.txt")


def read_lines(path):
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        return [l.strip() for l in f if l.strip()]


def cmd_seen(argv):
    ap = argparse.ArgumentParser(prog="model-lab seen", description="Models you already tested. Scout hides anything whose name contains one of these terms.")
    sub = ap.add_subparsers(dest="verb", required=True)
    add = sub.add_parser("add", help="remember terms"); add.add_argument("terms", nargs="+")
    sub.add_parser("list", help="print the terms")
    a = ap.parse_args(argv)
    if a.verb == "list":
        print("\n".join(read_lines(seen_path())))
        return 0
    have = {l.lower() for l in read_lines(seen_path())}
    fresh = []
    for t in a.terms:
        if t.lower() not in have:
            fresh.append(t); have.add(t.lower())
    os.makedirs(lab_home(), exist_ok=True)
    with open(seen_path(), "a", encoding="utf-8") as f:
        for t in fresh:
            f.write(t + "\n")
    print("added %d term(s) to %s" % (len(fresh), seen_path()))
    return 0


# ----------------------------------------------------------------------------------- wantlist
def family_term(repo):
    name = repo.split("/")[-1]
    name = re.sub(r"[-_.]?(gguf|mlx|i1)$", "", name, flags=re.I)
    return name.lower()


def cmd_wantlist(argv):
    ap = argparse.ArgumentParser(prog="model-lab wantlist", description="Turn a scout result into family terms for ambrosio's want-list.")
    ap.add_argument("--from", dest="src", required=True, help="scout --json output, or - for standard input")
    ap.add_argument("--top", type=int, default=10, help="most terms to print")
    ap.add_argument("--append-to", help="add the terms to this want-list file (existing lines stay, no duplicates)")
    ap.add_argument("--ambrosio", action="store_true", help="shorthand for --append-to $AMBROSIO_HOME/wantlist.txt (default ~/.ambrosio)")
    a = ap.parse_args(argv)
    try:
        rows = json.load(sys.stdin if a.src == "-" else open(a.src, encoding="utf-8"))
        assert isinstance(rows, list)
    except Exception as e:
        die("%s is not scout --json output (%s)" % (a.src, e))
    terms = []
    for r in rows:
        if not (r.get("fits") and r.get("trusted")) or r.get("seen") or r.get("risk") or r.get("variant") or r.get("bad_arch") or r.get("arch_ok") is False:
            continue
        t = family_term(r["repo"])
        if t not in terms:
            terms.append(t)
    terms = terms[: a.top]
    print("\n".join(terms))
    target = a.append_to
    if a.ambrosio:
        target = os.path.join(os.environ.get("AMBROSIO_HOME") or os.path.join(os.path.expanduser("~"), ".ambrosio"), "wantlist.txt")
    if target:
        have = {l.lower() for l in read_lines(target)}
        fresh = [t for t in terms if t.lower() not in have]
        if fresh:
            os.makedirs(os.path.dirname(os.path.abspath(target)), exist_ok=True)
            with open(target, "a", encoding="utf-8") as f:
                for t in fresh:
                    f.write(t + "\n")
        print("model-lab: added %d new term(s) to %s" % (len(fresh), target), file=sys.stderr)
    return 0


# ---------------------------------------------------------------------------------- pass-through
def run_script(name, args, profile):
    args = list(args)
    env = dict(os.environ, MODEL_LAB_HOME=lab_home(), PYTHONIOENCODING="utf-8")
    helping = any(x in ("-h", "--help") for x in args)
    if profile and profile.get("server") and not os.environ.get("LLM_BASE"):
        env["LLM_BASE"] = profile["server"]
    if name == "scout" and not helping:
        for flag, key in (("--mem-gb", "mem_gb"), ("--bandwidth", "bandwidth_gbs"), ("--format", "format")):
            if not has_flag(args, flag) and profile and profile.get(key) not in (None, 0):
                args += [flag, str(profile[key])]
        if not has_flag(args, "--mem-gb"):
            die("scout needs to know how much memory the weights may use. Run `model-lab profile set NAME --mem-gb N --bandwidth GBPS`"
                " and pass --profile NAME (or name it `default`), or pass --mem-gb on this command.")
        if not has_flag(args, "--seen") and os.path.exists(seen_path()):
            args += ["--seen", seen_path()]
    return subprocess.call([sys.executable, os.path.join(HERE, PASS_THROUGH[name])] + args, env=env)


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    cli_profile = None
    if argv[:1] == ["--profile"]:
        if len(argv) < 2:
            die("--profile needs a name")
        cli_profile, argv = argv[1], argv[2:]
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0 if argv else 64
    cmd, rest = argv[0], argv[1:]
    if cmd == "profile":
        return cmd_profile(rest)
    if cmd == "seen":
        return cmd_seen(rest)
    if cmd == "wantlist":
        return cmd_wantlist(rest)
    if cmd in PASS_THROUGH:
        explicit = cli_profile or os.environ.get("MODEL_LAB_PROFILE")
        profile = load_profile(resolve_name(cli_profile), required=bool(explicit))
        return run_script(cmd, rest, profile)
    die("unknown command %r. Run `model-lab --help`." % cmd, 64)


if __name__ == "__main__":
    sys.exit(main())
