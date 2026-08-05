https://agentclientprotocol.com/get-started/agents

@ghost ACP stuff for connecting Claude, Codex, and others

***GhOST reply, 2026-08-03 22:52:***

*Solid — the Zed-built ACP adapters are already exactly the piece kicker needs: 'Claude Agent (via Zed's SDK adapter)' and a separate Zed-built Codex CLI adapter both exist today, bridging each into ACP. Cline/Cursor/OpenHands (see the OpenHands tech-to-try item) have native ACP support, no adapter needed. Ties directly to your Cli-proxy note's cwd/symlink gripe — ACP itself is the standard both adapters speak, so the fixed-cwd/no-symlink constraint applies uniformly regardless of adapter. Practical next step if you want to actually try this: point Zed's Claude adapter at a real ~/svnCheckouts-resident bot (per your own workaround) and see if the cwd constraint is actually a non-issue in practice, same as the Cli-proxy conclusion.*

https://agentclientprotocol.com/get-started/agents

@ghost ACP stuff for connecting Claude, Codex, and others

***GhOST reply, 2026-08-03 22:52:***

*Solid — the Zed-built ACP adapters are already exactly the piece kicker needs: 'Claude Agent (via Zed's SDK adapter)' and a separate Zed-built Codex CLI adapter both exist today, bridging each into ACP. Cline/Cursor/OpenHands (see the OpenHands tech-to-try item) have native ACP support, no adapter needed. Ties directly to your Cli-proxy note's cwd/symlink gripe — ACP itself is the standard both adapters speak, so the fixed-cwd/no-symlink constraint applies uniformly regardless of adapter. Practical next step if you want to actually try this: point Zed's Claude adapter at a real ~/svnCheckouts-resident bot (per your own workaround) and see if the cwd constraint is actually a non-issue in practice, same as the Cli-proxy conclusion.*

@astra