#!/usr/bin/env bash

set -euo pipefail

repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)

cleanup() {
    if [[ -n $test_root && -d $test_root ]]; then
        rm -rf -- "$test_root"
    fi
}
trap cleanup EXIT HUP INT TERM

# shellcheck source=scripts/hardware-capabilities.sh
source "$repository/scripts/hardware-capabilities.sh"

assert_capability() {
    hardware_capability_has "$1" || {
        printf 'Expected capability: %s\n' "$1" >&2
        exit 1
    }
}

assert_no_capability() {
    if hardware_capability_has "$1"; then
        printf 'Unexpected capability: %s\n' "$1" >&2
        exit 1
    fi
}

laptop_sys=$test_root/laptop-sys
mkdir -p "$laptop_sys/class/power_supply/BAT0" \
    "$laptop_sys/class/backlight/intel_backlight" \
    "$laptop_sys/class/bluetooth/hci0" \
    "$laptop_sys/class/drm/card0-eDP-1"
printf 'Battery\n' > "$laptop_sys/class/power_supply/BAT0/type"
printf 'connected\n' > "$laptop_sys/class/drm/card0-eDP-1/status"
BLANKWEAVE_SYSFS_ROOT=$laptop_sys \
BLANKWEAVE_TEST_LSPCI_OUTPUT=$'00:02.0 VGA compatible controller: Intel Corporation Arc Graphics\n00:1f.3 Audio device: Intel Corporation Audio' \
BLANKWEAVE_TEST_LSUSB_OUTPUT='' \
BLANKWEAVE_TEST_DDC_DISPLAY=false \
    hardware_capabilities_detect
assert_capability gpu-intel
assert_capability audio-intel
assert_capability battery
assert_capability internal-display
assert_capability internal-backlight
assert_capability bluetooth
assert_capability gaming
assert_no_capability gpu-nvidia
assert_no_capability ddc-display

desktop_sys=$test_root/desktop-sys
mkdir -p "$desktop_sys/class/drm/card1-DP-1"
printf 'connected\n' > "$desktop_sys/class/drm/card1-DP-1/status"
BLANKWEAVE_SYSFS_ROOT=$desktop_sys \
BLANKWEAVE_TEST_LSPCI_OUTPUT=$'01:00.0 VGA compatible controller: NVIDIA Corporation Device\n02:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Device' \
BLANKWEAVE_TEST_LSUSB_OUTPUT='Bus 001 Device 002: ID 1234:5678 Bluetooth Radio' \
BLANKWEAVE_TEST_DDC_DISPLAY=auto \
    hardware_capabilities_detect
assert_capability gpu-amd
assert_capability gpu-nvidia
assert_capability ddc-display
assert_capability bluetooth
assert_capability gaming
assert_no_capability battery
assert_no_capability internal-display

capability_file=$test_root/capabilities.json
hardware_capabilities_write_json "$capability_file"
jq -e '.schema == 1' "$capability_file" >/dev/null
jq -e '.gpuVendors == ["amd", "nvidia"]' "$capability_file" >/dev/null
jq -e '."ddc-display" and .bluetooth and .gaming' "$capability_file" >/dev/null
jq -e '(.battery | not) and (."internal-display" | not)' "$capability_file" >/dev/null

sysfs_only=$test_root/sysfs-only
mkdir -p "$sysfs_only/class/drm/card0/device" \
    "$sysfs_only/bus/pci/devices/0000:00:1f.3"
printf '0x1002\n' > "$sysfs_only/class/drm/card0/device/vendor"
printf '0x8086\n' > "$sysfs_only/bus/pci/devices/0000:00:1f.3/vendor"
printf '0x040300\n' > "$sysfs_only/bus/pci/devices/0000:00:1f.3/class"
BLANKWEAVE_SYSFS_ROOT=$sysfs_only \
BLANKWEAVE_TEST_LSPCI_OUTPUT='' \
BLANKWEAVE_TEST_LSUSB_OUTPUT='' \
BLANKWEAVE_TEST_DDC_DISPLAY=false \
    hardware_capabilities_detect
assert_capability gpu-amd
assert_capability audio-intel
assert_capability gaming

printf 'Hardware capability detection tests passed.\n'
