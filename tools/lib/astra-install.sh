#!/usr/bin/env bash
# astra-install.sh — the one place that decides WHERE an astra tool lands in a
# repo and what it records about itself. Every tool's install.sh sources this.
#
# WHY THIS EXISTS (Jonathan, 2026-08-18)
# --------------------------------------
# The first design copied tools into whatever directory each repo happened to
# use — 13_Scripts, scripts, tools, pdf, one repo's root — and then kept a
# central list in astra of where everything went. That list was built by
# matching FILENAMES across the workspace, which meant any repo's own
# rules.json or lib.sh was adopted as an astra install and overwritten by a
# post-commit hook. Ownership was inferred, and inference is a guess.
#
# Two corrections, both his:
#
#   "Why wouldn't you be writing someplace you know isn't going to be touched?
#    like .astra or whatever?"
#
# Everything lands in <repo>/.astra/<tool>/. Ownership stops being a guess and
# becomes a fact: if it is in there, it is ours, and nothing else is. The
# collision bug cannot occur rather than being guarded against.
#
#   "probably worth each .astra able to find where it was installed FROM and
#    check for updates?"
#
# So the direction of the relationship flips. Astra no longer pushes into
# repos it keeps a list of; each repo records where it was installed from and
# pulls. That removes the blast radius entirely — nothing reaches into another
# repo uninvited — and it survives the repo being cloned or moved, which a
# central list of absolute paths does not.
#
# Usage from a tool's install.sh:
#     . "$(dirname "$0")/../lib/astra-install.sh"
#     astra_target "$@"                 # parses --into, validates, sets $TARGET
#     astra_place check-prose check-prose.js rules.json
#
set -euo pipefail

ASTRA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

# Parse --into and refuse anywhere that is not a project checkout. Global
# installs were removed on 2026-08-18 and nothing here may recreate one.
astra_target() {
  TARGET=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --into) TARGET="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  [ -n "$TARGET" ] || { echo "usage: --into <repo>" >&2; exit 64; }
  [ -d "$TARGET" ] || { echo "no such directory: $TARGET" >&2; exit 66; }
  # -P resolves symlinks: js-hoa and js-speedway are symlinks into Dropbox.
  TARGET="$(cd "$TARGET" && pwd -P)"
  case "$TARGET" in
    "$HOME"|"$HOME/.claude"*|"$HOME/.agents"*|"$HOME/.config"*|"$HOME/Library"*)
      echo "REFUSING: $TARGET is a home/global location." >&2
      echo "  Astra tools install per-repo only." >&2
      exit 78 ;;
  esac
  export TARGET
}

# Copy a tool's files into <repo>/.astra/<tool>/ and record its origin.
astra_place() {
  local tool="$1"; shift
  local src="$ASTRA_ROOT/tools/$tool"
  local dest="$TARGET/.astra/$tool"
  mkdir -p "$dest"

  local f
  for f in "$@"; do
    [ -f "$src/$f" ] || { echo "missing source file: $src/$f" >&2; exit 65; }
    # Write beside and rename. A plain cp truncates the destination before it
    # copies, so an interrupted install leaves a zero-length tool where a
    # working one used to be.
    cp "$src/$f" "$dest/$f.astra-tmp"
    mv -f "$dest/$f.astra-tmp" "$dest/$f"
  done

  astra_record "$tool" "$@"
  astra_vendor_updater
  echo "installed $tool -> $dest"
}

# The manifest is what makes a repo self-sufficient: it knows what it has,
# where it came from, and what it looked like when it arrived. Local
# divergence is therefore detectable without asking astra anything.
astra_record() {
  local tool="$1"; shift
  local manifest="$TARGET/.astra/manifest.json"
  local dest="$TARGET/.astra/$tool"
  # The source's git-remote identity, recorded so a cloned repo on another machine can
  # verify a sibling-source guess is the SAME project before it feeds content in
  # (adversarial round: an impostor sibling sharing only the basename could inject
  # arbitrary content). Empty when the source has no remote — then no sibling fallback.
  local src_remote
  src_remote="$(git -C "$ASTRA_ROOT" remote get-url origin 2>/dev/null || true)"
  ASTRA_TOOL="$tool" ASTRA_SRC="$ASTRA_ROOT" ASTRA_SRC_REMOTE="$src_remote" ASTRA_DEST="$dest" \
  ASTRA_MANIFEST="$manifest" ASTRA_FILES="$*" python3 - <<'PY'
import hashlib, json, os, pathlib

manifest = pathlib.Path(os.environ["ASTRA_MANIFEST"])
tool = os.environ["ASTRA_TOOL"]
dest = pathlib.Path(os.environ["ASTRA_DEST"])
files = os.environ["ASTRA_FILES"].split()

def sha(p):
    return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()[:16]

try:
    data = json.loads(manifest.read_text())
except Exception:
    data = {}
data.setdefault("tools", {})
# The SOURCE is recorded per-install rather than once for the file, because a
# repo may legitimately be fed by more than one astra checkout over its life.
entry = {
    "source": os.environ["ASTRA_SRC"],
    "files": {f: sha(dest / f) for f in files},
}
if os.environ.get("ASTRA_SRC_REMOTE"):
    entry["source_remote"] = os.environ["ASTRA_SRC_REMOTE"]
data["tools"][tool] = entry
manifest.parent.mkdir(parents=True, exist_ok=True)
tmp = manifest.with_suffix(".json.tmp")
tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
os.replace(tmp, manifest)
PY
}

# Drop the puller into the repo so it can check itself without astra reaching in.
astra_vendor_updater() {
  local u="$TARGET/.astra/astra-update"
  cp "$ASTRA_ROOT/tools/lib/astra-update" "$u.astra-tmp"
  mv -f "$u.astra-tmp" "$u"
  chmod +x "$u"
}

# Remove a tool and forget it. Leaves .astra/ itself alone if other tools remain.
astra_remove() {
  local tool="$1"
  rm -rf "$TARGET/.astra/$tool"
  ASTRA_TOOL="$tool" ASTRA_MANIFEST="$TARGET/.astra/manifest.json" python3 - <<'PY'
import json, os, pathlib
m = pathlib.Path(os.environ["ASTRA_MANIFEST"])
try:
    data = json.loads(m.read_text())
except Exception:
    raise SystemExit(0)
data.get("tools", {}).pop(os.environ["ASTRA_TOOL"], None)
tmp = m.with_suffix(".json.tmp")
tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
os.replace(tmp, m)
PY
  echo "removed $tool from $TARGET/.astra"
}
