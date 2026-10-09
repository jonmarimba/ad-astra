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
         --hook=EVENT|MATCHER|script registers a Claude Code hook, and
         --settings=<entries file> writes config entries into agent config
         files (.claude/settings.json, .qwen/settings.json, .codex/config.toml);
         both are recorded so unplace removes exactly them.
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
    """Copy src:dest pairs and record them under one tool entry. Re-placing a
    tool replaces its entry, so a file a newer installer no longer ships stops
    being tracked (and is removed) rather than lingering forever."""
    hook_specs = [a[len("--hook="):] for a in pairs if a.startswith("--hook=")]
    settings_srcs = [a[len("--settings="):] for a in pairs if a.startswith("--settings=")]
    pairs = [a for a in pairs if not a.startswith(("--hook=", "--settings="))]
    repo = Path(repo)
    data = load(repo)
    old = data.get("tools", {}).get(tool, {})
    settings = [e for src in settings_srcs for e in load_settings_entries(src)]
    # Checked before any file is copied, so a conflict leaves the repo exactly as it was.
    edited_settings = check_settings(repo, tool, settings, old.get("settings"))
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
    apply_settings(repo, tool, data, settings, old.get("settings"), edited_settings)
    if settings:
        # An edited leaf keeps the value astra last wrote on record, as an edited file keeps its hash.
        entry["settings"] = [dict(e, value=edited_settings.get(_leaf_key(e), e["value"])) for e in settings]
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


# ---- agent config entries, per repo -----------------------------------------
# A tool may also own plain entries in an agent's repo config: a statusLine in
# .claude/settings.json, ui.statusLine in .qwen/settings.json, tui.status_line in
# .codex/config.toml. It ships them as a JSON file of
# {"entries": [{"file": <repo-relative config>, "path": [key, ...], "value": ...}]},
# passed as --settings=<astra-relative file>. Each path names one leaf, so a tool
# owns enabledPlugins["x@y"] without owning the rest of enabledPlugins. The
# manifest records each leaf with its value: uninstall removes a leaf only while
# it still holds that value, and install refuses to replace a value it did not
# write.
#
# A .json file is edited as JSON. A .toml file is edited as text, one line per
# leaf, because Python 3.9 has no TOML library: a TOML leaf is exactly
# [table].key, its value is a string, number, bool or flat list of those
# (written as JSON, which TOML reads the same), and a value on more than one
# line is never edited.

_MISSING = object()
_TOML_KEY = re.compile(r"^[A-Za-z0-9_-]+$")


def _label(e):
    return f"{'.'.join(e['path'])} in {e['file']}"


def load_settings_entries(src_rel):
    src = ASTRA / src_rel
    try:
        entries = json.loads(src.read_text())["entries"]
    except (OSError, ValueError, KeyError, TypeError) as e:
        die(f"{src} is not a settings-entries file ({e})")
    if not isinstance(entries, list) or not entries:
        die(f"{src}: 'entries' must be a non-empty list")
    for e in entries:
        if not isinstance(e, dict):
            die(f"{src}: each entry must be an object: {e}")
        path, file = e.get("path"), e.get("file")
        if (not isinstance(path, list) or not path or not all(isinstance(k, str) and k for k in path)
                or "value" not in e):
            die(f"{src}: each entry needs a non-empty 'path' list of keys and a 'value': {e}")
        if (not isinstance(file, str) or file.startswith("/") or ".." in Path(file).parts
                or Path(file).suffix not in (".json", ".toml")):
            die(f"{src}: 'file' must be a repo-relative .json or .toml path: {e}")
        if Path(file).suffix == ".toml":
            v = e["value"]
            scalar = (str, int, float, bool)
            if (len(path) != 2 or not all(_TOML_KEY.match(k) for k in path)
                    or not (isinstance(v, scalar) or (isinstance(v, list) and all(isinstance(x, scalar) for x in v)))):
                die(f"{src}: a TOML entry is [table].key with a scalar or flat-list value: {e}")
    return [{"file": e["file"], "path": e["path"], "value": e["value"]} for e in entries]


def _write_atomic(repo, rel, text):
    p = Path(repo) / rel
    if not text.strip():
        if p.exists():
            p.unlink()
            prune(Path(repo), p.parent)
        return
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_name(p.name + ".astra-tmp")
    tmp.write_text(text)
    os.replace(tmp, p)


