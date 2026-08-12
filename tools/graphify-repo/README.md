# graphify-repo

Local-only graphify pipeline for any repo (client repos included): tree-sitter extraction + clustering with **no LLM by default** (nothing leaves the machine). Output lives in the repo's `graphify-out/` but is excluded via `.git/info/exclude` (the project's own .gitignore is never touched). The report is symlinked into the Obsidian chokepoint (`~/.notesq/vault/graphify/<repo>/`, override with `GRAPHIFY_VAULT`).

```sh
graphify-repo ~/svnCheckouts/pot-mhm                      # extract + cluster, unlabeled communities
graphify-repo ~/repo --label-backend ollama --label-model ornith   # opt-in local labeling
```
First run on pot-mhm (2026-08-12): 2,592 nodes, 3,318 edges, 166 communities; GRAPH_REPORT.md + interactive graph.html. Andrew can run this too — nothing GhOST-specific.

## Install
```sh
./install.sh   # brew uv + `uv tool install graphifyy` (the graphify CLI)
```
Optional local labeling needs ollama + a local model (`--label-backend ollama --label-model ornith:latest`).

## Repos mapped so far
- pot-mhm (8/12): 2,592 nodes / 166 communities, ornith-labeled
- js-llmKicker (8/12): see vault graphify/js-llmKicker
