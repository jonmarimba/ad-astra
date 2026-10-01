I have confirmed four breaks with executable tests and several surfaces that held. Here is the full adversarial report.

---

# ADVERSARIAL PANEL — REFUTATION REPORT

## SEVERITY RANKED, MOST-SEVERE FIRST

---

### BREAK 1 — CRITICAL: `tools_still_claimed` flat-list fallback silently under-claims for a template removed from the catalogue, violating the non-exclusive property

**File:** `tools/lib/template.py:155-167` (read), `tools/lib/template.py:147` (the fallback path)

The code comment at line 155 says: "A recorded template the catalogue no longer resolves still claims its FLAT list — under-claiming here is what deletes another template's tools." The fallback at line 167 does:

```python
claimed.update(t.get(name, {}).get("tools", []))
```

This reads from `t` — the **current catalogue** loaded at line 147 (`t = load()["templates"]`). A template that was renamed or removed from the catalogue after install is not in `t`, so `t.get(name, {})` returns `{}`, and `.get("tools", [])` returns `[]`. The fallback claims nothing, exactly the failure the comment says it prevents.

The manifest still records the template as installed, and the `installed_templates(repo)` call at line 152 still returns it. But `tools_still_claimed` cannot resolve its tools because it reads from the catalogue, not from the manifest.

**Demonstrated by execution:**

```
install old-template: rc=0
install sibling: rc=0
manifest templates: ['old-template', 'sibling']
check-prose.js exists: True

uninstall sibling (catalogue without old-template): rc=0
  uninstalled  check-prose

BREAK CONFIRMED: check-prose was REMOVED by sibling's uninstall
old-template is still in the manifest but the fallback returned []
because it reads from the catalogue (where old-template no longer exists)
instead of the manifest's recorded tools.
```

**The attack:** Two templates share a tool. Install both. Upstream renames or removes one template from `templates.json`. Uninstall the other. The removed template's tools are silently deleted, even though the manifest still records it as installed and its tools are still on disk.

**Runnable test (copy-paste):**

```python
python3 - <<'EOF'
import json, os, tempfile, subprocess, shutil
from pathlib import Path
ASTRA = Path("/Users/jonathan/svnCheckouts/js-db-ad-astra")
TPL = ASTRA / "tools/lib/template.py"
SB = Path(tempfile.mkdtemp())
CAT_WITH = SB / "with.json"
CAT_WITHOUT = SB / "without.json"
CAT_WITH.write_text(json.dumps({"templates": {
    "old-template": {"description": "x", "tools": ["check-prose"]},
    "sibling": {"description": "x", "tools": ["check-prose"]},
}}))
CAT_WITHOUT.write_text(json.dumps({"templates": {
    "sibling": {"description": "x", "tools": ["check-prose"]},
}}))
repo = SB / "repo"; repo.mkdir(); subprocess.run(["git", "init", "-q", str(repo)], check=True)
env_with = {**os.environ, "ASTRA_TEMPLATES_JSON": str(CAT_WITH)}
subprocess.run(["python3", str(TPL), "install", "old-template", "--into", str(repo)], env=env_with, capture_output=True)
subprocess.run(["python3", str(TPL), "install", "sibling", "--into", str(repo)], env=env_with, capture_output=True)
prose = repo / ".astra/check-prose/check-prose.js"
assert prose.exists(), "precondition: check-prose installed"
env_without = {**os.environ, "ASTRA_TEMPLATES_JSON": str(CAT_WITHOUT)}
subprocess.run(["python3", str(TPL), "uninstall", "sibling", "--into", str(repo)], env=env_without, capture_output=True)
if prose.exists():
    print("HELD")
else:
    print("BREAK: check-prose deleted by sibling uninstall while old-template still in manifest")
shutil.rmtree(SB)
EOF
```

---

### BREAK 2 — HIGH: `run-all.sh` budget assertion never fires on a hung test file — the tier stalls forever with no verdict

**File:** `tools/tests/run-all.sh:27-32` (read)

