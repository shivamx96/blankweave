#!/usr/bin/env bash

set -u

lookup_dir=$(mktemp -d)
trap 'rm -rf -- "$lookup_dir"' EXIT

lookup() {
    local family=$1
    local url=$2
    local destination=$3

    curl "-$family" \
        --silent \
        --fail \
        --connect-timeout 2 \
        --max-time 4 \
        "$url" 2>/dev/null \
        | awk -F= '$1 == "ip" { print $2; exit }' \
        > "$destination" || true
}

lookup 4 'https://1.1.1.1/cdn-cgi/trace' "$lookup_dir/ipv4" &
ipv4_pid=$!
lookup 6 'https://[2606:4700:4700::1111]/cdn-cgi/trace' "$lookup_dir/ipv6" &
ipv6_pid=$!

wait "$ipv4_pid" || true
wait "$ipv6_pid" || true

ipv4=$(<"$lookup_dir/ipv4")
ipv6=$(<"$lookup_dir/ipv6")

jq -cn --arg ipv4 "$ipv4" --arg ipv6 "$ipv6" '{ipv4:$ipv4, ipv6:$ipv6}'
