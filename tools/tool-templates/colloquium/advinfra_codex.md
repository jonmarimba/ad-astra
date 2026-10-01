## Findings

### 1. A same-named sibling checkout can supply impostor updates.

Severity: High.

Read: [`resolve_source()`](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/astra-update:74) accepts a sibling when it has the recorded basename and any `tools/` directory. It checks no repository identity, remote URL, source digest, or tool provenance at [line 99](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/astra-update:99). An unchanged installed file is then replaced from that source at [line 159](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/astra-update:159).

Executed: I passed a nonexistent recorded path ending in `js-db-ad-astra`. The resolver accepted `/Users/jonathan/svnCheckouts/js-db-ad-astra` solely because that sibling exists and contains `tools/`.

Inference: The intended case is a genuine relocated clone. The same evidence also fits an unrelated or hostile checkout with the same basename. The updater cannot distinguish them and will copy executable content from either. Printing the substituted path does not prevent a noninteractive `--pull`.

The resolution is also per tool at [line 110](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/astra-update:110). A manifest can therefore use an existing recorded source for one tool and `$ASTRA_SOURCE` or a sibling for another. The output identifies only fallback resolutions, so a mixed-source update is not summarized as such.

### 2. The template system can write into `$HOME` despite its “NEVER GLOBAL” promise.

Severity: High.

Read: The promise says delegated installers refuse `$HOME` and global configuration locations at [template.py:26](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/template.py:26). The template target validator checks only that the path is a directory at [template.py:232](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/template.py:232).

The ponytail shim forwards that path without applying `astra_target` at [ponytail/install.sh:14](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/ponytail/install.sh:14). Its real installer writes directly under `<target>/.claude/skills` at [install-into-repo.sh:12](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/ponytail/install-into-repo.sh:12).

Inference: `template.py install swift --into "$HOME"` can write the ponytail skills into the global Claude skill directory. Other members can fail their own guards, but `_apply()` continues through later members at [template.py:283](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/template.py:283). The command can therefore return failure and withhold the template record after it has already changed global state.

Ponytail also downloads unpinned files from the `main` branch during template installation at [install-into-repo.sh:10](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/ponytail/install-into-repo.sh:10). Its idempotency gate accepts any existing `SKILL.md`, including an empty or corrupted file, at [line 13](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/ponytail/install-into-repo.sh:13). The current idempotency test checks only a valid file produced by the first network fetch at [test-installers-which-first.sh:29](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-installers-which-first.sh:29).

### 3. An unresolvable recorded wrapper can lose its transitive tools.

Severity: High.

Read: If a recorded template no longer resolves, `tools_still_claimed()` falls back to that wrapper’s own flat `tools` list at [template.py:188](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/template.py:188).

The benign case is a wrapper whose own flat list includes every tool it needs. A normal composed wrapper instead has an empty flat list and receives its tools from `templates`, as `mac-swift` does at [templates.json:26](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/templates.json:26).

Inference: If one member is renamed or removed from the catalogue, the wrapper remains recorded but its transitive claims become empty. Uninstalling another template that shares one of those tools can then delete the tool from disk while the wrapper remains installed.

A second branch also breaks. If the unresolvable wrapper has a matching flat tool, the fallback marks it as kept, but the reporting comprehension calls `resolve_tools()` again without catching `ValueError` at [template.py:285](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/template.py:285). That produces a traceback instead of a controlled uninstall result.

### 4. The fast-tier budget cannot stop a hung test.

Severity: High.

Read: `run-all.sh` waits for `xargs` and every child to return at [run-all.sh:39](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/run-all.sh:39). It evaluates elapsed time only afterward at [line 58](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/run-all.sh:58).

The current test sleeps for two seconds and then exits at [test-run-tiers.sh:68](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-run-tiers.sh:68). It proves that a finite overrun eventually gets a failure verdict.

Inference: A test blocked on a pipe, network call, child process, or infinite loop prevents the runner from ever reaching its budget assertion. The claimed 15-second self-budget is therefore an after-the-fact duration check, not a deadline.

### 5. `mcp_tools.py` silently misses paginated tools and collisions.

Severity: Medium.

Read: The shipped stub explicitly supports `nextCursor` pagination at [stub_mcp_server.py:95](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/stub_mcp_server.py:95). `probe()` reads one `tools/list` response and returns its `tools` array at [mcp_tools.py:171](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/mcp_tools.py:171). It never reads `nextCursor`.

