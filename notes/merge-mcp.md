**Merge MCP**

https://github.com/nazar256/combine-mcp

https://github.com/domdomegg/mcp-aggregator

@ghost I would like to proxy the Xcode MCP. Because it requires the user to click an allow pop up for every connection a that sucks for working afk with an ensemble of bots. Better yet, I'd like to merge a few related MCPs.

***GhOST reply, 2026-08-02 23:32:***

*Two candidates: mcp-aggregator (domdomegg) and combine-mcp (nazar256), both merge multiple MCP servers behind one endpoint. Since you confirmed Xcode's approval is per-PID on connect (not OAuth-token-based), either works for the connection-friction problem via the same mechanism: a single persistent aggregator process = one stable PID = one Xcode approval, reused by every bot in the ensemble instead of a fresh prompt per bot/session. mcp-aggregator has the edge for the actual merging you also asked for (namespaced tools from multiple upstream MCPs).*

@ghost add to the tech to try list. Oh. Also. I need to add the Mac control MCP thing to the install MCP scripts for kicker. Claude's is shite.

***GhOST reply, 2026-08-03 22:02:***

*Added to tech-to-try.md — filed alongside mcp-aggregator/combine-mcp (same note, same connection-friction problem). On the Mac Control MCP install-script ask: already done — commit 99cdad9f ('tooling: install MacControlMCP for project providers') already wires it into scripts/setup-mcp.sh across all three CLIs (claude/qwen/codex), same as the other MCPs in that script. Nothing further needed there unless you meant something more specific by 'Claude's is shite.'*

@astra