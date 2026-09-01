#!/usr/bin/env bash

set -uo pipefail

detail_mode=${1:-summary}

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

emit_nvidia() {
    local raw index name driver usage memory_usage temperature memory_used_mib
    local memory_total_mib power_draw power_limit clock_mhz max_clock_mhz fan_percent pstate
    local processes_json process_lines tooltip

    raw=$(nvidia-smi \
        --query-gpu=index,name,driver_version,utilization.gpu,utilization.memory,temperature.gpu,memory.used,memory.total,power.draw,power.limit,clocks.current.graphics,clocks.max.graphics,fan.speed,pstate \
        --format=csv,noheader,nounits 2>/dev/null | sed -n '1p')
    [[ -n "$raw" ]] || return 1

    IFS=',' read -r index name driver usage memory_usage temperature memory_used_mib \
        memory_total_mib power_draw power_limit clock_mhz max_clock_mhz fan_percent pstate <<< "$raw"
    index=$(trim "$index")
    name=$(trim "$name")
    driver=$(trim "$driver")
    usage=$(trim "$usage")
    memory_usage=$(trim "$memory_usage")
    temperature=$(trim "$temperature")
    memory_used_mib=$(trim "$memory_used_mib")
    memory_total_mib=$(trim "$memory_total_mib")
    power_draw=$(trim "$power_draw")
    power_limit=$(trim "$power_limit")
    clock_mhz=$(trim "$clock_mhz")
    max_clock_mhz=$(trim "$max_clock_mhz")
    fan_percent=$(trim "$fan_percent")
    pstate=$(trim "$pstate")

    processes_json='[]'
    if [[ "$detail_mode" == detail ]]; then
        process_lines=$(nvidia-smi pmon -i "$index" -c 1 -s um 2>/dev/null \
            | awk -v gpu_index="$index" '
                $1 !~ /^#/ && $1 == gpu_index && $2 ~ /^[0-9]+$/ {
                    sm = $4 == "-" ? "" : $4
                    framebuffer = $10 == "-" ? 0 : $10
                    printf "%s\t%s\t%.0f\t%s\n", $2, $12, framebuffer * 1048576, sm
                }
            ' \
            | sort -t $'\t' -k3,3nr \
            | sed -n '1,5p')
        processes_json=$(printf '%s\n' "$process_lines" | jq -Rn '[
            inputs
            | select(length > 0)
            | split("\t")
            | {
                pid: (.[0] | tonumber),
                name: .[1],
                memoryBytes: (.[2] | tonumber),
                usage: (.[3] | if length > 0 then tonumber else null end)
            }
        ]')
    fi

    tooltip=$(printf '%s: %s%%\nTemperature: %s°C\nVRAM: %.1f / %.1f GiB' \
        "$name" "$usage" "$temperature" \
        "$(awk -v mib="$memory_used_mib" 'BEGIN { print mib / 1024 }')" \
        "$(awk -v mib="$memory_total_mib" 'BEGIN { print mib / 1024 }')")

    jq -cn \
        --arg text "$usage" \
        --arg tooltip "$tooltip" \
        --arg backend "nvidia" \
        --arg vendor "NVIDIA" \
        --arg name "$name" \
        --arg driver "$driver" \
        --arg usage "$usage" \
        --arg memoryUsage "$memory_usage" \
        --arg temperature "$temperature" \
        --arg memoryUsedMiB "$memory_used_mib" \
        --arg memoryTotalMiB "$memory_total_mib" \
        --arg powerDraw "$power_draw" \
        --arg powerLimit "$power_limit" \
        --arg clockMHz "$clock_mhz" \
        --arg maxClockMHz "$max_clock_mhz" \
        --arg fanPercent "$fan_percent" \
        --arg performanceState "$pstate" \
        --arg detailMode "$detail_mode" \
        --argjson processes "$processes_json" \
        '{
            available: true,
            detailed: ($detailMode == "detail"),
            text: $text,
            tooltip: $tooltip,
            backend: $backend,
            vendor: $vendor,
            name: $name,
            driver: $driver,
            accuracy: "live",
            usage: ($usage | tonumber),
            memoryUsage: ($memoryUsage | tonumber),
            temperature: ($temperature | if . == "N/A" or . == "" then null else tonumber end),
            memoryUsedBytes: ($memoryUsedMiB | tonumber * 1048576),
            memoryTotalBytes: ($memoryTotalMiB | tonumber * 1048576),
            powerDrawWatts: ($powerDraw | if . == "N/A" or . == "" then null else tonumber end),
            powerLimitWatts: ($powerLimit | if . == "N/A" or . == "" then null else tonumber end),
            clockMHz: ($clockMHz | if . == "N/A" or . == "" then null else tonumber end),
            maxClockMHz: ($maxClockMHz | if . == "N/A" or . == "" then null else tonumber end),
            fanPercent: ($fanPercent | if . == "N/A" or . == "" then null else tonumber end),
            performanceState: $performanceState,
            idlePercent: null,
            engines: [
                {name: "Graphics", usage: ($usage | tonumber)},
                {name: "Memory controller", usage: ($memoryUsage | tonumber)}
            ],
            processes: $processes
        }'
}

