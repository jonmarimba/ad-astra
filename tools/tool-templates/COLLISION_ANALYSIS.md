# Live collision analysis — Apple's mcpbridge vs Drew's server

By Claude (Fable), 2026-08-31, from the LIVE combined daemon (port 8767) once Xcode was serving MCP: 50 tools, 21 `xcode__` (Apple's `xcrun mcpbridge`, reporting `xcode-tools 24952` — Xcode 26.6), 29 `drews__` (`Xcode MCP Server 1.29.1`). This is the comparison the sieve and map exist to act on, and it was impossible all session until the approval wedge was cleared. **Caveat, load-bearing: this reads tool NAMES and DESCRIPTIONS, not behaviour — I did not run each pair. Treat every semantic pairing below as a lead to verify, not a measured fact.**

## What string comparison finds (certain)

- **Zero exact bare-name collisions** after prefix stripping. Prefixing does its job.
- **One same-token-bag pair:** `xcode__BuildProject` ~ `drews__build_project`. Same words, different casing/separator — the two servers' names for building a project.

## What only reading the descriptions finds (my read, unverified)

These are semantic overlaps — two tools doing substantially the same job under unrelated names — which is exactly the incoherence prefixing does NOT resolve and the sieve/map do. Grouped by job:

- **Build:** `xcode__BuildProject` and `drews__build_project` build; `xcode__GetBuildLog` overlaps `drews__get_build_results` / `get_build_errors`. Drew's adds `clean_project`, which Apple's has no equivalent for.
- **Tests:** `xcode__RunAllTests` / `RunSomeTests` / `GetTestList` overlap `drews__run_project_tests` / `list_project_tests` / `get_latest_test_results`. Both cover run-and-list-tests; the vocabularies are unrelated.
- **Windows / screenshots:** `xcode__XcodeListWindows` overlaps `drews__list_mac_app_windows`; Drew's has four `take_*_screenshot` variants and `xcode__RenderPreview` is preview-shaped — adjacent, not identical.
- **Filesystem:** Apple's bridge has a full suite (`XcodeLS`, `XcodeRead`, `XcodeWrite`, `XcodeMV`, `XcodeRM`, `XcodeMakeDir`, `XcodeGlob`, `XcodeGrep`); Drew's has only `get_directory_listing` / `get_directory_tree`. If the surface should own one filesystem vocabulary, this is the biggest single block-or-map decision.

## The answer to your standing scheme-switching question

You asked which server to use for changing schemes, Drew's vs Apple's. **Measured, live, 26.6: scheme and run-destination switching is Drew's-server-only.** Apple's `xcrun mcpbridge` exposes NONE of it — no scheme list, no destination set. Drew's server has the whole set: `get_project_schemes`, `list_run_destinations`, `get_active_run_destination`, `set_run_destination`. So today there is nothing to compare — if you want to switch schemes or run destinations from MCP, it is Drew's server or nothing. That is also the case for `clean_project`, simulator control (`list_booted_simulators`), and running Mac apps.

This is a per-VERSION fact. The roadmap wants Xcode 27 measured precisely because Apple may add scheme-switching there, which would turn this Drew's-only capability into a real coherence decision (two ways to switch a scheme → the sieve picks one). Until 27's components are installed (your admin call), there is one way and no decision to make.

## A starter sieve, if you want coherence enforced

Not applied — this is a recommendation, and every entry would carry its `why`. The cleanest first cut, given the above: let Drew's server OWN building, testing, schemes, destinations, screenshots and Mac-app control (it is broader there), and let Apple's bridge OWN the filesystem suite and the code-issue / navigator tools Drew's lacks (`XcodeListNavigatorIssues`, `XcodeRefreshCodeIssuesInFile`, `RunCodeSnippet`, `RenderPreview`). That would block `xcode__BuildProject` and the `xcode__Run*Tests` family in favour of Drew's, and block `drews__get_directory_*` in favour of Apple's fuller filesystem set. Each of those is a judgement about which implementation you trust more for the job — which is yours to make, and which the map lets you express by exposing the winner under a clean name regardless of vendor.
