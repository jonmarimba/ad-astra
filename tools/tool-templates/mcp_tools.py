#!/usr/bin/env python3
"""mcp_tools — list the tools an MCP server offers, and compare two servers for collisions.

    mcp_tools.py list    --config _mcp_info.json --server xcode
    mcp_tools.py compare --config _mcp_info.json --server xcode --against drews
    mcp_tools.py compare --config _mcp_info.json --server xcode --against drews --summarize

WHY. Wrapping several MCP servers behind one surface means deciding which server does a job when
more than one covers it, and that decision needs the two tool lists side by side. Doing it by
reading documentation is how you miss the pair that are named nothing alike and do the same
thing. This prints both lists, finds the overlaps that string comparison can find, and will
optionally hand the rest to a model, which is the part string comparison cannot do.

It reads the Claude Code config shape — {"mcpServers": {"<name>": {"command", "args", "env"}}} —
because that is the shape the wrapper is specified to take, so one file drives both.

TWO THINGS THIS REFUSES TO DO, both learned the hard way on 2026-08-31.

A server that answers `initialize` and then never answers `tools/list` is NOT a server with zero
tools, and reporting it as one cost a night. Xcode raises a per-process approval dialog lazily on
the first real tools/list, so the call blocks until a human or a clicker answers it, and a probe
that gives up reports silence as emptiness. This tool distinguishes them: an answered-but-empty
list is a fact, a timeout is reported as a timeout, with the approval dialog named as the likely
cause when the server is one that shows one.

And the child's stdin stays open for the whole exchange. Closing it after writing makes the
server exit cleanly, which looks identical to a server that refused to answer — that mistake
produced a confident and wrong "mcpbridge is broken" diagnosis the same day.
"""
import argparse
import json
import os
import select
import subprocess
import sys

# Long by design. The first tools/list against a server that gates on an approval dialog does not
# return until the dialog is answered, and a short timeout here turns "waiting for a human" into
# "server has no tools" — which is the failure this file exists to refuse.
DEFAULT_TIMEOUT = 45.0


def load_servers(path):
    try:
        raw = open(path, encoding="utf-8").read()
    except OSError as e:
        sys.exit("mcp_tools: cannot read %s (%s)" % (path, e))
    try:
        cfg = json.loads(raw)
    except ValueError as e:
        # A jsonc human file will land here. Say so rather than "invalid JSON", because the
        # difference between a typo and a deliberate comment is the whole remedy.
        sys.exit("mcp_tools: %s is not strict JSON (%s). If this is the commented human-owned "
                 "file, point at the generated one instead — comments are only allowed there."
                 % (path, e))
    servers = cfg.get("mcpServers")
    if not isinstance(servers, dict) or not servers:
        sys.exit("mcp_tools: %s has no non-empty mcpServers object" % path)
    return servers


def probe(name, spec, timeout):
    """-> dict with serverInfo and tools, or an explicit failure. Never guesses."""
    command = spec.get("command")
    if not command:
        return {"error": "server %r has no 'command'; http upstreams are not supported yet" % name}
    args = spec.get("args") or []
    env = dict(os.environ)
    env.update(spec.get("env") or {})

    p = subprocess.Popen([command] + list(args), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, text=True, bufsize=1, env=env)

    def send(obj):
        try:
            p.stdin.write(json.dumps(obj) + "\n")
            p.stdin.flush()
            return True
        except (BrokenPipeError, ValueError):
            return False

    def readline(limit):
        ready, _, _ = select.select([p.stdout], [], [], limit)
        if not ready:
            return None          # still open, said nothing — NOT the same as empty
        return p.stdout.readline()

    try:
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}},
                         "clientInfo": {"name": "mcp_tools", "version": "1"}}})
        line = readline(timeout)
        if not line:
            return {"error": "no answer to initialize within %.0fs" % timeout}
        init = json.loads(line).get("result") or {}

        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        line = readline(timeout)
        if line is None:
            return {"serverInfo": init.get("serverInfo"),
                    "error": "initialize answered but tools/list did not, within %.0fs. This is "
                             "NOT an empty tool list. A server that gates tool access behind an "
                             "approval dialog blocks here until the dialog is answered — check "
                             "for one before believing anything about this server." % timeout}
        if line == "":
            return {"serverInfo": init.get("serverInfo"),
                    "error": "the server closed its output after initialize rather than answering "
                             "tools/list"}
        tools = (json.loads(line).get("result") or {}).get("tools")
        if tools is None:
            return {"serverInfo": init.get("serverInfo"),
                    "error": "tools/list returned no result field: %s" % line.strip()[:200]}
        return {"serverInfo": init.get("serverInfo"), "tools": tools}
    finally:
        p.kill()


def describe(info):
    si = info.get("serverInfo") or {}
    return "%s %s" % (si.get("name", "?"), si.get("version", "?"))