# -- JSON

def _read_json(repo, rel):
    p = Path(repo) / rel
    if not p.exists():
        return {}
    try:
        cfg = json.loads(p.read_text())
    except Exception as e:
        die(f"{p} is unreadable ({e}); refusing to edit it")
    if not isinstance(cfg, dict):
        die(f"{p} does not hold a JSON object; refusing to edit it")
    return cfg


def _write_json(repo, rel, cfg):
    _write_atomic(repo, rel, json.dumps(cfg, indent=2) + "\n" if cfg else "")


def _json_get(cfg, path):
    node = cfg
    for key in path:
        if not isinstance(node, dict) or key not in node:
            return _MISSING
        node = node[key]
    return node


def _json_check_shape(repo, e):
    node = _read_json(repo, e["file"])
    for key in e["path"][:-1]:
        node = node.get(key, {})
        if not isinstance(node, dict):
            die(f"{Path(repo) / e['file']}: {key} is not an object; cannot set {'.'.join(e['path'])}")


def _json_set(cfg, path, value):
    node = cfg
    for key in path[:-1]:
        node = node.setdefault(key, {})
    node[path[-1]] = value


def _json_drop(cfg, path):
    """Delete one leaf and every object it leaves empty on the way up."""
    parents = [cfg]
    for key in path[:-1]:
        parents.append(parents[-1][key])
    del parents[-1][path[-1]]
    for depth in range(len(path) - 1, 0, -1):
        if parents[depth]:
            break
        del parents[depth - 1][path[depth - 1]]


# -- TOML (text, one line per leaf)

def _toml_lines(repo, rel):
    p = Path(repo) / rel
    return p.read_text().splitlines() if p.exists() else []


def _toml_table_span(lines, table):
    """(header index, end index) of [table], or None. End is the next header or EOF."""
    header = re.compile(r"^\s*\[\s*" + re.escape(table) + r"\s*\]\s*(#.*)?$")
    start = next((i for i, l in enumerate(lines) if header.match(l)), None)
    if start is None:
        return None
    end = next((i for i in range(start + 1, len(lines)) if re.match(r"^\s*\[", lines[i])), len(lines))
    return start, end


def _toml_find(repo, e):
    """(lines, span, line index, parsed value) for e's leaf. Refuses a layout this
    editor cannot change safely: the key set outside its [table], or a value it
    cannot read as one line."""
    p = Path(repo) / e["file"]
    lines = _toml_lines(repo, e["file"])
    table, key = e["path"]
    dotted = re.compile(r"^\s*" + re.escape(table) + r"\s*\.")
    if any(dotted.match(l) for l in lines):
        die(f"{p} sets {table}.* with dotted keys; edit {'.'.join(e['path'])} by hand")
    span = _toml_table_span(lines, table)
    if span is None:
        return lines, None, None, _MISSING
    key_line = re.compile(r"^\s*" + re.escape(key) + r"\s*=\s*(.*?)\s*$")
    for i in range(span[0] + 1, span[1]):
        m = key_line.match(lines[i])
        if m:
            try:
                return lines, span, i, json.loads(m.group(1))
            except ValueError:
                die(f"{p}: cannot read {'.'.join(e['path'])} = {m.group(1)}; edit it by hand")
    return lines, span, None, _MISSING


def _toml_set(repo, e):
    lines, span, at, _ = _toml_find(repo, e)
    table, key = e["path"]
    line = f"{key} = {json.dumps(e['value'])}"
    if at is not None:
        lines[at] = line
    elif span is not None:
        lines.insert(span[0] + 1, line)
    else:
        if lines and lines[-1].strip():
            lines.append("")
        lines += [f"[{table}]", line]
    _write_atomic(repo, e["file"], "\n".join(lines) + "\n")


def _toml_drop(repo, e):
    lines, span, at, _ = _toml_find(repo, e)
    del lines[at]
    end = span[1] - 1
    # A table this left with no keys goes too, with the blank line that set it off.
    if not any(l.strip() and not l.strip().startswith("#") for l in lines[span[0] + 1:end]):
        del lines[span[0]:end]
        if span[0] > 0 and span[0] <= len(lines) and not lines[span[0] - 1].strip():
            del lines[span[0] - 1]
    _write_atomic(repo, e["file"], "\n".join(lines) + "\n" if lines else "")


