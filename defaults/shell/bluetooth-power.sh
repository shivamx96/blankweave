#!/usr/bin/env bash

# Persist Bluetooth power through rfkill so systemd-rfkill restores the choice
# after reboot. BlueZ's adapter Powered property alone is not persistent.

POWER_WAIT_SECONDS=${BLANKWEAVE_BLUETOOTH_POWER_WAIT_SECONDS:-2}

controllers() {
    timeout 2 bluetoothctl list 2>/dev/null | awk '{print $2}'
}

powered() {
    local controller

    for controller in $(controllers); do
        if [[ $(timeout 2 bluetoothctl show "$controller" 2>/dev/null) == *"Powered: yes"* ]]; then
            return 0
        fi
    done

    return 1
}

wait_powered() {
    local deadline=$((SECONDS + POWER_WAIT_SECONDS))

    while :; do
        powered && return 0
        ((SECONDS < deadline)) || return 1
        sleep 0.2
    done
}

power_on() {
    rfkill unblock bluetooth
    wait_powered && return 0

    timeout 5 bluetoothctl power on >/dev/null 2>&1
    wait_powered
}

case "${1:-}" in
    on)
        power_on
        ;;
    off)
        rfkill block bluetooth
        ;;
    toggle)
        if powered; then
            rfkill block bluetooth
        else
            power_on
        fi
        ;;
    is-on)
        powered
        ;;
    *)
        printf 'Usage: bluetooth-power.sh <on|off|toggle|is-on>\n' >&2
        exit 2
        ;;
esac
