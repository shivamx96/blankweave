#!/usr/bin/env bash

# Hardware detection shared by setup, install, update preflight, and doctor.
# Capabilities are ordered, stable identifiers; callers must branch on these
# rather than infer a machine class such as "laptop" or "pc".

HARDWARE_CAPABILITY_SCHEMA=1
HARDWARE_CAPABILITIES=()

hardware_capability_add() {
    local requested=$1 existing

    [[ $requested =~ ^[a-z0-9][a-z0-9-]*$ ]] || return 1
    for existing in "${HARDWARE_CAPABILITIES[@]}"; do
        [[ $existing == "$requested" ]] && return 0
    done
    HARDWARE_CAPABILITIES+=("$requested")
}

hardware_capability_has() {
    local requested=$1 capability

    for capability in "${HARDWARE_CAPABILITIES[@]}"; do
        [[ $capability == "$requested" ]] && return 0
    done
    return 1
}

hardware_capabilities_list() {
    printf '%s\n' "${HARDWARE_CAPABILITIES[*]}"
}

hardware_capabilities_pci() {
    if [[ ${BLANKWEAVE_TEST_LSPCI_OUTPUT+x} ]]; then
        printf '%s\n' "$BLANKWEAVE_TEST_LSPCI_OUTPUT"
    elif command -v lspci >/dev/null 2>&1; then
        lspci -nn 2>/dev/null || true
    fi
}

hardware_capabilities_usb() {
    if [[ ${BLANKWEAVE_TEST_LSUSB_OUTPUT+x} ]]; then
        printf '%s\n' "$BLANKWEAVE_TEST_LSUSB_OUTPUT"
    elif command -v lsusb >/dev/null 2>&1; then
        lsusb 2>/dev/null || true
    fi
}

hardware_capabilities_detect() {
    local sys_root=${BLANKWEAVE_SYSFS_ROOT:-/sys}
    local pci_output usb_output line connector status_file type_file vendor_file vendor_id
    local device class_id
    local has_external_display=false has_gpu=false
    local -a power_supplies=() backlights=() bluetooth_adapters=() connectors=()
    local -a gpu_vendor_files=() pci_devices=()

    HARDWARE_CAPABILITIES=()
    pci_output=$(hardware_capabilities_pci)
    usb_output=$(hardware_capabilities_usb)

    if grep -Eiq '(VGA compatible controller|3D controller|Display controller).*Intel' <<< "$pci_output"; then
        hardware_capability_add gpu-intel
        has_gpu=true
    fi
    if grep -Eiq '(VGA compatible controller|3D controller|Display controller).*(AMD|ATI|Advanced Micro Devices)' <<< "$pci_output"; then
        hardware_capability_add gpu-amd
        has_gpu=true
    fi
    if grep -Eiq '(VGA compatible controller|3D controller|Display controller).*NVIDIA' <<< "$pci_output"; then
        hardware_capability_add gpu-nvidia
        has_gpu=true
    fi
    if grep -Eiq 'Audio device.*Intel|Multimedia audio controller.*Intel' <<< "$pci_output"; then
        hardware_capability_add audio-intel
    fi

    shopt -s nullglob
    gpu_vendor_files=("$sys_root"/class/drm/card*/device/vendor)
    for vendor_file in "${gpu_vendor_files[@]}"; do
        [[ -r $vendor_file ]] || continue
        vendor_id=$(<"$vendor_file")
        case ${vendor_id,,} in
            0x8086) hardware_capability_add gpu-intel; has_gpu=true ;;
            0x1002) hardware_capability_add gpu-amd; has_gpu=true ;;
            0x10de) hardware_capability_add gpu-nvidia; has_gpu=true ;;
        esac
    done
    pci_devices=("$sys_root"/bus/pci/devices/*)
    for device in "${pci_devices[@]}"; do
        [[ -r $device/vendor && -r $device/class ]] || continue
        vendor_id=$(<"$device/vendor")
        class_id=$(<"$device/class")
        if [[ ${vendor_id,,} == 0x8086 && ${class_id,,} == 0x0403* ]]; then
            hardware_capability_add audio-intel
            break
        fi
    done

    power_supplies=("$sys_root"/class/power_supply/*)
    for line in "${power_supplies[@]}"; do
        type_file=$line/type
        if [[ -r $type_file ]] && grep -Fxiq Battery "$type_file"; then
            hardware_capability_add battery
            break
        fi
    done

    backlights=("$sys_root"/class/backlight/*)
    if (( ${#backlights[@]} > 0 )); then
        hardware_capability_add internal-backlight
        hardware_capability_add internal-display
    fi

    connectors=("$sys_root"/class/drm/card*-*)
    for connector in "${connectors[@]}"; do
        status_file=$connector/status
        if [[ ! -r $status_file ]] || ! grep -Fqx connected "$status_file"; then
            continue
        fi
        case ${connector##*/} in
            *-eDP-*|*-LVDS-*|*-DSI-*) hardware_capability_add internal-display ;;
            *)
                has_external_display=true
                ;;
        esac
    done

    case ${BLANKWEAVE_TEST_DDC_DISPLAY:-auto} in
        true) hardware_capability_add ddc-display ;;
        false) ;;
        auto)
            if command -v ddcutil >/dev/null 2>&1 \
                && timeout 10 ddcutil detect --brief 2>/dev/null | grep -Fq 'Display'; then
                hardware_capability_add ddc-display
            elif [[ $has_external_display == true ]]; then
                # On a fresh install ddcutil is not available yet. A connected
                # external DRM display is the conservative package-selection
                # signal; the brightness widget verifies DDC/CI at runtime.
                hardware_capability_add ddc-display
            fi
            ;;
        *) return 1 ;;
    esac

    bluetooth_adapters=("$sys_root"/class/bluetooth/hci*)
    if (( ${#bluetooth_adapters[@]} > 0 )) \
        || grep -Eiq 'Bluetooth' <<< "$pci_output" \
        || grep -Eiq 'Bluetooth' <<< "$usb_output"; then
        hardware_capability_add bluetooth
    fi
    shopt -u nullglob

    if [[ $has_gpu == true ]]; then
        hardware_capability_add gaming
    fi
}

hardware_capabilities_write_json() {
    local destination=$1 capability separator='' gpu_vendor
    local staged
    local -a gpu_vendors=()

    staged=$(mktemp "$(dirname "$destination")/.hardware-capabilities.XXXXXX")
    {
        printf '{\n  "schema": %d,\n  "capabilities": [' "$HARDWARE_CAPABILITY_SCHEMA"
        for capability in "${HARDWARE_CAPABILITIES[@]}"; do
            printf '%s"%s"' "$separator" "$capability"
            separator=', '
            case $capability in
                gpu-*)
                    gpu_vendor=${capability#gpu-}
                    gpu_vendors+=("$gpu_vendor")
                    ;;
            esac
        done
        printf '],\n  "gpuVendors": ['
        separator=
        for gpu_vendor in "${gpu_vendors[@]}"; do
            printf '%s"%s"' "$separator" "$gpu_vendor"
            separator=', '
        done
        printf '],\n'
        for capability in battery internal-display internal-backlight ddc-display bluetooth gaming; do
            if hardware_capability_has "$capability"; then
                printf '  "%s": true' "$capability"
            else
                printf '  "%s": false' "$capability"
            fi
            [[ $capability == gaming ]] && printf '\n' || printf ',\n'
        done
        printf '}\n'
    } > "$staged"
    chmod 0644 "$staged"
    mv -f "$staged" "$destination"
}
