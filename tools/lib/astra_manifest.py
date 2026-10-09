#!/usr/bin/env python3
"""
astra_manifest.py — the ONE place that writes a repo's astra install state.

Every per-repo installer and uninstaller goes through here, so every tool is
installed the same way (Jonathan, 2026-10-04: "I'm getting kind of annoyed with
robots doing divergent stuff ... Why not be consistent?"). Before this file,
five installers recorded what they placed, two recorded it their own way, and
the rest copied files nobody tracked, so those copies never updated, could not
be cleanly uninstalled, and only one installer wired the updater hook.

    astra_manifest.py place   <repo> <tool> <src-rel>:<dest-rel> [...]
    astra_manifest.py unplace <repo> <tool>
    astra_manifest.py finish  <repo>
    astra_manifest.py hooks   <repo>
    astra_manifest.py status  <repo>

THE CONTRACT
------------
place    copies each file from the astra checkout into the repo, atomically,
         and records it in .astra/manifest.json with its src and dest. A file
         can land anywhere in the repo (a skill under .claude/skills/, doctrine
         under .doctrine/), so .astra/astra-update can keep it current.
unplace  deletes exactly the files the manifest records for that tool and the
         tool's entry. With the entry gone, no automatic update can bring the
         tool back: astra-update only ever touches what the manifest lists.
finish   runs after either. While any tool is installed it vendors the updater
         (itself a manifest entry), wires the post-commit and post-merge hooks,
         and keeps the per-machine update log out of git. When the last tool is
         gone it removes all of that again, leaving nothing astra-shaped behind.

Nothing here requires astra to be present for the repo to work. Placed files are
ordinary committed files, and the hook does nothing when the updater is absent
or cannot find an astra checkout on this machine.
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ASTRA = Path(__file__).resolve().parent.parent.parent
UPDATER_SRC = "tools/lib/astra-update"
UPDATER_DEST = ".astra/astra-update"

HOOK_BEGIN = "# >>> astra-update (managed by astra; edit outside this block) >>>"
HOOK_END = "# <<< astra-update <<<"
HOOK_BODY = """_astra_root="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -x "$_astra_root/.astra/astra-update" ]; then
  ( "$_astra_root/.astra/astra-update" --pull --log "$_astra_root/.astra/update.log" \\
      >/dev/null 2>&1 & ) >/dev/null 2>&1