Executed: Two stub servers each placed a shared tool on page two. `compare` reported:

```text
left  —  left 1.0-stub  —  1 tools
right  —  right 1.0-stub  —  1 tools
EXACT NAME COLLISIONS: 0
observed_rc=0
```

Inference: Compare’s refusal protects transport failures, but it does not protect incomplete successful responses. A spec-compliant paginated server can produce a confident false “zero collisions.”

### 6. Several MCP failure paths escape the promised refusal.

Severity: Medium.

Read and executed: `subprocess.Popen()` occurs before the protected exchange at [mcp_tools.py:73](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/mcp_tools.py:73). Comparing two nonexistent commands produced a `FileNotFoundError` traceback and exit code 1. Execution never reached the controlled “Refusing to compare” path at [line 230](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/mcp_tools.py:230).

Read: The byte splitter handles CRLF because parsed lines are stripped at [line 136](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/mcp_tools.py:136). It also preserves partial UTF-8 sequences until a complete line is available. A huge unterminated line is different: `pending[0] += chunk` at [line 120](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/mcp_tools.py:120) has no size bound and repeatedly copies the growing bytes object. The deadline eventually fires, unless memory exhaustion or copying cost wins first.

Read: The stderr-drain thread is never joined at [lines 176–179](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/mcp_tools.py:176). The EOF error builds its stderr suffix before cleanup at [lines 165–170](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/mcp_tools.py:165). A child that writes stderr immediately before exiting can race that diagnostic construction.

### 7. `tooljson.py` accepts whitespace-only and duplicate dependencies.

Severity: Low.

Read: The parser rejects only an exactly empty coordinate at [tooljson.py:113](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/tooljson.py:113). It does not trim coordinates or detect duplicates before appending them at [line 115](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/tooljson.py:115).

Executed: This descriptor returned exit code 0:

```json
{"name":"dev","description":"d","provides":"cli","dependencies":["brew:   ","brew:jq","brew:jq"]}
```

It printed one whitespace-only brew dependency and `brew: jq` twice. The existing test checks `brew:` with no coordinate indirectly through the implementation’s stated contract, but it has no whitespace or duplicate case.

### 8. `red()` proves an output signature, not necessarily the named guard.

Severity: Low.

Read: The implementation correctly requires the declared exit code and literal substring at [lib.sh:79](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/lib.sh:79). This is materially stronger than accepting any nonzero result.

Inference: No `(rc, substring)` pair can establish guard identity when several paths share it. The weaker migrated call sites include the generic `rc=1` plus `usage: geo-evidence` oracle for an unknown command at [test-geo-evidence.sh:81](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-geo-evidence.sh:81), and the generic shell `No such file or directory` oracle at [test-uninstall-common.sh:50](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-uninstall-common.sh:50). These prove rejection, but they do not exclude every unrelated failure that produces the same pair. The field-specific tooljson diagnostics and MCP refusal diagnostics are substantially stronger call sites.

## Runnable test for the source-impostor break

The sandbox rejected `mktemp` with `EPERM`, so I could not add this file to the tree. This script fails against the current updater because the installed file becomes `IMPOSTOR`.

```bash
#!/usr/bin/env bash
set -euo pipefail

ASTRA_REPO="${ASTRA_REPO:-$(git rev-parse --show-toplevel)}"
TEST_ROOT="$(mktemp -d -t astra-source-impostor)"
trap 'rm -rf "$TEST_ROOT"' EXIT

CONSUMER="$TEST_ROOT/checkouts/consumer"
IMPOSTOR="$TEST_ROOT/checkouts/my-astra"

mkdir -p "$CONSUMER/.astra/footool" "$IMPOSTOR/tools/footool"
printf 'SAFE\n' > "$CONSUMER/.astra/footool/foo.sh"
printf 'IMPOSTOR\n' > "$IMPOSTOR/tools/footool/foo.sh"

INSTALLED_SHA="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest()[:16])' "$CONSUMER/.astra/footool/foo.sh")"

cat > "$CONSUMER/.astra/manifest.json" <<EOF
{
  "tools": {
    "footool": {
      "source": "/machine-that-does-not-exist/my-astra",
      "files": {
        "foo.sh": "$INSTALLED_SHA"
      }
    }
  }
}
EOF

cp "$ASTRA_REPO/tools/lib/astra-update" "$CONSUMER/.astra/astra-update"
chmod +x "$CONSUMER/.astra/astra-update"

set +e
OUTPUT="$(env -u ASTRA_SOURCE "$CONSUMER/.astra/astra-update" --pull 2>&1)"
RC=$?
set -e

if grep -qxF 'IMPOSTOR' "$CONSUMER/.astra/footool/foo.sh"; then
  printf 'FAIL: a same-named sibling supplied executable update content.\n%s\n' "$OUTPUT" >&2
  exit 1
fi

if [ "$RC" -eq 0 ]; then
  printf 'FAIL: the updater accepted an unauthenticated sibling source.\n%s\n' "$OUTPUT" >&2
  exit 1
fi

printf 'ok: an unauthenticated same-named sibling was refused\n'
```

