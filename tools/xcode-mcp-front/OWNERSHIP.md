# Xcode 27 combined tool ownership

The combined front joins Apple's Xcode MCP, Drew's Xcode MCP, and XcodeBuildMCP. The table records which tool owns each overlapping task on Xcode 27.0. A different scope is listed separately only when the tools do different work.

| Task | Exposed owner | Other path and reason |
| --- | --- | --- |
| Create an Xcode project | Apple `XcodeListTemplates`, `XcodeNewProject` | Drew `create_project` overlaps Apple's template creation path. |
| Build an Xcode project | Drew `build` | Apple `BuildProject` hides warnings in a log path. XcodeBuildMCP `build_sim` has no measured advantage over Drew's build. |
| Read build warnings and errors | Drew `get_build_results`, `get_build_errors` | Apple `GetBuildLog` returned no entries or hung in the measured runs. |
| Read current issues in one source file | Apple `XcodeRefreshCodeIssuesInFile` | Drew has no matching SourceKit diagnostic tool. Apple's messages can suggest edits; `XcodeUpdate` makes literal text replacements. There is no exposed apply-fix-it command. |
| List and select a scheme in the open workspace | Apple `XcodeListSchemes`, `XcodeSwitchScheme` | Drew's list included dependency schemes. XcodeBuildMCP `list_schemes` remains available for a project when Xcode is closed. |
| List and select an Xcode run destination | Apple `XcodeListRunDestinations`, `XcodeSwitchRunDestination` | Apple reports the active and eligible destinations. XcodeBuildMCP `list_sims` remains available for all simulator IDs. |
| List and run tests in the open workspace | Apple `GetTestList`, `RunAllTests`, `RunSomeTests` | Drew's listing took about 28 seconds for the same Work Tool test. XcodeBuildMCP `test_sim` accepts prepared test products and `.xctestrun` files. |
| Build and run in a visible Xcode window | Apple `RunProject`, `StopProject`, `GetConsoleOutput` | Apple's run verified launch and returned a PID and console session. Drew's unmonitored run returned before launch completed. |
| Build and run when Xcode is closed | XcodeBuildMCP `build_run_sim` and session defaults | Apple's run needs an Xcode workspace window. This route builds, installs, and launches on a simulator. |
| Wait for an app to terminate and collect its logs | Drew `run_project_until_terminated`, `get_runtime_output` | This bounded, unattended workflow is different from Apple's interactive run. |
| Clean build products | Drew `clean_project` | XcodeBuildMCP `clean` duplicates it. |
| Discover projects on disk | Drew `get_xcode_projects` | XcodeBuildMCP `discover_projs` duplicates it. Apple's `XcodeListWorkspaces` lists open workspaces instead. |
| Read build settings | Apple `GetTargetBuildSettings` for an open target; XcodeBuildMCP `show_build_settings` for a project path | The latter works through build defaults without an open Xcode window. |
| Inspect a built app | XcodeBuildMCP `get_app_bundle_id`, `get_sim_app_path` | These read a built product rather than a target's declared build settings. |
| Capture simulator pixels or video | `ios-simulator` screenshot and video tools | Drew's simulator screenshot and XcodeBuildMCP's screenshot/video tools duplicate them. Drew's Mac app, window, and Xcode screenshots remain available. |
| Inspect UI semantics in an Xcode device session | Apple `DeviceInteractionSynthesize` | Apple returns the hierarchy and screenshots in one response. The standalone `ios-simulator` UI tools remain available for simulator inspection outside that session. |
| Get simulator state | XcodeBuildMCP `list_sims` for all devices; Drew `list_booted_simulators` for running devices | Apple lists destinations eligible for the selected Xcode scheme. These scopes answer different questions. |
| Install, launch, or stop an arbitrary simulator app | `ios-simulator` app tools | XcodeBuildMCP's separate app tools duplicate them. Apple's `DeviceInteraction` tools remain for Xcode's device session and synthesis workflow. |

Apple also owns Xcode workspace tabs, project navigator files, test plans, target settings, compiler flags, entitlements, Info.plist editing, and string catalogs. Apple also handles previews, debugger commands, and crash or field issue queries. Drew retains Mac app windows and processes, filesystem listings, project discovery, screenshots of Mac windows, post-run output, and test result retrieval. XcodeBuildMCP retains coverage reports, built-product inspection, Xcode-closed scheme and settings queries, simulator inventory, prepared-product testing, and its session defaults.

The block list in `xcode-combined-front-run.sh` names each removed tool and its reason. An upstream tool that is not blocked remains exposed, so a new upstream feature does not disappear silently.
