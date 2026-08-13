# geo-evidence

Turn a macOS Photos library into **queryable, location-classified evidence.** Query by date, classify every geotagged photo and video to the *nearest known property*, preview with zero downloads, checkbox the keepers, and pull only those at full resolution with EXIF intact. Built for litigation media where "which house was this shot at?" and "did the GPS survive?" actually matter — and where two properties can sit 50 metres apart.

## Why it exists

Collecting evidence media by hand is: scroll Photos, guess which shots are the right property, export, hope the GPS didn't get stripped, repeat. geo-evidence makes it a query. On one real run it separated **60 property shots out of 259 unrelated ones** (gym selfies, family photos, the dog on the bed) across a 10-day window — without pulling a single home photo into the set, and without downloading originals until the exact ones were chosen.

## Install

```
./install.sh
```

Installs `exiftool` (Brewfile, which-first) and `osxphotos` (`uv tool install osxphotos --python 3.12` — it needs Python 3.10+; the pin stops uv grabbing an older one that crashes on import). `uv` is auto-installed if absent.

**TCC:** the Photos library is permission-protected. Run from an interactive terminal that holds Photos/Full-Disk-Access, or behind an FDA `.app` wrapper for automation — same rule as any Mail/Messages/Photos reader.

## Configure

First run writes a template to `~/.geo-evidence/config` and exits, telling you to edit it. Replace the placeholders with **your** properties — the tool refuses to run on the `Example`/`0,0` placeholders (silently classifying against 0,0 would find nothing and look like "no media" when it's really "not configured"):

```
# NAME<TAB>LATITUDE<TAB>LONGITUDE   (decimal degrees, real coordinates)
HouseA	35.409458	-80.646172
HouseB	35.40911	-80.64578
# a shot farther than MAX_M from EVERY property is classified "elsewhere" and skipped.
MAX_M=402
# a GPS-less shot inherits the nearest-in-time GPS'd shot's property if within this many minutes
MAX_TIME_GAP_MIN=30
```

**Why nearest-property, not a radius:** when two lots are ~50 m apart, a circle tight enough to exclude the neighbour also clips the far edge of your own lot. Nearest-centroid assigns each shot to whichever property it's *closest* to — the decision boundary is the perpendicular bisector between the houses — so the whole lot is captured while the neighbour is always excluded, *at any circle size*. `MAX_M` is just the outer cutoff for "not at any property."

## Commands

### `scan` — dry run, no downloads
```
geo-evidence scan --since 2026-08-04 --until 2026-08-14
```
Lists every geotagged item in the window with the property it's nearest to, distance, kind (photo/video), and a per-property count. Nothing is downloaded or exported. (`osxphotos --to-date` is **exclusive** — pass the day *after* your last day.)

### `pull` — export the matched originals
```
# everything classified to a property
geo-evidence pull --property HouseA --since D --until D --out DIR

# fast look: on-disk versions only, converted to browser-viewable JPEG, no iCloud downloads
geo-evidence pull --property HouseA --since D --until D --out DIR --preview

# exactly the items a gallery selection picked (see below)
geo-evidence pull --select geo-evidence-selection.txt --out DIR
```
- Full mode pulls the originals (downloading only the matched ones from iCloud, EXIF written) and writes a `MANIFEST.md` with per-file GPS + timestamp — flagging anything that lost GPS so you can re-export it.
- `--preview` downloads nothing; it exports the small local derivatives (even for iCloud-only items) so you can eyeball everything first. It also writes `.items.tsv` / `.uuidmap.tsv` so the gallery can show and select the full set.

### `gallery` — a date-grouped, checkbox pick-list
```
geo-evidence gallery <DIR> --out <DIR>/index.html
open <DIR>/index.html
```
Self-contained HTML: every item as a thumbnail (videos show a poster frame, items not downloaded show a selectable placeholder), grouped by capture date, each captioned with time + a GPS note. Per-day **select all / none**, a bottom bar with **Select all / Clear** and **⬇ Download selection** — which writes `geo-evidence-selection.txt` (the chosen UUIDs) for `pull --select`.

## The workflow

```
1. geo-evidence scan  --since 2026-08-04 --until 2026-08-14        # what's there, by property
2. geo-evidence pull  --property HouseA --since … --until … --out PV --preview
3. geo-evidence gallery PV --out PV/index.html && open PV/index.html
4.   ↳ tick the keepers → Download selection → geo-evidence-selection.txt
5. geo-evidence pull  --select geo-evidence-selection.txt --out EVIDENCE_DIR   # full originals, only your picks
```

Preview costs no disk; you review everything; only the chosen items get the real download.

## Handling GPS-stripped media

Photos re-exported as PNG (or otherwise) often lose their GPS. Those show as `NO-GPS` — but a second pass gives a GPS-less shot the property of its **nearest-in-time GPS'd neighbour** (within `MAX_TIME_GAP_MIN`), marked `~` / "time-inferred" so it's clearly location-*inferred*, not GPS-confirmed. This recovers storm-session shots that lost their location but sit inside a run of GPS'd shots.

## Seams / env overrides

`OSXPHOTOS_BIN`, `EXIFTOOL_BIN`, `SUBL_BIN`, and `GEO_EVIDENCE_HOME` override the respective binary / config dir — used by the test to run the real script against recorded payloads (no library, no network), and handy when a binary isn't on the default PATH.

## Test

```
../tests/run-all.sh          # runs test-geo-evidence.sh
```

Drives the real script against a recorded osxphotos JSON payload with the transports stubbed at their seams — so it needs neither osxphotos nor a Photos library. Proves the 52 m nearest-property separation, whole-lot capture, the elsewhere cutoff, NO-GPS flagging, time-proximity recovery, the checkbox/UUID wiring, `pull --select`, the placeholder gallery, and the config guard.

## Not this tool

- Reviewing a single video frame-by-frame → `frame-review` (contact sheet of stills).
- geo-evidence organizes *source* media by capture time + location; frame-review scans *within* one clip.