fi"""
HOOK_NAMES = ("post-commit", "post-merge")

# The block every hook carried before 2026-10-04, written by pdf-sidecars and by
# hand. It is recognised and replaced, so a migrated hook never runs the
# updater twice.
# Both blocks hooks carried before 2026-10-04 (the plain redirect, and the
# --log variant from 2026-10-02) start with the same comment line and end at
# the first bare `fi`. They are recognised and replaced, so a migrated hook
# never runs the updater twice.
LEGACY_HOOK = re.compile(
    r"# astra: keep this repo's vendored tools current\.\n(?:.*\n)*?fi(?:\n|$)")

IGNORE_BEGIN = "# >>> astra (managed) >>>"
IGNORE_END = "# <<< astra <<<"
IGNORE_BODY = "# Per-machine log of automatic tool updates; not shared state.\n.astra/update.log"


def die(msg, code=65):
    print(f"astra: {msg}", file=sys.stderr)
    sys.exit(code)


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()[:16]


def manifest_path(repo):
    return Path(repo) / ".astra" / "manifest.json"


def load(repo):
    p = manifest_path(repo)
    try:
        return json.loads(p.read_text())
    except FileNotFoundError:
        return {"tools": {}}
    except Exception as e:
        # Reading a corrupt manifest as empty would unregister every tool in the
        # repo and let the next write erase the record. Refuse instead.
        die(f"{p} is unreadable ({e}); refusing to act on it")


def save(repo, data):
    p = manifest_path(repo)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    os.replace(tmp, p)


def source_remote():
    try:
        r = subprocess.run(["git", "-C", str(ASTRA), "remote", "get-url", "origin"],
                           capture_output=True, text=True, timeout=10)
        return r.stdout.strip() if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def recorded_source(repo):
    """Where to write 'source' in the manifest. The manifest is committed, so an absolute
    path puts one machine's home directory into every repo and breaks on every other
    machine. When astra is this repo itself or sits beside it (the normal workspace layout)
    the path is recorded RELATIVE to the repo ('.' or '../<name>'), which is the same on
    every machine that keeps the two together. Anywhere else there is no portable form, so
    it stays absolute; ASTRA_SOURCE covers that case at update time."""
    repo_real = Path(repo).resolve()
    astra_real = ASTRA.resolve()
    if astra_real == repo_real:
        return "."
    if astra_real.parent == repo_real.parent:
        return "../" + astra_real.name
    return str(ASTRA)


def copy_atomic(src, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_name(dest.name + ".astra-tmp")
    shutil.copy2(src, tmp)          # copy2 keeps the executable bit
    os.replace(tmp, dest)


def place(repo, tool, pairs):
    hook_specs = [a[len("--hook="):] for a in pairs if a.startswith("--hook=")]
    pairs = [a for a in pairs if not a.startswith("--hook=")]
    """Copy src:dest pairs and record them under one tool entry. Re-placing a
    tool replaces its entry, so a file a newer installer no longer ships stops
    being tracked (and is removed) rather than lingering forever."""
    repo = Path(repo)
    data = load(repo)
    old = data.get("tools", {}).get(tool, {})
    files, paths = {}, {}
    for pair in pairs:
        if ":" not in pair:
            die(f"bad pair '{pair}' (want src-rel:dest-rel)", 64)
        src_rel, dest_rel = pair.split(":", 1)
        src = ASTRA / src_rel
        if not src.is_file():
            die(f"missing source file: {src}")
        if dest_rel.startswith("/") or ".." in Path(dest_rel).parts:
            die(f"dest must be repo-relative: {dest_rel}", 64)
        dest = repo / dest_rel
        # A symlink at the destination is a foreign install (npx skills add
        # left one for the humanizer). Replace it with a real file, never write
        # through it into whatever it points at.
        if dest.is_symlink():
            dest.unlink()
        key = dest_rel
        paths[key] = {"src": src_rel, "dest": dest_rel}
        # A file the user edited after astra placed it is theirs. Re-running an install is the
        # documented update path, so it must not silently throw the edit away: keep the file, keep
        # the recorded hash (astra-update then keeps reporting LOCAL EDITS), and say so.
        # ASTRA_FORCE=1 overwrites. A file with no record, or one the user has not touched, is
        # copied as before.
        was = recorded_hashes(tool, old).get(dest_rel)
        if (was and dest.is_file() and sha(dest) != was and sha(dest) != sha(src)
                and os.environ.get("ASTRA_FORCE") != "1"):
            print(f"astra: kept your edited {dest_rel} (it differs from what astra placed; "
                  f"ASTRA_FORCE=1 overwrites it)", file=sys.stderr)
            files[key] = was
            continue
        copy_atomic(src, dest)
        files[key] = sha(dest)
    for stale in set(old_dests(tool, old)) - {p["dest"] for p in paths.values()}:
        remove_file(repo, stale)
    entry = {"source": recorded_source(repo), "files": files, "paths": paths}
    if hook_specs:
        entry["hooks"] = hook_specs
    add_hooks(repo, tool, hook_specs, old.get("hooks"))
    remote = source_remote()
    if remote:
        entry["source_remote"] = remote
    data.setdefault("tools", {})[tool] = entry
    save(repo, data)


def recorded_hashes(tool, entry):
    """dest path -> the hash astra recorded when it placed that file."""
    paths = entry.get("paths", {})
    return {(paths.get(f, {}).get("dest") or f".astra/{tool}/{f}"): h
            for f, h in entry.get("files", {}).items()}


def old_dests(tool, entry):
    """Every dest an existing entry tracks, in either manifest shape: explicit
    paths, or the original <repo>/.astra/<tool>/<file> layout."""
    paths = entry.get("paths", {})
    return [paths.get(f, {}).get("dest") or f".astra/{tool}/{f}"
            for f in entry.get("files", {})]


def remove_file(repo, dest_rel):
    p = Path(repo) / dest_rel
    if p.is_symlink() or p.exists():
        p.unlink()
    prune(Path(repo), p.parent)


def prune(repo, d):
    """Remove directories this left empty, up to but never including the repo."""
    repo = Path(os.path.realpath(repo))
    d = Path(os.path.realpath(d))
    while d != repo and repo in d.parents:
        try:
            d.rmdir()
        except OSError:
            break
        d = d.parent


# ---- Claude Code hooks, per repo -------------------------------------------
# A tool may register hooks in <repo>/.claude/settings.json, which Claude Code
# reads for sessions in that repo only, so a hook is never machine-wide
# (2026-10-04: "I'd love to have hooks be non-global"). Each command runs a
# script the tool placed, through $CLAUDE_PROJECT_DIR, so the entry is
# portable. Ownership is the command path: everything under .astra/<tool>/
# belongs to <tool>, which is how uninstall removes exactly its own entries.

def _settings_path(repo):
    return Path(repo) / ".claude" / "settings.json"


def _hook_command(rel):
    return f'"$CLAUDE_PROJECT_DIR"/{rel}'


def _owned(cmd, tool, specs):
    """A hook belongs to a tool when its command is one the tool recorded.
    Entries recorded before 2026-10-04 carry no specs; for those, fall back to
    the tool's own .astra/<tool>/ directory in the command path."""
    if specs:
        return cmd in {_hook_command(spec.split("|", 2)[2]) for spec in specs}
    return f"/.astra/{tool}/" in cmd


