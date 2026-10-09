#!/bin/bash
#
# Qwen Code status line: current directory, then the context size and this
# session's non-cache-read tokens. It is the Qwen Code counterpart of
# statusline.sh, which shows subscription limits that Qwen Code does not report.
#
# Installed per repo as .astra/usage-meters/statusline-qwen.sh by
# tools/usage-meters/install.sh. Edit the copy in astra, not the installed one;
# the repo's post-commit hook keeps the installed copy current.
#
# Input schema: Qwen Code's docs/features/status-line.md ("JSON input").
# Qwen Code shows at most two lines of this output.

set -u

readonly FIELD_SEPARATOR=$'\x1f'

readonly COLOR_RESET=$'\033[0m'
readonly COLOR_BOLD=$'\033[1m'
readonly COLOR_DIM_GRAY=$'\033[38;5;240m'
readonly COLOR_CHECK_GREEN=$'\033[2;32m'
readonly COLOR_CRITICAL=$'\033[31m'
readonly GROUP_GAP='    '

if ! command -v jq >/dev/null 2>&1; then
    printf '%sstatusline: jq is not installed%s\n' "$COLOR_CRITICAL" "$COLOR_RESET"
    exit 0
fi

input=$(cat)

# Qwen Code counts a request's prompt with its cached part included, and its
# completion with its reasoning included (thoughts is a subset of completion for
# OpenAI-compatible providers), so non-cache-read tokens are prompt - cached + completion.
# context_window.current_usage is 0 until the first response; that shows as a dash.
IFS="$FIELD_SEPARATOR" read -r current_dir context_tokens session_tokens < <(
    jq -r --arg separator "$FIELD_SEPARATOR" '
        def non_cache_read:
            [(.metrics.models // {})[] | .tokens | (.prompt // 0) - (.cached // 0) + (.completion // 0)] | add // 0;
        [
            (.workspace.current_dir // ""),
            ((.context_window.current_usage // 0) | floor),
            (non_cache_read | floor)
        ] | map(tostring) | join($separator)
    ' <<<"$input"
)

# Compact token count, as the Claude Code plugin shows it: 950, 134k, 2.98M.
format_tokens() {
    local count=$1
    if ((count < 1000)); then
        printf '%d' "$count"
    elif ((count < 1000000)); then
        printf '%dk' $(((count + 500) / 1000))
    else
        local hundredths=$(((count + 5000) / 10000))
        printf '%d.%02dM' $((hundredths / 100)) $((hundredths % 100))
    fi
}

format_or_dash() {
    if (($1 > 0)); then format_tokens "$1"; else printf '–'; fi
}

printf '%s√%s %s%s%s%s\n' "$COLOR_CHECK_GREEN" "$COLOR_RESET" "$COLOR_BOLD" "$COLOR_DIM_GRAY" "$(basename "$current_dir")" "$COLOR_RESET"
printf '%sContext%s %s%s%sNCR tok%s %s %sthis session%s\n' \
    "$COLOR_BOLD" "$COLOR_RESET" "$(format_or_dash "$context_tokens")" "$GROUP_GAP" \
    "$COLOR_BOLD" "$COLOR_RESET" "$(format_or_dash "$session_tokens")" "$COLOR_DIM_GRAY" "$COLOR_RESET"
