# Building Xcode, Swift, Objective-C, iOS, macOS projects

- ALWAYS make sure your changes build without errors or new warnings.
- ALWAYS be careful when fixing small build issues - these are often a source of mistakes.
- ALWAYS build with the `build` tool on the `xcode-combined` MCP server. It is the measured winner for builds (inline warnings with file:line), exposed under one canonical name. Do not go hunting for a vendor-named build tool; if you see `drews__build_project` or `BuildProject` mentioned anywhere, `build` is their replacement.
- The `xcode-combined` server needs Xcode running with the project open. If Xcode is NOT running and the task does not need it, use the XcodeBuildMCP server instead - it builds headlessly. That is the ONLY sanctioned use of an xcodebuild-based path; never shell out to raw `xcodebuild` yourself.
- ALWAYS make sure the project builds correctly after your implementation/changes.
