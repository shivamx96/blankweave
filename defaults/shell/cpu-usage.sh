#!/usr/bin/env bash

set -uo pipefail

runtime_dir="${XDG_RUNTIME_DIR:-/tmp/blankweave-cpu-${UID}}"
state_file="$runtime_dir/blankweave-cpu-usage.state"
process_state_file="$runtime_dir/blankweave-cpu-processes.state"
current_file=$(mktemp "${runtime_dir}/blankweave-cpu-current.XXXXXX" 2>/dev/null || true)

if [[ -z "$current_file" ]]; then
    runtime_dir="/tmp/blankweave-cpu-${UID}"
    mkdir -p "$runtime_dir"
    chmod 700 "$runtime_dir"
    state_file="$runtime_dir/blankweave-cpu-usage.state"
    process_state_file="$runtime_dir/blankweave-cpu-processes.state"
    current_file=$(mktemp "${runtime_dir}/blankweave-cpu-current.XXXXXX")
fi
current_process_file=$(mktemp "${runtime_dir}/blankweave-cpu-processes.XXXXXX")

cleanup() {
    rm -f "$current_file" "$current_process_file"
}
trap cleanup EXIT

capture_cpu_ticks() {
    awk '
        /^cpu([0-9]+)? / {
            idle = $5 + $6
            total = 0
            for (field = 2; field <= 9; field++)
                total += $field
            print $1, total, idle
        }
    ' /proc/stat > "$1"
}

