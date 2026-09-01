# Xcode 27 vs Drew — measured collisions (Claude/Fable, 2026-09-01)

Probe: Jonathan's real Maharam workspace, `pot-mhm/pot-mhm-goals-tool/GoalsTool.xcworkspace`,
open in Xcode-beta 27A5252f, live aggregator on 8768 (53 xcode27__ + 29 drews__ = 82 tools).
Every verdict below is from RUNNING both tools on that workspace, not reading descriptions.

## Context: 27 is a superset of 26.6 and closes the old gaps

26.6 had no scheme, destination, run, or console tools — those were Drew's-only, no decision
to make. Xcode 27 adds all of them (XcodeListSchemes/XcodeSwitchScheme,
XcodeListRunDestinations/XcodeSwitchRunDestination, RunProject/StopProject,
GetConsoleOutput, plus test plans, build settings, entitlements, string catalogs, device
interaction, crash/field data, DocumentationSearch). So the 26.6-era sieve is stale exactly
where 27 grew, and each contested capability was re-measured.

## Measured: schemes -> xcode27

- `xcode27__XcodeListSchemes`: the 3 schemes a human sees in the picker (GoalsTool active,
  prettyJSON, GoalsTool PRIVATE), structured JSON, isActive/isShared/container flags.
- `drews__get_project_schemes`: ~115 schemes as flat text — every Pod and dependency
  (Alamofire, Mantle, RxSwift, Pods-*), with duplicates. The 3 real ones are buried.
For "what can I build here," Drew's answer is noise. xcode27 owns schemes.

## Measured: run destinations -> xcode27

- `xcode27__XcodeListRunDestinations`: grouped like the Xcode picker (Build/Devices/
  Simulators), isActive + isEligible flags, active destination named inline.
- `drews__list_run_destinations`: exhaustive simctl-style list with UDIDs (the one datum
  Apple's lacks) but no active flag, and `drews__get_active_run_destination` ERRORED on this
  workspace: "Unexpected destination format: dvtdevice-DVTiPhonePlaceholder-iphoneos" — a
  live defect against a generic device destination.
xcode27 owns destinations. (Drew's UDID list is simulator territory — the next aggregation
project — not a destination-picker capability.)

## Measured: build -> Drew (same verdict as 26.6)

- `xcode27__BuildProject`: success in 25s, errors[] empty, full log path. NO warnings inline
  — unchanged from 26.6.
- `drews__build_project`: success in 6s, 13 warnings INLINE with file:line and message text
  (SwiftLint violations, Alamofire deprecations, enum-conversion warnings) plus log path.
On real Maharam code the difference is decisive: Drew surfaces the actionable diagnostics;
Apple reports "built successfully" and hides 13 warnings behind a log file. Drew owns build.

## Measured: build diagnostics -> Drew (worse for Apple than 26.6)

- `xcode27__GetBuildLog`: hung >8 minutes after the successful build and broke the
  daemon's connection (26.6's at least returned instantly, if empty).
- `drews__get_build_results`: instant, structured — 12 warnings with file/line/column/
  message, plus rebuild analysis (7 files recompiled multiple times) Apple has no
  equivalent for. Drew owns build diagnostics.

## Measured: tests -> xcode27 (26.6 verdict reconfirmed, harder)

- `xcode27__GetTestList`: structured, honest "0 tests (0 enabled, 0 disabled)" for the
  GoalsTool scheme, which carries no test plan.
- `drews__list_project_tests`: ERRORED — "Could not find a buildable run destination for
  scheme 'Rx (Playground)'" — its Pod-noise scheme enumeration poisons its own test
  listing. xcode27 owns tests. The 26.6 CAVEAT for path-based .xcodeproj workflows stands.

## Root cause of the all-night "connection closed at 5s" — mcpbridge CRASHES

Crash reports on disk (~/Library/Logs/DiagnosticReports/mcpbridge-2026-09-01-102037.ips
and siblings from 2026-08-31, -08-30, -08-26): Swift `assertionFailure` in
`MCPBridge.main()`, EXC_BREAKPOINT/SIGTRAP. The unapproved/unanswered path ASSERTS and
dies instead of waiting. Approved connections never hit it. Apple beta bug — worth filing.
Once the approval dialog was clicked ONCE (identity "Xcode27CombinedFront"), everything
served; the daemon's armed clicker (Automation grant) now auto-answers reconnect dialogs
hands-free (observed 11:00:19 and again on the 11:01 restart, zero manual clicks).

## APPLIED and VERIFIED by effect (2026-09-01 ~11:05)

The sieve/map above is written into xcode27-combined-front-run.sh and running live on
8768: 82 -> 74 tools (51 xcode27__ + 22 drews__ + 1 canonical `build`). All 16
presence/absence checks pass. The canonical `build` was then called on
GoalsTool.xcworkspace through the composed surface: built, 0 errors, 9 warnings inline.

## Not measured (leads, not verdicts)

- Run/stop + console: xcode27 RunProject/StopProject/GetConsoleOutput vs drews
  run_project_*/stop_project/get_runtime_output. Both remain exposed; launching the real
  app was deferred. Measure before trusting either vendor's story here.
- XcodeSwitchScheme / XcodeSwitchRunDestination / XcodeSwitchTestPlan: unmeasured setters;
  their families went to xcode27 on list/active evidence. If a switch fails in practice,
  revisit (drews__set_run_destination is the blocked fallback).
- Dissolved-in-26.6 pairs (windows, fs listing, project discovery, screenshots): different
  jobs then; nothing in 27's descriptions suggests that changed, but not re-run.