def remove_hooks(repo, tool, specs=None, settings_name="settings.json", owned=None):
    sp = Path(repo) / ".claude" / settings_name
    if not sp.exists():
        return
    try:
        cfg = json.loads(sp.read_text())
    except Exception as e:
        die(f"{sp} is unreadable ({e}); refusing to edit its hooks")
    test = owned or (lambda cmd: _owned(cmd, tool, specs))
    hooks = cfg.get("hooks", {})
    for event in list(hooks):
        groups = []
        for g in hooks[event]:
            g = dict(g)
            g["hooks"] = [h for h in g.get("hooks", []) if not test(h.get("command", ""))]
            if g["hooks"]:
                groups.append(g)
        if groups:
            hooks[event] = groups
        else:
            del hooks[event]
    if hooks:
        cfg["hooks"] = hooks
    else:
        cfg.pop("hooks", None)
    if cfg:
        sp.write_text(json.dumps(cfg, indent=2) + "\n")
    else:
        sp.unlink()
        prune(Path(repo), sp.parent)


def add_hooks(repo, tool, specs, old_specs=None):
    """specs: EVENT|MATCHER|repo-relative-script. Re-adding replaces the
    tool's previous entries, so a reinstall never duplicates a hook."""
    remove_hooks(repo, tool, old_specs)
    if not specs:
        return
    sp = _settings_path(repo)
    cfg = json.loads(sp.read_text()) if sp.exists() else {}
    hooks = cfg.setdefault("hooks", {})
    for spec in specs:
        event, matcher, rel = spec.split("|", 2)
        hooks.setdefault(event, []).append({
            "matcher": matcher,
            "hooks": [{"type": "command", "command": _hook_command(rel)}]})
    sp.parent.mkdir(parents=True, exist_ok=True)
    sp.write_text(json.dumps(cfg, indent=2) + "\n")


def unplace(repo, tool):
    repo = Path(repo)
    data = load(repo)
    entry = data.get("tools", {}).pop(tool, None)
    if entry is None:
        print(f"astra: {tool} is not recorded in {manifest_path(repo)}; nothing to remove")
        return
    remove_hooks(repo, tool, entry.get("hooks"))
    was = recorded_hashes(tool, entry)
    for dest in old_dests(tool, entry):
        p = repo / dest
        if (was.get(dest) and p.is_file() and not p.is_symlink() and sha(p) != was[dest]
                and os.environ.get("ASTRA_FORCE") != "1"):
            print(f"astra: kept your edited {dest} (it differs from what astra placed; "
                  f"delete it yourself, or run again with ASTRA_FORCE=1)", file=sys.stderr)
            continue
        remove_file(repo, dest)
    save(repo, data)
    print(f"astra: removed {tool}")


