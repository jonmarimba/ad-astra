# frame-review

Turn video(s) into a timestamped HTML contact sheet so you can scan an hour of footage in a minute and jump to the moments that matter. Built for storm-drainage clips reviewed against a punchlist, but it's generic — any video, any reason.

Each frame is extracted at a chosen rate, laid out in a grid, captioned with its time offset (`MM:SS`), and linked to the full-size still. One section per video.

## Install

```
./install.sh
```

Which-first: uses the `ffmpeg` you already have; installs it via the Brewfile only if it's missing. `ffmpeg` is the sole dependency.

## Use

```
frame-review <video> [more videos...] [--fps 0.5] [--outdir DIR]
```

- `--fps` — frames per second to extract. Default `0.5` = **one frame every 2 seconds**: dense enough to catch water-flow changes, sparse enough to eyeball. Use `1` for finer, `0.2` (one per 5s) for a longer clip.
- `--outdir DIR` — where to write output. Default `frame-review-out/`.

### Examples

```
# one contact sheet from a single clip
frame-review IMG_1836.MOV --outdir storm_review

# several clips at once, one frame per second, into a named folder
frame-review rainfall_20260808/videos/*.MOV --fps 1 --outdir 0808_review

# open the result
open 0808_review/index.html
```

## Output

```
DIR/
  index.html                  # the contact sheet — open this
  <video-stem>/frame_0001.jpg # extracted frames, one folder per video
  <video-stem>/frame_0002.jpg
  ...
```

Open `index.html` in any browser. Each thumbnail shows its offset into the clip and links to the full-size frame; videos are grouped under their own headings.

## Notes

- **Timestamps are clip-relative** (`00:00`, `00:02`, …), i.e. seconds into that video — not wall-clock capture time. For capture-time + GPS organization of the *source* media, that's `geo-evidence`, not this.
- **Fails loudly, not silently:** a missing video, a non-video file, a bad `--fps`, or an unknown flag errors out; if ffmpeg extracts zero frames it says so rather than writing an empty sheet.
- **`FFMPEG_BIN`** overrides the ffmpeg binary (used by the test to run against a stub; also handy if ffmpeg isn't on the default PATH).
- Portable / agent-agnostic: no hardcoded paths or identity; drive it entirely by arguments.

## Test

```
../tests/run-all.sh          # runs test-frame-review.sh among the suite
```

Real ffmpeg on generated test footage: asserts the frame count matches the requested rate, the timestamps are right, every frame is referenced in the sheet, and the RED cases (missing video, non-video bytes, bad flags) all fail as they should.
