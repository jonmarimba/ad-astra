#!/usr/bin/env python3
"""Light smoke test for the local LLM server (LM Studio's OpenAI-compatible API). Standard library only.

  python llm_smoke.py tiel                 stream a short reply from one model, live
  python llm_smoke.py --all                test every recommended model in turn, print a table
  python llm_smoke.py tiel --long          also run the 20k-token cold / cached prefix test (slower)
  python llm_smoke.py --list               show the model keys it knows

Output streams to the console as it arrives (reasoning is shown dimmed). Each run appends a row to
smoke-results.csv next to this file, so you can see trends after an LM Studio / llama.cpp update.
Server address: $LLM_BASE, else the server in the active model-lab profile, else http://localhost:1234.
Models: any model id the server lists. Optional short names live in <lab home>/models.json as
{"tiel": ["tiel-coder-35b-a3b-mtp", "fast default"]}; with that file, --all tests those names in file order.
Results append to <lab home>/smoke-results.csv (default ~/.model-lab).
"""
import argparse, csv, json, os, sys, time, urllib.request, urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lab_common import lab_home, llm_base  # noqa: E402

BASE = llm_base()
CSV_PATH = os.path.join(lab_home(), "smoke-results.csv")


def load_aliases():
    """short name -> (model key, what it is for), from <lab home>/models.json when that file exists."""
    path = os.path.join(lab_home(), "models.json")
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as f:
        return {k: (v[0], v[1] if len(v) > 1 else "") for k, v in json.load(f).items()}


MODELS = load_aliases()
ALL_ORDER = list(MODELS)


def server_models():
    """Chat model ids the server lists (embedding models left out), or [] when it cannot be reached."""
    try:
        with urllib.request.urlopen(BASE + "/v1/models", timeout=15) as r:
            return [m["id"] for m in json.load(r).get("data", []) if "embed" not in m["id"].lower()]
    except Exception:
        return []

DIM, RESET = "\033[2m", "\033[0m"
os.system("")  # enables ANSI colours in the Windows console


def post_json(path, body, timeout=1800):
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    return urllib.request.urlopen(req, timeout=timeout)


def get_json(path, timeout=15):
    with urllib.request.urlopen(BASE + path, timeout=timeout) as r:
        return json.load(r)


def loaded_info(key):
    """(state, loaded context) for a model from LM Studio's REST API, or ('?', '?') if unavailable."""
    try:
        for m in get_json("/api/v0/models").get("data", []):
            if m.get("id") == key:
                return m.get("state", "?"), m.get("loaded_context_length") or m.get("max_context_length") or "?"
    except Exception:
        pass
    return "?", "?"


