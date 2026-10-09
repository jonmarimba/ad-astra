#!/usr/bin/env python3
"""Tests for model-lab. Standard library only, so the same file runs on macOS, Linux and Windows.

Every test runs the real scripts as subprocesses against two local stub servers: one that speaks
the Hugging Face API (model lists, repo metadata, file downloads with Range support) and one that
speaks the OpenAI chat API the way LM Studio and llama-server do. Nothing touches the network or a
real model. A test asserts an effect: a row in the JSON, a file on disk, an exit code.

Run:  python test_model_lab.py        (from any directory)
"""
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
PY = sys.executable
GB = 10 ** 9


def days_ago(n):
    return (datetime.now(timezone.utc) - timedelta(days=n)).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def read(path, mode="r"):
    with open(path, mode, **({} if "b" in mode else {"encoding": "utf-8"})) as f:
        return f.read()


def sib(name, size, sha=None):
    s = {"rfilename": name, "size": size}
    if sha:
        s["lfs"] = {"sha256": sha}
    return s


# ----------------------------------------------------------------------------------------------
# What the Hugging Face stub knows. Each repo is chosen to exercise one rule in scout.py.
# ----------------------------------------------------------------------------------------------
DOWNLOAD_BYTES = bytes(range(256)) * 4096          # 1 MiB, deterministic
DOWNLOAD_SHA = hashlib.sha256(DOWNLOAD_BYTES).hexdigest()

REPOS = {
    "unsloth/alpha-30b-a3b-GGUF": dict(
        listing=dict(downloads=50000, likes=300, trendingScore=90, createdAt=days_ago(10), tags=[], pipeline_tag="text-generation"),
        gguf=dict(total=30 * GB, architecture="alpha-moe"),
        siblings=[sib("alpha-Q4_K_M.gguf", 18 * GB), sib("alpha-Q6_K.gguf", 25 * GB), sib("alpha-Q8_0.gguf", 32 * GB),
                  sib("alpha-BF16.gguf", 60 * GB), sib("mmproj-alpha-F16.gguf", 1 * GB)]),
    "someuser/beta-8b-abliterated-GGUF": dict(
        listing=dict(downloads=9000, likes=10, trendingScore=50, createdAt=days_ago(5), tags=[], pipeline_tag="text-generation"),
        gguf=dict(total=8 * GB, architecture="beta"), siblings=[sib("beta-Q4_K_M.gguf", 5 * GB)]),
    "bartowski/gamma-405b-GGUF": dict(
        listing=dict(downloads=80000, likes=900, trendingScore=70, createdAt=days_ago(20), tags=[], pipeline_tag="text-generation"),
        gguf=dict(total=405 * GB, architecture="gamma"), siblings=[sib("gamma-IQ2_XS.gguf", 140 * GB)]),
    "qwen/old-7b-GGUF": dict(
        listing=dict(downloads=70000, likes=500, trendingScore=10, createdAt=days_ago(400), tags=[], pipeline_tag="text-generation"),
        gguf=dict(total=7 * GB, architecture="old"), siblings=[sib("old-Q4_K_M.gguf", 4 * GB)]),
    "someorg/delta-12b-rocmfp4-GGUF": dict(
        listing=dict(downloads=4000, likes=20, trendingScore=40, createdAt=days_ago(8), tags=[], pipeline_tag="text-generation"),
        gguf=dict(total=12 * GB, architecture="delta"), siblings=[sib("delta-Q4_K_M.gguf", 7 * GB)]),
    "unsloth/epsilon-image-GGUF": dict(
        listing=dict(downloads=90000, likes=100, trendingScore=95, createdAt=days_ago(3), tags=["text-to-image"], pipeline_tag="text-to-image"),
        gguf=dict(total=12 * GB, architecture="epsilon"), siblings=[sib("epsilon-Q4_K_M.gguf", 7 * GB)]),
    "unsloth/quiet-9b-GGUF": dict(
        listing=dict(downloads=500, likes=1, trendingScore=1, createdAt=days_ago(4), tags=[], pipeline_tag="text-generation"),
        gguf=dict(total=9 * GB, architecture="quiet"), siblings=[sib("quiet-Q4_K_M.gguf", 5 * GB)]),
    "unsloth/zeta-9b-GGUF": dict(
        listing=dict(downloads=30000, likes=40, trendingScore=60, createdAt=days_ago(6), tags=[], pipeline_tag="text-generation"),
        gguf=dict(total=9 * GB, architecture="newarch"), siblings=[sib("zeta-Q4_K_M.gguf", 5 * GB)]),
    # a sharded repo whose file really downloads, for the driver tests
    "unsloth/shard-12b-GGUF": dict(
        listing=dict(downloads=20000, likes=5, trendingScore=30, createdAt=days_ago(7), tags=[], pipeline_tag="text-generation"),
        gguf=dict(total=12 * GB, architecture="shardarch"),
        siblings=[sib("shard-Q4_K_M-00001-of-00002.gguf", len(DOWNLOAD_BYTES), DOWNLOAD_SHA),
                  sib("shard-Q4_K_M-00002-of-00002.gguf", len(DOWNLOAD_BYTES), DOWNLOAD_SHA),
                  sib("shard-Q8_0.gguf", 40 * GB)]),
}

