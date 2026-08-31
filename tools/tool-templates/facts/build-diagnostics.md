# Overlap: build-diagnostics — MEASURED 2026-08-31, live, by effect
Drew get_build_results: structured — total_warnings, warnings_by_type, per-file
  aggregated_warnings with file:line:col.
Drew get_build_errors: errors_and_warnings text with the real warning line inline.
Apple GetBuildLog: buildLogEntries=[] , totalFound=0 — EMPTY structured output, just
  "build succeeded" + a fullLogPath. No warning/error entries returned.
DECISION: Drew owns build-diagnostics. Sieve xcode__GetBuildLog. Drew's
  get_build_results/get_build_errors kept.
