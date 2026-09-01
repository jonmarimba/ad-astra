#!/usr/bin/env python3
"""stub_mcp_server — a minimal, dependency-free stdio MCP server for tests.

Speaks just enough newline-delimited JSON-RPC for the aggregator's client to connect:
initialize, notifications/initialized, tools/list, tools/call, ping. Every knob is an
argument so any test (or any other agent's harness) can shape it without editing it:

    stub_mcp_server.py --name alpha --tool ping=alpha-pong --tool build=done
    stub_mcp_server.py --name empty                       # connects fine, zero tools
    stub_mcp_server.py --name chatty --banner "starting"  # spec-illegal stdout banner line
    stub_mcp_server.py --name pager --tool a=1 --tool b=2 --page-size 1   # paginates

--tool NAME=REPLY declares one tool; calling it returns REPLY as text content. Two REPLY
  prefixes change the behaviour: "env:VAR" answers with os.environ[VAR] resolved at call
  time (proves an env pass-through by effect), and "error:MSG" answers with a JSON-RPC
  ERROR response (an application-level error a proxy must forward, not treat as a dead
  transport).
--banner LINE prints LINE to stdout before serving (reproduces the class of server that
  breaks naive next-line readers).
--notify-before-reply emits a spec-legal notification line immediately before every
  response (a next-line reader misreads the notification as the answer).
--stall-tools answers initialize normally and then never answers tools/list (reproduces
  the approval-dialog gate that must read as a timeout, never as an empty tool list).
--page-size N makes tools/list return N tools per page with a nextCursor, exercising
  per-upstream cursors.
--page-loop makes every tools/list page carry nextCursor "0" forever (a cursor cycle,
  the upstream bug a drain must bound rather than follow to memory exhaustion).
Python 3.9-compatible; no third-party imports.
"""
import argparse
import json
import os
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--version", default="1.0-stub")
    ap.add_argument("--tool", action="append", default=[], metavar="NAME=REPLY")
    ap.add_argument("--describe", action="append", default=[], metavar="NAME=TEXT",
                    help="override a tool's description (for description-rewrite tests)")
    ap.add_argument("--banner", default=None)
    ap.add_argument("--notify-before-reply", action="store_true")
    ap.add_argument("--blank-before-reply", action="store_true",
                    help="emit one empty line before every response (must NOT read as EOF)")
    ap.add_argument("--stall-tools", action="store_true")
    ap.add_argument("--stall-log", default=None, metavar="FILE",
                    help="with --stall-tools: append one line to FILE on EVERY tools/list "
                         "request before refusing to answer. The line count is the fire count — "
                         "how many times the client (re)issued tools/list — asserted by effect.")
    ap.add_argument("--emit-list-changed-on-call", default=None, metavar="TOOL",
                    help="emit notifications/tools/list_changed before answering a call "
                         "to TOOL (deterministic trigger for notification-relay tests)")
    ap.add_argument("--page-size", type=int, default=0)
    ap.add_argument("--page-loop", action="store_true")
    a = ap.parse_args()

    tools = {}
    for spec in a.tool:
        name, _, reply = spec.partition("=")
        tools[name] = reply
    described = {}
    for spec in a.describe:
        n, _, text = spec.partition("=")
        described[n] = text
    tool_list = [{"name": n,
                  "description": described.get(n, "stub tool %s on %s" % (n, a.name)),
                  "inputSchema": {"type": "object"}}
                 for n in tools]

    def send(obj):
        if a.blank_before_reply and "id" in obj:
            sys.stdout.write("\n")   # a spec-irrelevant blank line before every response
        if a.notify_before_reply and "id" in obj:
            sys.stdout.write(json.dumps({"jsonrpc": "2.0",
                                         "method": "notifications/message",
                                         "params": {"level": "info",
                                                    "data": "stub %s chatter" % a.name}}) + "\n")
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()

    if a.banner is not None:
        sys.stdout.write(a.banner + "\n")
        sys.stdout.flush()

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        msg = json.loads(line)
        method = msg.get("method")
        mid = msg.get("id")
        if mid is None:
            continue  # a notification; nothing to answer
        if method == "initialize":
            send({"jsonrpc": "2.0", "id": mid, "result": {
                "protocolVersion": msg.get("params", {}).get("protocolVersion", "2025-06-18"),
                "capabilities": {"tools": {"listChanged": True}},
                "serverInfo": {"name": a.name, "version": a.version}}})
        elif method == "tools/list" and a.stall_tools:
            if a.stall_log:
                with open(a.stall_log, "a") as f:
                    f.write("tools/list %s\n" % mid)
                    f.flush()
            continue  # never answer — the approval-dialog gate, as a stub
        elif method == "tools/list":
            if a.page_loop:
                send({"jsonrpc": "2.0", "id": mid, "result": {
                    "tools": tool_list, "nextCursor": "0"}})
            elif a.page_size > 0:
                cursor = msg.get("params") or {}
                start = int(cursor.get("cursor") or 0)
                page = tool_list[start:start + a.page_size]
                result = {"tools": page}
                if start + a.page_size < len(tool_list):
                    result["nextCursor"] = str(start + a.page_size)
                send({"jsonrpc": "2.0", "id": mid, "result": result})
            else:
                send({"jsonrpc": "2.0", "id": mid, "result": {"tools": tool_list}})
        elif method == "tools/call":
            params = msg.get("params") or {}
            name = params.get("name")
            if name in tools:
                if a.emit_list_changed_on_call == name:
                    send({"jsonrpc": "2.0", "method": "notifications/tools/list_changed"})
                reply = tools[name]
                if reply.startswith("env:"):
                    reply = os.environ.get(reply[4:], "<unset:%s>" % reply[4:])
                if reply.startswith("error:"):
                    send({"jsonrpc": "2.0", "id": mid, "error": {
                        "code": -32050, "message": reply[6:]}})
                    continue
                send({"jsonrpc": "2.0", "id": mid, "result": {
                    "content": [{"type": "text", "text": reply}], "isError": False}})
            else:
                send({"jsonrpc": "2.0", "id": mid, "error": {
                    "code": -32602, "message": "unknown tool %r on stub %s" % (name, a.name)}})
        elif method == "ping":
            send({"jsonrpc": "2.0", "id": mid, "result": {}})
        else:
            send({"jsonrpc": "2.0", "id": mid, "error": {
                "code": -32601, "message": "stub %s does not implement %s" % (a.name, method)}})


if __name__ == "__main__":
    main()