FIXED_UTIL = ("def paginate(items, page, size):\n    start = (page - 1) * size\n    return items[start:start + size]\n\n"
              "def dedupe(items):\n    return list(dict.fromkeys(items))\n\n"
              "def parse_range(s):\n    a, b = s.split('-')\n    return list(range(int(a), int(b) + 1))\n")


class Stub(BaseHTTPRequestHandler):
    """One handler for both stubs, so a single port serves Hugging Face and an OpenAI-style server."""
    corrupt_downloads = False
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urlparse(self.path)
        path = unquote(u.path)
        if path == "/api/models":                                   # Hugging Face listing
            rows = [dict(id=rid, **r["listing"]) for rid, r in REPOS.items()]
            return self._json(rows)
        if path.startswith("/api/models/"):                         # repo metadata
            rid = path[len("/api/models/"):]
            r = REPOS.get(rid)
            if not r:
                return self._json({"error": "not found"}, 404)
            return self._json({"id": rid, "gguf": r["gguf"], "siblings": r["siblings"]})
        if "/resolve/main/" in path:                                # file download with Range
            data = DOWNLOAD_BYTES if not Stub.corrupt_downloads else bytes(reversed(DOWNLOAD_BYTES))
            start = 0
            rng = self.headers.get("Range")
            if rng and rng.startswith("bytes="):
                start = int(rng[6:].split("-")[0] or 0)
            chunk = data[start:]
            self.send_response(206 if start else 200)
            self.send_header("Content-Length", str(len(chunk)))
            self.send_header("Content-Type", "application/octet-stream")
            if start:
                self.send_header("Content-Range", "bytes %d-%d/%d" % (start, len(data) - 1, len(data)))
            self.end_headers()
            self.wfile.write(chunk)
            return
        if path == "/v1/models":
            return self._json({"data": [{"id": "stub-model"}, {"id": "stuck-model"}, {"id": "looper-model"},
                                        {"id": "text-embedding-nomic"}]})
        if path == "/api/v0/models":
            return self._json({"data": [{"id": "stub-model", "state": "loaded", "loaded_context_length": 4096}]})
        self._json({"error": "unknown " + path}, 404)

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n) or b"{}")
        if urlparse(self.path).path != "/v1/chat/completions":
            return self._json({"error": "unknown"}, 404)
        model = body.get("model")
        if body.get("stream"):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Connection", "close")
            self.end_headers()
            for piece in ["Hello", " from", " the", " stub", " model"]:
                self.wfile.write(("data: " + json.dumps({"choices": [{"delta": {"content": piece}}]}) + "\n\n").encode())
            self.wfile.write(("data: " + json.dumps({"choices": [], "usage": {"completion_tokens": 5}}) + "\n\n").encode())
            self.wfile.write(b"data: [DONE]\n\n")
            self.close_connection = True
            return
        # non-stream: the agent test. The stub model behaves per its name.
        msgs = body.get("messages", [])
        tool_turns = sum(1 for m in msgs if m.get("role") == "tool")
        if not body.get("tools") or model == "stuck-model":
            return self._json({"choices": [{"message": {"role": "assistant", "content": "I looked and I am done."}}]})

        def call(name, args):
            return {"choices": [{"message": {"role": "assistant", "content": "", "tool_calls": [
                {"id": "c%d" % tool_turns, "type": "function", "function": {"name": name, "arguments": json.dumps(args)}}]}}]}
        if model == "looper-model":
            if tool_turns < 6:
                return self._json(call("run_tests", {}))
            return self._json({"choices": [{"message": {"role": "assistant", "content": "done"}}]})
        if tool_turns == 0:
            return self._json(call("write_file", {"path": "src/util.py", "content": FIXED_UTIL}))
        if tool_turns == 1:
            return self._json(call("run_tests", {}))
        self._json({"choices": [{"message": {"role": "assistant", "content": "Fixed all three bugs."}}]})


class LabCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), Stub)
        cls.port = cls.server.server_address[1]
        cls.base = "http://127.0.0.1:%d" % cls.port
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.home = os.path.join(self._tmp.name, "lab-home")
        self.env = dict(os.environ, MODEL_LAB_HOME=self.home, MODEL_LAB_HF_BASE=self.base, LLM_BASE=self.base,
                        PYTHONIOENCODING="utf-8", HOME=self._tmp.name, USERPROFILE=self._tmp.name)
        for k in ("MODEL_LAB_PROFILE", "AMBROSIO_HOME", "LMS_MODELS"):
            self.env.pop(k, None)
        Stub.corrupt_downloads = False

    def tearDown(self):
        self._tmp.cleanup()

    def lab(self, *args, env=None, input=None, timeout=120):
        e = dict(self.env, **(env or {}))
        return subprocess.run([PY, os.path.join(HERE, "model_lab.py")] + list(args), capture_output=True, text=True,
                              env=e, input=input, timeout=timeout, encoding="utf-8", errors="replace")

    def py(self, script, *args, env=None, timeout=120):
        e = dict(self.env, **(env or {}))
        return subprocess.run([PY, os.path.join(HERE, script)] + list(args), capture_output=True, text=True,
                              env=e, timeout=timeout, encoding="utf-8", errors="replace")

    def scout_rows(self, *args):
        r = self.lab("scout", "--mem-gb", "40", "--bandwidth", "250", "--json", *args)
        self.assertEqual(r.returncode, 0, r.stderr)
        return {row["repo"]: row for row in json.loads(r.stdout)}


