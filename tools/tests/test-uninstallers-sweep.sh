#!/usr/bin/env bash
# test-uninstallers-sweep.sh — the 9 swept uninstallers, proved BY EFFECT: each removes its OWN
# state (redirected to a temp via the SAME env var its tool honors, so the real ~/.ambrosio etc. are
# never touched), leaves shared deps alone on a plain run, and hits the $BREW_BIN/$UV_BIN/$PYTHON_BIN
# seams only with --deps. Special cases (convocation keeps agents, harness-settings keeps backups)
# are asserted too.
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
T="$HERE/.."

STUB="$SB/stub"; LOG="$SB/stub.log"
cat > "$STUB" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$LOG"
EOF
chmod +x "$STUB"
export BREW_BIN="$STUB" UV_BIN="$STUB" PYTHON_BIN="$STUB"

# helper: assert a plain uninstall removes state ($2=envvar $3=path-under-it) and touches no dep
state_case(){ # $1 tool  $2 ENVVAR  $3 relpath-or-file  $4 "is-file"?
  local tool="$1" ev="$2" rel="$3" isfile="${4:-}"
  local home="$SB/$tool.home" target
  if [ -n "$isfile" ]; then mkdir -p "$home"; target="$home/model.bin"; printf 'x\n' > "$target"
  else mkdir -p "$home/$rel"; printf 'x\n' > "$home/$rel/config"; target="$home"; fi
  : > "$LOG"
  export "$ev=$target"
  # A REPO-SCOPED tool's uninstaller needs --into; a global one must not be given it. The
  # difference is visible in the script: repo-scoped ones call astra_target. Calling every
  # uninstaller bare made graphify-repo exit 64 with "usage: --into <repo>", which read as a
  # broken uninstaller and was the sweep treating a per-repo tool as a global one.
  local scope_args=()
  if grep -q "astra_target" "$T/$tool/uninstall.sh" 2>/dev/null; then
    mkdir -p "$SB/$tool.repo"
    scope_args=(--into "$SB/$tool.repo")
  fi
  # ${a[@]+"${a[@]}"} rather than "${a[@]}": under bash 3.2 — which is what macOS ships — an
  # EMPTY array expanded under `set -u` is an unbound variable error, not an empty list.
  assert_rc 0 "$tool plain uninstall succeeds" "$T/$tool/uninstall.sh" ${scope_args[@]+"${scope_args[@]}"}
  unset "$ev"
  assert_no_file "$target" "$tool plain uninstall removed its state ($ev)"
  assert_empty "$(cat "$LOG" 2>/dev/null)" "$tool plain uninstall touched NO deps"
}

# ---- state-owning tools: state removed, deps untouched on a plain run ----
state_case ambrosio     AMBROSIO_HOME     .           ""
state_case botline      BOTLINE_HOME      inbox       ""
state_case graphify-repo GRAPHIFY_VAULT   .           ""
state_case ollama-watch OLLAMA_WATCH_HOME .           ""
state_case speech-bee   SPEECH_BEE_MODEL  .           file

# ---- --deps hits the right dep at the seam ----
: > "$LOG"; env BOTLINE_HOME="$SB/b.home" "$T/botline/uninstall.sh" --deps >/dev/null 2>&1
assert_contains "$LOG" "uninstall imsg" "botline --deps removed imsg (brew seam)"
: > "$LOG"; mkdir -p "$SB/g.repo"; env GRAPHIFY_VAULT="$SB/g.home" "$T/graphify-repo/uninstall.sh" --into "$SB/g.repo" --deps >/dev/null 2>&1
assert_contains "$LOG" "tool uninstall graphifyy" "graphify-repo --deps removed graphifyy (uv seam)"
: > "$LOG"; "$T/periphery/uninstall.sh" --deps >/dev/null 2>&1
assert_contains "$LOG" "uninstall periphery" "periphery --deps removed periphery (brew seam)"
# CRITICAL: redirect SPEECH_BEE_MODEL to a temp — an unset env here would delete the REAL whisper
# model at ~/.cache/whisper/ggml-base.en.bin (this exact bug bit once; the model had to be re-fetched).
: > "$LOG"; env SPEECH_BEE_MODEL="$SB/sb.model" "$T/speech-bee/uninstall.sh" --deps >/dev/null 2>&1 || true
assert_contains "$LOG" "uninstall whisper-cpp" "speech-bee --deps removed whisper-cpp (brew seam)"
: > "$LOG"; "$T/pdf-sidecars/uninstall.sh" --deps >/dev/null 2>&1
assert_contains "$LOG" "uninstall ocrmypdf" "pdf-sidecars --deps removed ocrmypdf (brew seam)"
assert_contains "$LOG" "tool uninstall marker-pdf" "pdf-sidecars --deps removed marker-pdf (uv seam)"

# ---- ambrosio/pdf-sidecars keep foundational deps even with --deps ----
: > "$LOG"; env AMBROSIO_HOME="$SB/a.home" "$T/ambrosio/uninstall.sh" --deps >/dev/null 2>&1
assert_empty "$(cat "$LOG" 2>/dev/null)" "ambrosio --deps still removes NO deps (curl+python are foundational)"

# ---- convocation: NEVER removes the agent CLIs, even with --deps ----
: > "$LOG"; "$T/convocation/uninstall.sh" --deps >/dev/null 2>&1
assert_empty "$(cat "$LOG" 2>/dev/null)" "convocation --deps did NOT remove any agent CLI"
out="$("$T/convocation/uninstall.sh" --deps 2>&1)"
case "$out" in *"refuses to remove agent"*) pass "convocation --deps says it refuses to remove agents";; *) fail "convocation --deps missing the refusal notice";; esac

# ---- harness-settings: preserves backups + settings files on a plain run ----
BK="$SB/hsbackups/20260101"; mkdir -p "$BK"; printf '{}' > "$BK/settings.json"
: > "$LOG"
env HARNESS_BACKUP_ROOT="$SB/hsbackups" "$T/harness-settings/uninstall.sh" >/dev/null 2>&1
assert_file "$BK/settings.json" "harness-settings plain uninstall PRESERVED the backups (revert path)"
assert_empty "$(cat "$LOG" 2>/dev/null)" "harness-settings plain uninstall touched no deps"
: > "$LOG"
env HARNESS_BACKUP_ROOT="$SB/hsbackups" "$T/harness-settings/uninstall.sh" --deps >/dev/null 2>&1
assert_contains "$LOG" "uninstall jq" "harness-settings --deps removed jq (brew seam)"
assert_contains "$LOG" "pip uninstall -y tomlkit" "harness-settings --deps removed tomlkit (python seam)"
assert_file "$BK/settings.json" "harness-settings --deps STILL preserved the backups"

# ---- RED ----
red "an unknown flag is refused by every uninstaller (via shared uc_parse)" 64 "unknown flag" "$T/ambrosio/uninstall.sh" --wat

finish
