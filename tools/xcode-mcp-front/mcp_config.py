#!/usr/bin/env python3
"""mcp_config — load and validate the aggregator's upstream config (_mcp_info.json).

The shape is Claude Code's own — {"mcpServers": {"<name>": {"command": ..., "args": [...]}}} —
because Jonathan already reads and writes that shape, and an entry can then move between this
file and a real .mcp.json by copy and paste. Two additive fields belong to the wrapper:

  prefix  exposed-name prefix for this upstream's tools, defaulting to "<name>__"
  quirks  list of named per-upstream behaviours; today only "require_xcode" (wait for a live
          Xcode before connecting). Keeping quirks per-upstream is the point: the old parser
          made require-Xcode a positional boolean every upstream had to answer, so every
          server was described in Xcode's terms whether or not it had anything to do with it.

EVERYTHING ELSE IS REJECTED BY NAME. Claude Code's format also carries env, cwd and url; the
daemon passes only command and args to the child, so accepting those fields would drop them
silently and the failure would surface later, at the first call, pointing at nothing. A field
we do not implement is an error naming the field and the server, at load — the same policy for
keys we have never heard of. (tool-templates increment 1.1; roadmap: "red when a config with
url is accepted silently".)

Runs on python3 >= 3.9 (the tests use the system interpreter, which is 3.9.6 on this machine;
scheduled jobs get the same one).

CLI, used by test-mcp-front-config.sh and handy for a human:
    mcp_config.py validate <file>     rc 0 and one line per upstream, or a named rejection
Exit codes: 65 (EX_DATAERR) config invalid, 66 (EX_NOINPUT) unreadable file.
"""
import json
import sys

KNOWN_QUIRKS = frozenset({"require_xcode"})
# Claude Code fields the daemon does not pass through yet. Named individually so the error
# can say "unimplemented" — which invites implementing — rather than "unknown", which reads
# as a typo. type/transport/headers travel with url in real .mcp.json files.
UNIMPLEMENTED_FIELDS = ("env", "cwd", "url", "type", "transport", "headers")
IMPLEMENTED_FIELDS = frozenset({"command", "args", "prefix", "quirks"})


class ConfigError(ValueError):
    """A named rejection. str() is the full user-facing message."""


class UpstreamSpec:
    def __init__(self, name, command, args, prefix, quirks):
        self.name = name
        self.command = command
        self.args = args
        self.prefix = prefix
        self.quirks = quirks

    @property
    def require_xcode(self):
        return "require_xcode" in self.quirks


def _parse_server(name, spec):
    if not isinstance(spec, dict):
        raise ConfigError("server %r must be an object, got %s" % (name, type(spec).__name__))
    for field in UNIMPLEMENTED_FIELDS:
        if field in spec:
            raise ConfigError(
                "unimplemented field '%s' on server '%s' — the wrapper passes only command "
                "and args to the child; remove it or implement it, but do not expect it to "
                "take effect" % (field, name))
    for field in spec:
        if field not in IMPLEMENTED_FIELDS:
            raise ConfigError("unknown field '%s' on server '%s'" % (field, name))

    command = spec.get("command")
    if not isinstance(command, str) or not command:
        raise ConfigError("server '%s' has no 'command' (non-empty string required)" % name)

    args = spec.get("args", [])
    if not isinstance(args, list) or not all(isinstance(a, str) for a in args):
        raise ConfigError("server '%s': 'args' must be a list of strings" % name)

    prefix = spec.get("prefix", name + "__")
    if not isinstance(prefix, str):
        raise ConfigError("server '%s': 'prefix' must be a string" % name)

    quirks = spec.get("quirks", [])
    if not isinstance(quirks, list) or not all(isinstance(q, str) for q in quirks):
        raise ConfigError("server '%s': 'quirks' must be a list of strings" % name)
    for q in quirks:
        if q not in KNOWN_QUIRKS:
            raise ConfigError("unknown quirk '%s' on server '%s' (known: %s)"
                              % (q, name, ", ".join(sorted(KNOWN_QUIRKS))))

    return UpstreamSpec(name, command, list(args), prefix, frozenset(quirks))


