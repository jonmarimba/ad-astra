#!/usr/bin/env bash
# test-uninstall-common.sh — the shared uninstall contract, proved BY EFFECT through the two real
# uninstallers (frame-review, geo-evidence): plain run dis-integrates local state and LEAVES shared
# deps alone; --deps removes them. Dep removal is captured by a stub at the $BREW_BIN/$UV_BIN seam,
# so the real ffmpeg/exiftool/osxphotos are never touched.
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
FR="$HERE/../frame-review/uninstall.sh"
GEO="$HERE/../geo-evidence/uninstall.sh"

# a stub that records every invocation (one line per call) — stands in for brew AND uv
STUB="$SB/toolstub"; LOG="$SB/toolstub.log"
cat > "$STUB" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$LOG"
EOF
chmod +x "$STUB"
export BREW_BIN="$STUB" UV_BIN="$STUB"

# ---- geo-evidence: plain uninstall removes config, does NOT touch deps ----
GH="$SB/geohome"; mkdir -p "$GH"; printf 'HouseA\t1\t2\n' > "$GH/config"
: > "$LOG"
GEO_EVIDENCE_HOME="$GH" assert_rc 0 "geo plain uninstall succeeds" "$GEO"
assert_no_file "$GH/config" "plain uninstall removed the geo config/state dir"
assert_empty "$(cat "$LOG" 2>/dev/null)" "plain uninstall did NOT invoke brew/uv (deps left alone)"

# ---- geo-evidence: --deps removes exiftool (brew) AND osxphotos (uv tool) ----
GH2="$SB/geohome2"; mkdir -p "$GH2"; printf 'x\n' > "$GH2/config"
: > "$LOG"
GEO_EVIDENCE_HOME="$GH2" assert_rc 0 "geo --deps uninstall succeeds" "$GEO" --deps
assert_contains "$LOG" "uninstall exiftool" "--deps removed exiftool via brew seam"
assert_contains "$LOG" "tool uninstall osxphotos" "--deps removed osxphotos via uv seam"
assert_no_file "$GH2/config" "--deps uninstall also removed the config dir"

# ---- frame-review: plain leaves ffmpeg; --deps removes it ----
: > "$LOG"
assert_rc 0 "frame-review plain uninstall succeeds" "$FR"
assert_empty "$(cat "$LOG" 2>/dev/null)" "frame-review plain uninstall did NOT touch ffmpeg"
: > "$LOG"
assert_rc 0 "frame-review --deps uninstall succeeds" "$FR" --deps
assert_contains "$LOG" "uninstall ffmpeg" "frame-review --deps removed ffmpeg via brew seam"

# ---- a non-symlink at a symlink slot is preserved (never delete a real file) ----
. "$HERE/../lib/uninstall-common.sh"
realf="$SB/realfile"; printf 'precious\n' > "$realf"
uc_rm_symlink "$realf" >/dev/null
assert_file "$realf" "uc_rm_symlink refused to delete a real (non-symlink) file"

# ---- RED controls ----
red "unknown flag must fail" 64 "unknown flag" "$GEO" --nuke-everything
red "missing shared lib would break sourcing (sanity: bad path fails)" 1 "No such file or directory" bash -c '. /no/such/uninstall-common.sh'

finish