def cmd_list(a):
    servers = load_servers(a.config)
    if a.server not in servers:
        sys.exit("mcp_tools: %r is not in %s (have: %s)"
                 % (a.server, a.config, ", ".join(sorted(servers))))
    info = probe(a.server, servers[a.server], a.timeout)
    if "error" in info and "tools" not in info:
        print("%s: %s" % (a.server, info["error"]), file=sys.stderr)
        return 2
    print("%s  —  %s  —  %d tools" % (a.server, describe(info), len(info["tools"])))
    for t in sorted(info["tools"], key=lambda t: t.get("name", "")):
        desc = " ".join((t.get("description") or "").split())
        print("  %-34s %s" % (t.get("name"), desc[:110]))
    return 0


def _norm(name):
    """window_close, close_window and closeWindow all reduce to the same token bag.

    Deliberately crude. It exists to catch the word-order and separator variants that two
    independently written servers produce for the same job — Jonathan's example was window_open
    against open_window — and it is not pretending to find semantic matches. That is what the
    optional model pass is for, and the two must not be confused for each other.
    """
    out = []
    for ch in name:
        if ch in "_-. ":
            out.append(" ")
        elif ch.isupper():
            out.append(" " + ch.lower())
        else:
            out.append(ch)
    return frozenset(w for w in "".join(out).split() if w)


def cmd_compare(a):
    servers = load_servers(a.config)
    for want in (a.server, a.against):
        if want not in servers:
            sys.exit("mcp_tools: %r is not in %s (have: %s)"
                     % (want, a.config, ", ".join(sorted(servers))))
    left = probe(a.server, servers[a.server], a.timeout)
    right = probe(a.against, servers[a.against], a.timeout)

    failed = False
    for nm, info in ((a.server, left), (a.against, right)):
        if "tools" not in info:
            print("%s: %s" % (nm, info.get("error")), file=sys.stderr)
            failed = True
    if failed:
        print("\nRefusing to compare. A server whose tools could not be listed would show up as "
              "having no overlaps, which reads as 'no collisions' and is the opposite of what is "
              "known.", file=sys.stderr)
        return 2

    lnames = {t.get("name") for t in left["tools"]}
    rnames = {t.get("name") for t in right["tools"]}
    print("%s  —  %s  —  %d tools" % (a.server, describe(left), len(lnames)))
    print("%s  —  %s  —  %d tools" % (a.against, describe(right), len(rnames)))

    exact = sorted(lnames & rnames)
    print("\nEXACT NAME COLLISIONS: %d" % len(exact))
    for n in exact:
        print("  %s" % n)

    lmap = {}
    for t in left["tools"]:
        lmap.setdefault(_norm(t.get("name", "")), []).append(t.get("name"))
    near = []
    for t in right["tools"]:
        key = _norm(t.get("name", ""))
        for other in lmap.get(key, []):
            if other != t.get("name"):
                near.append((other, t.get("name")))
    print("\nSAME WORDS, DIFFERENT ORDER OR SEPARATOR: %d" % len(near))
    for l, r in sorted(near):
        print("  %-34s %s" % (l, r))

    print("\nThese are the collisions STRING COMPARISON can find. Two tools that do the same job "
          "under unrelated names will not appear above; use --summarize for that pass.")

    if a.summarize:
        payload = ["Server A: %s" % describe(left)]
        for t in sorted(left["tools"], key=lambda t: t.get("name", "")):
            payload.append("  A %s: %s" % (t.get("name"), " ".join((t.get("description") or "").split())[:200]))
        payload.append("Server B: %s" % describe(right))
        for t in sorted(right["tools"], key=lambda t: t.get("name", "")):
            payload.append("  B %s: %s" % (t.get("name"), " ".join((t.get("description") or "").split())[:200]))
        prompt = ("Below are the tools of two MCP servers that are about to be merged behind one "
                  "surface. List pairs that do substantially the same job and would confuse a "
                  "caller if both were offered, naming which one looks better suited and why in "
                  "one sentence. Ignore pairs that merely share words but do different work. Be "
                  "specific and short; do not restate tools that have no counterpart.")
        # The prompt is positional in this CLI. `llm -p` is the codex/qwen convention and is not
        # a prompt flag here; using it silently sends the wrong thing.
        proc = subprocess.run(["llm", prompt], input="\n".join(payload),
                              capture_output=True, text=True)
        print("\n=== possible semantic collisions, per %s ===" % (
            subprocess.run(["llm", "models", "default"], capture_output=True, text=True).stdout.strip() or "llm"))
        if proc.returncode != 0:
            print("  llm failed (%d): %s" % (proc.returncode, (proc.stderr or "").strip()[:300]))
            return 2
        print(proc.stdout.strip())
    return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    l = sub.add_parser("list", help="list one server's tools")
    l.add_argument("--config", required=True)
    l.add_argument("--server", required=True)
    l.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT)
    l.set_defaults(fn=cmd_list)

    c = sub.add_parser("compare", help="compare two servers for collisions")
    c.add_argument("--config", required=True)
    c.add_argument("--server", required=True)
    c.add_argument("--against", required=True)
    c.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT)
    c.add_argument("--summarize", action="store_true",
                   help="hand both lists to the default llm model for a semantic pass")
    c.set_defaults(fn=cmd_compare)

    a = ap.parse_args()
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())