def load(path):
    """-> list of UpstreamSpec, in the file's order. Raises ConfigError (bad content) or
    OSError (unreadable file); the caller chooses the exit code."""
    try:
        raw = open(path, encoding="utf-8").read()
    except OSError as e:
        raise OSError("mcp_config: cannot read %s (%s)" % (path, e))
    try:
        cfg = json.loads(raw)
    except ValueError as e:
        # A jsonc human file lands here. Say so: the difference between a typo and a
        # deliberate comment is the whole remedy. Same wording as mcp_tools.py on purpose.
        raise ConfigError(
            "%s is not strict JSON (%s). If this is the commented human-owned file, point "
            "at the generated one instead — comments are only allowed there." % (path, e))
    servers = cfg.get("mcpServers") if isinstance(cfg, dict) else None
    if not isinstance(servers, dict) or not servers:
        raise ConfigError("%s has no non-empty mcpServers object" % path)
    specs = [_parse_server(name, spec) for name, spec in servers.items()]
    _check_prefixes(specs)
    return specs


def _check_prefixes(specs):
    """The prefix set must compose into an unambiguous surface (increment 1.3).

    Two upstreams sharing a prefix collide exposed names. A prefix that is a prefix of
    another — 'a__' and 'a__b__' — makes routing 'a__b__tool' depend on iteration order.
    An empty prefix beside another upstream exposes bare names that cannot be routed
    back. All three are author mistakes; reject them at load, when the author can still
    fix them, never at call time as a misroute."""
    if len(specs) < 2:
        return
    seen = {}
    for s in specs:
        if s.prefix == "":
            raise ConfigError(
                "server '%s' has an empty prefix beside other upstreams — its bare tool "
                "names could not be routed back to it" % s.name)
        if s.prefix in seen:
            raise ConfigError("servers '%s' and '%s' have the same prefix '%s' — their "
                              "exposed names would collide" % (seen[s.prefix], s.name, s.prefix))
        seen[s.prefix] = s.name
    ordered = sorted(specs, key=lambda s: s.prefix)
    for a, b in zip(ordered, ordered[1:]):
        if b.prefix.startswith(a.prefix):
            raise ConfigError(
                "server '%s' prefix '%s' is a prefix of server '%s' prefix '%s' — routing "
                "a name under the longer one would be order-dependent"
                % (a.name, a.prefix, b.name, b.prefix))


def resolve_specs(environ):
    """How the daemon picks its upstreams (increment 1.2). One mechanism wins, visibly:

    - XCODE_MCP_FRONT_UPSTREAMS set: HARD ERROR. The colon/comma format silently corrupted
      a colon in a command path and a comma in an argument; it is replaced, not deprecated,
      because a daemon half-honouring both mechanisms would hide which one won.
    - XCODE_MCP_FRONT_MCP_INFO set: load that _mcp_info.json.
    - neither: the deployed single-upstream env contract, unchanged — UPSTREAM_CMD
      (default xcrun), UPSTREAM_ARGS (default mcpbridge), REQUIRE_XCODE (default 1),
      served unprefixed exactly as before.
    """
    if environ.get("XCODE_MCP_FRONT_UPSTREAMS"):
        raise ConfigError(
            "XCODE_MCP_FRONT_UPSTREAMS has been replaced by _mcp_info.json — set "
            "XCODE_MCP_FRONT_MCP_INFO=<path> instead. The colon/comma format corrupts a "
            "command path containing ':' and an argument containing ',', silently.")
    info = environ.get("XCODE_MCP_FRONT_MCP_INFO")
    if info:
        return load(info)
    quirks = frozenset({"require_xcode"}) if environ.get(
        "XCODE_MCP_FRONT_REQUIRE_XCODE", "1") == "1" else frozenset()
    return [UpstreamSpec(
        name="default",
        command=environ.get("XCODE_MCP_FRONT_UPSTREAM_CMD", "xcrun"),
        args=environ.get("XCODE_MCP_FRONT_UPSTREAM_ARGS", "mcpbridge").split(),
        prefix="",
        quirks=quirks,
    )]


def _print_specs(upstreams):
    for u in upstreams:
        quirks = ",".join(sorted(u.quirks)) or "-"
        print("%s  prefix=%s  quirks=%s  %s %s" % (u.name, u.prefix, quirks, u.command,
                                                   " ".join(u.args)))


def main(argv):
    import os
    if len(argv) == 2 and argv[1] == "resolve":
        try:
            upstreams = resolve_specs(os.environ)
        except ConfigError as e:
            print("mcp_config: %s" % e, file=sys.stderr)
            return 65
        except OSError as e:
            print(str(e), file=sys.stderr)
            return 66
        _print_specs(upstreams)
        return 0
    if len(argv) != 3 or argv[1] != "validate":
        print("usage: mcp_config.py validate <file> | resolve", file=sys.stderr)
        return 64
    try:
        upstreams = load(argv[2])
    except ConfigError as e:
        print("mcp_config: %s" % e, file=sys.stderr)
        return 65
    except OSError as e:
        print(str(e), file=sys.stderr)
        return 66
    _print_specs(upstreams)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
