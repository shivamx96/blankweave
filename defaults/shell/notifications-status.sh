#!/usr/bin/env bash

set -uo pipefail

empty_status() {
    local message=${1:-}
    jq -cn --arg error "$message" '{
        available:false,
        paused:false,
        displayedCount:0,
        waitingCount:0,
        historyCount:0,
        error:$error,
        notifications:[]
    }'
}

if ! command -v dunstctl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    empty_status 'Dunst notification controls are unavailable'
    exit 0
fi

if ! history_payload=$(dunstctl history 2>/dev/null) \
    || ! jq -e '.data[0] | type == "array"' >/dev/null 2>&1 <<< "$history_payload"; then
    empty_status 'Could not read Dunst notification history'
    exit 0
fi

paused=false
if [ "$(dunstctl is-paused 2>/dev/null || printf false)" = true ]; then
    paused=true
fi

displayed_count=$(dunstctl count displayed 2>/dev/null || printf 0)
waiting_count=$(dunstctl count waiting 2>/dev/null || printf 0)
history_count=$(dunstctl count history 2>/dev/null || printf 0)

jq -cn \
    --argjson history "$history_payload" \
    --argjson paused "$paused" \
    --argjson displayedCount "${displayed_count:-0}" \
    --argjson waitingCount "${waiting_count:-0}" \
    --argjson historyCount "${history_count:-0}" '
    def field($name; $fallback):
        (.[$name].data // $fallback);
    def plain:
        tostring
        | gsub("<[^>]*>"; "")
        | gsub("[\\r\\n\\t]+"; " ")
        | gsub("  +"; " ")
        | ltrimstr(" ")
        | rtrimstr(" ");

    {
        available:true,
        paused:$paused,
        displayedCount:$displayedCount,
        waitingCount:$waitingCount,
        historyCount:$historyCount,
        error:"",
        notifications:[
            ($history.data[0] // [])[]
            | {
                id:(field("id"; 0) | tonumber),
                appName:(field("appname"; "Application") | plain),
                title:(field("summary"; "Notification") | plain),
                body:(field("body"; "") | plain),
                iconPath:(field("icon_path"; "") | tostring),
                urgency:(field("urgency"; "NORMAL") | ascii_downcase),
                category:(field("category"; "") | tostring),
                url:(field("urls"; "") | tostring)
            }
        ]
    }
'
