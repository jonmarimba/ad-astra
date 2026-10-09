# ad-astra

Through hardships to the stars.

This is a shared toolbox for AI development work: MCP servers, command-line tools, skills, and the operating rules agents follow. You do not use it in place. You install what a project needs into that project, and the project keeps its own copy.

The toolbox runs on macOS. Nobody has tested it on Linux, and nothing here promises it works there. The writing and PDF tools use only git, Python 3.9 or newer, jq, and common Homebrew packages, so they may work. The Xcode, Mac control, and wrapper-app tools work on a Mac only.

## Start here

Start with QUICKSTART.md. It explains how to install a template. It also explains where each kind of tool lands and how each kind stays current. A tool lands in your repo, in your repo's agent config, on the machine, or runs from this checkout. Four more guides cover the main templates and how to extend the toolbox:

- QUICKSTART-ios.md covers iOS and Mac app work, the Xcode aggregator, and simulator driving.
- QUICKSTART-writing.md covers the prose tools: what each skill does and the order they run in.
- QUICKSTART-pdf.md covers PDF text sidecars for document repos.
- CONTRIBUTING.md explains how to add a tool, a skill, or a template, and which tests check your work.

Clone with `git clone https://github.com/jonmarimba/ad-astra.git`. Add `--recurse-submodules` only if you can read the private `jonmarimba/authsec-bridge` repository, which holds the search engine in `vendor/authsec-bridge`. Without that engine, installing `convoq` still works, but the `convoq` command stops and says the engine is missing, and `agent-sync` cannot run. No other tool needs it. The toolbox runs from any directory under any name. `tools/tests/run-all.sh` runs the fast tests and `tools/tests/run-slow.sh` the slow ones. Both pass from a copy of the checkout on a machine with an empty home directory, and `tools/tests/test-clone-portability.sh` checks that.

## Templates

A template is a named set of tools for one kind of project. A template can hold other templates as well as tools, to any depth. The tree below shows how the shipped templates nest. A name that ends in a slash is a template. A bare name is a tool. A tag in square brackets marks a tool that lives above the repo. The tag `[repo-config]` means an entry in the agent config files. The tag `[machine]` means software on the machine itself.

<!-- template-tree:start -->
```
kicker-dev/
  mcp-kickerd  [repo-config]
  mcp-mac-control-mcp  [repo-config]
  mcp-xcode  [repo-config]
legal-pdf/
  base/
    writing/
      check-prose
      check-banned-phrases
      asd-ste100
      humanizer
      prose
      writing-doctrine
    convocation
    convoq
    no-silent-truncation
    act-first-doctrine
  pdf-sidecars
mac-swift/
  base/
    writing/
      check-prose
      check-banned-phrases
      asd-ste100
      humanizer
      prose
      writing-doctrine
    convocation
    convoq
    no-silent-truncation
    act-first-doctrine
  xcode/
    mcp-xcode-combined  [repo-config]
    xcode-mcp-front  [machine]
  swift/
    ponytail
    dedup-scan
  mac/
    mcp-mac-control-mcp  [repo-config]
swift-ios/
  base/
    writing/
      check-prose
      check-banned-phrases
      asd-ste100
      humanizer
      prose
      writing-doctrine
    convocation
    convoq
    no-silent-truncation
    act-first-doctrine
  xcode/
    mcp-xcode-combined  [repo-config]
    xcode-mcp-front  [machine]
  swift/
    ponytail
    dedup-scan
  mac/
    mcp-mac-control-mcp  [repo-config]
  mcp-ios-simulator  [repo-config]
  axe  [machine]
  ios-ui-driving
```
<!-- template-tree:end -->

You can build your own set from the same pieces. Suppose you want one install for a project that has iOS code and also produces prose for people. Add an entry to `tools/lib/templates.json` that names the two templates:

```
"ios-writer": {
  "description": "iOS app work in a repo that also produces prose for humans.",
  "templates": ["swift-ios", "writing"]
}
```

A tool that arrives through two paths installs once. Uninstalling a parent keeps every tool that another installed template still needs. A cycle is refused by name. Run `tools/astra tree` to print the nesting at any time, or `tools/astra tree swift-ios` for one template. When you change `templates.json`, run `tools/lib/refresh-readme-tree.sh` to update the tree above. The test suite fails if the two disagree.

Tools that no template installs stay available one at a time. `tools/astra add adhd` installs the ADHD output-shaping skill. `tools/astra list` shows every tool.

## The commands

Run these from inside the repo you want to change. `astra` lives at `tools/astra` in this checkout.

- `astra add <tool-or-template>` installs it into the current repo.
- `astra remove <tool-or-template>` removes it. An installed file you edited by hand stays in place and the command says so.
- `astra status` shows what the repo asked for and whether its update hooks are wired.
- `astra tree [template]` prints how templates nest.
- `astra list` prints every template and every tool.
- `astra upgrade [--list] [tool...]` refreshes software on the machine without touching any repo.
- `astra sync [dir...]` wires the update hooks in every repo beside this checkout, once per machine or fresh clone.
- `astra doctor [dir...]` reports on the whole machine: the prerequisites, then each repo with its templates, update state, and hook wiring.
- `astra new <name> --kind <kind>` scaffolds a new tool with its uninstaller and test.

## Removing astra from a repo or a machine

To take astra out of one repo, run `astra remove` for each template listed by `astra status`. When the last tool goes, the updater, the hooks, and `.astra/manifest.json` go with it. A file you edited stays behind, and so does the backup of any git hook the installer replaced. Delete those by hand when you no longer need them.

To take astra off a machine, remove it from every repo first. Then run each machine tool's `uninstall.sh`. The directories under `tools/` whose `install.sh` declares `# astra-scope: machine` are the machine tools, and `tools/astra tree` tags them. Pass `--deps` to an uninstaller to remove the Homebrew and uv packages it used. Leave `--deps` off when other software on the machine might use the same package. Last, delete this checkout and, if you made one, `~/.config/astra/config`.
