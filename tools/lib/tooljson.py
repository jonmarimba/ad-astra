#!/usr/bin/env python3
"""tooljson.py — the reader for tools/*/tool.json (Phase 6.1 of the tool-template work).

Seven descriptors existed for weeks with NOTHING reading them (INVENTORY.md, 2026-08-31:
"seven carry a tool.json descriptor... and nothing reads those files"). This converts
them into a validated registry: every descriptor either parses into a known shape or
fails naming what is wrong. The roadmap's rule for the schema: build on what exists, do
not invent a third format.

THE SHAPE
---------
Required: name (must equal the tool's directory name), description, provides,
dependencies (a list). provides == "mcp-server" additionally requires server (the MCP
server key the tool configures). Optional: backed_by (an astra-relative path that must
exist).

DEPENDENCIES ARE DECLARED BY ECOSYSTEM — "eco:coordinate" strings:
    brew:jq           npm:ios-simulator-mcp      uv:drews-xcode-mcp
    human:Full Disk Access for Mail
The human class is real and first-class on this machine: xcode-mcp-front needs an
Automator .app, a launchd plist, and TCC grants a person clicks. A brew-only model
under-declares more than half of what is here, silently (ROADMAP phase 6). Bare legacy
tokens (claude, uvx, xcrun, node_npx, mac_control_mcp) are ACCEPTED and reported on
stderr, so existing descriptors keep validating while getting nudged toward migration;
an unknown "eco:" prefix is an error, because a typo'd ecosystem is a dependency that
never installs.

THIRD-PARTY ADOPTION (optional trio): source (coordinate), version (pin), digest
(artifact hash). source requires version — a coordinate without a pin is an
unrepeatable install; digest is recommended and validated as a string when present.

CLI:
    tooljson.py list                 validate every tools/*/tool.json; table to stdout
    tooljson.py validate <file|dir>  one descriptor; rc 65 with a named reason
    tooljson.py deps <tool-name>     dependencies grouped by ecosystem
Runs on python3 >= 3.9 (the system interpreter runs the tests and any scheduled job).
"""
import json
import os
import sys
from pathlib import Path

ASTRA = Path(__file__).resolve().parent.parent.parent
TOOLS = ASTRA / "tools"

KNOWN_ECOSYSTEMS = ("brew", "npm", "uv", "human")
# Bare tokens the seven pre-existing descriptors use. Accepted, reported, not grown:
# a NEW bare token is an error, so the legacy set only ever shrinks.
LEGACY_TOKENS = frozenset({"claude", "uvx", "xcrun", "node_npx", "mac_control_mcp"})
REQUIRED = ("name", "description", "provides", "dependencies")
KNOWN_FIELDS = frozenset({"name", "server", "description", "dependencies", "provides",
                          "backed_by", "source", "version", "digest"})


class DescriptorError(ValueError):
    pass


def parse(path, expect_dirname=None):
    """-> dict descriptor. Raises DescriptorError with a named reason. Legacy
    dependency tokens are collected under key '_legacy' and reported by the caller."""
    path = Path(path)
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as e:
        raise DescriptorError("cannot read %s (%s)" % (path, e))
    try:
        d = json.loads(raw)
    except ValueError as e:
        raise DescriptorError("%s is not valid JSON (%s)" % (path, e))
    if not isinstance(d, dict):
        raise DescriptorError("%s: a descriptor is an object" % path)

    for field in d:
        if field not in KNOWN_FIELDS:
            raise DescriptorError("%s: unknown field '%s'" % (path, field))
    for field in REQUIRED:
        if field not in d:
            raise DescriptorError("%s has no '%s'" % (path, field))

    name = d["name"]
    if not isinstance(name, str) or not name:
        raise DescriptorError("%s has no 'name' (non-empty string required)" % path)
    dirname = expect_dirname or path.parent.name
    if name != dirname:
        raise DescriptorError(
            "%s: name '%s' does not match its directory '%s' — the directory is the "
            "identity everything else keys on" % (path, name, dirname))

    if not isinstance(d["description"], str) or not d["description"].strip():
        raise DescriptorError("%s has no 'description' text" % path)

    provides = d["provides"]
    if not isinstance(provides, str) or not provides:
        raise DescriptorError("%s has no 'provides'" % path)
    if provides == "mcp-server" and not d.get("server"):
        raise DescriptorError(
            "%s provides 'mcp-server' but names no 'server' — the MCP server key is "
            "what installers configure" % path)

    deps = d["dependencies"]
    if not isinstance(deps, list) or not all(isinstance(x, str) for x in deps):
        raise DescriptorError("%s: 'dependencies' must be a list of strings" % path)
    grouped = {eco: [] for eco in KNOWN_ECOSYSTEMS}
    legacy = []
    seen = set()
    for dep in deps:
        if dep in seen:
            # A duplicate is a mistake, not a doubled install — reject it so a typo
            # that repeats a dep is caught rather than emitted twice (adversarial round).
            raise DescriptorError("%s: duplicate dependency '%s'" % (path, dep))
        seen.add(dep)
        eco, sep, coord = dep.partition(":")
        if sep:
            if eco not in KNOWN_ECOSYSTEMS:
                raise DescriptorError(
                    "%s: unknown dependency ecosystem '%s' in '%s' (known: %s)"
                    % (path, eco, dep, ", ".join(KNOWN_ECOSYSTEMS)))
            # strip() then emptiness: a whitespace-only coordinate ('brew:   ') cleared
            # the bare `if not coord` gate and validated as a dep that never installs
            # (adversarial round). Store the stripped coordinate so it is used verbatim.
            coord = coord.strip()
            if not coord:
                raise DescriptorError("%s: dependency '%s' names no coordinate" % (path, dep))
            grouped[eco].append(coord)
        elif dep in LEGACY_TOKENS:
            legacy.append(dep)
        else:
            raise DescriptorError(
                "%s: bare dependency '%s' is neither ecosystem-qualified (eco:coordinate) "
                "nor a known legacy token (%s)" % (path, dep, ", ".join(sorted(LEGACY_TOKENS))))

    backed_by = d.get("backed_by")
    if backed_by is not None:
        if not isinstance(backed_by, str):
            raise DescriptorError("%s: 'backed_by' must be a string path" % path)
        if not (ASTRA / backed_by).exists():
            raise DescriptorError("%s: backed_by '%s' does not exist under %s"
                                  % (path, backed_by, ASTRA))

    for field in ("source", "version", "digest"):
        if field in d and not isinstance(d[field], str):
            raise DescriptorError("%s: '%s' must be a string" % (path, field))
    if d.get("source") and not d.get("version"):
        raise DescriptorError(
            "%s: 'source' requires 'version' — a coordinate without a pin is an "
            "unrepeatable install" % path)

    d["_grouped"] = grouped
    d["_legacy"] = legacy
    return d


