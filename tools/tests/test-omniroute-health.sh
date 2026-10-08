#!/usr/bin/env bash
# test-omniroute-health.sh — the health tool's own logic, against a stub endpoint.
#
# omniroute-health probes a live deployment, so its VERDICTS are not testable anywhere but there. What
# is testable is that it reports honestly: it refuses to run with nothing to probe, its RED control
# comes first and trips on a harness that cannot fail, and each probe it runs reads the endpoint's
# real answer. The stub serves only some of what the live service does, so the probes about the live
# service's quirks (hf/ dead, the small-max_tokens trap) must come back FAIL here; that is the check
# that those probes are not vacuous.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need curl "ships with macOS"; need jq "brew install jq"; need python3 "install python3"
HEALTH="$ASTRA_ROOT/tools/omniroute-health/omniroute-health"
export HOME="$SB/home"; mkdir -p "$HOME"
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME OMNIROUTE_API_KEY

red "no key anywhere: it refuses to run" 2 "no OmniRoute key" env OMNIROUTE_BASE=http://127.0.0.1:9 "$HEALTH"
red "an endpoint that is not answering: it refuses to run" 2 "is not answering" env OMNIROUTE_API_KEY=k OMNIROUTE_BASE=http://127.0.0.1:9 "$HEALTH"

python3 "$ASTRA_ROOT/tools/tests/stub_omniroute.py" --port-file "$SB/port" --model ollamacloud/glm-5.2 --no-listing ollamacloud/deepseek-v4-pro &
STUB=$!
trap 'kill "$STUB" 2>/dev/null; _lib_cleanup' EXIT
for _ in $(seq 1 30); do [ -s "$SB/port" ] && break; sleep 0.2; done
BASE="http://127.0.0.1:$(cat "$SB/port")"

OMNIROUTE_API_KEY=k OMNIROUTE_BASE="$BASE" "$HEALTH" >"$SB/h.out" 2>&1; rc=$?
assert_eq 1 "$rc" "against the stub it exits 1: the live-service probes cannot pass on a stub"
assert_contains "$SB/h.out" "RED control fails as it must" "the RED control ran first and passed"
assert_contains "$SB/h.out" "OmniRoute serves ollamacloud/glm-5.2" "a served model is reported as served"
assert_contains "$SB/h.out" "is in the catalog" "a listed model is found in the catalog"
assert_contains "$SB/h.out" "unlisted id ollamacloud/deepseek-v4-pro still serves" "an unlisted-but-serving model is not called dead"
assert_contains "$SB/h.out" "FAIL hf/ failed in an unexpected way" "the hf/ probe reads the real answer and does not pass by default"
finish
