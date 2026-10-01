#!/usr/bin/env bash
# test-frame-review.sh — real ffmpeg on generated test footage: frame counts match the
# requested rate, timestamps are right, the contact sheet references every frame.
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
FR="$HERE/../frame-review/frame-review"
need ffmpeg "brew install ffmpeg"

ffmpeg -nostdin -loglevel error -f lavfi -i "testsrc=duration=10:size=320x240:rate=10" "$SB/clip.mov"
assert_file "$SB/clip.mov" "test footage generated (10s)"

# ---- 1 fps over 10s -> 10 frames, timestamps 00:00..00:09, all in the sheet ----
assert_rc 0 "extraction succeeds" "$FR" "$SB/clip.mov" --fps 1 --outdir "$SB/out"
n="$(ls "$SB/out/clip"/frame_*.jpg 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "10" "$n" "10s at --fps 1 yields 10 frames"
assert_file "$SB/out/index.html" "contact sheet written"
assert_contains "$SB/out/index.html" "00:00" "first timestamp present"
assert_contains "$SB/out/index.html" "00:09" "last timestamp present"
refs="$(grep -o "clip/frame_[0-9]*\.jpg" "$SB/out/index.html" | wc -l | tr -d ' ')"
assert_eq "20" "$refs" "every frame referenced twice (link + img; grep -o counts occurrences, -c counted lines)"

# ---- multiple videos -> one section each ----
cp "$SB/clip.mov" "$SB/clip2.mov"
"$FR" "$SB/clip.mov" "$SB/clip2.mov" --fps 1 --outdir "$SB/out2" >/dev/null 2>&1
assert_contains "$SB/out2/index.html" "<h2>clip " "section for first video"
assert_contains "$SB/out2/index.html" "<h2>clip2 " "section for second video"

# ---- RED controls ----
red "missing video must fail" 1 "no such video" "$FR" "$SB/no-such.mov" --outdir "$SB/out3"
printf 'not a video' > "$SB/fake.mov"
red "non-video bytes must fail (zero frames is loud, not empty success)" 1 "ffmpeg failed" "$FR" "$SB/fake.mov" --outdir "$SB/out4"
red "unknown flag must fail" 64 "unknown flag" "$FR" "$SB/clip.mov" --fsp 1
red "--fps without a value must fail" 64 "--fps needs a value" "$FR" "$SB/clip.mov" --fps
red "no arguments must fail with usage" 64 "usage:" "$FR"

finish
