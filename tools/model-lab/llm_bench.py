#!/usr/bin/env python3
"""Portable benchmarks for any OpenAI-compatible local LLM server (LM Studio, llama-server, oMLX, ...).
Standard library only; runs on Windows, macOS and Linux with Python 3.8+.

  python llm_bench.py cache --model KEY            24k-token prompt: cold vs same-prefix (cache hit) vs new prefix
  python llm_bench.py agent --model KEY --trials 5 multi-turn tool-calling task with a real code check + loop detection
  python llm_bench.py agent --model KEY --task easy

Server: set LLM_BASE (default http://localhost:1234). The model must be loaded or loadable on demand.

SAFETY NOTE: the agent test executes code written by the model (a few lines, in a temp directory, 20 s timeout).
Run it on a machine where that is acceptable.
"""
import argparse, json, os, subprocess, sys, tempfile, time, urllib.error, urllib.request

BASE = os.environ.get("LLM_BASE", "http://localhost:1234").rstrip("/")
SAMPLING = {"temperature": 0.7, "top_p": 0.8, "top_k": 20}   # a setting that gave 0 loops in testing; override per model if its card says otherwise


def post(path, body, timeout=1800):
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    return urllib.request.urlopen(req, timeout=timeout)


def chat(model, messages, tools=None, max_tokens=1500):
    body = {"model": model, "messages": messages, "max_tokens": max_tokens, **SAMPLING}
    if tools:
        body["tools"] = tools
    with post("/v1/chat/completions", body) as r:
        return json.load(r)


# ---------------------------------------------------------------- cache test
def synthetic(tag):
    parts = ["Project %s codebase excerpt:" % tag]
    for i in range(1, 261):
        parts.append("def handler_%d(request, session, cache):\n    key = f'user:{request.user_id}:%d'\n    if key in cache:\n"
                     "        return cache[key]\n    result = session.query('SELECT * FROM t_%d WHERE id = ?', request.id)\n"
                     "    cache[key] = [r for r in result if r.score > %d]\n    return cache[key]\n" % (i, i, i, i % 17))
    return "\n".join(parts)


def first_token_seconds(model, prompt):
    body = {"model": model, "stream": True, "max_tokens": 30, "messages": [{"role": "user", "content": prompt}], **SAMPLING}
    t0 = time.time()
    with post("/v1/chat/completions", body) as resp:
        for raw in resp:
            line = raw.decode("utf-8", "replace").strip()
            if line.startswith("data:") and line[5:].strip() not in ("", "[DONE]"):
                try:
                    d = json.loads(line[5:])["choices"][0]["delta"]
                except (ValueError, KeyError, IndexError):
                    continue
                if d.get("content") or d.get("reasoning_content"):
                    return time.time() - t0
    return time.time() - t0


def cmd_cache(a):
    chat(a.model, [{"role": "user", "content": "Say hi."}], max_tokens=5)   # make sure it is loaded first
    cold = first_token_seconds(a.model, synthetic("ALPHA") + "\nQuestion: write a unit test for handler_42.")
    warm = first_token_seconds(a.model, synthetic("ALPHA") + "\nQuestion: now write a unit test for handler_77.")
    new = first_token_seconds(a.model, synthetic("BETA") + "\nQuestion: write a unit test for handler_42.")
    print("%s  (~24k-token prompt)\n  cold first token      %.1f s\n  same prefix, new ask  %.1f s   <- prefix cache\n  different prefix      %.1f s" % (a.model, cold, warm, new))


# ---------------------------------------------------------------- agent test
EASY = {
    "src/pricing.py": "def apply_discount(price, pct):\n    # BUG: wrong formula\n    return price * pct / 100\n",
    "tests/test_pricing.py": "from src.pricing import apply_discount\n\ndef test_ten_percent():\n    assert apply_discount(200, 10) == 180\n\ndef test_zero():\n    assert apply_discount(50, 0) == 50\n",
}
EASY_DRIVER = "ns={}; exec(open('mod.py').read(), ns); assert ns['apply_discount'](200,10)==180 and ns['apply_discount'](50,0)==50; print('PASS')"
EASY_SRC = "src/pricing.py"

HARD = {
    "README.md": "# utils\nSmall helper library. Run the tests with the run_tests tool.\n",
    "src/util.py": ("def paginate(items, page, size):\n    # pages are 1-based\n    start = page * size\n    return items[start:start + size]\n\n"
                    "def dedupe(items):\n    # keep first occurrence, preserve original order\n    return list(set(items))\n\n"
                    "def parse_range(s):\n    # '3-7' -> [3, 4, 5, 6, 7] (inclusive on both ends)\n    a, b = s.split('-')\n    return list(range(int(a), int(b)))\n"),
    "tests/test_util.py": ("from src.util import paginate, dedupe, parse_range\n\ndef test_paginate_first():\n    assert paginate(list(range(1, 11)), 1, 3) == [1, 2, 3]\n\n"
                           "def test_paginate_last():\n    assert paginate(list(range(1, 11)), 4, 3) == [10]\n\ndef test_dedupe_order():\n    assert dedupe([3, 1, 3, 2, 1]) == [3, 1, 2]\n\n"
                           "def test_parse_range():\n    assert parse_range('3-7') == [3, 4, 5, 6, 7]\n"),
}
HARD_DRIVER = ("ns={}; exec(open('mod.py', encoding='utf-8-sig').read(), ns)\n"
               "t={'test_paginate_first': lambda: ns['paginate'](list(range(1,11)),1,3)==[1,2,3],\n"
               "   'test_paginate_last': lambda: ns['paginate'](list(range(1,11)),4,3)==[10],\n"
               "   'test_dedupe_order': lambda: ns['dedupe']([3,1,3,2,1])==[3,1,2],\n"
               "   'test_parse_range': lambda: ns['parse_range']('3-7')==[3,4,5,6,7]}\n"
               "bad=[]\n"
               "for k,f in t.items():\n"
               "    try: ok=f()\n"
               "    except Exception: ok=False\n"
               "    if not ok: bad.append(k)\n"
               "print('FAILED: '+', '.join(bad) if bad else 'PASS')\n")