class TestScout(LabCase):
    def test_picks_the_largest_sane_quant_that_fits(self):
        row = self.scout_rows()["unsloth/alpha-30b-a3b-GGUF"]
        self.assertTrue(row["fits"])
        self.assertEqual(row["best_quant"], "Q6_K", "Q8_0 fits in 40 GB but is over 6.8 bits per weight, so Q6_K wins")
        self.assertEqual(row["best_gb"], 25.0)
        self.assertEqual(row["arch"], "alpha-moe")
        self.assertEqual(row["params_b"], 30.0)
        self.assertEqual(row["active_b"], 3.0)

    def test_speed_ceiling_is_the_documented_formula(self):
        # 0.6 x bandwidth / GB read per token: 3B active x (25/30 bytes per param) = 2.5 GB; 0.6 x 250 / 2.5 = 60
        self.assertEqual(self.scout_rows()["unsloth/alpha-30b-a3b-GGUF"]["est_tok_s"], 60)

    def test_a_model_too_big_for_memory_is_listed_as_too_big(self):
        row = self.scout_rows()["bartowski/gamma-405b-GGUF"]
        self.assertFalse(row["fits"])
        self.assertEqual(row["smallest_gb"], 140.0)

    def test_old_repos_and_non_text_models_and_unpopular_repos_are_dropped(self):
        rows = self.scout_rows()
        self.assertNotIn("qwen/old-7b-GGUF", rows, "older than --days")
        self.assertNotIn("unsloth/epsilon-image-GGUF", rows, "text-to-image")
        self.assertNotIn("unsloth/quiet-9b-GGUF", rows, "below the download floor")
        self.assertIn("unsloth/alpha-30b-a3b-GGUF", rows)

    def test_abliterated_variants_are_hidden_unless_asked_for(self):
        self.assertNotIn("someuser/beta-8b-abliterated-GGUF", self.scout_rows())
        shown = self.scout_rows("--include-variants")["someuser/beta-8b-abliterated-GGUF"]
        self.assertIn("abliterat", shown["variant"])
        self.assertFalse(shown["trusted"])

    def test_risky_formats_and_unknown_publishers_are_flagged(self):
        row = self.scout_rows()["someorg/delta-12b-rocmfp4-GGUF"]
        self.assertIn("rocmfp", row["risk"])
        self.assertFalse(row["trusted"])
        self.assertTrue(self.scout_rows()["unsloth/alpha-30b-a3b-GGUF"]["trusted"])

    def test_seen_models_are_hidden_then_shown_on_request(self):
        self.assertEqual(self.lab("seen", "add", "alpha-30b").returncode, 0)
        self.assertNotIn("unsloth/alpha-30b-a3b-GGUF", self.scout_rows())
        row = self.scout_rows("--show-seen")["unsloth/alpha-30b-a3b-GGUF"]
        self.assertTrue(row["seen"])

    def test_the_text_table_names_the_notes(self):
        r = self.lab("scout", "--mem-gb", "40", "--bandwidth", "250", "--include-variants")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("TOO BIG", r.stdout)
        self.assertIn("RISK:rocmfp", r.stdout)
        self.assertIn("VARIANT", r.stdout)

    def test_architectures_missing_from_a_runtime_are_flagged_and_sorted_last(self):
        rt = os.path.join(self._tmp.name, "runtime"); os.makedirs(rt)
        with open(os.path.join(rt, "llama.dll"), "wb") as f:
            f.write(b"\0" * 1_100_000 + b"alpha-moe" + b"\0" * 10)
        rows = self.scout_rows("--runtime", rt)
        self.assertIs(rows["unsloth/alpha-30b-a3b-GGUF"]["arch_ok"], True)
        self.assertIs(rows["unsloth/zeta-9b-GGUF"]["arch_ok"], False, "newarch is not in the runtime binary")
        r = self.lab("scout", "--mem-gb", "40", "--runtime", rt)
        self.assertIn("ARCH NOT IN RUNTIME", r.stdout)

    def test_a_dead_hugging_face_is_an_error_not_an_empty_list(self):
        r = self.lab("scout", "--mem-gb", "40", "--json", env={"MODEL_LAB_HF_BASE": "http://127.0.0.1:9"}, timeout=180)
        self.assertNotEqual(r.returncode, 0, "RED: no repos reachable must not look like 'nothing new'")
        self.assertIn("Hugging Face", r.stderr)


