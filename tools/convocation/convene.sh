#!/usr/bin/env bash
# convene.sh — run ONE grouped, mixed-brand code-review convocation over a cluster of related tools.
# Portable + agent-agnostic: any caller passes a cluster spec; nothing about GhOST is baked in.
#
# Doctrine (tools/convocation/convocation-doctrine.md), enforced here:
#   1. convoq-FIRST — pull the cluster's known bugs/edge-cases from the record and feed them in.
#   2. mix models AND brands — dispatch the SAME thorough prompt to three brand CLIs in parallel:
#      claude -p (Claude), codex exec (GPT), and ollama-cloud GLM (Zhipu). All hosted/cloud — this
#      machine is NOT an inference box (local silicon lives on the M5 laptop / the Strix box). Group
#      review, not per-tool, so we don't multiply inference: each brand is told to be thorough across
#      ALL the listed tools in one pass. The ollama brand is non-agentic, so it gets file contents
#      embedded; claude and codex read the files (and codex reads runtime logs) themselves.
#
# Usage:
#   convene.sh --name <cluster> --repo <dir> --files "f1 f2 ..." \
#              --convoq "term1|term2|..." [--ollama-model <id>] [--timeout <secs>] [--out <dir>]
#
# Writes: <out>/<cluster>.context.md (convoq findings), <out>/<cluster>.<brand>.txt (each brand's
# raw findings). Cross-brand verification + synthesis is the caller's job (a different brand should
# verify each finding). Each brand call is timeout-bounded so one hang can't stall the cluster.
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"

NAME=""; REPO=""; FILES=""; CONVOQ=""; OMODEL="${OLLAMA_MODEL:-glm-5.2:cloud}"; TIMEOUT=300; OUT=""
CONVOQ_DIR="${CONVOQ_DIR:-$HOME/svnCheckouts/js-llmKicker/contrib/authsec-bridge}"
while [ $# -gt 0 ]; do case "$1" in
  --name) NAME="$2"; shift 2;; --repo) REPO="$2"; shift 2;; --files) FILES="$2"; shift 2;;
  --convoq) CONVOQ="$2"; shift 2;; --ollama-model) OMODEL="$2"; shift 2;;
  --timeout) TIMEOUT="$2"; shift 2;; --out) OUT="$2"; shift 2;;
  *) echo "unknown arg '$1'" >&2; exit 64;;
esac; done
[ -n "$NAME" ] && [ -n "$REPO" ] && [ -n "$FILES" ] || { echo "usage: convene.sh --name X --repo D --files '...' [--convoq 'a|b'] [--ollama-model id]" >&2; exit 64; }
[ -d "$REPO" ] || { echo "no such repo: $REPO" >&2; exit 1; }
OUT="${OUT:-$REPO/.convocation}"; mkdir -p "$OUT"
CONVOQ_BIN="${CONVOQ_BIN:-$HOME/svnCheckouts/js-project-GhOST/tools/convoq}"
if [ -n "${CONVOQ:-}" ] && [ ! -x "$CONVOQ_BIN" ]; then
  echo "convene: convoq wrapper not executable at $CONVOQ_BIN" >&2
  echo "convene: convoq-first is doctrine; refusing to run a convocation blind." >&2
  exit 3
fi
CTX="$OUT/$NAME.context.md"

