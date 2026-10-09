# Quickstart: iOS and Mac app work

This guide covers the `swift-ios` and `mac-swift` templates, the Xcode aggregator they ride on, and the tools that land beside it. The general template mechanics are in QUICKSTART.md. Written 2026-09-02 by Claude (Fable), reviewed against the live system.

## Install

```
cd <your astra clone>/tools/lib
python3 template.py install swift-ios --into ~/path/to/YourApp
```

The template command changes only your repo. Two pieces of the iOS setup live on the machine, and the install prints a `MACHINE` line for each. Run them once per machine, from your astra clone:

```
tools/xcode-mcp-front/install.sh      # the Xcode aggregator daemon (all of swift-ios and mac-swift)
tools/axe/install.sh                  # the axe CLI for simulator driving (swift-ios only)
```

Without the daemon, the `xcode-combined` entry in your repo points at a port where nothing answers. The simulator MCP server installs idb itself during the template install. `tools/astra upgrade` refreshes all of this later.

Use `mac-swift` instead for a Mac app; it is the same template minus the simulator pieces. Both compose `base`, so the writing stack and convocation arrive too. Restart your agent session afterward, because agents read MCP config at session start.

## How the MCP plumbing works

An MCP server is a process that offers tools to an agent. Each agent normally spawns its own copy per session, from `.mcp.json` (Claude Code), `.qwen/settings.json` (Qwen), or `.codex/config.toml` (Codex). The Xcode servers cannot work that way: Xcode's bridge shows an approval dialog for every new connecting process, so per-session spawns became a dialog storm.

So the template writes no direct Xcode spawns. It writes one HTTP entry, `xcode-combined`, pointing at a single long-lived daemon on port 8767, shared by every agent and session. The daemon holds the three upstream connections itself: Apple's Xcode bridge (`xcrun mcpbridge`), Drew's `xcode-mcp-server`, and a narrow slice of XcodeBuildMCP. Xcode's approval dialog is answered once, for the daemon, and never again. The daemon runs under launchd, survives reboots, and reconnects on its own.

Inside, each upstream's tools get a prefix (`xcode__`, `drews__`, `xbm__`) so nothing collides. A sieve blocks the duplicates, and a map renames the winners. Every entry has a recorded reason. Head-to-head measurement on real projects picked the winners. The result is one surface where each capability appears once. `build` comes from Drew and returns warnings inline with file and line. Scheme, destination, and test queries come from Apple. The headless simulator loop (`xbm__build_run_sim`, `xbm__test_sim`, coverage) comes from XcodeBuildMCP and works with Xcode closed.

Day to day: build with the `build` tool, and never call raw `xcodebuild`. The Apple half serves only while a workspace is open in Xcode; the `xbm__` slice keeps working when Xcode is closed.

## Driving iOS UI

The `ios-ui-driving` skill states the rules, and two are absolute. Every element you create or touch gets an accessibility identifier. And no image recognition as perception: screenshots check appearance; the accessibility tree as text is how you find things to tap.

The rest is a cost ladder ruled by time-to-goal. Probe with `axe` (`describe-ui`, `tap --id`, `type`) or the ios-simulator MCP tools for exploration and one-offs. Promote a flow to an XCUITest-by-identifier when you will iterate on the feature across many builds; the test then stays as a regression guard. On identifier-poor branches, target by `--label` or tree structure and stay in the probe tier.

## The other tools that land

- The `ios-simulator` MCP server offers simulator UI as tools: taps, typing, and the AX tree. It drives Facebook's idb underneath; the installer owns both halves, the idb-companion daemon via Homebrew and the fb-idb CLI via pipx.
- `axe` is a CLI, not an MCP server; agents shell out to it for `describe-ui`, `tap`, `type`, and `swipe`. It covers the same niche as the ios-simulator tools — use whichever is wired in the session.
- MacControlMCP.app drives the Mac itself: windows, clicks, keys, screen capture, and the accessibility tree. It is Developer-ID signed, so its TCC grants survive updates; the installer pulls and verifies the latest release.
- The Swift quality tools are ponytail (the do-less decision ladder) and dedup-scan (duplicate code). Periphery, a dead-code scanner, is an opt-in tool under `tools/periphery`, not part of the template. Nobody has set it up in a repo, and kicker measured real false positives and a six-minute multi-graph run. Use it as an occasional audit if you want it.
- The writing stack and convocation arrive through `base` (QUICKSTART-writing.md).

## Update

Re-run the same install command, or run `.astra/astra-update --pull` inside your repo. The astra post-commit hook runs that update in the background on every commit. Anything you edited locally is reported and never overwritten.
