#!/usr/bin/env bash

set -u

read -r total used available < <(free -b | awk '/^Mem:/ { print $2, $3, $7 }')

if [[ -z ${total:-} || $total -eq 0 ]]; then
    jq -cn '{text:"—", tooltip:"Memory information unavailable"}'
    exit 0
fi

percentage=$((used * 100 / total))
used_gib=$(awk -v bytes="$used" 'BEGIN { printf "%.1f", bytes / 1073741824 }')
total_gib=$(awk -v bytes="$total" 'BEGIN { printf "%.1f", bytes / 1073741824 }')
available_gib=$(awk -v bytes="$available" 'BEGIN { printf "%.1f", bytes / 1073741824 }')
tooltip=$(printf 'Memory: %s / %s GiB\nAvailable: %s GiB' "$used_gib" "$total_gib" "$available_gib")

jq -cn \
    --arg text "$percentage" \
    --arg tooltip "$tooltip" \
    '{text:$text, tooltip:$tooltip}'
