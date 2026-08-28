#!/usr/bin/env bash

set -uo pipefail

read -r total_kib available_kib buffers_kib cached_kib reclaimable_kib shared_kib swap_total_kib swap_free_kib < <(
    awk '
        /^MemTotal:/ { total = $2 }
        /^MemAvailable:/ { available = $2 }
        /^Buffers:/ { buffers = $2 }
        /^Cached:/ { cached = $2 }
        /^SReclaimable:/ { reclaimable = $2 }
        /^Shmem:/ { shared = $2 }
        /^SwapTotal:/ { swap_total = $2 }
        /^SwapFree:/ { swap_free = $2 }
        END {
            print total + 0, available + 0, buffers + 0, cached + 0,
                reclaimable + 0, shared + 0, swap_total + 0, swap_free + 0
        }
    ' /proc/meminfo
)

if (( total_kib <= 0 )); then
    jq -cn '{text:"—", tooltip:"Memory information unavailable"}'
    exit 0
fi

used_kib=$((total_kib - available_kib))
cache_kib=$((buffers_kib + cached_kib + reclaimable_kib - shared_kib))
swap_used_kib=$((swap_total_kib - swap_free_kib))
(( used_kib < 0 )) && used_kib=0
(( cache_kib < 0 )) && cache_kib=0
(( swap_used_kib < 0 )) && swap_used_kib=0

usage=$((used_kib * 100 / total_kib))
if (( swap_total_kib > 0 )); then
    swap_usage=$((swap_used_kib * 100 / swap_total_kib))
else
    swap_usage=0
fi

pressure_10=$(awk '
    /^some / {
        for (field = 2; field <= NF; field++) {
            if ($field ~ /^avg10=/) {
                split($field, value, "=")
                print value[2]
                exit
            }
        }
    }
' /proc/pressure/memory 2>/dev/null)
pressure_10=${pressure_10:-0}

total_bytes=$((total_kib * 1024))
used_bytes=$((used_kib * 1024))
available_bytes=$((available_kib * 1024))
cache_bytes=$((cache_kib * 1024))
swap_total_bytes=$((swap_total_kib * 1024))
swap_used_bytes=$((swap_used_kib * 1024))

format_gib() {
    awk -v kib="$1" 'BEGIN { printf "%.1f", kib / 1048576 }'
}

total_gib=$(format_gib "$total_kib")
used_gib=$(format_gib "$used_kib")
available_gib=$(format_gib "$available_kib")
cache_gib=$(format_gib "$cache_kib")

process_lines=$(ps -eo pid=,comm=,rss= --sort=-rss 2>/dev/null \
    | awk -v self_pid="$$" -v parent_pid="$PPID" -v total_kib="$total_kib" '
        $1 != self_pid && $1 != parent_pid && shown < 5 {
            pid = $1
            rss = $NF
            name = $2
            for (field = 3; field <= NF - 1; field++)
                name = name " " $field
            usage = total_kib > 0 ? 100 * rss / total_kib : 0
            printf "%s\t%s\t%s\t%.1f\n", pid, name, rss * 1024, usage
            shown++
        }
    ')
processes_json=$(printf '%s\n' "$process_lines" | jq -Rn '[
    inputs
    | select(length > 0)
    | split("\t")
    | {
        pid: (.[0] | tonumber),
        name: .[1],
        rssBytes: (.[2] | tonumber),
        usage: (.[3] | tonumber)
    }
]')

tooltip=$(printf 'Memory: %s / %s GiB\nAvailable: %s GiB\nReclaimable cache: %s GiB' \
    "$used_gib" "$total_gib" "$available_gib" "$cache_gib")

jq -cn \
    --arg text "$usage" \
    --arg tooltip "$tooltip" \
    --argjson usage "$usage" \
    --argjson totalBytes "$total_bytes" \
    --argjson usedBytes "$used_bytes" \
    --argjson availableBytes "$available_bytes" \
    --argjson cacheBytes "$cache_bytes" \
    --argjson swapTotalBytes "$swap_total_bytes" \
    --argjson swapUsedBytes "$swap_used_bytes" \
    --argjson swapUsage "$swap_usage" \
    --argjson pressure10 "$pressure_10" \
    --argjson processes "$processes_json" \
    '{
        text: $text,
        tooltip: $tooltip,
        usage: $usage,
        totalBytes: $totalBytes,
        usedBytes: $usedBytes,
        availableBytes: $availableBytes,
        cacheBytes: $cacheBytes,
        swapTotalBytes: $swapTotalBytes,
        swapUsedBytes: $swapUsedBytes,
        swapUsage: $swapUsage,
        pressure10: $pressure10,
        processes: $processes
    }'
