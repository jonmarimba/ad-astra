**Cli proxy**

@Ghost research this

***GhOST reply, 2026-08-02 23:32:***

*CLIProxyAPI (github.com/router-for-me/CLIProxyAPI) — a gateway wrapping Claude Code/Codex/Gemini/Grok CLIs behind OpenAI/Gemini/Claude-compatible API endpoints, with multi-account round-robin load balancing across pooled accounts. Directly relevant to today's kicker situation: Root's Claude account hit its weekly cap and had to manually fail over to Codex — this is infrastructure for exactly that, pooling multiple accounts/providers behind one proxy instead of a manual seat-switch.*

@ghost the thing that makes me iffy about ACP is the one directory cwd forever thing. The spec even requires not allowing things like symlinks. I suppose my bot's could just live in ~/svnCheckouts. Lots of stuff that lets you sort of get around the annoying harness issues with (especially Claude) would be fun to try if I could get past that. Anyway. Add this to the tech to try list pls.

***GhOST reply, 2026-08-03 21:52:***

*Added to tech-to-try.md — filed as 'ACP cwd/symlink workaround' alongside CLIProxyAPI (same note, same underlying gripe: harness-imposed single-cwd-forever + no-symlinks restriction). Worth being precise on what ACP is here: Agent Client Protocol (Zed's spec for editor&lt-&gtagent communication) does mandate a fixed working directory and disallows symlink escapes by design — a security/sandboxing choice, not an oversight. Your 'bots could just live in ~/svnCheckouts' framing is the actual workaround already, not a stopgap: if the real repos live there natively (not symlinked in from elsewhere), the ACP constraint stops being a constraint. Worth trying practically rather than theorizing further.*

@astra