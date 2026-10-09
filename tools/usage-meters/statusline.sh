#!/bin/bash
#
# Claude Code status line: current directory, plus remaining 5-hour session and
# 7-day weekly subscription usage as colored bars.
#
# Installed per repo as .astra/usage-meters/statusline.sh by
# tools/usage-meters/install.sh. Edit the copy in astra, not the installed
# one; the repo's post-commit hook keeps the installed copy current.
#
# Input schema: https://code.claude.com/docs/en/statusline

set -u

readonly BAR_CELLS=20
# Two usage segments side by side need roughly this many columns; narrower
# terminals get one segment per line so nothing is truncated.
readonly SIDE_BY_SIDE_MIN_COLUMNS=136
readonly FIELD_SEPARATOR=$'\x1f'

readonly COLOR_RESET=$'\033[0m'
readonly COLOR_BOLD=$'\033[1m'
readonly COLOR_DIM_GRAY=$'\033[38;5;240m'
readonly COLOR_CHECK_GREEN=$'\033[2;32m'
readonly COLOR_PLENTY=$'\033[32m'
readonly COLOR_LOW=$'\033[33m'
readonly COLOR_CRITICAL=$'\033[31m'

if ! command -v jq >/dev/null 2>&1; then
    printf '%sstatusline: jq is not installed%s\n' "$COLOR_CRITICAL" "$COLOR_RESET"
    exit 0
fi

input=$(cat)

# rate_limits and each window inside it can be absent (before the first API
# response, for non-subscribers, or after a window's resets_at passes), so
# missing values come through as empty fields rather than numbers.
# A non-whitespace separator keeps `read` from collapsing empty fields.
IFS="$FIELD_SEPARATOR" read -r current_dir session_remaining session_reset_time week_remaining week_reset_time < <(
    jq -r --arg separator "$FIELD_SEPARATOR" '
        def remaining_percent($window):
            if $window.used_percentage == null then ""
            else (100 - $window.used_percentage) | if . < 0 then 0 elif . > 100 then 100 else . end | floor
            end;
        def local_reset_time($window):
            if $window.resets_at == null then ""
            else $window.resets_at | localtime | strftime("%a %b %-d %-I:%M%p") | sub("AM$"; "am") | sub("PM$"; "pm")
            end;
        [
            (.workspace.current_dir // ""),
            remaining_percent(.rate_limits.five_hour),
            local_reset_time(.rate_limits.five_hour),
            remaining_percent(.rate_limits.seven_day),
            local_reset_time(.rate_limits.seven_day)
        ] | map(tostring) | join($separator)
    ' <<<"$input"
)

color_for_remaining() {
    local remaining=$1
    if ((remaining >= 50)); then
        printf '%s' "$COLOR_PLENTY"
    elif ((remaining >= 20)); then
        printf '%s' "$COLOR_LOW"
    else
        printf '%s' "$COLOR_CRITICAL"
    fi
}

repeat_character() {
    local character=$1 count=$2 index
    for ((index = 0; index < count; index++)); do
        printf '%s' "$character"
    done
}

render_usage_segment() {
    local label=$1 remaining=$2 reset_time=$3
    if [[ -z "$remaining" ]]; then
        printf '%s%s%s %sno data yet%s' "$COLOR_BOLD" "$label" "$COLOR_RESET" "$COLOR_DIM_GRAY" "$COLOR_RESET"
        return
    fi

    local filled_cells=$(((remaining * BAR_CELLS + 50) / 100))
    local empty_cells=$((BAR_CELLS - filled_cells))
    local color
    color=$(color_for_remaining "$remaining")

    printf '%s%s%s %s%s%s%s%s %s%3d%% left%s' \
        "$COLOR_BOLD" "$label" "$COLOR_RESET" \
        "$color" "$(repeat_character '█' "$filled_cells")" \
        "$COLOR_DIM_GRAY" "$(repeat_character '░' "$empty_cells")" "$COLOR_RESET" \
        "$color" "$remaining" "$COLOR_RESET"
    if [[ -n "$reset_time" ]]; then
        printf ' %s· resets %s%s' "$COLOR_DIM_GRAY" "$reset_time" "$COLOR_RESET"
    fi
}

printf '%s√%s %s%s%s%s\n' "$COLOR_CHECK_GREEN" "$COLOR_RESET" "$COLOR_BOLD" "$COLOR_DIM_GRAY" "$(basename "$current_dir")" "$COLOR_RESET"

session_segment=$(render_usage_segment "Session" "$session_remaining" "$session_reset_time")
week_segment=$(render_usage_segment "Week   " "$week_remaining" "$week_reset_time")

if ((${COLUMNS:-0} >= SIDE_BY_SIDE_MIN_COLUMNS)); then
    printf '%s    %s\n' "$session_segment" "$week_segment"
else
    printf '%s\n%s\n' "$session_segment" "$week_segment"
fi
