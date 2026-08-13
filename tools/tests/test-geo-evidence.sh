#!/usr/bin/env bash
# test-geo-evidence.sh — the classification core run through the REAL geo-evidence script with
# a recorded osxphotos JSON payload (osxphotos + exiftool stubbed at their injectable seams, so
# the test needs neither the tools nor a Photos library). Proves nearest-property assignment,
# the whole-lot-vs-neighbor separation at 52m, the elsewhere cutoff, and NO-GPS flagging.
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
GE="$HERE/../geo-evidence/geo-evidence"
need python3 "xcode-select --install"

export GEO_EVIDENCE_HOME="$SB/geo-home"; mkdir -p "$GEO_EVIDENCE_HOME"
cat > "$GEO_EVIDENCE_HOME/config" <<CFG
Speedway	35.409458	-80.646172
Tyndall	35.40911	-80.64578
MAX_M=60
CFG

# stubs at the injectable seams (the script re-prepends system PATH, so seams > PATH shims)
mkdir -p "$SB/bin"
cat > "$SB/bin/osxphotos" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  query) cat "$OSX_FIXTURE" ;;
  --version) echo "osxphotos 0.0-test" ;;
  export) exit 0 ;;
esac
STUB
cat > "$SB/bin/exiftool" <<'STUB'
#!/usr/bin/env bash
echo ""
STUB
chmod +x "$SB/bin/"*
export OSXPHOTOS_BIN="$SB/bin/osxphotos" EXIFTOOL_BIN="$SB/bin/exiftool"

# fixture: osxphotos query --json shape. Points chosen to prove the classifier:
#  AT_SPEEDWAY  — the exact Speedway centroid -> Speedway
#  AT_TYNDALL   — the exact Tyndall centroid  -> Tyndall
#  SPD_EDGE     — 20m from Speedway, ~40m from Tyndall (far edge of Speedway lot) -> Speedway
#  TYN_DRIFT    — a Tyndall shot GPS-drifted ~8m toward Speedway (still nearer Tyndall) -> Tyndall
#  FARAWAY      — downtown Concord, ~4km off -> elsewhere (past MAX_M)
#  NOGPS        — null coords -> NO-GPS flag
cat > "$SB/fixture.json" <<'EOF'
[
 {"uuid":"u1","original_filename":"AT_SPEEDWAY.mov","date":"2026-08-08T20:02:39-04:00","latitude":35.409458,"longitude":-80.646172,"ismovie":true},
 {"uuid":"u2","original_filename":"AT_TYNDALL.heic","date":"2026-08-08T18:00:00-04:00","latitude":35.40911,"longitude":-80.64578,"ismovie":false},
 {"uuid":"u3","original_filename":"SPD_EDGE.jpeg","date":"2026-08-08T20:05:00-04:00","latitude":35.409637,"longitude":-80.646172,"ismovie":false},
 {"uuid":"u4","original_filename":"TYN_DRIFT.jpeg","date":"2026-08-08T19:00:00-04:00","latitude":35.409164,"longitude":-80.645835,"ismovie":false},
 {"uuid":"u5","original_filename":"FARAWAY.jpeg","date":"2026-08-08T12:00:00-04:00","latitude":35.4085,"longitude":-80.5900,"ismovie":false},
 {"uuid":"u6","original_filename":"NOGPS.jpeg","date":"2026-08-08T21:00:00-04:00","latitude":null,"longitude":null,"ismovie":false}
]
EOF
export OSX_FIXTURE="$SB/fixture.json"

