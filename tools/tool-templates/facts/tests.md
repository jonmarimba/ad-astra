# Overlap: test-listing + test-running — MEASURED 2026-08-31, live, by effect
Apple GetTestList (open workspace): structured — activeTestPlanName, counts
  (enabled/disabled/total), each test's displayName + filePath. Worked on the open
  SwiftPM package (AstraProbe), found example() with its path.
Drew list_project_tests (BuildCmp.xcodeproj): "no test target configured" — requires a
  .xcodeproj with a configured test target; cannot enumerate a SwiftPM package.
DECISION: Apple owns test-listing and test-running. Sieve drews__list_project_tests and
  drews__run_project_tests.
Reason: Apple returns structured test-plan-aware results and works on the open workspace
  including SwiftPM packages; Drew requires a configured .xcodeproj test target.
CAVEAT (for Jonathan): evidence is from a SwiftPM package, which favours Apple. For a
  real iOS .xcodeproj with a test target, Drew's path-based run (test a project without
  opening it) is a genuine advantage. If your workflow is path-based testing of unopened
  .xcodeproj apps, flip this decision.

# NOT overlaps (verified by behaviour, both kept):
# list-windows: Apple=Xcode workspace tabs; Drew=Mac app windows.
# project-discovery: Apple XcodeGlob=glob files IN the open project; Drew
#   get_xcode_projects=find .xcodeproj files on disk.
# screenshot: Apple RenderPreview=render a SwiftUI preview snapshot; Drew
#   take_*_screenshot=capture a window's pixels.
# fs-list: Apple XcodeLS=project-navigator (feeds its file-ops suite, project-relative);
#   Drew get_directory_listing=filesystem ls with sizes/mtimes. Different scopes.
