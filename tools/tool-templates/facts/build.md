# Overlap: build — MEASURED 2026-08-31 (Claude/Fable), live, by effect

Probe: a Swift file carrying a deliberate unused-variable warning.

## drews__build_project (include_warnings=true)
Response: {"summary":{"build_failed":false,"total_errors":0,"total_warnings":2,
"showing_warnings":2}, "errors_and_warnings":"Build succeeded with 2 warnings...\n..."}
- Surfaces warnings INLINE with structured counts.
- Builds an explicit .xcodeproj/.xcworkspace path (need not be open in Xcode).
- Refuses a bare SwiftPM package dir (requires .xcodeproj/.xcworkspace).

## xcode__BuildProject (tabIdentifier only)
Response: {"buildResult":"built successfully","elapsedTime":28.4,"errors":[],
"fullLogPath":"...log.txt"}
- No warning parameter exists; warnings never appear inline, only in the log file.
- Builds only the workspace OPEN in the given Xcode tab.

## DECISION: Drew owns `build`. Sieve xcode__BuildProject.
Reason: Drew's build returns warning counts + text inline and works on any path;
Apple's build response is errors-only + a log path with no warning access.

## NOT part of this overlap (Apple sole-owner, kept):
xcode__XcodeRefreshCodeIssuesInFile returned, live, per-file:
"[Warning] [Line: 5] Initialization of immutable value 'unusedVariable' was never
used; consider replacing with assignment to '_' or removing it"
— the SourceKit fixit. Drew has NO diagnostics/fixit tool. This is why Apple stays
for live diagnostics even though Drew wins the build.