def stream_chat(key, prompt, max_tokens=200, show=True):
    """Stream a chat completion. Returns dict(ttft, secs, tokens, tps, text)."""
    body = {"model": key, "stream": True, "stream_options": {"include_usage": True},
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": max_tokens, "temperature": 0.7, "top_p": 0.8, "top_k": 20}
    t0 = time.time(); first = None; chunks = 0; usage_tokens = None; text = []
    with post_json("/v1/chat/completions", body) as resp:
        for raw in resp:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            try:
                obj = json.loads(data)
            except ValueError:
                continue
            if obj.get("usage"):
                usage_tokens = obj["usage"].get("completion_tokens")
            for ch in obj.get("choices", []):
                d = ch.get("delta", {})
                reasoning, content = d.get("reasoning_content"), d.get("content")
                piece = (reasoning or "") + (content or "")
                if not piece:
                    continue
                if first is None:
                    first = time.time()
                chunks += 1
                text.append(piece)
                if show:
                    sys.stdout.write((DIM + reasoning + RESET if reasoning else "") + (content or ""))
                    sys.stdout.flush()
    end = time.time()
    first = first or end
    toks = usage_tokens if usage_tokens else chunks
    gen = max(end - first, 1e-6)
    return {"ttft": first - t0, "secs": end - t0, "tokens": toks, "tps": toks / gen, "text": "".join(text)}


def synthetic_prompt(tag):
    parts = ["Project %s codebase excerpt:" % tag]
    for i in range(1, 261):
        parts.append("def handler_%d(request, session, cache):\n    key = f'user:{request.user_id}:%d'\n    if key in cache:\n"
                     "        return cache[key]\n    result = session.query('SELECT * FROM t_%d WHERE id = ?', request.id)\n"
                     "    cache[key] = [r for r in result if r.score > %d]\n    return cache[key]\n" % (i, i, i, i % 17))
    return "\n".join(parts)


def run_one(name, long_test=False, show=True):
    key, why = MODELS.get(name, (name, "custom key"))
    print("\n" + "=" * 72)
    print("%s  (%s)  [%s]" % (name, key, why))
    print("=" * 72)
    row = {"time": time.strftime("%Y-%m-%d %H:%M:%S"), "model": key}
    try:
        t = time.time()
        stream_chat(key, "Say hi.", max_tokens=5, show=False)           # triggers the on-demand load
        row["load_s"] = round(time.time() - t, 1)
        state, ctx = loaded_info(key)
        print("loaded in %.1fs   state=%s   context=%s\n" % (row["load_s"], state, ctx))
        print("--- reply (reasoning dimmed) ---")
        r = stream_chat(key, "Write a Python function that merges overlapping intervals, with a docstring and two example calls.", 200, show)
        print("\n\n--- first token %.2fs | %d tokens in %.1fs | %.1f tok/s ---" % (r["ttft"], r["tokens"], r["secs"], r["tps"]))
        row.update(ctx=ctx, first_token_s=round(r["ttft"], 2), tok_s=round(r["tps"], 1))
        if long_test:
            print("\nlong prefix test (about 24k tokens)...")
            a = stream_chat(key, synthetic_prompt("ALPHA") + "\nQuestion: write a unit test for handler_42.", 40, False)
            b = stream_chat(key, synthetic_prompt("ALPHA") + "\nQuestion: now write a unit test for handler_77.", 40, False)
            print("  cold first token %.1fs | same prefix again %.1fs" % (a["ttft"], b["ttft"]))
            row.update(cold_s=round(a["ttft"], 1), cached_s=round(b["ttft"], 1))
        row["status"] = "ok"
    except urllib.error.URLError as e:
        print("\nCOULD NOT REACH THE SERVER at %s (%s). Is LM Studio's server running?" % (BASE, e))
        row["status"] = "unreachable"
    except Exception as e:
        print("\nFAILED: %s" % e)
        row["status"] = "failed: %s" % str(e)[:80]
    cols = ["time", "model", "status", "load_s", "ctx", "first_token_s", "tok_s", "cold_s", "cached_s"]
    new = not os.path.exists(CSV_PATH)
    os.makedirs(os.path.dirname(CSV_PATH), exist_ok=True)
    with open(CSV_PATH, "a", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        if new:
            w.writeheader()
        w.writerow({c: row.get(c, "") for c in cols})
    return row


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("model", nargs="?", help="a short name from models.json, or any model id the server lists")
    ap.add_argument("--all", action="store_true", help="test every recommended model and print a table")
    ap.add_argument("--long", action="store_true", help="also run the 24k-token cold/cached test")
    ap.add_argument("--list", action="store_true", help="list known model names")
    a = ap.parse_args()
    if a.list or (not a.model and not a.all):
        for n in ALL_ORDER:
            print("  %-11s %-32s %s" % (n, MODELS[n][0], MODELS[n][1]))
        listed = server_models()
        print("models on %s:" % BASE if listed else "no models listed by %s (is the server running?)" % BASE)
        for m in listed:
            print("  " + m)
        return
    names = (ALL_ORDER or server_models()) if a.all else [a.model]
    rows = [run_one(n, a.long, show=not a.all) for n in names]
    if len(rows) > 1:
        print("\n" + "=" * 72 + "\nSUMMARY")
        print("%-34s %-8s %7s %9s %8s" % ("model", "status", "load s", "1st tok", "tok/s"))
        for r in rows:
            print("%-34s %-8s %7s %9s %8s" % (r["model"], r.get("status", "?")[:8], r.get("load_s", ""), r.get("first_token_s", ""), r.get("tok_s", "")))
    print("\n(results appended to %s)" % CSV_PATH)


if __name__ == "__main__":
    main()
