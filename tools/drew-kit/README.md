# drew-kit

Wire Drew's shared agents-and-prompts components (Swift style rules, Jira conventions, etc.) into a *specific* repo's `CLAUDE.md`/`AGENTS.md` as a marked block of **repo-relative** `@`-imports — never a copy over the global file (see `WARNING-drews-update-sh.md` for why Drew's own `update.sh` must not run here).

The imports go in a fenced block:

```
# >>> drew-kit imports (managed by drew-kit/install-into-repo.sh) >>>
@.drew-kit/components/SwiftCodeStyle.md
…
# <<< drew-kit imports <<<
```

Reinstall refreshes the block in place (no duplication); `uninstall-from-repo.sh` removes the block and whatever files the method dropped in, leaving the rest of the file untouched. Broken markers abort rather than mangle.

## Install methods

`--method` decides HOW the component files get into the target repo. All three write the same repo-relative import block; they differ only in provenance and update path.

| method | files land in | self-contained | updates by | needs |
|--------|---------------|----------------|-----------|-------|
| `copy` (default) | `.drew-kit/components/` | yes | re-running install | nothing |
| `submodule` | `.drew-kit-src/` (pinned commit) | no (pointer) | bump the submodule | `--src` git URL |
| `subtree` | `.drew-kit-src/` (committed) | yes | `git subtree pull` | `--src` git URL |

**copy** is the pragmatic default: the selected components are copied straight in, so the repo is portable and needs no network — the tradeoff is it can **drift** from Drew's originals until you re-run install.

**submodule / subtree** give a single source of truth, but they need a repo to point at. Today Drew's components are a *subfolder of* `ad-astra`, not their own repo — so `--src git@github.com:jonmarimba/ad-astra.git` would drag the **entire** ad-astra repo in for six markdown files. They're only clean once the components live in a **dedicated** repo; until then, prefer `copy`. `--subpath` (default `agents-and-prompts/components`) tells the import block where the components sit inside the source repo.

## Usage

```
install-into-repo.sh <repo> [--set swift|jira|all] [--method copy|submodule|subtree]
                            [--src <git-url>] [--branch <b>] [--subpath <dir-in-src>]
uninstall-from-repo.sh <repo>
```

- `--set` — which components: `swift` (six Swift rule files, default), `jira` (Atlassian), `all` (every component minus UserPersona/END_OF_RESPONSE). Comma-combinable (`--set swift,jira`).

### Examples

```
# default: copy the Swift set into a repo
install-into-repo.sh ~/svnCheckouts/js-someproject

# jira conventions, copied in
install-into-repo.sh ~/svnCheckouts/js-someproject --set jira

# subtree from a dedicated components repo (once one exists)
install-into-repo.sh ~/svnCheckouts/js-someproject --method subtree \
  --src git@github.com:someone/drew-components.git --branch main --subpath components

# remove everything drew-kit added
uninstall-from-repo.sh ~/svnCheckouts/js-someproject
```

## Test

```
../tests/run-all.sh          # runs test-drew-kit.sh among the suite
```

Asserts by effect: the block lands in both files, imports are repo-relative with **no** absolute/`/Users/` path leaking, the copied component is present and non-empty, refresh doesn't duplicate, `--set` switching works, uninstall removes the block + files while preserving pre-existing prose. It runs a **real** `subtree` install against a throwaway local git source repo (proving the method, not just its guard), and RED-controls the method guards (unknown method, submodule/subtree without `--src`), an unknown set, broken markers, and a missing repo arg.