intel_card() {
    local vendor_file
    for vendor_file in /sys/class/drm/card*/device/vendor; do
        [[ -r "$vendor_file" ]] || continue
        if [[ "$(<"$vendor_file")" == "0x8086" ]]; then
            dirname "$(dirname "$vendor_file")"
            return 0
        fi
    done
    return 1
}

intel_frequency_file() {
    local card="$1" kind="$2" candidate
    local -a candidates

    if [[ "$kind" == current ]]; then
        candidates=(
            "$card/gt/gt0/rps_cur_freq_mhz"
            "$card/device/gt/gt0/rps_cur_freq_mhz"
            "$card/device/tile0/gt0/freq0/cur_freq"
            "$card/device/tile0/gt0/freq0/act_freq"
        )
    else
        candidates=(
            "$card/gt/gt0/rps_max_freq_mhz"
            "$card/device/gt/gt0/rps_max_freq_mhz"
            "$card/device/tile0/gt0/freq0/max_freq"
            "$card/device/tile0/gt0/freq0/rp0_freq"
        )
    fi

    for candidate in "${candidates[@]}"; do
        if [[ -r "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

intel_temperature() {
    local card="$1" input
    for input in "$card"/device/hwmon/hwmon*/temp1_input; do
        [[ -r "$input" ]] || continue
        awk -v raw="$(<"$input")" 'BEGIN { printf "%.0f", raw / 1000 }'
        return 0
    done
    return 1
}

emit_intel() {
    local card card_name pci_address pci_line name driver raw sample engines_json clients_json
    local usage frequency_mhz max_frequency_mhz temperature power_draw idle_percent accuracy
    local memory_used_bytes tooltip current_frequency_file max_frequency_file

    card=$(intel_card) || return 1
    card_name=$(basename "$card")
    pci_address=$(basename "$(readlink -f "$card/device")")
    pci_line=$(lspci -D -s "$pci_address" 2>/dev/null | sed -n '1p')
    name=${pci_line#*: }
    [[ -n "$name" && "$name" != "$pci_line" ]] || name="Intel integrated graphics"
    driver=$(basename "$(readlink -f "$card/device/driver" 2>/dev/null)" 2>/dev/null || true)
    [[ -n "$driver" ]] || driver="Intel DRM"

    raw=""
    if command -v intel_gpu_top >/dev/null 2>&1; then
        raw=$(timeout -s INT -k 1s 4s intel_gpu_top \
            -J -s 450 -n 2 -o - -d "drm:/dev/dri/${card_name}" 2>/dev/null || true)
    fi
    sample=$(printf '%s' "$raw" | jq -c '
        if type == "array" then
            (map(select(type == "object")) | last // {})
        elif type == "object" then .
        else {} end
    ' 2>/dev/null || printf '{}')

    engines_json=$(printf '%s' "$sample" | jq -c '
        [(.engines // {}) | to_entries[]
            | {
                name: (.key | sub("/[0-9]+$"; "")),
                usage: ((.value.busy // 0) | tonumber)
            }
        ]
        | group_by(.name)
        | map({
            name: .[0].name,
            usage: ([.[].usage] | max // 0 | if . > 100 then 100 else . end)
        })
    ' 2>/dev/null || printf '[]')
    usage=$(printf '%s' "$engines_json" | jq -r '[.[].usage] | max // empty')
    frequency_mhz=$(printf '%s' "$sample" | jq -r '
        (.frequency.actual // .["frequency-gt0"].actual // empty)
    ' 2>/dev/null)
    power_draw=$(printf '%s' "$sample" | jq -r '.power.GPU // empty' 2>/dev/null)
    idle_percent=$(printf '%s' "$sample" | jq -r '
        (.rc6.value // .["rc6-gt0"].value // empty)
    ' 2>/dev/null)

    accuracy="live"
    if [[ -z "$usage" ]]; then
        accuracy="frequency-estimate"
        current_frequency_file=$(intel_frequency_file "$card" current 2>/dev/null || true)
        max_frequency_file=$(intel_frequency_file "$card" max 2>/dev/null || true)
        frequency_mhz=0
        max_frequency_mhz=0
        [[ -n "$current_frequency_file" ]] && frequency_mhz=$(<"$current_frequency_file")
        [[ -n "$max_frequency_file" ]] && max_frequency_mhz=$(<"$max_frequency_file")
        if [[ -r "$card/device/gpu_busy_percent" ]]; then
            usage=$(<"$card/device/gpu_busy_percent")
            accuracy="live"
        elif (( max_frequency_mhz > 0 )); then
            usage=$(awk -v current="$frequency_mhz" -v maximum="$max_frequency_mhz" '
                BEGIN {
                    value = 100 * current / maximum
                    if (value < 0) value = 0
                    if (value > 100) value = 100
                    printf "%.0f", value
                }
            ')
        else
            usage=0
            accuracy="unavailable"
        fi
        engines_json='[]'
    else
        max_frequency_file=$(intel_frequency_file "$card" max 2>/dev/null || true)
        max_frequency_mhz=0
        [[ -n "$max_frequency_file" ]] && max_frequency_mhz=$(<"$max_frequency_file")
    fi

    temperature=$(intel_temperature "$card" 2>/dev/null || true)
    clients_json='[]'
    memory_used_bytes=0
    if [[ "$detail_mode" == detail && "$sample" != '{}' ]]; then
        clients_json=$(printf '%s' "$sample" | jq -c '
            [(.clients // {}) | to_entries[] | .value
                | {
                    pid: ((.pid // "0") | tonumber),
                    name: (.name // "GPU client"),
                    memoryBytes: (
                        ((.memory.system.resident // "0") | tonumber)
                        + ((.memory.local.resident // "0") | tonumber)
                    ),
                    usage: (
                        [(."engine-classes" // {})[]?.busy | tonumber]
                        | max // 0
                        | if . > 100 then 100 else . end
                    )
                }
            ]
            | sort_by([-.usage, -.memoryBytes])
            | .[:5]
        ' 2>/dev/null || printf '[]')
        memory_used_bytes=$(printf '%s' "$clients_json" | jq -r '[.[].memoryBytes] | add // 0')
    fi

    tooltip=$(printf '%s: %s%%\nClock: %s MHz\nTelemetry: %s' \
        "$name" "$usage" "${frequency_mhz:-0}" \
        "$([[ "$accuracy" == live ]] && printf 'engine busy' || printf 'frequency estimate')")

    jq -cn \
        --arg text "$(awk -v value="$usage" 'BEGIN { printf "%.0f", value }')" \
        --arg tooltip "$tooltip" \
        --arg backend "intel" \
        --arg vendor "Intel" \
        --arg name "$name" \
        --arg driver "$driver" \
        --arg accuracy "$accuracy" \
        --arg usage "$usage" \
        --arg temperature "$temperature" \
        --arg frequencyMHz "${frequency_mhz:-}" \
        --arg maxFrequencyMHz "${max_frequency_mhz:-}" \
        --arg powerDraw "${power_draw:-}" \
        --arg idlePercent "${idle_percent:-}" \
        --arg detailMode "$detail_mode" \
        --argjson memoryUsedBytes "$memory_used_bytes" \
        --argjson engines "$engines_json" \
        --argjson processes "$clients_json" \
        '{
            available: true,
            detailed: ($detailMode == "detail"),
            text: $text,
            tooltip: $tooltip,
            backend: $backend,
            vendor: $vendor,
            name: $name,
            driver: $driver,
            accuracy: $accuracy,
            usage: ($usage | tonumber),
            memoryUsage: null,
            temperature: ($temperature | if length > 0 then tonumber else null end),
            memoryUsedBytes: $memoryUsedBytes,
            memoryTotalBytes: 0,
            powerDrawWatts: ($powerDraw | if length > 0 then tonumber else null end),
            powerLimitWatts: null,
            clockMHz: ($frequencyMHz | if length > 0 then tonumber else null end),
            maxClockMHz: ($maxFrequencyMHz | if length > 0 then tonumber else null end),
            fanPercent: null,
            performanceState: "",
            idlePercent: ($idlePercent | if length > 0 then tonumber else null end),
            engines: $engines,
            processes: $processes
        }'
}

amd_card() {
    local vendor_file
    for vendor_file in /sys/class/drm/card*/device/vendor; do
        [[ -r $vendor_file ]] || continue
        if [[ $(<"$vendor_file") == 0x1002 ]]; then
            dirname "$(dirname "$vendor_file")"
            return 0
        fi
    done
    return 1
}

emit_amd() {
    local card pci_address pci_line name driver usage temperature memory_used memory_total
    local memory_usage frequency_mhz tooltip input

    card=$(amd_card) || return 1
    pci_address=$(basename "$(readlink -f "$card/device")")
    pci_line=$(lspci -D -s "$pci_address" 2>/dev/null | sed -n '1p')
    name=${pci_line#*: }
    [[ -n $name && $name != "$pci_line" ]] || name='AMD graphics'
    driver=$(basename "$(readlink -f "$card/device/driver" 2>/dev/null)" 2>/dev/null || true)
    [[ -n $driver ]] || driver=amdgpu

    usage=0
    [[ -r $card/device/gpu_busy_percent ]] && usage=$(<"$card/device/gpu_busy_percent")
    [[ $usage =~ ^[0-9]+([.][0-9]+)?$ ]] || usage=0
    memory_used=0
    memory_total=0
    [[ -r $card/device/mem_info_vram_used ]] && memory_used=$(<"$card/device/mem_info_vram_used")
    [[ -r $card/device/mem_info_vram_total ]] && memory_total=$(<"$card/device/mem_info_vram_total")
    [[ $memory_used =~ ^[0-9]+$ ]] || memory_used=0
    [[ $memory_total =~ ^[0-9]+$ ]] || memory_total=0
    memory_usage=0
    if (( memory_total > 0 )); then
        memory_usage=$(awk -v used="$memory_used" -v total="$memory_total" \
            'BEGIN { printf "%.1f", 100 * used / total }')
    fi

    temperature=
    for input in "$card"/device/hwmon/hwmon*/temp1_input; do
        [[ -r $input ]] || continue
        temperature=$(awk -v raw="$(<"$input")" 'BEGIN { printf "%.0f", raw / 1000 }')
        break
    done
    frequency_mhz=
    if [[ -r $card/device/pp_dpm_sclk ]]; then
        frequency_mhz=$(awk '$0 ~ /[*]/ { value=$2; gsub(/[^0-9.]/, "", value); print value; exit }' \
            "$card/device/pp_dpm_sclk")
    fi
    tooltip=$(printf '%s: %.0f%%\nTemperature: %s\nVRAM: %.1f / %.1f GiB' \
        "$name" "$usage" "${temperature:+$temperature°C}" \
        "$(awk -v bytes="$memory_used" 'BEGIN { print bytes / 1073741824 }')" \
        "$(awk -v bytes="$memory_total" 'BEGIN { print bytes / 1073741824 }')")

    jq -cn \
        --arg text "$(awk -v value="$usage" 'BEGIN { printf "%.0f", value }')" \
        --arg tooltip "$tooltip" \
        --arg name "$name" \
        --arg driver "$driver" \
        --arg usage "$usage" \
        --arg memoryUsage "$memory_usage" \
        --arg temperature "$temperature" \
        --arg frequencyMHz "$frequency_mhz" \
        --arg detailMode "$detail_mode" \
        --argjson memoryUsedBytes "$memory_used" \
        --argjson memoryTotalBytes "$memory_total" \
        '{
            available: true,
            detailed: ($detailMode == "detail"),
            text: $text,
            tooltip: $tooltip,
            backend: "amd",
            vendor: "AMD",
            name: $name,
            driver: $driver,
            accuracy: "live",
            usage: ($usage | tonumber),
            memoryUsage: ($memoryUsage | tonumber),
            temperature: ($temperature | if length > 0 then tonumber else null end),
            memoryUsedBytes: $memoryUsedBytes,
            memoryTotalBytes: $memoryTotalBytes,
            powerDrawWatts: null,
            powerLimitWatts: null,
            clockMHz: ($frequencyMHz | if length > 0 then tonumber else null end),
            maxClockMHz: null,
            fanPercent: null,
            performanceState: "",
            idlePercent: null,
            engines: [{name: "Graphics", usage: ($usage | tonumber)}],
            processes: []
        }'
}

if command -v nvidia-smi >/dev/null 2>&1 && emit_nvidia; then
    exit 0
fi

if emit_amd; then
    exit 0
fi

if emit_intel; then
    exit 0
fi

jq -cn '{
    available: false,
    detailed: false,
    text: "—",
    tooltip: "GPU telemetry unavailable",
    backend: "none",
    vendor: "",
    name: "Graphics processor",
    driver: "",
    accuracy: "unavailable",
    usage: 0,
    engines: [],
    processes: []
}'
