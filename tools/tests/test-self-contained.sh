#!/usr/bin/env bash
# test-self-contained.sh — astra must work on any Mac from this checkout alone
# (Jonathan, 2026-10-04). Fails on personal values or another machine's paths in
# tracked code: phone numbers, Tailnet hostnames, /Users/<name>/ paths, and
# paths into other projects, across the whole tracked tree. Prose records and comment
# lines are exempt, and so are the named exceptions below; nothing else is. Reserved 555 numbers and +1000... are test fixtures. Also checks lib/astra-config.sh, the one place
# personal values come from.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
. ./tools/tests/lib.sh 2>/dev/null || true
PASS=0; FAIL=0
# Named exceptions, each with its reason. Anything else that matches fails.
KNOWN='^agents-and-prompts/AGENTS\.md:'          # Drew's kit: his /Users/andrew imports; Jonathan's call (2026-10-04)
KNOWN="$KNOWN|^tools/tests/TESTING\.md:.*js-llmKicker/docs/TAUTOLOGY"          # provenance of the testing rules
ok(){ echo "  ok:   $1"; PASS=$((PASS+1)); }; bad(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# The whole tracked tree. Exempt only prose records (notes/, docs/, READMEs, top-level
# .md history, past panel output), the vendored submodule, and astra's own manifest,
# whose recorded source path is by design (astra-update falls back to a verified sibling).
hits="$(git ls-files \
  | grep -vE '^(notes|docs|vendor)/|^tools/tool-templates/(colloquium|facts)/|(^|/)README[^/]*$|^[A-Za-z0-9_-]+\.md$|^\.astra/manifest\.json$|^tools/tests/test-self-contained\.sh$' \
  | xargs grep -nIE '\+1[0-9]{10}|[a-z0-9-]+\.tail[0-9a-f]{6}\.ts\.net|/Users/[a-z][a-z0-9_-]*/|js-project-GhOST/|js-llmKicker/' 2>/dev/null \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
  | grep -vE '\+1555[0-9]{7}|\+10000000000' \
  | grep -vE "$KNOWN" )"
if [ -z "$hits" ]; then ok "no personal values or foreign paths in tracked code"
else bad "personal values or foreign paths in tracked code:"; echo "$hits" | sed 's/^/        /' | cut -c1-180; fi

cfg="$(mktemp)"; printf 'ASTRA_PEER_HOST="peer.example"  # comment\nASTRA_NOTIFY_PHONE="+15550000000"\n' > "$cfg"
r="$(ASTRA_CONFIG_FILE="$cfg" bash -c '. tools/lib/astra-config.sh; astra_config ASTRA_PEER_HOST')"
[ "$r" = "peer.example" ] && ok "config reader strips quotes and comments (bash)" || bad "bash reader returned '$r'"
if command -v zsh >/dev/null; then
  r="$(ASTRA_CONFIG_FILE="$cfg" zsh -c '. tools/lib/astra-config.sh; astra_config ASTRA_NOTIFY_PHONE')"
  [ "$r" = "+15550000000" ] && ok "config reader works when sourced by zsh" || bad "zsh reader returned '$r'"
fi
r="$(ASTRA_CONFIG_FILE="$cfg" ASTRA_PEER_HOST=override bash -c '. tools/lib/astra-config.sh; astra_config ASTRA_PEER_HOST')"
[ "$r" = "override" ] && ok "environment overrides the file" || bad "env override returned '$r'"
ASTRA_CONFIG_FILE="$cfg" bash -c '. tools/lib/astra-config.sh; astra_config_required ASTRA_LMS_HOST' 2>/dev/null \
  && bad "a missing required key did not fail" || ok "a missing required key fails"
rm -f "$cfg"
echo "== test-self-contained.sh: $PASS ok, $FAIL failed"
[ "$FAIL" -eq 0 ]
