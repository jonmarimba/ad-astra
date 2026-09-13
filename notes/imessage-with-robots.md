**iMessage with robots**

https://jsr.io/@wyattjoh/imessage

https://jsr.io/@wyattjoh/imessage-mcp

https://wyattjoh.ca/blog/imessage-mcp

Something like this better than the bespoke thing for Claude we use? Anything else out there? I know open claw has an iMessage plugin. I’m not totally averse to the idea of running open claw as a sort of proxy for stuff we want to do, given it has so many plugins. Not sure I want to go all the way down the rabbit hole on that.

@ghost look for ways for robots to use iMessage on the Mac to send my google voice number messages w/o relying on the conduit you currently use that IIRC is Claude-specific.

**GhOST reply, 2026-08-06 11:44:**

Good news: what you're currently using for OUTBOUND sending (the `imsg` command) is already NOT Claude-specific.

Checked directly — /opt/homebrew/bin/imsg is a standalone Homebrew package (steipete/tap, MIT licensed, &quotsend and read iMessage/SMS from the terminal"), and it's literally an OpenClaw project (github.com/openclaw/imsg) — the same OpenClaw you mentioned. Any process/script on this Mac can shell out to `imsg send` right now with zero Claude dependency;

that part of your worry is already solved, just not something anyone had pointed out explicitly. What IS genuinely Claude-Code-specific is the INBOUND side — the imessage plugin that polls chat.db and injects new messages into a live Claude Code session as a channel.

That's harness-specific by design (it's wired to inject into Claude Code's own conversation loop), and there's no way around that being tied to whatever process is doing the injecting —

any harness that wants inbound iMessage would need its own equivalent listener, but it could just as easily shell out to `imsg`'s own read/search commands under the hood rather than reading chat.db directly, since `imsg` already handles that safely. On the alternatives you linked:

@wyattjoh/imessage-mcp is real but READ-ONLY (search/retrieve messages only, no send) — wouldn't replace what you need on its own. Two other MCP servers do support write: carterlasalle/mac\_messages\_mcp (read/write) and marissamarym/imessage-mcp-server (AppleScript-based send, similar mechanism to what imsg itself likely uses under the hood).

None of these are meaningfully more general-purpose than what you already have with `imsg`, though — you already own the actually-portable piece. The remaining gap, if you want one, is just: build a thin inbound listener per-harness that all shell out to the same `imsg` read/search commands, rather than each harness reimplementing chat.db access separately.

@ghost I need you to make your messaging thing generic enough that any robot can message me with minimal setup on my part and I can message them back by replying

@ghost put the tool you make into @astra complete with install scripts and dependency management via Brewfile