class TestProfile(LabCase):
    def test_a_profile_supplies_the_scout_defaults(self):
        r = self.lab("profile", "set", "box", "--mem-gb", "40", "--bandwidth", "250", "--format", "gguf")
        self.assertEqual(r.returncode, 0, r.stderr)
        out = self.lab("--profile", "box", "scout", "--json")
        self.assertEqual(out.returncode, 0, out.stderr)
        rows = {x["repo"]: x for x in json.loads(out.stdout)}
        self.assertEqual(rows["unsloth/alpha-30b-a3b-GGUF"]["est_tok_s"], 60, "bandwidth came from the profile")
        self.assertFalse(rows["bartowski/gamma-405b-GGUF"]["fits"], "memory came from the profile")

    def test_explicit_flags_beat_the_profile(self):
        self.lab("profile", "set", "box", "--mem-gb", "10", "--bandwidth", "250")
        out = self.lab("--profile", "box", "scout", "--mem-gb", "40", "--json")
        rows = {x["repo"]: x for x in json.loads(out.stdout)}
        self.assertTrue(rows["unsloth/alpha-30b-a3b-GGUF"]["fits"], "40 GB on the command line overrides the profile's 10")

    def test_profiles_are_per_hardware_and_listed(self):
        self.lab("profile", "set", "strix", "--mem-gb", "85", "--bandwidth", "256")
        self.lab("profile", "set", "m5", "--mem-gb", "100", "--bandwidth", "614", "--format", "mlx")
        r = self.lab("profile", "list")
        self.assertIn("strix", r.stdout); self.assertIn("m5", r.stdout)
        shown = json.loads(self.lab("profile", "show", "m5").stdout)
        self.assertEqual((shown["mem_gb"], shown["bandwidth_gbs"], shown["format"]), (100, 614, "mlx"))

    def test_scout_with_no_profile_and_no_memory_fails_and_says_how_to_fix_it(self):
        r = self.lab("scout", "--json")
        self.assertNotEqual(r.returncode, 0, "RED: scout cannot guess how much memory the weights get")
        self.assertIn("model-lab profile set", r.stderr)

    def test_an_unknown_profile_is_refused_by_name(self):
        r = self.lab("--profile", "nope", "scout", "--json")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("nope", r.stderr)

    def test_a_bad_value_is_refused(self):
        r = self.lab("profile", "set", "box", "--mem-gb", "-5")
        self.assertNotEqual(r.returncode, 0, "RED: negative memory")
        self.assertFalse(os.path.exists(os.path.join(self.home, "profiles", "box.json")), "nothing was saved")

    def test_a_profile_name_cannot_escape_the_profiles_folder(self):
        r = self.lab("profile", "set", "../evil", "--mem-gb", "10")
        self.assertNotEqual(r.returncode, 0, "RED: path traversal")
        self.assertFalse(os.path.exists(os.path.join(self.home, "evil.json")))

    def test_detect_reports_this_machines_memory_without_saving_anything(self):
        r = self.lab("profile", "detect")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("RAM", r.stdout)
        self.assertFalse(os.path.exists(os.path.join(self.home, "profiles")))


class TestWantlist(LabCase):
    def queue(self):
        r = self.lab("scout", "--mem-gb", "40", "--bandwidth", "250", "--json")
        path = os.path.join(self._tmp.name, "queue.json")
        with open(path, "w", encoding="utf-8") as f:
            f.write(r.stdout)
        return path

    def test_wantlist_prints_family_terms_for_models_that_fit_and_are_trusted(self):
        r = self.lab("wantlist", "--from", self.queue())
        self.assertEqual(r.returncode, 0, r.stderr)
        terms = r.stdout.split()
        self.assertIn("alpha-30b-a3b", terms, "org and the -GGUF suffix are stripped")
        self.assertNotIn("gamma-405b", terms, "too big to fit")
        self.assertFalse(any("delta" in t for t in terms), "unknown publisher with a risky format")

    def test_wantlist_appends_to_ambrosios_file_without_duplicates(self):
        wl = os.path.join(self._tmp.name, "wantlist.txt")
        with open(wl, "w", encoding="utf-8") as f:
            f.write("alpha-30b-a3b\nsomething-else\n")
        r = self.lab("wantlist", "--from", self.queue(), "--append-to", wl)
        self.assertEqual(r.returncode, 0, r.stderr)
        lines = read(wl).split()
        self.assertEqual(lines.count("alpha-30b-a3b"), 1, "already in the file: not added twice")
        self.assertIn("something-else", lines, "existing entries stay")

    def test_wantlist_refuses_a_file_that_is_not_scout_output(self):
        bad = os.path.join(self._tmp.name, "bad.json")
        with open(bad, "w") as f:
            f.write("not json")
        r = self.lab("wantlist", "--from", bad)
        self.assertNotEqual(r.returncode, 0, "RED")