capture_process_ticks() {
    local stat_file stat_line process_id process_name process_parent fields

    : > "$1"
    for stat_file in /proc/[0-9]*/stat; do
        [[ -r "$stat_file" ]] || continue
        IFS= read -r stat_line < "$stat_file" || continue
        if [[ $stat_line =~ ^([0-9]+)\ \((.*)\)\ ([A-Za-z])\ (.*)$ ]]; then
            process_id=${BASH_REMATCH[1]}
            process_name=${BASH_REMATCH[2]//$'\t'/ }
            read -ra fields <<< "${BASH_REMATCH[4]}"
            process_parent=${fields[0]:-0}
            if [[ "$process_id" -eq "$$" || "$process_id" -eq "$PPID" || "$process_parent" -eq "$$" ]]; then
                continue
            fi
            printf '%s\t%s\t%s\t%s\n' \
                "$process_id" \
                "$(( ${fields[10]:-0} + ${fields[11]:-0} ))" \
                "${fields[20]:-0}" \
                "$process_name" >> "$1"
        fi
    done
}

capture_cpu_ticks "$current_file"
capture_process_ticks "$current_process_file"

if [[ ! -s "$state_file" || ! -s "$process_state_file" ]]; then
    install -m 600 "$current_file" "$state_file"
    install -m 600 "$current_process_file" "$process_state_file"
    sleep 0.12
    capture_cpu_ticks "$current_file"
    capture_process_ticks "$current_process_file"
fi

usage_lines=$(awk '
    NR == FNR {
        previous_total[$1] = $2
        previous_idle[$1] = $3
        next
    }
    {
        total_delta = $2 - previous_total[$1]
        idle_delta = $3 - previous_idle[$1]
        if (total_delta <= 0)
            usage = 0
        else
            usage = 100 * (total_delta - idle_delta) / total_delta
        if (usage < 0) usage = 0
        if (usage > 100) usage = 100
        printf "%s %.0f %.0f\n", $1, usage, total_delta
    }
' "$state_file" "$current_file")

usage=$(printf '%s\n' "$usage_lines" | awk 'NR == 1 { print $2 }')
total_tick_delta=$(printf '%s\n' "$usage_lines" | awk 'NR == 1 { print $3 }')
core_samples=$(while read -r cpu_name cpu_usage _; do
    [[ "$cpu_name" == cpu[0-9]* ]] || continue
    cpu_id=${cpu_name#cpu}
    topology_dir="/sys/devices/system/cpu/cpu${cpu_id}/topology"
    if [[ -r "$topology_dir/core_id" ]]; then
        core_id=$(<"$topology_dir/core_id")
    else
        core_id="$cpu_id"
    fi
    if [[ -r "$topology_dir/physical_package_id" ]]; then
        package_id=$(<"$topology_dir/physical_package_id")
    else
        package_id=0
    fi
    printf '%s:%s %s\n' "$package_id" "$core_id" "$cpu_usage"
done <<< "$usage_lines")
cores_json=$(printf '%s\n' "$core_samples" | awk '
    {
        key = $1
        if (!(key in seen)) {
            seen[key] = 1
            order[++count] = key
        }
        total[key] += $2
        siblings[key]++
    }
    END {
        for (position = 1; position <= count; position++) {
            key = order[position]
            printf "%.0f\n", total[key] / siblings[key]
        }
    }
' | jq -Rsc '
    split("\n")
    | map(select(length > 0) | tonumber)
')

model=$(awk -F ': *' '/^model name/ { print $2; exit }' /proc/cpuinfo)
model=${model//(R)/}
model=${model//(TM)/}
model=$(printf '%s' "$model" | tr -s ' ' | sed 's/^ //; s/ $//')

logical_cpus=$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '0')
physical_cores=$(lscpu -p=CORE,SOCKET 2>/dev/null \
    | awk -F, '!/^#/ { seen[$1 ":" $2] = 1 } END { print length(seen) }')
[[ -n "$physical_cores" ]] || physical_cores="$logical_cpus"

frequency_mhz=$(awk -F ': *' '
    /^cpu MHz/ { total += $2; count++ }
    END { if (count > 0) printf "%.0f", total / count }
' /proc/cpuinfo)
frequency_ghz=$(awk -v mhz="${frequency_mhz:-0}" 'BEGIN { printf "%.2f", mhz / 1000 }')

temperature=""
for hwmon in /sys/class/hwmon/hwmon*; do
    [[ -r "$hwmon/name" ]] || continue
    sensor_name=$(<"$hwmon/name")
    case "$sensor_name" in
        coretemp|k10temp|zenpower)
            preferred_input=""
            for label_file in "$hwmon"/temp*_label; do
                [[ -r "$label_file" ]] || continue
                label=$(<"$label_file")
                case "${label,,}" in
                    *package*|tctl|tdie)
                        preferred_input="${label_file%_label}_input"
                        break
                        ;;
                esac
            done
            if [[ -z "$preferred_input" ]]; then
                for input_file in "$hwmon"/temp*_input; do
                    [[ -r "$input_file" ]] || continue
                    preferred_input="$input_file"
                    break
                done
            fi
            if [[ -n "$preferred_input" && -r "$preferred_input" ]]; then
                raw_temperature=$(<"$preferred_input")
                temperature=$(awk -v raw="$raw_temperature" 'BEGIN { printf "%.0f", raw / 1000 }')
                break
            fi
            ;;
    esac
done

if [[ -z "$temperature" ]]; then
    for zone in /sys/class/thermal/thermal_zone*; do
        [[ -r "$zone/type" && -r "$zone/temp" ]] || continue
        zone_type=$(<"$zone/type")
        case "${zone_type,,}" in
            x86_pkg_temp|cpu-thermal|cpu_thermal|soc_thermal)
                raw_temperature=$(<"$zone/temp")
                temperature=$(awk -v raw="$raw_temperature" 'BEGIN { printf "%.0f", raw / 1000 }')
                break
                ;;
        esac
    done
fi

read -r load_1 load_5 load_15 _ < /proc/loadavg
uptime_seconds=$(awk '{ printf "%.0f", $1 }' /proc/uptime)
uptime_days=$((uptime_seconds / 86400))
uptime_hours=$(((uptime_seconds % 86400) / 3600))
uptime_minutes=$(((uptime_seconds % 3600) / 60))
if (( uptime_days > 0 )); then
    uptime_text="${uptime_days}d ${uptime_hours}h"
elif (( uptime_hours > 0 )); then
    uptime_text="${uptime_hours}h ${uptime_minutes}m"
else
    uptime_text="${uptime_minutes}m"
fi

page_size=$(getconf PAGESIZE 2>/dev/null || printf '4096')
total_memory_kib=$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo)
process_lines=$(awk -F '\t' \
    -v total_ticks="${total_tick_delta:-0}" \
    -v logical_cpus="$logical_cpus" \
    -v page_size="$page_size" \
    -v total_memory_kib="$total_memory_kib" '
    NR == FNR {
        previous_ticks[$1] = $2
        next
    }
    {
        tick_delta = $2 - previous_ticks[$1]
        if (tick_delta <= 0 || total_ticks <= 0)
            next
        usage = 100 * tick_delta * logical_cpus / total_ticks
        memory = total_memory_kib > 0 ? 100 * ($3 * page_size / 1024) / total_memory_kib : 0
        printf "%s\t%s\t%.1f\t%.1f\n", $1, $4, usage, memory
    }
' "$process_state_file" "$current_process_file" \
    | sort -t $'\t' -k3,3nr \
    | sed -n '1,5p')
processes_json=$(printf '%s\n' "$process_lines" \
    | jq -Rn '[
        inputs
        | select(length > 0)
        | split("\t")
        | {
            pid: (.[0] | tonumber),
            name: .[1],
            usage: (.[2] | tonumber),
            memory: (.[3] | tonumber)
        }
    ]')

state_staging="${state_file}.new"
process_state_staging="${process_state_file}.new"
install -m 600 "$current_file" "$state_staging"
install -m 600 "$current_process_file" "$process_state_staging"
mv -f "$state_staging" "$state_file"
mv -f "$process_state_staging" "$process_state_file"

temperature_text=""
if [[ -n "$temperature" ]]; then
    temperature_text=$(printf '\nTemperature: %s°C' "$temperature")
fi
tooltip=$(printf 'CPU: %s%%\nFrequency: %s GHz%s\nLoad: %s · %s · %s' \
    "$usage" "$frequency_ghz" "$temperature_text" "$load_1" "$load_5" "$load_15")

jq -cn \
    --arg text "$usage" \
    --arg tooltip "$tooltip" \
    --arg model "$model" \
    --argjson usage "$usage" \
    --argjson temperature "${temperature:-null}" \
    --argjson frequencyGhz "$frequency_ghz" \
    --argjson physicalCores "$physical_cores" \
    --argjson logicalCpus "$logical_cpus" \
    --argjson load1 "$load_1" \
    --argjson load5 "$load_5" \
    --argjson load15 "$load_15" \
    --arg uptime "$uptime_text" \
    --argjson cores "$cores_json" \
    --argjson processes "$processes_json" \
    '{
        text: $text,
        tooltip: $tooltip,
        model: $model,
        usage: $usage,
        temperature: $temperature,
        frequencyGhz: $frequencyGhz,
        physicalCores: $physicalCores,
        logicalCpus: $logicalCpus,
        load1: $load1,
        load5: $load5,
        load15: $load15,
        uptime: $uptime,
        cores: $cores,
        processes: $processes
    }'