# -- one interface over both

def _is_toml(e):
    return e["file"].endswith(".toml")


def _get_leaf(repo, e):
    if _is_toml(e):
        return _toml_find(repo, e)[3]
    return _json_get(_read_json(repo, e["file"]), e["path"])


def _set_leaf(repo, e):
    if _is_toml(e):
        _toml_set(repo, e)
        return
    cfg = _read_json(repo, e["file"])
    _json_set(cfg, e["path"], e["value"])
    _write_json(repo, e["file"], cfg)


def _drop_leaf(repo, e):
    if _is_toml(e):
        _toml_drop(repo, e)
        return
    cfg = _read_json(repo, e["file"])
    _json_drop(cfg, e["path"])
    _write_json(repo, e["file"], cfg)


def _leaf_key(e):
    return json.dumps([e["file"], e["path"]])


def _claimed_by_others(data, tool, e):
    return any(_leaf_key(o) == _leaf_key(e)
               for other, entry in data.get("tools", {}).items() if other != tool
               for o in entry.get("settings", []))


def check_settings(repo, tool, entries, old_entries):
    """Decide, before anything is written, what happens to each leaf that is
    already set to another value. A leaf this tool wrote and the user changed
    since is kept, as an edited file is. Any other value belongs to the repo:
    replacing a repo's own statusLine without asking would silently change its
    behaviour, so that refuses. ASTRA_FORCE=1 overwrites both. A config this
    cannot edit safely refuses even then.
    Returns {leaf key: value astra last wrote} for the kept leaves."""
    edited = {}
    if not entries:
        return edited
    current = {}
    for e in entries:
        if not _is_toml(e):
            _json_check_shape(repo, e)
        current[_leaf_key(e)] = _get_leaf(repo, e)
    if os.environ.get("ASTRA_FORCE") == "1":
        return edited
    ours = {_leaf_key(e): e["value"] for e in (old_entries or [])}
    for e in entries:
        key = _leaf_key(e)
        now = current[key]
        if now is _MISSING or now == e["value"] or ours.get(key, _MISSING) == now:
            continue
        if key in ours:
            print(f"astra: kept your edited setting {_label(e)} "
                  f"(it differs from what astra wrote; ASTRA_FORCE=1 overwrites it)", file=sys.stderr)
            edited[key] = ours[key]
            continue
        die(f"{Path(repo) / e['file']} already sets {'.'.join(e['path'])} to {json.dumps(now)}; "
            f"{tool} would replace it. Remove that entry first, or run again with ASTRA_FORCE=1 "
            f"to overwrite it.")
    return edited


def remove_settings(repo, tool, data, entries, keep=()):
    """Remove the leaves this tool recorded, except ones the user changed since
    (kept, and reported) and ones another installed tool also records."""
    keep = {_leaf_key(e) for e in keep}
    for e in entries or []:
        if _leaf_key(e) in keep or _claimed_by_others(data, tool, e):
            continue
        now = _get_leaf(repo, e)
        if now is _MISSING:
            continue
        if now != e["value"] and os.environ.get("ASTRA_FORCE") != "1":
            print(f"astra: kept your edited setting {_label(e)} "
                  f"(it differs from what astra wrote; ASTRA_FORCE=1 removes it)", file=sys.stderr)
            continue
        _drop_leaf(repo, e)


def apply_settings(repo, tool, data, entries, old_entries, edited):
    """Write this tool's leaves, after removing any leaf an older install wrote
    that this one no longer ships. check_settings has already run; the leaves
    it reported as edited stay as the user left them."""
    remove_settings(repo, tool, data, old_entries, keep=entries)
    for e in entries:
        if _leaf_key(e) not in edited:
            _set_leaf(repo, e)


def unplace(repo, tool):
    repo = Path(repo)
    data = load(repo)
    entry = data.get("tools", {}).pop(tool, None)
    if entry is None:
        print(f"astra: {tool} is not recorded in {manifest_path(repo)}; nothing to remove")
        return
    remove_hooks(repo, tool, entry.get("hooks"))
    remove_settings(repo, tool, data, entry.get("settings"))
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
