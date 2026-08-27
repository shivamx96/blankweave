#!/usr/bin/env bash

set -u

interface=$(ip route show default 2>/dev/null | awk 'NR == 1 { print $5 }')

if [[ -z $interface || ! -d /sys/class/net/$interface ]]; then
    jq -cn '{icon:"󰤭", text:"Offline", tooltip:"No network connection", kind:"disconnected", interface:"", connection:"", ip:"", gateway:"", download:"0 B/s", upload:"0 B/s"}'
    exit 0
fi

rx_file="/sys/class/net/$interface/statistics/rx_bytes"
tx_file="/sys/class/net/$interface/statistics/tx_bytes"
rx=$(<"$rx_file")
tx=$(<"$tx_file")
now=$(date +%s)

runtime_dir=${XDG_RUNTIME_DIR:-/tmp}
state_file="$runtime_dir/hyprarch-network-${UID}-${interface}"
previous_time=$now
previous_rx=$rx
previous_tx=$tx
down_rate=0
up_rate=0

if [[ -r $state_file ]]; then
    read -r previous_time previous_rx previous_tx down_rate up_rate < "$state_file" || true
fi

elapsed=$((now - previous_time))
if (( elapsed >= 2 )); then
    down_rate=$(((rx - previous_rx) / elapsed))
    up_rate=$(((tx - previous_tx) / elapsed))
    (( down_rate < 0 )) && down_rate=0
    (( up_rate < 0 )) && up_rate=0

    # Each monitor owns a bar instance. Keep a reusable result so near-simultaneous
    # pollers report the same rate instead of overwriting the sample with zero.
    state_tmp="${state_file}.$$"
    printf '%s %s %s %s %s\n' "$now" "$rx" "$tx" "$down_rate" "$up_rate" > "$state_tmp"
    mv -f "$state_tmp" "$state_file"
fi

format_rate() {
    local bytes=$1

    if (( bytes >= 1048576 )); then
        awk -v value="$bytes" 'BEGIN { printf "%.1fM", value / 1048576 }'
    elif (( bytes >= 1024 )); then
        awk -v value="$bytes" 'BEGIN { printf "%.0fK", value / 1024 }'
    else
        printf '%dB' "$bytes"
    fi
}

down=$(format_rate "$down_rate")
up=$(format_rate "$up_rate")
ip_address=$(ip -4 -o address show dev "$interface" scope global 2>/dev/null | awk 'NR == 1 { sub(/\/.*/, "", $4); print $4 }')
connection=$(nmcli -g GENERAL.CONNECTION device show "$interface" 2>/dev/null | head -n 1)

if [[ -d /sys/class/net/$interface/wireless ]]; then
    icon="󰤨"
    kind="wifi"
    signal=$(nmcli -t -f active,signal device wifi 2>/dev/null | awk -F: '$1 == "yes" { print $2; exit }')
    detail="Wi-Fi: ${connection:-Unknown}"$'\n'"Interface: $interface"
    [[ -n ${signal:-} ]] && detail+=$'\n'"Signal: ${signal}%"
else
    icon=""
    kind="ethernet"
    detail="Ethernet: ${connection:-Connected}"$'\n'"Interface: $interface"
fi

[[ -n ${ip_address:-} ]] && detail+=$'\n'"IP: $ip_address"
detail+=$'\n'"Download: ${down}/s · Upload: ${up}/s"
gateway=$(ip route show default dev "$interface" 2>/dev/null | awk 'NR == 1 { print $3 }')

jq -cn \
    --arg icon "$icon" \
    --arg text "↓${down} ↑${up}" \
    --arg tooltip "$detail" \
    --arg kind "$kind" \
    --arg interface "$interface" \
    --arg connection "${connection:-}" \
    --arg ip "${ip_address:-}" \
    --arg gateway "${gateway:-}" \
    --arg download "${down}/s" \
    --arg upload "${up}/s" \
    '{icon:$icon, text:$text, tooltip:$tooltip, kind:$kind, interface:$interface, connection:$connection, ip:$ip, gateway:$gateway, download:$download, upload:$upload}'