class TestSmokeAndBench(LabCase):
    def test_smoke_reports_first_token_and_tokens_per_second_and_logs_a_row(self):
        r = self.py("llm_smoke.py", "stub-model")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("tok/s", r.stdout)
        self.assertIn("Hello from the stub model", r.stdout)
        csv_path = os.path.join(self.home, "smoke-results.csv")
        self.assertTrue(os.path.exists(csv_path), "history is kept in the lab home, not in the checkout")
        self.assertIn("stub-model,ok", read(csv_path).replace(" ", ""))
        self.assertFalse(os.path.exists(os.path.join(HERE, "smoke-results.csv")), "nothing is written beside the code")

    def test_smoke_lists_the_servers_models_and_leaves_out_embedding_models(self):
        r = self.py("llm_smoke.py", "--list")
        self.assertIn("stub-model", r.stdout)
        self.assertNotIn("text-embedding", r.stdout)

    def test_smoke_against_a_dead_server_says_so(self):
        r = self.py("llm_smoke.py", "stub-model", env={"LLM_BASE": "http://127.0.0.1:9"})
        self.assertIn("COULD NOT REACH", r.stdout)
        self.assertIn("unreachable", read(os.path.join(self.home, "smoke-results.csv")))

    def test_agent_bench_counts_a_real_fix(self):
        r = self.py("llm_bench.py", "agent", "--model", "stub-model", "--task", "hard", "--trials", "1")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("fixed 1/1", r.stdout)
        self.assertIn("loops (repeat>=4) 0/1", r.stdout)

    def test_agent_bench_does_not_count_a_model_that_never_fixes_anything(self):
        r = self.py("llm_bench.py", "agent", "--model", "stuck-model", "--task", "hard", "--trials", "1")
        self.assertIn("fixed 0/1", r.stdout, "RED: claiming success without passing tests would make every ranking meaningless")

    def test_agent_bench_detects_a_loop(self):
        r = self.py("llm_bench.py", "agent", "--model", "looper-model", "--task", "hard", "--trials", "1")
        self.assertIn("loops (repeat>=4) 1/1", r.stdout)
        self.assertIn("fixed 0/1", r.stdout)

    def test_bench_against_a_dead_server_exits_with_a_clear_message(self):
        r = self.py("llm_bench.py", "agent", "--model", "x", "--trials", "1", env={"LLM_BASE": "http://127.0.0.1:9"})
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("Could not reach the server", r.stderr)

    def test_the_server_address_comes_from_the_profile(self):
        self.lab("profile", "set", "box", "--mem-gb", "40", "--server", self.base)
        r = self.lab("--profile", "box", "smoke", "stub-model", env={"LLM_BASE": ""})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("tok/s", r.stdout)