The xargs parallel block at line 46 runs all test files concurrently. The budget check at line 64 runs AFTER the xargs block returns. A test file that hangs (waiting on stdin, deadlocked, waiting for an approval dialog nobody will click) means xargs never returns, so the budget check never runs. The comment at line 14 says "THE TIME BUDGET IS AN ASSERTION, NOT A HOPE" — but the assertion is structurally unreachable for the one failure mode it was written to catch.

**Demonstrated by execution:**

```
BREAK CONFIRMED: run-all.sh hung past 10s wall-clock (budget was 3s)
The budget check never ran because xargs never returned (hung test).
```

The `timeout 10` killed the entire run-all.sh process at 10 seconds. The budget was 3 seconds. The budget assertion never fired.

**The fix:** Run the xargs block in the background, check the budget in the foreground, and kill xargs if the budget is exceeded. Or wrap each test file invocation in `timeout $ASTRA_FAST_TEST_TIMEOUT_S`.

**Runnable test (copy-paste):**

```bash
#!/usr/bin/env bash
SB="$(mktemp -d -t hung-test)"; trap 'rm -rf "$SB"' EXIT
cp /Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/run-all.sh "$SB/"
cat > "$SB/test-hung.sh" <<EOF
#!/usr/bin/env bash
sleep 999
EOF
cat > "$SB/test-fast.sh" <<EOF
#!/usr/bin/env bash
echo "== ok"
EOF
timeout 10 env ASTRA_FAST_BUDGET_S=3 bash "$SB/run-all.sh" >"$SB/out" 2>&1
rc=$?
[ "$rc" -eq 124 ] && echo "BREAK: hung past 10s (budget 3s)" || echo "HELD: exited rc=$rc"
```

---

### BREAK 3 — HIGH: `astra-update` sibling fallback feeds updates from an impostor checkout with the same basename

**File:** `tools/lib/astra-update:65-72` (read)

`resolve_source` falls back to a sibling directory of the repo's parent named like the recorded source's basename. The check at line 71 is `(cand / "tools").is_dir()` — any directory with the right name and a `tools/` subdirectory qualifies. The note at line 72 says which source it resolved but does not verify the source is the same repo it was recorded from.

An impostor, a stale fork, or a malicious checkout cloned beside the consumer under the right name feeds updates silently. The consumer's files are replaced with the impostor's content.

**Demonstrated by execution:**

```
rc=0
note: footool source (resolved sibling of this repo's parent: .../work/real-astra)
  updated      footool/foo.sh

foo.sh content after --pull: 'echo EVIL'
BREAK CONFIRMED: the impostor checkout fed the update!
```

