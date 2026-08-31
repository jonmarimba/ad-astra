#!/usr/bin/env python3
"""stub_mcp_server — a minimal, dependency-free stdio MCP server for tests.

Speaks just enough newline-delimited JSON-RPC for the aggregator's client to connect:
initialize, notifications/initialized, tools/list, tools/call, ping. Every knob is an
argument so any test (or any other agent's harness) can shape it without editing it:

    stub_mcp_server.py --name alpha --tool ping=alpha-pong --tool build=done
    stub_mcp_server.py --name empty                       # connects fine, zero tools
    stub_mcp_server.py --name chatty --banner "starting"  # spec-illegal stdout banner line
    stub_mcp_server.py --name pager --tool a=1 --tool b=2 --page-size 1   # paginates

--tool NAME=REPLY declares one tool; calling it returns REPLY as text content.
--banner LINE prints LINE to stdout before serving (reproduces the class of server that
  breaks naive next-line readers).
--page-size N makes tools/list return N tools per page with a nextCursor, exercising
  per-upstream cursors.
Python 3.9-compatible; no third-party imports.
"""
import argparse
import json
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--version", default="1.0-stub")
    ap.add_argument("--tool", action="append", default=[], metavar="NAME=REPLY")
    ap.add_argument("--banner", default=None)
    ap.add_argument("--page-size", type=int, default=0)
    a = ap.parse_args()

    tools = {}
    for spec in a.tool:
        name, _, reply = spec.partition("=")
        tools[name] = reply
    tool_list = [{"name": n,
                  "description": "stub tool %s on %s" % (n, a.name),
                  "inputSchema": {"type": "object"}}
                 for n in tools]

    def send(obj):
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
        elif method == "tools/list":
            if a.page_size > 0:
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
                send({"jsonrpc": "2.0", "id": mid, "result": {
                    "content": [{"type": "text", "text": tools[name]}], "isError": False}})
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