## Attacked and held

- The runner’s buffered output and exit aggregation held. Each test writes separate output and return-code files, and a missing return-code file forces overall failure at [run-all.sh:45](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/run-all.sh:45).
- A test filename containing spaces survived the exact `xargs -I` construction in execution. A quote-containing filename makes `xargs` reject the item, but the missing return-code file prevents a false green result.
- The first-three-lines marker rule held against a marker quoted later in a test body. The convention remains rigid: a genuine marker on line four is treated as fast.
- CRLF and partial UTF-8 boundaries held in the MCP splitter. The unbounded huge-line case did not.
- Wrapper-first and leaf-first uninstall ordering held while the catalogue remained resolvable. The failure begins when a recorded composition can no longer resolve.
- Member-first plus own-tools dedup retained every distinct tool and preserved first occurrence order at [template.py:71](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/template.py:71).
- The legacy-token allowlist held against unknown bare tokens. `list` also returns 65 when any descriptor is invalid while still printing the valid descriptors at [tooljson.py:164](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/tooljson.py:164).
- Plain swift-ios uninstall does not remove the real Periphery brew formula. `template.py` passes only `--into` at [template.py:99](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/template.py:99), and `uc_brew` keeps dependencies unless `--deps` was supplied at [uninstall-common.sh:44](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/uninstall-common.sh:44). This follows the shared dependency policy, although the template CLI provides no way to request dependency removal.
## Findings

### 1. A same-named sibling checkout can supply impostor updates.

Severity: High.

Read: [`resolve_source()`](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/astra-update:74) accepts a sibling when it has the recorded basename and any `tools/` directory. It checks no repository identity, remote URL, source digest, or tool provenance at [line 99](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/astra-update:99). An unchanged installed file is then replaced from that source at [line 159](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/astra-update:159).

Executed: I passed a nonexistent recorded path ending in `js-db-ad-astra`. The resolver accepted `/Users/jonathan/svnCheckouts/js-db-ad-astra` solely because that sibling exists and contains `tools/`.

Inference: The intended case is a genuine relocated clone. The same evidence also fits an unrelated or hostile checkout with the same basename. The updater cannot distinguish them and will copy executable content from either. Printing the substituted path does not prevent a noninteractive `--pull`.

The resolution is also per tool at [line 110](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/astra-update:110). A manifest can therefore use an existing recorded source for one tool and `$ASTRA_SOURCE` or a sibling for another. The output identifies only fallback resolutions, so a mixed-source update is not summarized as such.

### 2. The template system can write into `$HOME` despite its “NEVER GLOBAL” promise.

Severity: High.

Read: The promise says delegated installers refuse `$HOME` and global configuration locations at [template.py:26](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/template.py:26). The template target validator checks only that the path is a directory at [template.py:232](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/template.py:232).

The ponytail shim forwards that path without applying `astra_target` at [ponytail/install.sh:14](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/ponytail/install.sh:14). Its real installer writes directly under `<target>/.claude/skills` at [install-into-repo.sh:12](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/ponytail/install-into-repo.sh:12).

Inference: `template.py install swift --into "$HOME"` can write the ponytail skills into the global Claude skill directory. Other members can fail their own guards, but `_apply()` continues through later members at [template.py:283](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/template.py:283). The command can therefore return failure and withhold the template record after it has already changed global state.

Ponytail also downloads unpinned files from the `main` branch during template installation at [install-into-repo.sh:10](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/ponytail/install-into-repo.sh:10). Its idempotency gate accepts any existing `SKILL.md`, including an empty or corrupted file, at [line 13](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/ponytail/install-into-repo.sh:13). The current idempotency test checks only a valid file produced by the first network fetch at [test-installers-which-first.sh:29](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-installers-which-first.sh:29).

