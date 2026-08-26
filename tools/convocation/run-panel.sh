#!/usr/bin/env bash
# run-panel.sh — fire one prompt at a cross-brand panel and collect the answers.
#
# Usage:
#   run-panel.sh <prompt-file> <outdir> [model ...]
#
# With no models named it uses a default roster spanning three brands. Codex is
# always included and is the only panelist that can read files off disk, so a
# prompt may point it at repo paths; every ollama model gets the prompt text and
# nothing else, because they have no filesystem access.
#
# Each panelist writes <outdir>/<slug>.md and a one-line status to
# <outdir>/STATUS. A panelist that fails leaves its error in the file rather
# than vanishing, so a short roster is visible as a short roster and never as a
# silent drop.
#
# Written for the convocation doctrine in .doctrine/convocation.md. The doctrine
# requires a mixed-brand roster; a single-brand panel is an echo chamber.
set -uo pipefail

PROMPT_FILE=${1:?usage: run-panel.sh <prompt-file> <outdir> [model ...]}
OUTDIR=${2:?usage: run-panel.sh <prompt-file> <outdir> [model ...]}
shift 2

DEFAULT_ROSTER=(
    "ollamacloud/glm-5.2"
    "ollamacloud/kimi-k3"
    "ollamacloud/deepseek-v4-pro:preview"
    "ollamacloud/minimax-m3"
    "ollamacloud/qwen3.5:397b"
)
ROSTER=("$@")
[ ${#ROSTER[@]} -eq 0 ] && ROSTER=("${DEFAULT_ROSTER[@]}")

TIMEOUT=${TIMEOUT:-900}

mkdir -p "$OUTDIR"
: > "$OUTDIR/STATUS"
[ -r "$PROMPT_FILE" ] || { echo "FAIL: cannot read prompt file $PROMPT_FILE" >&2; exit 2; }

slug() { echo "$1" | sed 's|^ollamacloud/||; s|[^a-zA-Z0-9._-]|-|g'; }

# One ollama-cloud panelist, through the qwen CLI. The CLI holds the per-model
# settings, so it is the thing that knows each model's token budget. An earlier
# version of this script posted raw JSON at OmniRoute instead, which meant
# inventing a max_tokens; the invented value was four times what any panelist
# used and long enough to push two models past OmniRoute's queue budget. Do not
# go around the CLI to save a layer. The layer is where the settings live.
#
# -y is load-bearing: without it any prompt that trips tool-calling fails in
# non-interactive mode. Qwen cannot read local files, so the prompt must carry
# whatever the model needs to see.
ask_ollama() {
    local model=$1 out=$2
    qwen -m "$model" -p "$(cat "$PROMPT_FILE")" -y > "$out" 2>"$out.err" </dev/null
    local rc=$?

    if [ "$rc" -ne 0 ] || [ ! -s "$out" ]; then
        { echo "FAIL: $model exited $rc."; echo; head -c 2000 "$out.err"; } > "$out"
        rm -f "$out.err"
        return 1
    fi
    rm -f "$out.err"

    # An empty or near-empty answer is a failure, not a short answer.
    if [ "$(wc -c < "$out")" -lt 200 ]; then
        echo "FAIL: $model produced under 200 bytes." >> "$out"
        return 1
    fi
    # A byte count is not a success test. An OmniRoute error is JSON prose and
    # sails past any size floor, which is how a first version of this script
    # reported three queue-dropped panelists as "ok". Grep for the marker the
    # error path writes instead of trusting the length.
    grep -q '^FAIL: ' "$out" && return 1
    return 0
}

# Ollama panelists run in a bounded window, NOT all at once. OmniRoute keeps a
# local request queue with a maxWaitMs budget (120s by default), and a model
# still waiting when that budget runs out is dropped with a 502 that names the
# queue. Firing five long generations together saturated it and lost three of
# them; two at a time gets everyone served. Raise OLLAMA_CONCURRENCY only after
# raising the budget in OmniRoute's Settings → Resilience.
OLLAMA_CONCURRENCY=${OLLAMA_CONCURRENCY:-2}
pids=()
inflight=0
for model in "${ROSTER[@]}"; do
    out="$OUTDIR/$(slug "$model").md"
    ( if ask_ollama "$model" "$out"; then
          echo "ok    $model  $(wc -c < "$out") bytes" >> "$OUTDIR/STATUS"
      else
          echo "FAIL  $model" >> "$OUTDIR/STATUS"
      fi ) &
    pids+=($!)
    inflight=$((inflight + 1))
    if [ "$inflight" -ge "$OLLAMA_CONCURRENCY" ]; then wait -n 2>/dev/null || wait; inflight=$((inflight - 1)); fi
done

# Codex reads the repo, so give it the prompt on stdin and let it look around.
# </dev/null on the inner call is load-bearing per the doctrine: without it
# codex blocks forever waiting on stdin.
#
# NO_CODEX=1 skips it. Set that when re-running only the ollama panelists that
# failed a previous round: codex already answered, and a second codex run costs
# a long generation AND competes for the same queue slots the retry needs.
if [ "${NO_CODEX:-0}" != "1" ]; then
( out="$OUTDIR/codex.md"
  if command -v codex >/dev/null 2>&1; then
      codex exec --sandbox read-only "$(cat "$PROMPT_FILE")" </dev/null > "$out" 2>&1
      if [ -s "$out" ]; then echo "ok    codex  $(wc -c < "$out") bytes" >> "$OUTDIR/STATUS"
      else echo "FAIL  codex (empty)" >> "$OUTDIR/STATUS"; fi
  else
      echo "FAIL: codex not on PATH" > "$out"
      echo "FAIL  codex (not installed)" >> "$OUTDIR/STATUS"
  fi ) &
pids+=($!)
fi

for p in "${pids[@]}"; do wait "$p"; done

echo "=== panel complete: $OUTDIR ==="
sort "$OUTDIR/STATUS"
