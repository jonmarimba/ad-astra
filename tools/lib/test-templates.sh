#!/usr/bin/env bash
# Templates must be NON-EXCLUSIVE. Two templates sharing a tool must coexist, and
# uninstalling one must not remove a tool the other still needs.
#
# This test caught the property failing on the day it was written: uninstalling
# kicker-dev removed mcp-xcode and mcp-mac-control-mcp while swift-ios was
# installed and using both. Keep it red-capable — it is the only thing standing
# between "templates" and "the second install silently breaks the first".
set -u
A="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
command -v jq >/dev/null || { echo "MISSING DEPENDENCY: jq"; exit 1; }
# A throwaway git repo to install into. This used to clone ~/svnCheckouts/js-llmKicker,
# which made the test depend on another project being checked out at that path.
fixture_repo() { mkdir -p "$1" && git -C "$1" init -q && printf '# fixture\n' > "$1/CLAUDE.md" \
  && git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@t commit -qm fixture; }
T="$(mktemp -d)/repo"; fixture_repo "$T" || { echo "fixture repo failed"; exit 1; }
fail=()

iout="$(python3 "$A/tools/lib/template.py" install swift-ios --into "$T" 2>&1)"

# swift-ios carries the code-quality set (INVENTORY item 5: "an edit to one JSON file,
# not a system to build" — plus the member installers that edit required).
[ -f "$T/.claude/skills/ponytail/SKILL.md" ] || fail+=("swift-ios did not install the ponytail skill")
[ -f "$T/.astra/dedup-scan/dedup-scan" ] || fail+=("swift-ios did not install dedup-scan")
# periphery is a machine-level tool (a brew formula). A repo install names it
# and says how to get it, and never runs brew itself (2026-10-04).
echo "$iout" | grep -q "MACHINE periphery" || fail+=("swift-ios did not report periphery as a machine dependency")

python3 "$A/tools/lib/template.py" install kicker-dev --into "$T" >/dev/null 2>&1
out="$(python3 "$A/tools/lib/template.py" uninstall kicker-dev --into "$T" 2>&1)"
rc=$?
after="$(jq -r '.mcpServers|keys|join(",")' "$T/.mcp.json" 2>/dev/null)"

# swift-ios's MCP servers since 2026-09-01: the combined Xcode aggregator,
# mac-control (shared with kicker-dev, so it must be KEPT) and the simulator.
# mac-control-mcp may be ABSENT from the project .mcp.json if the user scope
# (~/.claude/.claude.json) already runs the same binary — the installer dedupes
# it to avoid doubling all 64 tools in sessions that merge scopes. When deduped
# the server is still available through user scope, so its absence is correct.
_user_has_mac_control=false
if [ -f "$HOME/.claude/.claude.json" ]; then
  _mc_bin="$(jq -r '.mcpServers["mac-control"].command // .mcpServers["mac-control-mcp"].command // empty' "$HOME/.claude/.claude.json" 2>/dev/null)"
  [ -z "$_mc_bin" ] || _user_has_mac_control=true
fi
for need in xcode-combined mac-control-mcp ios-simulator; do
  if [ "$need" = "mac-control-mcp" ] && $_user_has_mac_control; then
    echo "  mac-control-mcp deduped to user scope (correct — user scope already runs it)"
    continue
  fi
  echo "$after" | grep -q "$need" || fail+=("swift-ios lost $need after uninstalling an overlapping template")
done
echo "$after" | grep -q kickerd && fail+=("kickerd survived its own template's uninstall")
echo "$out" | grep -q "KEPT" || fail+=("shared tools were not reported as KEPT")
[ $rc -eq 0 ] || fail+=("uninstall exited $rc on a successful run")


# ── State-file integrity ────────────────────────────────────────────────────
# The overlap property above is only as good as the record it reasons from.
# installed_templates() used to swallow every read error into an empty list, so
# a corrupt or hand-edited state file made uninstall believe nothing else
# claimed a shared tool — and it would remove tools a still-installed template
# needed. Reading "I cannot tell" as "nothing installed" is the bug.

echo '{"templates": ["swift-ios"], "tools":' > "$T/.astra/manifest.json"   # truncated mid-write
out="$(python3 "$A/tools/lib/template.py" uninstall kicker-dev --into "$T" 2>&1)"; rc=$?
if [ "$rc" -eq 65 ] && echo "$out" | grep -q "unreadable"; then
  echo "  corrupt state refused instead of read as empty"
else
  fail+=("a corrupt manifest did not stop uninstall (rc=$rc) — it would remove tools another template still needs")
fi

# A deleted record with the tools still present is the same class: the repo is
# not empty, so an empty list is not the answer.
rm -f "$T/.astra/manifest.json"
out="$(python3 "$A/tools/lib/template.py" uninstall kicker-dev --into "$T" 2>&1)"; rc=$?
if [ "$rc" -eq 65 ] && echo "$out" | grep -q "not recorded as installed"; then
  echo "  deleted state refused rather than acted on as an empty list"
else
  fail+=("a deleted manifest let uninstall run from an empty list (rc=$rc)")
fi

# ── A failed install is not recorded as an install ──────────────────────────
# _apply() used to call record_template unconditionally after the member loop, so a
# template with failed member installs was recorded as installed and claimed tools it
# never placed (found by the round-one colloquium, codex leg, verified at the call
# site). Installers are idempotent re-runs, so the honest record after a partial
# failure is "not installed": fix the cause, re-run, and only then record.
T2="$(mktemp -d)/repo"; fixture_repo "$T2" || { echo "fixture repo failed"; exit 1; }
BROKEN_TPL="$(mktemp -d)/templates.json"
cat > "$BROKEN_TPL" <<'EOF'
{"templates": {"half-broken": {"description": "test template with a member that cannot install",
  "tools": ["check-prose", "no-such-tool-astra-test"]}}}
EOF
out="$(ASTRA_TEMPLATES_JSON="$BROKEN_TPL" python3 "$A/tools/lib/template.py" install half-broken --into "$T2" 2>&1)"; rc=$?
recorded="$(python3 -c "import json,sys; print(','.join(json.load(open('$T2/.astra/manifest.json')).get('templates',[])))" 2>/dev/null)"
[ "$rc" -ne 0 ] || fail+=("an install with a failed member exited 0")
echo "$out" | grep -q "FAILED  no-such-tool-astra-test" || fail+=("the failed member was not named in the output")
case ",$recorded," in
  *,half-broken,*) fail+=("a template with a FAILED member was recorded as installed (manifest: '$recorded')") ;;
  *) echo "  failed install left no false record (manifest: '${recorded:-empty}')" ;;
esac
echo "$out" | grep -qi "not record" || fail+=("the output does not say the record was withheld")
rm -rf "$(dirname "$T2")" "$(dirname "$BROKEN_TPL")"

rm -rf "$(dirname "$T")"
if [ ${#fail[@]} -eq 0 ]; then echo "templates: non-exclusive overlap holds"; exit 0; fi
printf 'FAIL: %s\n' "${fail[@]}"; exit 1