def hooks_dir(repo):
    r = subprocess.run(["git", "-C", str(repo), "rev-parse", "--git-path", "hooks"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None
    p = Path(r.stdout.strip())
    return p if p.is_absolute() else Path(repo) / p


def strip_block(text, begin, end):
    if begin not in text:
        return text
    pat = re.compile(r"\n*" + re.escape(begin) + r".*?" + re.escape(end) + r"\n?", re.S)
    out = pat.sub("\n", text, count=1)
    # Leave the file as it was before the block went in: no stray blank lines.
    return out.rstrip("\n") + "\n" if out.strip() else ""


def wire_hooks(repo, on=True):
    d = hooks_dir(repo)
    if d is None:
        print(f"astra: {repo} is not a git checkout; no hooks wired")
        return
    d.mkdir(parents=True, exist_ok=True)
    block = f"{HOOK_BEGIN}\n{HOOK_BODY}\n{HOOK_END}\n"
    for name in HOOK_NAMES:
        h = d / name
        text = h.read_text() if h.exists() else ""
        if text and not re.match(r"#!.*\b(sh|bash|zsh)\b", text):
            die(f"{h} is not a shell script, so astra will not edit it; have it run .astra/astra-update --pull")
        text = LEGACY_HOOK.sub("", text)
        text = strip_block(text, HOOK_BEGIN, HOOK_END)
        if on:
            if not text.strip():
                text = "#!/bin/sh\n"
            text = text.rstrip("\n") + "\n\n" + block
        else:
            if text.strip() in ("", "#!/bin/sh", "#!/bin/bash", "#!/usr/bin/env bash"):
                if h.exists():
                    h.unlink()
                continue
        h.write_text(re.sub(r"\n{3,}", "\n\n", text))
        h.chmod(0o755)


def ignore_log(repo, on=True):
    gi = Path(repo) / ".gitignore"
    text = gi.read_text() if gi.exists() else ""
    text = strip_block(text, IGNORE_BEGIN, IGNORE_END)
    already = re.search(r"^/?\.astra/update\.log\s*$", text, re.M)
    if on and already:
        on = False      # the repo ignores it already; do not add a second rule
        if not text.strip():
            return
    if on:
        text = text.rstrip("\n") + ("\n\n" if text.strip() else "") + \
            f"{IGNORE_BEGIN}\n{IGNORE_BODY}\n{IGNORE_END}\n"
    elif not text.strip():
        if gi.exists():
            gi.unlink()
        return
    gi.write_text(re.sub(r"\n{3,}", "\n\n", text))
    # A log git already tracks stays tracked despite the ignore rule. Untrack it
    # so it stops showing up in every commit; the file itself stays on disk.
    subprocess.run(["git", "-C", str(repo), "rm", "--cached", "-q", "--ignore-unmatch",
                    ".astra/update.log"], capture_output=True)


LEGACY_SAFETY = ("no-silent-truncation.sh", "no-killing-other-claudes.sh", "shell_word_literal.py",
                 "no-killing-other-claudes.reap-hint")


def migrate_legacy_safety_hooks(repo, watchlist_dest, scripts):
    """The pre-2026-10-04 per-repo install copied the safety-hook scripts into
    .claude/hooks/ and wired them in .claude/settings.local.json. Remove exactly
    those entries and files, and carry the repo's watchlist to its new home so
    an edited list is not lost."""
    repo = Path(repo)
    companions = {"no-killing-other-claudes.sh": ("shell_word_literal.py", "no-killing-other-claudes.reap-hint")}
    legacy = {f"$CLAUDE_PROJECT_DIR/.claude/hooks/{n}" for n in scripts}
    remove_hooks(repo, "legacy-safety", settings_name="settings.local.json",
                 owned=lambda cmd: cmd in legacy)
    hooks_dir = repo / ".claude" / "hooks"
    wl = hooks_dir / "no-silent-truncation.watchlist"
    if wl.exists() and watchlist_dest and "no-silent-truncation.sh" in scripts:
        dest = repo / watchlist_dest
        dest.parent.mkdir(parents=True, exist_ok=True)
        if not dest.exists():
            os.replace(wl, dest)
        else:
            wl.unlink()
    for n in scripts:
        for name in (n,) + companions.get(n, ()):
            f = hooks_dir / name
            if f.exists():
                f.unlink()
    prune(repo, hooks_dir)


def finish(repo):
    repo = Path(repo)
    data = load(repo)
    tools = {t for t in data.get("tools", {}) if t != "astra-update"}
    if tools:
        place(repo, "astra-update", [f"{UPDATER_SRC}:{UPDATER_DEST}"])
        wire_hooks(repo, True)
        ignore_log(repo, True)
        return
    # The last tool is gone: take every trace of astra with it.
    if "astra-update" in data.get("tools", {}):
        unplace(repo, "astra-update")
        data = load(repo)
    wire_hooks(repo, False)
    ignore_log(repo, False)
    log = repo / ".astra" / "update.log"
    if log.exists():
        log.unlink()
    if not data.get("tools") and not data.get("templates"):
        mp = manifest_path(repo)
        if mp.exists():
            mp.unlink()
        prune(repo, repo / ".astra")
    else:
        save(repo, data)


def status(repo):
    data = load(repo)
    print(f"repo: {Path(repo).resolve()}")
    print(f"  requested: {', '.join(data.get('templates', [])) or '(none recorded)'}")
    for tool, entry in sorted(data.get("tools", {}).items()):
        print(f"  {tool}: {len(entry.get('files', {}))} file(s)")
    d = hooks_dir(repo)
    for name in HOOK_NAMES:
        h = d / name if d else None
        wired = bool(h and h.exists() and HOOK_BEGIN in h.read_text())
        print(f"  hook {name}: {'wired' if wired else 'NOT wired'}")


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 64
    cmd, repo = argv[1], argv[2]
    if not Path(repo).is_dir():
        die(f"no such directory: {repo}", 66)
    if cmd == "place" and len(argv) >= 5:
        place(repo, argv[3], argv[4:])
    elif cmd == "unplace" and len(argv) == 4:
        unplace(repo, argv[3])
    elif cmd == "finish":
        finish(repo)
    elif cmd == "migrate-safety-hooks":
        migrate_legacy_safety_hooks(repo, argv[3], argv[4:])
    elif cmd == "hooks":
        wire_hooks(repo, True)
    elif cmd == "status":
        status(repo)
    else:
        print(__doc__)
        return 64
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