class TestDriver(LabCase):
    def driver(self, code):
        """Run a snippet with overnight_driver imported, pointed at the stub and a temp models folder."""
        models = os.path.join(self._tmp.name, "models")
        e = dict(self.env, LMS_MODELS=models)
        script = ("import sys, json, argparse; sys.path.insert(0, %r)\nimport overnight_driver as d\n"
                  "a = argparse.Namespace(workdir=%r, hours=2, mem_gb=40, max_download_gb=250, min_free_gb=0, repos='x',"
                  " runtimes={}, engines=[])\nrun = d.Run(a)\n" % (HERE, os.path.join(self._tmp.name, "wd"))) + code
        return subprocess.run([PY, "-c", script], capture_output=True, text=True, env=e, timeout=180, encoding="utf-8", errors="replace"), models

    def test_choose_groups_shards_and_picks_a_sane_quant(self):
        r, _ = self.driver("plan, err = run.choose('unsloth/shard-12b-GGUF'); print(json.dumps([plan, err]))")
        self.assertEqual(r.returncode, 0, r.stderr)
        plan, err = json.loads(r.stdout)
        self.assertIsNone(err)
        self.assertEqual(plan["quant"], "Q4_K_M")
        self.assertEqual([f["path"] for f in plan["files"]], ["shard-Q4_K_M-00001-of-00002.gguf", "shard-Q4_K_M-00002-of-00002.gguf"])
        self.assertEqual(plan["files"][0]["sha256"], DOWNLOAD_SHA)

    def test_choose_says_so_when_nothing_fits(self):
        r, _ = self.driver("print(json.dumps(run.choose('bartowski/gamma-405b-GGUF')))")
        plan, err = json.loads(r.stdout)
        self.assertIsNone(plan)
        self.assertIn("no quant fits", err)

    def test_download_resumes_a_partial_file_and_verifies_the_hash(self):
        code = ("plan, _ = run.choose('unsloth/shard-12b-GGUF')\n"
                "import os\n"
                "dest = os.path.join(d.MODELS_DIR, 'unsloth', 'shard-12b-GGUF', plan['files'][0]['path'])\n"
                "os.makedirs(os.path.dirname(dest), exist_ok=True)\n"
                "open(dest + '.part', 'wb').write((bytes(range(256)) * 4096)[:300000])\n"
                "print(run.download(plan))\n")
        r, models = self.driver(code)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        d1 = os.path.join(models, "unsloth", "shard-12b-GGUF")
        for name in ("shard-Q4_K_M-00001-of-00002.gguf", "shard-Q4_K_M-00002-of-00002.gguf"):
            data = read(os.path.join(d1, name), "rb")
            self.assertEqual(hashlib.sha256(data).hexdigest(), DOWNLOAD_SHA, name + " is complete and correct")
            self.assertFalse(os.path.exists(os.path.join(d1, name + ".part")), "the .part file was renamed away")

    def test_a_download_that_fails_its_hash_is_quarantined_not_installed(self):
        Stub.corrupt_downloads = True
        r, models = self.driver("plan, _ = run.choose('unsloth/shard-12b-GGUF')\ntry:\n    run.download(plan)\nexcept RuntimeError as e:\n    print('RAISED', e)\n")
        self.assertIn("RAISED", r.stdout, "RED: a corrupt file must stop the run")
        self.assertIn("SHA-256 mismatch", r.stdout)
        d1 = os.path.join(models, "unsloth", "shard-12b-GGUF")
        self.assertTrue(os.path.exists(os.path.join(d1, "shard-Q4_K_M-00001-of-00002.gguf.corrupt")))
        self.assertFalse(os.path.exists(os.path.join(d1, "shard-Q4_K_M-00001-of-00002.gguf")), "a bad file never takes the real name")

    def test_run_state_and_logs_stay_in_the_lab_home_by_default(self):
        r = self.lab("overnight", "report", "--workdir", os.path.join(self._tmp.name, "wd2"))
        # a report over an empty run is an error, not a crash trace into the checkout
        self.assertFalse(os.path.exists(os.path.join(HERE, "overnight")), "nothing is written beside the code")


class TestPortability(LabCase):
    def test_no_script_names_a_machine_or_a_user(self):
        bad = []
        for name in sorted(os.listdir(HERE)):
            if name.endswith((".py", ".cmd")) or name in ("model-lab",):
                text = read(os.path.join(HERE, name))
                if name == os.path.basename(__file__):
                    continue
                for needle in ("100.112.241.4", "C:\\Users\\Jonathan", "/Users/jonathan", "svnCheckouts", "oggsmash"):
                    if needle in text:
                        bad.append("%s mentions %s" % (name, needle))
        self.assertEqual(bad, [], "RED: a hardcoded machine breaks the tool on every other computer")

    def test_every_python_file_compiles_on_this_interpreter(self):
        for name in sorted(os.listdir(HERE)):
            if name.endswith(".py"):
                r = subprocess.run([PY, "-m", "py_compile", os.path.join(HERE, name)], capture_output=True, text=True)
                self.assertEqual(r.returncode, 0, name + ": " + r.stderr)

    def test_help_works_for_every_subcommand(self):
        for sub in ("scout", "smoke", "bench", "overnight", "watch", "arch", "profile", "seen", "wantlist"):
            r = self.lab(sub, "--help")
            self.assertEqual(r.returncode, 0, "%s --help: %s" % (sub, r.stderr))

    def test_an_unknown_subcommand_is_refused(self):
        r = self.lab("frobnicate")
        self.assertNotEqual(r.returncode, 0, "RED")


if __name__ == "__main__":
    unittest.main(verbosity=2)