**The fix:** The fallback should verify the sibling directory is the same repo — by comparing a recorded identifier (git remote, a UUID file written at install time, or a hash of the source tree's structure) rather than just the basename and the presence of `tools/`.

**Runnable test (copy-paste):**

```python
python3 - <<'EOF'
import json, os, tempfile, subprocess, shutil
from pathlib import Path
CANON = Path("/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/astra-update")
SB = Path(tempfile.mkdtemp()); WORK = SB / "work"
os.makedirs(WORK / "impostor/tools/footool"); (WORK / "impostor/tools/footool/foo.sh").write_text("echo EVIL\n")
os.makedirs(WORK / "consumer/.astra/footool"); (WORK / "consumer/.astra/footool/foo.sh").write_text("echo v1\n")
v1sha = subprocess.check_output(["python3", "-c", f"import hashlib;print(hashlib.sha256(open('{WORK}/consumer/.astra/footool/foo.sh','rb').read()).hexdigest()[:16])"]).decode().strip()
(WORK / "consumer/.astra/manifest.json").write_text(json.dumps({"tools": {"footool": {"source": "/dead/real-astra", "files": {"foo.sh": v1sha}}}}))
shutil.copy(str(CANON), str(WORK / "consumer/.astra/astra-update")); os.chmod(str(WORK / "consumer/.astra/astra-update"), 0o755)
shutil.move(str(WORK / "impostor"), str(WORK / "real-astra"))
env = {k: v for k, v in os.environ.items() if k != "ASTRA_SOURCE"}
subprocess.run([str(WORK / "consumer/.astra/astra-update"), "--pull"], capture_output=True, text=True, env=env)
content = (WORK / "consumer/.astra/footool/foo.sh").read_text().strip()
print("BREAK: impostor fed update" if content == "echo EVIL" else f"HELD: {content}")
shutil.rmtree(SB)
EOF
```

---

### BREAK 4 — MEDIUM: `ponytail/install-into-repo.sh` idempotency check uses file existence, not content — a failed curl leaves an empty SKILL.md that is never re-downloaded

**File:** `tools/ponytail/install-into-repo.sh:14` (read)

```bash
if [ -f "$DEST/SKILL.md" ]; then echo "already installed: $DEST"; continue; fi
```

A curl failure (network down, 404, DNS failure) with `-o "$DEST/SKILL.md"` truncates the output file to zero before the request fails. The `grep -q "name:"` check at line 17 catches this on the first run and exits 1. But the empty file is left on disk. On the next run, `[ -f "$DEST/SKILL.md" ]` sees the empty file and prints "already installed", skipping the download entirely. The skill is permanently empty.

Inside a template install, this means: the first skill (ponytail) fails, the script exits 1, the template is not recorded. On re-run, ponytail is skipped ("already installed"), ponytail-audit downloads successfully, the script exits 0, and the template is recorded as installed — with an empty SKILL.md for ponytail.

**Demonstrated by execution:**

```
BREAK CONFIRMED: install-into-repo.sh would say 'already installed'
and skip re-downloading, leaving an EMPTY SKILL.md in place.
SKILL.md size: 0 bytes
```

**The fix:** Change `[ -f "$DEST/SKILL.md" ]` to `grep -q "name:" "$DEST/SKILL.md" 2>/dev/null` — check the file has the expected content, not just that it exists.

---

### BREAK 5 — LOW: `tooljson.py` accepts whitespace-only and duplicate ecosystem coordinates

**File:** `tools/lib/tooljson.py:83-84` (read)

The check for empty coordinates at line 84 is `if not coord:` — but `" "` (whitespace) is truthy in Python, so `"brew:  "` passes validation with coordinate `" "`. The code validates that a coordinate is non-empty but not that it is non-whitespace.

Duplicate coordinates are also accepted. `"brew:jq"` can appear twice in the dependencies list and both are validated and printed. The `deps` subcommand would list `brew: jq` twice, and a dependency installer would attempt to install jq twice.

**Demonstrated by execution:**

```
whitespace coordinate 'brew:  ': rc=0
  brew:   
  npm: express

duplicate 'brew:jq' x2: rc=0
  brew: jq
  brew: jq
```

The `brew:` empty-coordinate check at line 83 (`if not coord:`) catches `brew:` (coordinate is `""`, falsy) but not `brew: ` (coordinate is `" "`, truthy). A `.strip()` on the coordinate before the check would fix both the whitespace and the duplicate issue (duplicates could be detected by checking if the coordinate is already in `grouped[eco]`).

---

### BREAK 6 — LOW: `red()` diagnostic substrings are short and generic at 15 call sites — a different guard producing the same rc + substring would satisfy the control for the wrong reason

**File:** `tools/tests/lib.sh:47` (read — the `grep -qF -- "$want_msg"` check), 15 call sites across the test suite

The `red()` contract checks the exact exit code AND that the diagnostic appears as a literal substring. A call site is weak when the expected diagnostic is a short generic string that multiple unrelated failure modes could produce. Found 15 call sites with diagnostics under 10 characters or starting with `usage:`:

| File | rc | Diagnostic | Chars |
|---|---|---|---|
| `test-frame-review.sh:33` | 64 | `usage:` | 6 |
| `test-speech-bee.sh:33` | 1 | `usage:` | 6 |
| `test-mcp-front-config.sh:131` | 65 | `prefix of` | 9 |

The `usage:` cases are the weakest. If a tool is refactored to exit 64 and print `usage:` for a different reason (a `--help` flag, a deprecation warning), the `red` control for "no arguments must fail with usage" would pass even if the no-arguments guard itself is removed — because `--help`'s output contains `usage:` and exits 64.

This is a minor weakness in practice — the tests call the tool with no arguments, so only the no-arguments guard can fire. But the `red()` contract was written to catch "the command failed for the wrong reason," and a 6-character substring shared with another guard is exactly that.

---

## ATTACKED AND HELD

Each verdict names the attack and why it held.

**`mcp_tools.py` CRLF line splitting.** `next_line` splits on `b"\n"` only, leaving `\r` at line ends. Held: `read_response` does `line = line.strip()` at `mcp_tools.py:80`, which removes `\r`. Tested with `json.loads` on a CRLF-terminated line — Python's JSON parser also tolerates trailing `\r`. No break.

**`mcp_tools.py` partial UTF-8 at chunk boundaries.** A multi-byte UTF-8 character split across two `os.read` chunks. Held: `\n` is ASCII (0x0A) and cannot appear inside a multi-byte UTF-8 sequence, so line boundaries always fall at complete UTF-8 character boundaries. The partial byte stays in `pending[0]` and is completed by the next chunk before the line is decoded. No break.

**`mcp_tools.py` deadline arithmetic.** Each `read_response` call gets its own full timeout. Held: the deadline is set once per call (`time.monotonic() + limit`) and each `select` uses the remaining time. The total is bounded by `2 * timeout` (one per request), which is by design — each request gets its own full window.

**`mcp_tools.py` stderr-drain thread lifetime.** The thread is `daemon=True` and reads until EOF. Held: after `p.kill()` and `p.wait()` in the `finally` block, the process's stderr pipe closes from the write end, the thread gets EOF, and stops. No zombie, no leak.

**`mcp_tools.py` compare refusal logic.** Attack: compare should refuse when one side fails to list. Held: `cmd_compare` checks `if "tools" not in info` for both sides, sets `failed = True`, and returns 2 with a "Refusing to compare" message. Confirmed by `test-mcp-tools.sh:48`.

**`run-all.sh` output interleaving.** Attack: parallel tests' output could interleave. Held: each test writes to `$TMPOUT/$b.out` (per-file buffer), and the output is read sequentially in the `for t in "${fast[@]}"` loop after all tests complete. No interleaving.

**`run-all.sh` rc aggregation losing a failure.** Attack: a killed test's exit code could be lost. Held: `rc="$(cat "$TMPOUT/$b.rc" 2>/dev/null || echo missing)"` catches the missing-rc case, and `[ "$rc" != "0" ]` catches any non-zero exit. The `missing` case gets its own diagnostic line.

**`run-all.sh` xargs with space in filename.** Attack: `xargs -I{}` splits filenames at spaces. Held: `-I` implies one line per invocation, so the entire filename (including spaces) is substituted as one unit. Tested with a file named `test-foo bar.sh` — it ran successfully.

**`tooljson.py` list exit semantics with one broken descriptor.** Attack: `list` could hide a broken descriptor. Held: errors go to stderr, valid descriptors go to stdout, exit code is 65 if any errors. A caller checking the exit code and reading stderr gets the full picture. Standard Unix behavior.

**`template.py` uninstall ordering (wrapper + leaf in one session).** Attack: uninstalling a wrapper and leaf in one session could remove tools the other still needs. Held: `tools_still_claimed` reads the current manifest state after each uninstall, and `record_template` updates the manifest before the next uninstall runs. The non-exclusive property holds as long as the catalogue resolves all recorded templates — modulo Break 1 above.

**`template.py` corrupt/deleted state refusal.** Attack: a corrupt or deleted manifest could let uninstall run from an empty list. Held: `_read_state` refuses corrupt files with exit 65, and `_apply` refuses to uninstall a template not in the record. Both confirmed by `test-templates.sh` state-integrity section.

**`template.py` failed install not recorded.** Attack: a partial install could be recorded as complete. Held: `record_template` only runs when `fail_n == 0` (line 195). Confirmed by `test-templates.sh` half-broken test case.

**`lib.sh` `assert_contains` empty-needle guard.** Attack: an unset variable could pass `assert_contains` against any output. Held: `lib.sh:25` checks `[ -n "$2" ]` before the grep and fails with a tautology-guard message. Confirmed by `test-lib.sh` case 7.
