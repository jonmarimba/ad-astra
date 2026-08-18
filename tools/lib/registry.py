#!/usr/bin/env python3
"""
registry.py — where every astra tool is installed, and whether those copies are current.

THE PROBLEM
-----------
Astra's model is copy-on-install: a tool is copied into a target repo, and
re-running the installer is the update path. Nothing ever ran the installer
again. On 2026-08-18 `generate_pdf_sidecars.sh` existed in five places at four
different vintages — canonical from 08-10, js-utils from 08-07, grandparentLegal
from 07-08, js-speedway from 07-03. Nobody had forked it; every copy was simply
an old snapshot. The legal repos were generating PDF text sidecars with a
month-old converter and no one could have known.

Jonathan: "I had you make these things so they could be used everywhere."

WHAT THIS IS
------------
A registry of tool -> installed locations, and a `status` that compares each
installed copy's hash against canonical. Feeds an astra post-commit hook that
pushes updates to stale copies automatically, so "installed once in June" stops
being a silent state.

THREE THINGS IT MUST GET RIGHT, each bought by a real bug today
---------------------------------------------------------------
1. FOLLOW SYMLINKS. js-speedway is a symlink into Dropbox, and `find` does not
   descend symlinked directories by default. An earlier scan silently omitted an
   entire repo — the exact class of miss this registry exists to end.

2. NEVER TOUCH A GLOBAL PATH. Every target must resolve inside the workspace
   root. A path under ~/.claude, ~/.agents, ~/.config or ~/Library is refused.
   Those global installs were removed today; nothing here may recreate one.

3. NEVER CLOBBER LOCAL EDITS. If an installed copy differs from BOTH the current
   canonical and the version it was installed from, someone changed it in place.
   That is a fork, not a stale copy, and updating it would destroy work. Report
   it and skip.
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ASTRA = Path(__file__).resolve().parent.parent.parent      # js-db-ad-astra
WORKSPACE = Path(os.environ.get("ASTRA_WORKSPACE", Path.home() / "svnCheckouts")).resolve()
REGISTRY = ASTRA / "tools" / "lib" / "installed.json"

FORBIDDEN_PREFIXES = [
    Path.home() / ".claude",
    Path.home() / ".agents",
    Path.home() / ".config",
    Path.home() / "Library",
]


def sha(p):
    try:
        return hashlib.sha256(Path(p).read_bytes()).hexdigest()[:16]
    except OSError:
        return None


def is_safe_target(p):
    """A target must live inside the workspace and never in a global config dir.

    TWO DIFFERENT PATHS ARE TESTED, deliberately:

      forbidden-global  -> the RESOLVED path, so a symlink pointing at
                           ~/.claude cannot smuggle a global install past us.
      workspace member  -> the path AS GIVEN, because several repos are
                           themselves symlinks out of the workspace. js-speedway
                           and js-hoa both live in Dropbox and are linked into
                           ~/svnCheckouts. Resolving before that test declared
                           fourteen perfectly legitimate installs "outside the
                           workspace" — the symlink lesson biting for the third
                           time today, in a third place.
    """
    given = Path(p)
    try:
        rp = given.resolve()
    except OSError:
        rp = given

    for bad in FORBIDDEN_PREFIXES:
        for candidate in (rp, given):
            try:
                candidate.relative_to(bad.resolve())
                return False, f"global location ({bad})"
            except (ValueError, OSError):
                pass

    # Membership uses the given path so symlinked repos count as inside.
    try:
        given.relative_to(WORKSPACE)
        return True, ""
    except ValueError:
        pass
    try:
        rp.relative_to(WORKSPACE)
        return True, ""
    except ValueError:
        return False, f"outside workspace {WORKSPACE}"


def load():
    try:
        return json.loads(REGISTRY.read_text())
    except FileNotFoundError:
        return {"tools": {}}
    except Exception as e:
        print(f"registry unreadable ({e}) — refusing to continue rather than "
              f"overwrite it", file=sys.stderr)
        raise


def save(reg):
    REGISTRY.parent.mkdir(parents=True, exist_ok=True)
    tmp = REGISTRY.with_suffix(".tmp")
    tmp.write_text(json.dumps(reg, indent=2, sort_keys=True) + "\n")
    os.replace(tmp, REGISTRY)


def discover(names):
    """Find installed copies of the given canonical files across the workspace.

    ONE filesystem walk, not one per file. The first version ran a separate
    `find` for every canonical file — forty full-workspace traversals for a job
    that runs on every astra commit, which took minutes. Walk once, bucket by
    basename, match afterwards.

    Uses `find -L` to FOLLOW SYMLINKS: js-speedway is a symlink into Dropbox and
    a plain find silently skips it, which is how an entire repo vanished from an
    earlier scan."""
    wanted = {Path(c).name: c for c in names}
    buckets = {c: [] for c in names}
    try:
        r = subprocess.run(
            ["find", "-L", str(WORKSPACE), "-type", "f",
             "(", "-name", "*.sh", "-o", "-name", "*.py", ")",
             "-not", "-path", "*/.git/*",
             "-not", "-path", "*/node_modules/*",
             "-not", "-path", "*/tmp/*",
             "-not", "-path", "*/Pods/*",
             "-not", "-path", "*/.venv/*",
             "-not", "-path", f"{ASTRA}/*"],
            capture_output=True, text=True, timeout=300)
        hits = r.stdout.splitlines()
    except Exception as e:
        print(f"  discover failed: {e}", file=sys.stderr)
        return buckets

    seen = set()
    for h in hits:
        h = h.strip()
        if not h:
            continue
        base = os.path.basename(h)
        canon = wanted.get(base)
        if not canon:
            continue
        # -L can surface one real file through several symlinked paths.
        try:
            rp = str(Path(h).resolve())
        except OSError:
            continue
        key = (canon, rp)
        if key in seen:
            continue
        seen.add(key)
        buckets[canon].append(h)
    return buckets


def cmd_scan(_):
    """Rebuild the registry from what is actually on disk."""
    reg = load()
    canon_files = []
    for d in (ASTRA / "tools").iterdir() if (ASTRA / "tools").is_dir() else []:
        if not d.is_dir():
            continue
        for f in d.iterdir():
            if f.is_file() and f.suffix in (".sh", ".py") and f.name not in (
                    "install.sh", "uninstall.sh", "setup.sh"):
                canon_files.append(str(f))

    found = discover(canon_files)
    tools = {}
    for canon, hits in found.items():
        if not hits:
            continue
        entry = {"canonical": str(Path(canon).relative_to(ASTRA)),
                 "canonical_sha": sha(canon), "installs": []}
        for h in hits:
            ok, why = is_safe_target(h)
            entry["installs"].append({
                "path": str(h),
                "sha": sha(h),
                "safe": ok,
                "unsafe_reason": why or None,
            })
        tools[Path(canon).name] = entry
    reg["tools"] = tools
    save(reg)
    n = sum(len(t["installs"]) for t in tools.values())
    print(f"registry: {len(tools)} tool(s), {n} installed cop(y|ies) -> {REGISTRY}")
    return 0


def cmd_status(_):
    reg = load()
    stale = current = unsafe = 0
    for name, t in sorted(reg.get("tools", {}).items()):
        csha = sha(ASTRA / t["canonical"])
        lines = []
        for i in t["installs"]:
            live = sha(i["path"])
            if live is None:
                lines.append(("GONE   ", i["path"])); continue
            if not i.get("safe", True):
                lines.append(("UNSAFE ", f"{i['path']}  ({i.get('unsafe_reason')})"))
                unsafe += 1
            elif live == csha:
                lines.append(("current", i["path"])); current += 1
            else:
                lines.append(("STALE  ", i["path"])); stale += 1
        if lines:
            print(f"── {name}  (canonical {csha})")
            for st, p in lines:
                print(f"     {st}  {p.replace(str(Path.home()) + '/', '~/')}")
    print(f"\n{current} current, {stale} STALE, {unsafe} unsafe")
    return 1 if (stale or unsafe) else 0


def cmd_sync(args):
    """Copy canonical over stale installs. Refuses to clobber local edits."""
    dry = "--dry-run" in args
    only = [a for a in args if not a.startswith("-")]
    reg = load()
    updated, skipped = 0, 0
    for name, t in sorted(reg.get("tools", {}).items()):
        if only and name not in only:
            continue
        canon = ASTRA / t["canonical"]
        csha = sha(canon)
        recorded = t.get("canonical_sha")
        for i in t["installs"]:
            live = sha(i["path"])
            if live is None or live == csha:
                continue
            ok, why = is_safe_target(i["path"])
            if not ok:
                print(f"  REFUSED  {i['path']}  ({why})")
                skipped += 1
                continue
            # A copy that matches NEITHER canonical nor its recorded install
            # point has been edited in place. Updating it destroys that work.
            if recorded and live != i.get("sha") and i.get("sha") != recorded:
                print(f"  LOCAL EDITS, skipping  {i['path']}")
                print(f"     differs from canonical AND from what was installed — "
                      f"this is a fork, resolve by hand")
                skipped += 1
                continue
            if dry:
                print(f"  would update  {i['path']}")
            else:
                shutil.copy2(canon, i["path"])
                i["sha"] = csha
                print(f"  updated  {i['path']}")
            updated += 1
        t["canonical_sha"] = csha
    if not dry:
        save(reg)
    print(f"\n{updated} updated, {skipped} skipped")
    return 0


def main():
    cmds = {"scan": cmd_scan, "status": cmd_status, "sync": cmd_sync}
    if len(sys.argv) < 2 or sys.argv[1] not in cmds:
        print(f"usage: registry.py {{{'|'.join(cmds)}}} [--dry-run] [tool...]")
        return 64
    return cmds[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    sys.exit(main())
