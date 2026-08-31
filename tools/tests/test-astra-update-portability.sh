#!/usr/bin/env bash
# test-astra-update-portability.sh — Phase 6: a cloned repo must update on a machine
# where the recorded source path does not exist.
#
# astra-install records an ABSOLUTE source path and astra-update required it to exist,
# so a repo cloned to another machine could never update — which forecloses third-party
# adoption entirely (ROADMAP phase 6). The updater now resolves the source with
# fallbacks: the recorded path, then $ASTRA_SOURCE, then a sibling directory of the
# repo's parent carrying the source's basename (the cloned-workspace convention). When
# nothing resolves, SOURCE GONE names the remedy instead of dead-ending.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

need python3 "xcode-select --install"
CANON="$HERE/../lib/astra-update"

# A fake source tree and a fake repo whose manifest records a DEAD absolute path.
WORK="$SB/work"
mkdir -p "$WORK/checkouts/my-astra/tools/footool" "$WORK/checkouts/consumer/.astra/footool"
printf 'echo v2\n' > "$WORK/checkouts/my-astra/tools/footool/foo.sh"
printf 'echo v1\n' > "$WORK/checkouts/consumer/.astra/footool/foo.sh"
V1SHA="$(python3 -c "import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest()[:16])" "$WORK/checkouts/consumer/.astra/footool/foo.sh")"
cat > "$WORK/checkouts/consumer/.astra/manifest.json" <<EOF
{"tools": {"footool": {"source": "/machine-that-no-longer-exists/my-astra",
  "files": {"foo.sh": "$V1SHA"}}}}
EOF
cp "$CANON" "$WORK/checkouts/consumer/.astra/astra-update"
chmod +x "$WORK/checkouts/consumer/.astra/astra-update"

# --- no fallback available: SOURCE GONE, and the message says what to do ---
mv "$WORK/checkouts/my-astra" "$WORK/elsewhere-astra"
out="$SB/gone.out"
env -u ASTRA_SOURCE "$WORK/checkouts/consumer/.astra/astra-update" >"$out" 2>&1
assert_contains "$out" "SOURCE GONE" "a dead recorded path is reported"
assert_contains "$out" "ASTRA_SOURCE" "and the report names the env override remedy"

# --- ASTRA_SOURCE resolves the source explicitly ---
out="$SB/env.out"
ASTRA_SOURCE="$WORK/elsewhere-astra" "$WORK/checkouts/consumer/.astra/astra-update" >"$out" 2>&1
assert_contains "$out" "BEHIND" "with ASTRA_SOURCE set, the stale copy is seen as behind"
out="$SB/envpull.out"
ASTRA_SOURCE="$WORK/elsewhere-astra" "$WORK/checkouts/consumer/.astra/astra-update" --pull >"$out" 2>&1
assert_contains "$out" "updated" "and --pull updates it"
assert_contains "$WORK/checkouts/consumer/.astra/footool/foo.sh" "v2" "the file really moved forward"

# --- the sibling convention: source cloned beside the repo under its recorded basename ---
printf 'echo v1\n' > "$WORK/checkouts/consumer/.astra/footool/foo.sh"   # stale again
cat > "$WORK/checkouts/consumer/.astra/manifest.json" <<EOF
{"tools": {"footool": {"source": "/machine-that-no-longer-exists/my-astra",
  "files": {"foo.sh": "$V1SHA"}}}}
EOF
mv "$WORK/elsewhere-astra" "$WORK/checkouts/my-astra"
out="$SB/sibling.out"
env -u ASTRA_SOURCE "$WORK/checkouts/consumer/.astra/astra-update" >"$out" 2>&1
assert_contains "$out" "BEHIND" "a sibling clone named like the recorded source is found without any env"
assert_contains "$out" "my-astra" "and the fallback says which source it resolved"

finish