### 3. An unresolvable recorded wrapper can lose its transitive tools.

Severity: High.

Read: If a recorded template no longer resolves, `tools_still_claimed()` falls back to that wrapper’s own flat `tools` list at [template.py:188](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/template.py:188).

The benign case is a wrapper whose own flat list includes every tool it needs. A normal composed wrapper instead has an empty flat list and receives its tools from `templates`, as `mac-swift` does at [templates.json:26](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/templates.json:26).

Inference: If one member is renamed or removed from the catalogue, the wrapper remains recorded but its transitive claims become empty. Uninstalling another template that shares one of those tools can then delete the tool from disk while the wrapper remains installed.

A second branch also breaks. If the unresolvable wrapper has a matching flat tool, the fallback marks it as kept, but the reporting comprehension calls `resolve_tools()` again without catching `ValueError` at [template.py:285](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/template.py:285). That produces a traceback instead of a controlled uninstall result.

### 4. The fast-tier budget cannot stop a hung test.

Severity: High.

Read: `run-all.sh` waits for `xargs` and every child to return at [run-all.sh:39](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/run-all.sh:39). It evaluates elapsed time only afterward at [line 58](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/run-all.sh:58).

The current test sleeps for two seconds and then exits at [test-run-tiers.sh:68](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-run-tiers.sh:68). It proves that a finite overrun eventually gets a failure verdict.

Inference: A test blocked on a pipe, network call, child process, or infinite loop prevents the runner from ever reaching its budget assertion. The claimed 15-second self-budget is therefore an after-the-fact duration check, not a deadline.

### 5. `mcp_tools.py` silently misses paginated tools and collisions.

Severity: Medium.

Read: The shipped stub explicitly supports `nextCursor` pagination at [stub_mcp_server.py:95](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/stub_mcp_server.py:95). `probe()` reads one `tools/list` response and returns its `tools` array at [mcp_tools.py:171](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/mcp_tools.py:171). It never reads `nextCursor`.

Executed: Two stub servers each placed a shared tool on page two. `compare` reported:

```text
left  —  left 1.0-stub  —  1 tools
right  —  right 1.0-stub  —  1 tools
EXACT NAME COLLISIONS: 0
observed_rc=0
```

Inference: Compare’s refusal protects transport failures, but it does not protect incomplete successful responses. A spec-compliant paginated server can produce a confident false “zero collisions.”

### 6. Several MCP failure paths escape the promised refusal.

Severity: Medium.

Read and executed: `subprocess.Popen()` occurs before the protected exchange at [mcp_tools.py:73](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/mcp_tools.py:73). Comparing two nonexistent commands produced a `FileNotFoundError` traceback and exit code 1. Execution never reached the controlled “Refusing to compare” path at [line 230](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/mcp_tools.py:230).

Read: The byte splitter handles CRLF because parsed lines are stripped at [line 136](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/mcp_tools.py:136). It also preserves partial UTF-8 sequences until a complete line is available. A huge unterminated line is different: `pending[0] += chunk` at [line 120](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/mcp_tools.py:120) has no size bound and repeatedly copies the growing bytes object. The deadline eventually fires, unless memory exhaustion or copying cost wins first.

Read: The stderr-drain thread is never joined at [lines 176–179](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/mcp_tools.py:176). The EOF error builds its stderr suffix before cleanup at [lines 165–170](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tool-templates/mcp_tools.py:165). A child that writes stderr immediately before exiting can race that diagnostic construction.

### 7. `tooljson.py` accepts whitespace-only and duplicate dependencies.

Severity: Low.

Read: The parser rejects only an exactly empty coordinate at [tooljson.py:113](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/tooljson.py:113). It does not trim coordinates or detect duplicates before appending them at [line 115](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/tooljson.py:115).

Executed: This descriptor returned exit code 0:

```json
{"name":"dev","description":"d","provides":"cli","dependencies":["brew:   ","brew:jq","brew:jq"]}
```

It printed one whitespace-only brew dependency and `brew: jq` twice. The existing test checks `brew:` with no coordinate indirectly through the implementation’s stated contract, but it has no whitespace or duplicate case.

### 8. `red()` proves an output signature, not necessarily the named guard.

Severity: Low.

