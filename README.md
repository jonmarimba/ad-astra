# ad-astra

Through hardships to the stars.

This is a shared toolbox for AI development work: MCP servers, command-line tools, skills, and the operating rules agents follow. You do not use it in place. You install what a project needs into that project, and the project keeps its own copy.

Start with QUICKSTART.md. It explains how to install a template. It also explains where each kind of tool lands and how each kind stays current. A tool lands in your repo, in your repo's agent config, on the machine, or runs from this checkout. Three guides cover the main templates:

- QUICKSTART-ios.md covers iOS and Mac app work, the Xcode aggregator, and simulator driving.
- QUICKSTART-writing.md covers the prose tools: what each skill does and the order they run in.
- QUICKSTART-pdf.md covers PDF text sidecars for document repos.

Clone with `--recurse-submodules`, because `convoq` needs the engine in `vendor/authsec-bridge`. The toolbox runs from any directory under any name. `tools/tests/run-all.sh` runs the fast tests and `tools/tests/run-slow.sh` the slow ones. Both pass from a copy of the checkout on a machine with an empty home directory, and `tools/tests/test-clone-portability.sh` checks that.
