#!/usr/bin/env bash

set -u

if ! command -v fastfetch >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    jq -cn '{available:false, error:"System overview requires fastfetch and jq"}'
    exit 0
fi

snapshot=$(mktemp)
trap 'rm -f -- "$snapshot"' EXIT

if ! fastfetch \
    --format json \
    --structure OS:Host:Kernel:Uptime:Packages:Display:WM:CPU:GPU:Memory:Disk \
    > "$snapshot" 2>/dev/null; then
    jq -cn '{available:false, error:"Could not collect system information"}'
    exit 0
fi

hostname=$(uname -n 2>/dev/null || printf 'unknown')
inventory_file="$HOME/.local/share/hyprarch/system-hardware.json"
motherboard_name=""
motherboard_vendor=""
memory_spec=""
memory_details=""
display_model=""

if [ -r "$inventory_file" ]; then
    motherboard_name=$(jq -r '.motherboard.name // ""' "$inventory_file" 2>/dev/null || true)
    motherboard_vendor=$(jq -r '.motherboard.vendor // ""' "$inventory_file" 2>/dev/null || true)
    memory_spec=$(jq -r '.memorySpec // ""' "$inventory_file" 2>/dev/null || true)
    memory_details=$(jq -r '.memoryDetails // ""' "$inventory_file" 2>/dev/null || true)

    active_connector=""
    if command -v hyprctl >/dev/null 2>&1; then
        active_connector=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].name // ""' 2>/dev/null || true)
    fi
    if [ -n "$active_connector" ]; then
        display_model=$(jq -r \
            --arg connector "$active_connector" \
            '.displays[]? | select(.connector == $connector) | .name // empty' \
            "$inventory_file" 2>/dev/null | head -n 1)
    fi
    if [ -z "$display_model" ]; then
        display_model=$(jq -r '.displays[]? | .name // empty' "$inventory_file" 2>/dev/null | head -n 1)
    fi
fi

if [ -z "$motherboard_name" ] && [ -r /sys/class/dmi/id/board_name ]; then
    motherboard_name=$(tr -d '\000\r\n' < /sys/class/dmi/id/board_name)
fi
if [ -z "$motherboard_vendor" ] && [ -r /sys/class/dmi/id/board_vendor ]; then
    motherboard_vendor=$(tr -d '\000\r\n' < /sys/class/dmi/id/board_vendor)
fi

jq -c \
    --arg hostname "$hostname" \
    --arg motherboardName "$motherboard_name" \
    --arg motherboardVendor "$motherboard_vendor" \
    --arg memorySpec "$memory_spec" \
    --arg memoryDetails "$memory_details" \
    --arg displayModel "$display_model" '
    def result_for($name): map(select(.type == $name and .error == null))[0].result;
    . as $modules
    | ($modules | result_for("OS")) as $os
    | ($modules | result_for("Host")) as $host
    | ($modules | result_for("Kernel")) as $kernel
    | ($modules | result_for("Uptime")) as $uptime
    | ($modules | result_for("Packages")) as $packages
    | ($modules | result_for("Display")) as $displays
    | ($modules | result_for("WM")) as $wm
    | ($modules | result_for("CPU")) as $cpu
    | ($modules | result_for("GPU")) as $gpus
    | ($modules | result_for("Memory")) as $memory
    | ($modules | result_for("Disk")) as $disks
    | (($disks // []) | map(select(.mountpoint == "/"))[0] // ($disks // [])[0] // {}) as $disk
    | (($displays // [])[0] // {}) as $display
    | {
        available:true,
        error:"",
        hostname:$hostname,
        os:($os.prettyName // $os.name // "Linux"),
        hardware:([($host.vendor // ""), ($host.name // "")] | map(select(length > 0)) | join(" ")),
        kernel:($kernel.release // "—"),
        architecture:($kernel.architecture // ""),
        uptimeSeconds:((($uptime.uptime // 0) / 1000) | floor),
        packages:($packages.all // $packages.pacman // 0),
        session:([($wm.prettyName // "Hyprland"), ($wm.version // ""), ($wm.protocolName // "Wayland")] | map(select(length > 0)) | join(" · ")),
        cpu:($cpu.cpu // "Unknown processor"),
        physicalCores:($cpu.cores.physical // 0),
        logicalCores:($cpu.cores.logical // 0),
        gpu:(($gpus // []) | map(.name // empty) | unique | join(" · ")),
        motherboardName:$motherboardName,
        motherboardVendor:$motherboardVendor,
        memorySpec:$memorySpec,
        memoryDetails:$memoryDetails,
        memoryUsed:($memory.used // 0),
        memoryTotal:($memory.total // 0),
        diskUsed:($disk.bytes.used // 0),
        diskTotal:($disk.bytes.total // 0),
        diskFilesystem:($disk.filesystem // ""),
        displayModel:(if ($displayModel | length) > 0 then $displayModel
            else ($display.name // "Display") end),
        displayDetails:(if ($display.output.width // 0) > 0 then
            ((($display.output.width // 0) | tostring) + "×"
                + (($display.output.height // 0) | tostring) + " @ "
                + (($display.output.refreshRate // 0) | round | tostring) + " Hz")
            else "No active display" end)
    }
' "$snapshot" 2>/dev/null \
    || jq -cn '{available:false, error:"Could not parse system information"}'
