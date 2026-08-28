#!/usr/bin/env bash

set -u
umask 077

account=${1:-${SUDO_USER:-}}
if [ -z "$account" ]; then
    account=$(id -un)
fi
if ! account_uid=$(id -u "$account" 2>/dev/null); then
    printf 'Unknown user: %s\n' "$account" >&2
    exit 1
fi
if [ "$EUID" -ne 0 ] && [ "$account_uid" -ne "$(id -u)" ]; then
    printf 'Run as %s, or use sudo to refresh another user inventory.\n' "$account" >&2
    exit 1
fi
if ! command -v fastfetch >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    printf 'Hardware inventory requires fastfetch and jq.\n' >&2
    exit 1
fi

account_home=$(getent passwd "$account" | cut -d: -f6)
if [ -z "$account_home" ] || [ ! -d "$account_home" ]; then
    printf 'Could not resolve the home directory for %s.\n' "$account" >&2
    exit 1
fi

dots_dir="$account_home/.local/share/hyprarch"
inventory_file="$dots_dir/system-hardware.json"
overrides_file="$dots_dir/hardware-overrides.json"
mkdir -p "$dots_dir"

read_dmi_value() {
    local field_file=$1
    if [ -r "$field_file" ]; then
        tr -d '\000\r\n' < "$field_file"
    fi
}

board_vendor=$(read_dmi_value /sys/class/dmi/id/board_vendor)
board_name=$(read_dmi_value /sys/class/dmi/id/board_name)
board_version=$(read_dmi_value /sys/class/dmi/id/board_version)
bios_vendor=$(read_dmi_value /sys/class/dmi/id/bios_vendor)
bios_version=$(read_dmi_value /sys/class/dmi/id/bios_version)

memory_modules='[]'
if [ "$EUID" -eq 0 ]; then
    physical_snapshot=$(mktemp)
    if fastfetch --format json --structure PhysicalMemory > "$physical_snapshot" 2>/dev/null; then
        memory_modules=$(jq -c '[
            (map(select(.type == "PhysicalMemory" and .error == null))[0].result // [])[]
            | select((.installed // true) == true and (.size // 0) > 0)
            | {
                size:(.size // 0),
                maxSpeed:(.maxSpeed // 0),
                runningSpeed:(.runningSpeed // 0),
                type:(.type // ""),
                locator:(.locator // ""),
                formFactor:(.formFactor // ""),
                vendor:(.vendor // ""),
                partNumber:(.partNumber // ""),
                ecc:(.ecc // false)
            }
        ]' "$physical_snapshot" 2>/dev/null || printf '[]')
    fi
    rm -f -- "$physical_snapshot"
elif [ -r "$inventory_file" ]; then
    memory_modules=$(jq -c '.memoryModules // []' "$inventory_file" 2>/dev/null || printf '[]')
fi

monitor_inventory='[]'
for connector_dir in /sys/class/drm/card*-*; do
    edid_file="$connector_dir/edid"
    if [ ! -r "$edid_file" ]; then
        continue
    fi

    read -r manufacturer_high manufacturer_low product_low product_high \
        < <(od -An -tu1 -j8 -N4 "$edid_file" 2>/dev/null)
    if [ -z "${product_high:-}" ]; then
        continue
    fi

    manufacturer_code=$((manufacturer_high * 256 + manufacturer_low))
    first_letter=$((((manufacturer_code >> 10) & 31) + 64))
    second_letter=$((((manufacturer_code >> 5) & 31) + 64))
    third_letter=$(((manufacturer_code & 31) + 64))
    manufacturer=$(printf "\\$(printf '%03o' "$first_letter")\\$(printf '%03o' "$second_letter")\\$(printf '%03o' "$third_letter")")
    product_id=$((product_low + product_high * 256))
    monitor_key="$manufacturer:$product_id"
    connector=$(basename "$connector_dir")
    connector=${connector#card*-}
    friendly_name=""
    if [ -r "$overrides_file" ]; then
        friendly_name=$(jq -r --arg key "$monitor_key" '.monitorAliases[$key] // ""' "$overrides_file" 2>/dev/null || true)
    fi
    monitor_inventory=$(jq -cn \
        --argjson existing "$monitor_inventory" \
        --arg connector "$connector" \
        --arg key "$monitor_key" \
        --arg manufacturer "$manufacturer" \
        --argjson productId "$product_id" \
        --arg name "$friendly_name" \
        '$existing + [{
            connector:$connector,
            key:$key,
            manufacturer:$manufacturer,
            productId:$productId,
            name:$name
        }]')
done

staged_inventory=$(mktemp "$dots_dir/.system-hardware.XXXXXX")
jq -cn \
    --arg boardVendor "$board_vendor" \
    --arg boardName "$board_name" \
    --arg boardVersion "$board_version" \
    --arg biosVendor "$bios_vendor" \
    --arg biosVersion "$bios_version" \
    --argjson memoryModules "$memory_modules" \
    --argjson displays "$monitor_inventory" \
    --argjson privileged "$([ "$EUID" -eq 0 ] && printf true || printf false)" \
    --argjson generatedAt "$(date +%s)" '
        def gib:
            (((. / 1073741824) * 10 | round) / 10 | tostring) + " GB";
        def module_label:
            [
                (.size | gib),
                (.type // ""),
                (if (.runningSpeed // 0) > 0 then ((.runningSpeed | tostring) + " MT/s")
                 elif (.maxSpeed // 0) > 0 then ((.maxSpeed | tostring) + " MT/s max")
                 else "" end)
            ] | map(select(length > 0)) | join(" ");
        ($memoryModules | map(module_label) | unique) as $moduleLabels
        | ($memoryModules
            | map([(.vendor // ""), (.partNumber // "")] | map(select(length > 0)) | join(" "))
            | map(select(length > 0))
            | unique) as $memoryDetails
        | {
            generatedAt:$generatedAt,
            privileged:$privileged,
            motherboard:{
                vendor:$boardVendor,
                name:$boardName,
                version:$boardVersion
            },
            bios:{vendor:$biosVendor, version:$biosVersion},
            memoryModules:$memoryModules,
            memorySpec:(if ($memoryModules | length) == 0 then ""
                elif ($moduleLabels | length) == 1 then
                    (($memoryModules | length | tostring) + "× " + $moduleLabels[0])
                else $moduleLabels | join(" + ") end),
            memoryDetails:($memoryDetails | join(" · ")),
            displays:$displays
        }
    ' > "$staged_inventory"

chmod 0644 "$staged_inventory"
mv -f "$staged_inventory" "$inventory_file"
if [ "$EUID" -eq 0 ]; then
    account_group=$(id -gn "$account")
    chown "$account:$account_group" "$inventory_file"
fi

if [ "$EUID" -eq 0 ]; then
    printf 'Refreshed hardware inventory for %s, including privileged DIMM data.\n' "$account"
else
    printf 'Refreshed non-privileged hardware inventory for %s; existing DIMM data was preserved.\n' "$account"
fi
