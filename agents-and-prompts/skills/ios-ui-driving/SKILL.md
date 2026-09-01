---
name: ios-ui-driving
description: Drive iOS app UI in the simulator the Maharam way - accessibility identifiers everywhere, AX-tree targeting for ad-hoc probes (axe or ios-simulator MCP), and promotion of stable flows to XCUITest-by-identifier. Use when tapping, typing, reading, or verifying iOS UI.
---

# Driving iOS UI

Two absolute rules, then a cost ladder. The rules come from kicker's measured 2026-06-18 session and Jonathan's standing doctrine; the ladder ordering is Jonathan's (2026-09-01).

## Rule 1: accessibility identifiers are mandatory

Every on-screen element you create or touch gets an `.accessibilityIdentifier` (and a human `.accessibilityLabel` where a person would want one). Every tier below depends on them. If the element you need has no identifier and you are editing that code anyway, add one - that is part of the task, not a detour. The measured lesson: a field without an id forced positional taps, which dropped a typed character and produced a real authentication failure; the same flow by identifier ran clean end to end.

Reality check for the Maharam apps specifically (Jonathan, 2026-09-01): most shipped branches have FEW identifiers - the identifier-rich branches are experimental. So when driving an existing build you cannot edit (a release-branch repro, an installed .app), do not go add identifiers to a branch that does not want them: read `describe-ui` and target by `--label` or the element's AX structure instead, and accept that flows there stay in the probe tier. Identifier work belongs on the branches being actively developed.

## Rule 2: no image recognition as perception

Jonathan's line: "You are welcome to look at a screenshot to see if your UI looks right - NOT to find something to click." The accessibility tree as text is how you target elements and read state. Screenshots are for appearance checks only, paired with a stated expectation.

## The cost ladder

The underlying rule (Jonathan, 2026-09-01): spend as little time as possible getting to the goal. Working a bug and axe reproduces it right away? Just keep using axe. Working a feature and poking it with axe is taking forever? Try an XCUITest. Neither tier is "the right way" - the fast way for THIS task is the right way, and the ladder below only describes what each tier costs and buys.

**Probe tier (default for exploration and one-offs).** Cheap, no code written. Read the tree, act by identifier:

- `axe describe-ui --udid <UDID>` - the AX tree as text.
- `axe tap --id <identifier>` (or `--label`), `axe type "<text>"`, `axe swipe`, `axe button`.
- The ios-simulator MCP tools (`ui_describe_all`, `ui_tap`, `ui_type` via idb) cover the same niche; use whichever is wired in the session.
- Get the UDID from `drews__list_booted_simulators` (on the xcode-combined server) or `axe list-simulators`.

**Regression tier (promote when a flow earns it).** When you are going to work on a feature for a while, an XCUITest that drives its flow by identifier is super valuable - you rerun the exact same sequence after every change instead of re-tapping it by hand, it runs in-sim so it never grabs the host mouse, and when the feature ships the test stays in the repo as a regression. It pairs with the probe tier rather than replacing it: the XCUITest carries the stable spine of the flow, and axe/ios-simulator probes handle the ad-hoc pokes around it (checking a value mid-flow, trying a variant, exploring an unexpected state). Writing XCUITest is time-consuming - pay that cost only when it is the fast path NET: you will iterate on this feature across many builds, re-tapping the flow by hand is what is taking forever, or the flow must survive as a regression guard.

Run the tests through the xcode-combined server: `xcode__RunSomeTests` / `xcode__GetTestList` against the open workspace, or `xbm__test_sim` headless by path when Xcode is not running.

## Building and seeing the result

Build with the `build` tool on xcode-combined (inline warnings). For the build-install-launch-logs loop on the simulator without Xcode open, `xbm__build_run_sim`. Screenshot for appearance via `drews__take_simulator_screenshot` or `axe screenshot` - appearance only, per Rule 2.