def load_all():
    """-> (descriptors by name, error list). Reads every tools/*/tool.json."""
    found, errors = {}, []
    for tdir in sorted(TOOLS.iterdir()):
        tj = tdir / "tool.json"
        if not tdir.is_dir() or not tj.is_file():
            continue
        try:
            found[tdir.name] = parse(tj)
        except DescriptorError as e:
            errors.append(str(e))
    return found, errors


def _report_legacy(name, legacy):
    if legacy:
        print("tooljson: %s uses legacy dependency token(s) %s — migrate to "
              "eco:coordinate form" % (name, ", ".join(sorted(legacy))), file=sys.stderr)


def cmd_list(_):
    found, errors = load_all()
    for e in errors:
        print("tooljson: %s" % e, file=sys.stderr)
    for name, d in sorted(found.items()):
        eco = "; ".join("%s:%d" % (k, len(v)) for k, v in d["_grouped"].items() if v)
        print("%-24s %-11s %s%s" % (name, d["provides"],
                                    d["description"][:60],
                                    ("  [" + eco + "]") if eco else ""))
        _report_legacy(name, d["_legacy"])
    print("%d descriptor(s), %d invalid" % (len(found), len(errors)))
    return 65 if errors else 0


def cmd_validate(args):
    if not args:
        print("usage: tooljson.py validate <file|dir>", file=sys.stderr)
        return 64
    p = Path(args[0])
    if p.is_dir():
        p = p / "tool.json"
    try:
        d = parse(p)
    except DescriptorError as e:
        print("tooljson: %s" % e, file=sys.stderr)
        return 65
    _report_legacy(d["name"], d["_legacy"])
    print("%s: valid (%s)" % (d["name"], d["provides"]))
    for eco in KNOWN_ECOSYSTEMS:
        for coord in d["_grouped"][eco]:
            print("  %s: %s" % (eco, coord))
    for tok in d["_legacy"]:
        print("  legacy: %s" % tok)
    return 0


def cmd_deps(args):
    if not args:
        print("usage: tooljson.py deps <tool-name>", file=sys.stderr)
        return 64
    found, errors = load_all()
    d = found.get(args[0])
    if d is None:
        print("tooljson: no valid descriptor for '%s' (have: %s)"
              % (args[0], ", ".join(sorted(found))), file=sys.stderr)
        return 66
    for eco in KNOWN_ECOSYSTEMS:
        for coord in d["_grouped"][eco]:
            print("%s: %s" % (eco, coord))
    for tok in d["_legacy"]:
        print("legacy: %s" % tok)
    return 0


def main():
    cmds = {"list": cmd_list, "validate": cmd_validate, "deps": cmd_deps}
    if len(sys.argv) < 2 or sys.argv[1] not in cmds:
        print("usage: tooljson.py {list|validate|deps} [...]", file=sys.stderr)
        return 64
    return cmds[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    sys.exit(main())
