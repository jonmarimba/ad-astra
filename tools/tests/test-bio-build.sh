#!/usr/bin/env bash
# test-bio-build.sh — assembles a fixture sections dir and asserts by effect: title, an auto
# TOC listing every section heading in prefix order, all bodies present in order, and — the
# no-silent-loss guarantee — a build REFUSES when a section is empty or unindexable rather than
# quietly shipping a bio with a hole.
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
BB="$HERE/../bio-build/bio-build"

SRC="$SB/sections"; mkdir -p "$SRC"
printf '# Who\nBody one, unmistakable ALPHA.\n'     > "$SRC/00_who.md"
printf '# The Work\nBody two, unmistakable BETA.\n' > "$SRC/20_work.md"
printf '# The Life\nBody three, unmistakable GAMMA.\n' > "$SRC/10_life.md"   # out of lexical order on purpose

export BIO_BUILD_DATE="2026-08-13"
assert_rc 0 "build succeeds" "$BB" "$SRC" --out "$SB/bio.md" --title "Test Person" --subtitle "a subtitle"
assert_file "$SB/bio.md" "output written"
assert_contains "$SB/bio.md" "# Test Person" "title present"
assert_contains "$SB/bio.md" "*a subtitle*" "subtitle present"
assert_contains "$SB/bio.md" "## Contents" "TOC present"
# all three headings appear in the TOC
for h in "Who" "The Life" "The Work"; do assert_contains "$SB/bio.md" "- $h" "TOC lists '$h'"; done
# all three bodies present
for b in ALPHA BETA GAMMA; do assert_contains "$SB/bio.md" "$b" "body '$b' present"; done

# ---- ORDER: prefix 00 < 10 < 20, so Who then Life then Work, regardless of filename lexical order ----
order="$(grep -oE 'ALPHA|BETA|GAMMA' "$SB/bio.md" | grep -vE 'Contents' | tr '\n' ' ')"
# bodies in doc order: ALPHA(00) GAMMA(10) BETA(20)
assert_eq "ALPHA GAMMA BETA " "$order" "sections concatenated in numeric-prefix order (00,10,20), not lexical"
# TOC order matches too
toc="$(sed -n '/## Contents/,/^---/p' "$SB/bio.md" | grep '^- ' | tr '\n' '|')"
assert_eq "- Who|- The Life|- The Work|" "$toc" "TOC ordered by prefix, not filename"

# ---- no-silent-loss: an empty or unindexable section must FAIL the build ----
: > "$SRC/30_broken.md"   # empty
red "empty section fails the build (no silent hole)" 1 "is EMPTY — refusing to build" "$BB" "$SRC" --out "$SB/b2.md"
assert_no_file "$SB/b2.md" "no partial bio written when a section was empty"
printf 'no heading here at all\n' > "$SRC/30_broken.md"   # non-empty, but no '# '
red "section with no top-level heading fails (can't index it)" 1 "has no top-level '# Heading' — can't index it" "$BB" "$SRC" --out "$SB/b3.md"
rm "$SRC/30_broken.md"

# ---- RED controls ----
red "missing --out must fail" 64 "--out FILE is required" "$BB" "$SRC"
red "missing sections dir must fail" 1 "no such sections dir" "$BB" "$SB/nope" --out "$SB/b4.md"
mkdir -p "$SB/empty"
red "a dir with no NN_ section files must fail" 1 "no NN_*.md section files" "$BB" "$SB/empty" --out "$SB/b5.md"
red "unknown flag must fail" 64 "unknown flag '--frobnicate'" "$BB" "$SRC" --out "$SB/b6.md" --frobnicate

finish
