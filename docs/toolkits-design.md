# Toolkits — grouping skills, tools, and MCP servers into installable bundles

Nothing in this design exists yet except the individual pieces.

## The problem

Jonathan's assistant setup has grown to include skills (asd-ste100, humanizer, adhd, convocation) and standalone tools (check-prose.js, unwrap-markdown.js, mailq, shotq, notesq, imsgq, recall, archive_contact). It also includes MCP servers (mac-control, xcode-mcp-front, ghost-channel, imessage, safari-mcp-stp, claude-in-chrome) and voice registers (attorney, business-friendly-client, casual-contractor-and-text). These pieces are scattered across four repos (js-db-ad-astra, js-project-GhOST, pot-mhm-newmanPostmanNPM, js-llmKicker) and two install mechanisms (Claude Code plugins and manual PATH/symlink setup). A new machine or a new agent needs someone to remember what goes together and install each piece by hand.

## What a toolkit is

A toolkit is a named bundle of related capabilities that can be installed as a unit. It declares what it contains and what it needs from the host environment.

### Example: `writing` toolkit

Contains:
- `asd-ste100` skill (sentence rules, three-question gate, banned vocabulary)
- `humanizer` skill (AI-tell removal, voice calibration)
- `check-prose.js` tool (mechanical STE-100 enforcement)
- `unwrap-markdown.js` tool (hard-wrap cleanup)
- Voice register files (attorney, business-friendly-client, casual-contractor-and-text)

Needs from host:
- Node.js (for check-prose.js and unwrap-markdown.js)
- A Claude Code session (for skill loading)

### Example: `local-search` toolkit

Contains:
- `mailq` (Apple Mail FTS5 search)
- `imsgq` (iMessage FTS5 search + decode)
- `shotq` (screenshot OCR search)
- `notesq` (Apple Notes FTS5 search)
- `recall` (unified multi-source search)

Needs from host:
- Python 3 with sqlite3
- macOS (for Mail.app, Messages, Notes access)
- TCC grants (Full Disk Access for Mail/Messages containers)
- Vision OCR binary at `~/.shotq/bin/vision_ocr_batch` (for shotq)

### Example: `browser-automation` toolkit

Contains:
- `claude-in-chrome` MCP server
- `safari-mcp-stp` MCP server
- `mac-control-mcp` MCP server

Needs from host:
- Chrome with the Claude extension (for claude-in-chrome)
- Safari Technology Preview (for safari-mcp-stp)
- Accessibility permission (for mac-control-mcp)

## The MCP aggregator idea

MCP servers currently need individual entries in `.mcp.json` or `settings.local.json`. Each project that wants browser automation has to copy the same three server definitions. Each machine that runs GhOST has to configure the same set of servers.

An MCP aggregator would be a single MCP server that proxies requests to a configured set of downstream MCP servers. The project's `.mcp.json` would list one aggregator entry instead of N individual servers. The aggregator's own config would name the toolkit and resolve it to the individual servers.

### What this buys

- One `.mcp.json` entry per toolkit instead of one per server.
- A toolkit definition in one place instead of copied across projects.
- The aggregator can handle server lifecycle (start/stop downstream servers on demand, restart on crash) instead of each client managing its own stdio processes.
- The aggregator can namespace tool names to avoid collisions when two servers expose similar tools (e.g., xcode-mcp-front and XcodeBuildMCP both have build tools).

### What this costs

- One more layer between the client and the server. Latency on every tool call.
- The aggregator needs to merge tool lists from downstream servers and route calls correctly.
- Error handling gets harder: is the error from the aggregator or the downstream server?
- Authentication/TCC grants still need to happen per downstream server, not per aggregator.

### Prior art to check

- `mcp-proxy` (if it exists) — a generic MCP-to-MCP proxy
- Claude Code's own plugin system already does some of this (a plugin can bundle an MCP server)
- The `xcode-mcp-front` pattern (HTTP proxy in front of a stdio MCP server) is a single-server version of this idea

## Toolkit manifest format (strawman)

A toolkit is a directory containing a `toolkit.json` manifest:

```json
{
  "name": "writing",
  "version": "1.0",
  "description": "Prose quality tools: STE-100 enforcement, humanizer, voice calibration",
  "skills": [
    {"name": "asd-ste100", "path": "skills/asd-ste100/SKILL.md"},
    {"name": "humanizer", "path": "skills/humanizer/SKILL.md"}
  ],
  "tools": [
    {"name": "check-prose", "path": "tools/check-prose.js", "runtime": "node"},
    {"name": "unwrap-markdown", "path": "tools/unwrap-markdown.js", "runtime": "node"}
  ],
  "data": [
    {"name": "voice-registers", "path": "reference/voice/", "description": "Jonathan's per-register voice files"}
  ],
  "requires": {
    "node": ">=18",
    "platform": "any"
  }
}
```

An `install` command would symlink or copy the pieces into the right places (`~/.claude/skills/`, `~/bin/`, etc.) and report what TCC grants are needed.

## Open questions

1. Should toolkits live in js-db-ad-astra (the shared utility repo) or in their own repo?
2. Should the MCP aggregator be a standalone project or a feature of the toolkit installer?
3. How does a toolkit declare that it needs a TCC grant without being able to request one programmatically?
4. Should the aggregator handle tool-name collisions by namespacing (prefix with toolkit name) or by priority (first server wins)?
5. Does Claude Code's plugin system already solve enough of this that we should build on it rather than beside it?