# ---- 1. convoq-FIRST: gather the cluster's known issues from the record ----
{
  echo "# Known issues for cluster '$NAME' (from convoq — treat as ground truth, do not rediscover)"
  echo
  if [ -n "$CONVOQ" ]; then
    # Use the pinned-interpreter wrapper. A bare `python3` here resolves to
    # Xcode's 3.9 on Jonathan's Mac and dies on the `str | os.PathLike` union in
    # session_bridge/paths.py:19 — so this block used to swallow a TypeError into
    # /dev/null and hand every panelist an empty "known issues" section while
    # reporting success. Found by the 2026-08-24 instruction audit.
    if ! "$CONVOQ_BIN" update >/dev/null 2>&1; then
      echo "convene[$NAME]: WARNING — convoq update failed; searching stale index" >&2
      "$CONVOQ_BIN" update >&2 || true   # re-run visibly so the cause is on the record
    fi
    old_ifs="$IFS"; IFS='|'
    for term in $CONVOQ; do
      IFS="$old_ifs"
      echo "## \"$term\""
      "$CONVOQ_BIN" search "$term" 2>/dev/null \
        | grep -iE "human:|assistant:" | sed 's/^/  /'
      echo
      IFS='|'
    done
    IFS="$old_ifs"
  else
    echo "(no --convoq terms supplied)"
  fi
} > "$CTX"
echo "convene[$NAME]: convoq context -> $CTX ($(wc -l < "$CTX") lines)"

# ---- 2. build the shared, thorough review prompt ----
PROMPT_FILE="$OUT/$NAME.prompt.txt"
{
  echo "You are ONE brand in a multi-brand code-review convocation. Thoroughly review EACH of these"
  echo "tools (read every file fully before judging) in repo $REPO:"
  for f in $FILES; do echo "  - $f"; done
  echo
  echo "KNOWN issues from prior sessions follow — treat as ground truth, do NOT waste effort"
  echo "rediscovering them; instead confirm they are fixed or find NEW defects:"
  echo
  cat "$CTX"
  echo
  echo "Hunt these failure classes, REAL defects only, each cited file:line with a concrete failure"
  echo "(inputs -> wrong result) and a severity(low/med/high):"
  echo "- SILENT DATA LOSS: unjustified LIMIT/time-window/[:N]/cap with no stated reason; anything"
  echo "  destructive to source data a tool is supposed to only READ; rows/results dropped silently."
  echo "- SILENT-SKIP GATES: a precondition that quietly passes/skips; errors to /dev/null; an"
  echo "  unconditional success after an unchecked command."
  echo "- TCC-context: a launchd COMMAND job reading protected Mail/Messages/Notes/Photos with no"
  echo "  FDA .app wrapper (silent EPERM)."
  echo "- Shell/Python quoting, path-with-spaces, glob-nomatch, FTS special-char traps."
  echo "Be thorough and terse. Output a numbered findings list. Do NOT modify any files."
} > "$PROMPT_FILE"
P="$(cat "$PROMPT_FILE")"

# The ollama-cloud brand is NON-agentic (it can't open files), so it gets the file CONTENTS embedded.
# It runs on ollama's servers, not local silicon — this machine is not an inference box.
OPROMPT="$OUT/$NAME.ollama_prompt.txt"
{ cat "$PROMPT_FILE"; echo; echo "=== FILE CONTENTS (you cannot open files — review the source below) ===";
  for f in $FILES; do echo; echo "----- $f -----"; cat "$REPO/$f" 2>/dev/null; done; } > "$OPROMPT"
OP="$(cat "$OPROMPT")"

# ---- 3. dispatch to three brand CLIs in parallel, each timeout-bounded ----
run_brand(){ # $1 label  $2... command
  local label="$1"; shift
  echo "convene[$NAME]: $label starting…"
  if timeout "$TIMEOUT" "$@" < /dev/null > "$OUT/$NAME.$label.txt" 2>&1; then
    echo "convene[$NAME]: $label done (rc=0)"
  else
    echo "convene[$NAME]: $label ended rc=$? (see $OUT/$NAME.$label.txt)"
  fi
}
( cd "$REPO" && run_brand claude claude -p "$P" ) &
( cd "$REPO" && run_brand codex  codex exec --sandbox read-only "$P" ) &
( cd "$REPO" && run_brand ollama ollama run "$OMODEL" "$OP" ) &
wait
echo "convene[$NAME]: all brands returned. Raw findings in $OUT/$NAME.{claude,codex,ollama}.txt"