Read: The implementation correctly requires the declared exit code and literal substring at [lib.sh:79](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/lib.sh:79). This is materially stronger than accepting any nonzero result.

Inference: No `(rc, substring)` pair can establish guard identity when several paths share it. The weaker migrated call sites include the generic `rc=1` plus `usage: geo-evidence` oracle for an unknown command at [test-geo-evidence.sh:81](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-geo-evidence.sh:81), and the generic shell `No such file or directory` oracle at [test-uninstall-common.sh:50](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/test-uninstall-common.sh:50). These prove rejection, but they do not exclude every unrelated failure that produces the same pair. The field-specific tooljson diagnostics and MCP refusal diagnostics are substantially stronger call sites.

## Runnable test for the source-impostor break

The sandbox rejected `mktemp` with `EPERM`, so I could not add this file to the tree. This script fails against the current updater because the installed file becomes `IMPOSTOR`.

```bash
#!/usr/bin/env bash
set -euo pipefail

ASTRA_REPO="${ASTRA_REPO:-$(git rev-parse --show-toplevel)}"
TEST_ROOT="$(mktemp -d -t astra-source-impostor)"
trap 'rm -rf "$TEST_ROOT"' EXIT

CONSUMER="$TEST_ROOT/checkouts/consumer"
IMPOSTOR="$TEST_ROOT/checkouts/my-astra"

mkdir -p "$CONSUMER/.astra/footool" "$IMPOSTOR/tools/footool"
printf 'SAFE\n' > "$CONSUMER/.astra/footool/foo.sh"
printf 'IMPOSTOR\n' > "$IMPOSTOR/tools/footool/foo.sh"

INSTALLED_SHA="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest()[:16])' "$CONSUMER/.astra/footool/foo.sh")"

cat > "$CONSUMER/.astra/manifest.json" <<EOF
{
  "tools": {
    "footool": {
      "source": "/machine-that-does-not-exist/my-astra",
      "files": {
        "foo.sh": "$INSTALLED_SHA"
      }
    }
  }
}
EOF

cp "$ASTRA_REPO/tools/lib/astra-update" "$CONSUMER/.astra/astra-update"
chmod +x "$CONSUMER/.astra/astra-update"

set +e
OUTPUT="$(env -u ASTRA_SOURCE "$CONSUMER/.astra/astra-update" --pull 2>&1)"
RC=$?
set -e

if grep -qxF 'IMPOSTOR' "$CONSUMER/.astra/footool/foo.sh"; then
  printf 'FAIL: a same-named sibling supplied executable update content.\n%s\n' "$OUTPUT" >&2
  exit 1
fi

if [ "$RC" -eq 0 ]; then
  printf 'FAIL: the updater accepted an unauthenticated sibling source.\n%s\n' "$OUTPUT" >&2
  exit 1
fi

printf 'ok: an unauthenticated same-named sibling was refused\n'
```

## Attacked and held

- The runner’s buffered output and exit aggregation held. Each test writes separate output and return-code files, and a missing return-code file forces overall failure at [run-all.sh:45](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/tests/run-all.sh:45).
- A test filename containing spaces survived the exact `xargs -I` construction in execution. A quote-containing filename makes `xargs` reject the item, but the missing return-code file prevents a false green result.
- The first-three-lines marker rule held against a marker quoted later in a test body. The convention remains rigid: a genuine marker on line four is treated as fast.
- CRLF and partial UTF-8 boundaries held in the MCP splitter. The unbounded huge-line case did not.
- Wrapper-first and leaf-first uninstall ordering held while the catalogue remained resolvable. The failure begins when a recorded composition can no longer resolve.
- Member-first plus own-tools dedup retained every distinct tool and preserved first occurrence order at [template.py:71](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/template.py:71).
- The legacy-token allowlist held against unknown bare tokens. `list` also returns 65 when any descriptor is invalid while still printing the valid descriptors at [tooljson.py:164](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/tooljson.py:164).
- Plain swift-ios uninstall does not remove the real Periphery brew formula. `template.py` passes only `--into` at [template.py:99](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/template.py:99), and `uc_brew` keeps dependencies unless `--deps` was supplied at [uninstall-common.sh:44](/Users/jonathan/svnCheckouts/js-db-ad-astra/tools/lib/uninstall-common.sh:44). This follows the shared dependency policy, although the template CLI provides no way to request dependency removal.