out="$("$GE" scan --since 2026-08-08 --until 2026-08-09 2>/dev/null)"
line(){ printf '%s\n' "$out" | grep -F "$1"; }
case "$(line AT_SPEEDWAY.mov)" in *Speedway*) pass "Speedway centroid -> Speedway";; *) fail "AT_SPEEDWAY misclassified: $(line AT_SPEEDWAY.mov)";; esac
case "$(line AT_TYNDALL.heic)" in *Tyndall*) pass "Tyndall centroid -> Tyndall";; *) fail "AT_TYNDALL misclassified: $(line AT_TYNDALL.heic)";; esac
case "$(line SPD_EDGE.jpeg)" in *Speedway*) pass "far edge of Speedway lot (20m out) still -> Speedway (radius would have clipped it)";; *) fail "SPD_EDGE misclassified: $(line SPD_EDGE.jpeg)";; esac
case "$(line TYN_DRIFT.jpeg)" in *Tyndall*) pass "Tyndall shot drifted toward Speedway still -> Tyndall (nearest-centroid holds the 52m line)";; *) fail "TYN_DRIFT misclassified: $(line TYN_DRIFT.jpeg)";; esac
case "$(line FARAWAY.jpeg)" in *elsewhere*) pass "4km-away shot -> elsewhere (past MAX_M cutoff)";; *) fail "FARAWAY not excluded: $(line FARAWAY.jpeg)";; esac
case "$(line NOGPS.jpeg)" in *NO-GPS*) pass "null-GPS shot flagged NO-GPS (integrity catch)";; *) fail "NOGPS not flagged: $(line NOGPS.jpeg)";; esac

# ordering: output sorted by capture time (evidence sequence)
first="$(printf '%s\n' "$out" | grep -E 'AT_SPEEDWAY|AT_TYNDALL|SPD_EDGE|TYN_DRIFT|FARAWAY|NOGPS' | head -1)"
case "$first" in *FARAWAY*) pass "scan sorted chronologically (12:00 shot first)";; *) fail "scan not time-sorted (got: $first)";; esac

# ---- config guard: the shipped template / placeholder coords must REFUSE to run ----
# (proves the tool ships generic, not with someone's real house baked in)
UNCONF="$SB/unconf-home"; mkdir -p "$UNCONF"
red "unconfigured template config (Example/0,0) refuses to run" env GEO_EVIDENCE_HOME="$UNCONF" "$GE" scan --since 2026-08-08 --until 2026-08-09
# and it auto-wrote a template the user can edit
assert_file "$UNCONF/config" "template config written for the user to edit"
assert_contains "$UNCONF/config" "ExampleSite" "shipped config is a placeholder, not real coordinates"

# ---- RED controls ----
red "missing --since must fail" "$GE" scan --until 2026-08-09
red "pull without --property must fail" "$GE" pull --since 2026-08-08 --until 2026-08-09 --out "$SB/o"
red "unknown command must fail" "$GE" frobnicate --since 2026-08-08 --until 2026-08-09
red "unknown flag must fail" "$GE" scan --since 2026-08-08 --until 2026-08-09 --wat x

# ---- gallery: a media folder -> date-grouped HTML with images inline + videos as players ----
GMED="$SB/media"; mkdir -p "$GMED"
: > "$GMED/a_photo.jpeg"; : > "$GMED/b_clip.mov"; : > "$GMED/c_later.jpeg"
# exiftool stub that returns per-file dates + a GPS so the gallery can group + caption
cat > "$SB/bin/exiftool-gal" <<'STUB'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in
  *a_photo.jpeg) echo "2026:08:08 20:02:39"; echo "-80.6"; exit 0;;
  *b_clip.mov)   echo "2026:08:08 20:05:00"; echo "-80.6"; exit 0;;
  *c_later.jpeg) echo "2026:08:09 09:00:00"; echo "-80.6"; exit 0;;
esac; done
echo ""
STUB
chmod +x "$SB/bin/exiftool-gal"
EXIFTOOL_BIN="$SB/bin/exiftool-gal" "$GE" gallery "$GMED" --out "$GMED/index.html" >/dev/null 2>&1
assert_file "$GMED/index.html" "gallery HTML written"
assert_contains "$GMED/index.html" "2026-08-08" "date group header present"
assert_contains "$GMED/index.html" "2026-08-09" "second date group present"
assert_contains "$GMED/index.html" "<img" "image rendered as <img>"
assert_contains "$GMED/index.html" "<video" "video rendered as <video> player"
assert_contains "$GMED/index.html" "b_clip.mov" "video file referenced"
red "gallery with no folder must fail" "$GE" gallery --out "$SB/g.html"
red "gallery without --out must fail" "$GE" gallery "$GMED"

finish
