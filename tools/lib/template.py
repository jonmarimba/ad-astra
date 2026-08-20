#!/usr/bin/env python3
"""
template.py — install a NAMED GROUP of astra tools into a repo.

The middle layer Jonathan described on 2026-08-18: "templates for installing
groups of these tools that are fit for a particular kind of project, a middle
level where we can say the mhm project(s) has the swift and iOS stuff installed
via a template for that along with the writing tools. Whereas the legal repos
have the pdf to text stuff and the writing stuff."

    template.py list
    template.py show <name>
    template.py install   <name> --into <repo>
    template.py uninstall <name> --into <repo>
    template.py status --into <repo>

TWO PROPERTIES THAT ARE NOT NEGOTIABLE
--------------------------------------
NON-EXCLUSIVE. Installing a template ADDS its tools. It never removes anything
another template put there, and two templates may overlap freely — the legal and
Maharam sets both want the writing tools, and installing one after the other must
leave both intact. Uninstall removes only what that template names, so a shared
tool survives until the last template needing it is gone. Anything else would
make the second install silently break the first.

NEVER GLOBAL. Templates delegate to each tool's own install.sh --into <repo>,
and those already refuse a target under $HOME, ~/.claude, ~/.agents, ~/.config or
~/Library. The global installs that had accumulated were removed on 2026-08-18
and nothing here may recreate one.

Templates are DATA (templates.json), not code, so adding one is an edit rather
than a patch. Every tool a template names must have its own install.sh and
uninstall.sh — that is what made splitting the MCP bundle into seven small tools
the prerequisite for this layer.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

ASTRA = Path(__file__).resolve().parent.parent.parent
TOOLS = ASTRA / "tools"
TEMPLATES = TOOLS / "lib" / "templates.json"


def load():
    try:
        return json.loads(TEMPLATES.read_text())
    except FileNotFoundError:
        return {"templates": {}}


def tool_dir(name):
    d = TOOLS / name
    return d if d.is_dir() else None


def run_tool(name, verb, repo):
    """Delegate to the tool's own installer. Missing tools are LOUD.

    A template that silently skips a tool it names would report success while
    installing less than it claimed — the same shape as a test that passes
    against a broken implementation."""
    d = tool_dir(name)
    if d is None:
        return False, f"no such tool: tools/{name}"
    script = d / f"{verb}.sh"
    if not script.exists():
        return False, f"tools/{name} has no {verb}.sh (every template member needs one)"
    try:
        r = subprocess.run([str(script), "--into", str(repo)],
                           capture_output=True, text=True, timeout=300)
        if r.returncode != 0:
            tail = (r.stderr or r.stdout or "").strip().splitlines()
            return False, (tail[-1] if tail else f"exit {r.returncode}")
        return True, ""
    except Exception as e:
        return False, f"{e}"


def state_path(repo):
    """Template state lives in the SAME file as tool state.

    It used to sit in its own .astra-templates.json at the repo root, which made
    two files that had to agree about one repo and gave no reason they would.
    Everything a repo knows about its astra install now lives in
    .astra/manifest.json.
    """
    return Path(repo) / ".astra" / "manifest.json"


def _read_state(repo):
    p = state_path(repo)
    try:
        return json.loads(p.read_text())
    except FileNotFoundError:
        # Genuinely nothing installed. A legitimate empty answer.
        legacy = Path(repo) / ".astra-templates.json"
        if legacy.exists():
            try:
                old = json.loads(legacy.read_text()).get("installed", [])
                return {"templates": sorted(old)}
            except Exception:
                pass
        return {}
    except Exception as e:
        # NOT the same as "nothing installed", and the difference is the whole
        # non-exclusive property. installed_templates() used to swallow every
        # error into an empty list, so a corrupt or hand-edited state file made
        # uninstall believe no other template claimed anything — and it would
        # then remove tools a second, still-installed template needed. Refuse.
        print(f"{p} is unreadable ({e}). Refusing to act on template state we "
              f"cannot read, because reading it as empty would let uninstall "
              f"remove tools another template still needs.", file=sys.stderr)
        sys.exit(65)


def installed_templates(repo):
    return _read_state(repo).get("templates", [])


def record_template(repo, name, add=True):
    data = _read_state(repo)
    cur = list(data.get("templates", []))
    if add and name not in cur:
        cur.append(name)
    if not add and name in cur:
        cur.remove(name)
    data["templates"] = sorted(cur)
    p = state_path(repo)
    p.parent.mkdir(parents=True, exist_ok=True)
    # Write beside and rename: a half-written manifest is exactly the corrupt
    # state the refusal above exists to catch, and there is no reason to
    # manufacture it ourselves.
    tmp = p.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    os.replace(tmp, p)
    # Retire the old sidecar file once its contents are safely carried over.
    legacy = Path(repo) / ".astra-templates.json"
    if legacy.exists():
        legacy.unlink()


def tools_still_claimed(repo, excluding):
    """Tools that templates OTHER than `excluding` still need in this repo.

    This is the whole non-exclusive property. Without it, uninstalling
    kicker-dev removed mcp-xcode and mcp-mac-control-mcp — both still required
    by swift-ios, which was installed and working. Caught by the overlap test on
    2026-08-18, which is exactly what that test exists for."""
    t = load()["templates"]
    claimed = set()
    for name in installed_templates(repo):
        if name == excluding:
            continue
        claimed.update(t.get(name, {}).get("tools", []))
    return claimed


def cmd_list(_):
    t = load()["templates"]
    if not t:
        print("no templates defined")
        return 0
    for name, meta in sorted(t.items()):
        print(f"── {name}")
        print(f"     {meta.get('description','')}")
        print(f"     tools: {', '.join(meta.get('tools', []))}")
    return 0


def cmd_show(args):
    name = args[0] if args else ""
    meta = load()["templates"].get(name)
    if not meta:
        print(f"no such template: {name}")
        return 66
    print(json.dumps(meta, indent=2))
    return 0


def _target(args):
    if "--into" not in args:
        print("usage: template.py <cmd> <name> --into <repo>", file=sys.stderr)
        sys.exit(64)
    repo = Path(args[args.index("--into") + 1]).expanduser()
    if not repo.is_dir():
        print(f"no such directory: {repo}", file=sys.stderr)
        sys.exit(66)
    return repo


def _apply(verb, args):
    name = args[0] if args and not args[0].startswith("-") else ""
    meta = load()["templates"].get(name)
    if not meta:
        print(f"no such template: {name}", file=sys.stderr)
        return 66
    repo = _target(args)

    # UNINSTALL ONLY WHAT THE RECORD SAYS IS INSTALLED.
    #
    # tools_still_claimed() answers "what do the OTHER installed templates
    # need" by reading the record. If the record has been deleted, truncated or
    # hand-edited, that question comes back empty and uninstall happily removes
    # tools a second, still-installed template depends on. The corrupt case is
    # refused when the file is read; this catches the deleted one, and it does
    # so without guessing at what is installed by inspecting the filesystem —
    # which cannot work anyway, since MCP templates write .mcp.json rather than
    # a directory of their own.
    #
    # Being asked to remove something no record mentions is suspicious on its
    # own terms. Say so rather than acting on an empty list.
    if verb == "uninstall" and name not in installed_templates(repo):
        print(f"'{name}' is not recorded as installed in {repo}.", file=sys.stderr)
        print(f"  Refusing, because deciding what to remove means asking which "
              f"OTHER templates still need each tool, and that question cannot "
              f"be answered from a record that does not list this one.",
              file=sys.stderr)
        print(f"  Recorded: {', '.join(installed_templates(repo)) or '(none)'}",
              file=sys.stderr)
        return 65

    ok_n = fail_n = kept_n = 0
    print(f"{verb}ing template '{name}' -> {repo}")
    keep = tools_still_claimed(repo, name) if verb == "uninstall" else set()
    for t in meta.get("tools", []):
        if t in keep:
            others = [n for n in installed_templates(repo) if n != name
                      and t in load()["templates"].get(n, {}).get("tools", [])]
            print(f"  KEPT    {t} — still required by: {', '.join(others)}")
            kept_n += 1
            continue
        ok, why = run_tool(t, verb, repo)
        if ok:
            print(f"  {verb}ed  {t}")
            ok_n += 1
        else:
            print(f"  FAILED  {t}: {why}")
            fail_n += 1
    record_template(repo, name, add=(verb == "install"))
    extra = f", {kept_n} kept (shared with another template)" if kept_n else ""
    print(f"\n{ok_n} ok, {fail_n} failed{extra}")
    return 1 if fail_n else 0


def cmd_install(args):
    return _apply("install", args)


def cmd_uninstall(args):
    return _apply("uninstall", args)


def cmd_status(args):
    """Which templates are fully present in a repo?"""
    repo = _target(args)
    mcp = {}
    f = repo / ".mcp.json"
    if f.exists():
        try:
            mcp = json.loads(f.read_text()).get("mcpServers", {})
        except Exception:
            pass
    print(f"repo: {repo}")
    print(f"  MCP servers present: {', '.join(sorted(mcp)) or 'none'}")
    for name, meta in sorted(load()["templates"].items()):
        want = [t for t in meta.get("tools", []) if t.startswith("mcp-")]
        have = [t for t in want if t.replace("mcp-", "", 1) in mcp]
        if want:
            state = "complete" if len(have) == len(want) else (
                "partial" if have else "absent")
            print(f"  {name:<14} {state:<9} ({len(have)}/{len(want)} mcp tools)")
    return 0


def main():
    cmds = {"list": cmd_list, "show": cmd_show, "install": cmd_install,
            "uninstall": cmd_uninstall, "status": cmd_status}
    if len(sys.argv) < 2 or sys.argv[1] not in cmds:
        print(f"usage: template.py {{{'|'.join(cmds)}}} [name] [--into <repo>]")
        return 64
    return cmds[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    sys.exit(main())
