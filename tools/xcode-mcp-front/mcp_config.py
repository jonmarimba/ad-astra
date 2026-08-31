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
    return [_parse_server(name, spec) for name, spec in servers.items()]


def main(argv):
    if len(argv) != 3 or argv[1] != "validate":
        print("usage: mcp_config.py validate <file>", file=sys.stderr)
        return 64
    try:
        upstreams = load(argv[2])
    except ConfigError as e:
        print("mcp_config: %s" % e, file=sys.stderr)
        return 65
    except OSError as e:
        print(str(e), file=sys.stderr)
        return 66
    for u in upstreams:
        quirks = ",".join(sorted(u.quirks)) or "-"
        print("%s  prefix=%s  quirks=%s  %s %s" % (u.name, u.prefix, quirks, u.command,
                                                   " ".join(u.args)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