HARD_SRC = "src/util.py"

TOOLS = [
    {"type": "function", "function": {"name": "list_files", "description": "List files in the repo", "parameters": {"type": "object", "properties": {}, "required": []}}},
    {"type": "function", "function": {"name": "read_file", "description": "Read a file from the repo", "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}},
    {"type": "function", "function": {"name": "write_file", "description": "Overwrite a file in the repo", "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "content": {"type": "string"}}, "required": ["path", "content"]}}},
    {"type": "function", "function": {"name": "run_tests", "description": "Run the test suite and return the output", "parameters": {"type": "object", "properties": {}, "required": []}}},
]


def run_candidate(source, driver):
    with tempfile.TemporaryDirectory() as d:
        with open(os.path.join(d, "mod.py"), "w", encoding="utf-8") as f:
            f.write(source)
        try:
            p = subprocess.run([sys.executable, "-c", driver], cwd=d, capture_output=True, text=True, timeout=20)
        except subprocess.TimeoutExpired:
            return False, "FAILED: timeout"
        out = (p.stdout + p.stderr).strip()
        return out.endswith("PASS"), out[-400:] or "FAILED: no output"


def agent_trial(model, task, max_turns):
    files = dict(HARD if task == "hard" else EASY)
    driver, src = (HARD_DRIVER, HARD_SRC) if task == "hard" else (EASY_DRIVER, EASY_SRC)
    tools = TOOLS if task == "hard" else [t for t in TOOLS if t["function"]["name"] != "list_files"]
    msgs = [{"role": "system", "content": "You are a coding agent. Use the tools to make all tests pass. Read files before editing. Do not edit the tests. When all tests pass, reply with a short summary and no tool call."},
            {"role": "user", "content": "Tests are failing in this repo. Find and fix every bug in the source."}]
    calls, invalid, edited_tests, passed = [], 0, False, False
    t0 = time.time(); turns = 0
    for turns in range(1, max_turns + 1):
        m = chat(model, msgs, tools, 2000)["choices"][0]["message"]
        msgs.append({"role": "assistant", "content": m.get("content") or "", **({"tool_calls": m["tool_calls"]} if m.get("tool_calls") else {})})
        if not m.get("tool_calls"):
            break
        for tc in m["tool_calls"]:
            name, raw = tc["function"]["name"], tc["function"]["arguments"]
            try:
                args = json.loads(raw) if raw else {}
            except ValueError:
                invalid += 1; args = {}
            calls.append(name + "|" + str(raw))
            if name == "list_files":
                res = "\n".join(sorted(files))
            elif name == "read_file":
                res = files.get(args.get("path"), "ERROR: no such file")
            elif name == "write_file":
                if str(args.get("path", "")).startswith("tests/"):
                    edited_tests = True; res = "ERROR: tests are read-only"
                elif args.get("path"):
                    files[args["path"]] = str(args.get("content", "")); res = "ok"
                else:
                    res = "ERROR: bad args"
            elif name == "run_tests":
                ok, res = run_candidate(files[src], driver); passed = passed or ok
            else:
                res = "ERROR: unknown tool"
            msgs.append({"role": "tool", "tool_call_id": tc.get("id", ""), "content": res})
    run = best = 1 if calls else 0
    for i in range(1, len(calls)):
        run = run + 1 if calls[i] == calls[i - 1] else 1
        best = max(best, run)
    return {"fixed": passed, "turns": turns, "calls": len(calls), "invalid": invalid, "max_repeat": best,
            "edited_tests": edited_tests, "secs": time.time() - t0}


def cmd_agent(a):
    chat(a.model, [{"role": "user", "content": "Say hi."}], max_tokens=5)   # ensure loaded
    rows = []
    for i in range(1, a.trials + 1):
        r = agent_trial(a.model, a.task, a.max_turns); rows.append(r)
        print("trial %d: fixed=%s turns=%d calls=%d invalid=%d max_identical_repeat=%d edited_tests=%s %.0fs" %
              (i, r["fixed"], r["turns"], r["calls"], r["invalid"], r["max_repeat"], r["edited_tests"], r["secs"]))
    n = len(rows)
    print("\n%s  task=%s  fixed %d/%d | loops (repeat>=4) %d/%d | avg %.0fs, %.1f turns" % (
        a.model, a.task, sum(r["fixed"] for r in rows), n, sum(r["max_repeat"] >= 4 for r in rows), n,
        sum(r["secs"] for r in rows) / n, sum(r["turns"] for r in rows) / n))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("cache"); c.add_argument("--model", required=True); c.set_defaults(fn=cmd_cache)
    g = sub.add_parser("agent"); g.add_argument("--model", required=True)
    g.add_argument("--trials", type=int, default=5); g.add_argument("--task", choices=["easy", "hard"], default="hard")
    g.add_argument("--max-turns", type=int, default=16); g.set_defaults(fn=cmd_agent)
    a = ap.parse_args()
    try:
        a.fn(a)
    except urllib.error.URLError as e:
        sys.exit("Could not reach the server at %s (%s). Set LLM_BASE if it is elsewhere." % (BASE, e))


if __name__ == "__main__":
    main()
