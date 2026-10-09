# Test tool ownership

On 2026-10-09, Apple's `GetTestList` found `WorkTool_PRIVATEUITests/testBatchCloseUI()` in the open Work Tool PRIVATE scheme. Drew's `list_project_tests` found the same test with an explicit workspace path and scheme. Apple's result included the active plan, enabled status, and source location. Drew's listing took about 28 seconds because it built for testing. Apple owns test listing on the combined front.

Apple's `RunAllTests` and `RunSomeTests` own normal tests in the open Xcode workspace. Drew's `run_project_tests` has not been run in this comparison, so there is no measured runner verdict. It is hidden to give the open-workspace test task one owner. XcodeBuildMCP's `test_sim` remains available because it accepts prepared `.xctestrun` and `.xctestproducts` files. Those inputs are a distinct test task.

The 2026-08-31 comparison used a SwiftPM package and a project without a configured test target. Drew could not list tests there. On 2026-09-01, Drew chose a dependency scheme in Goals Tool and failed to list its tests. The current Work Tool result shows Drew can list tests when given the right scheme. These observations support Apple's listing result without claiming Drew cannot test an iOS project.
