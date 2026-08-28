#!/usr/bin/env bash

# Pair, connect, disconnect, or forget one validated Bluetooth device.

set -e

ACTION=${1:-}
ADDRESS=${2:-}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if [[ $ACTION != pair && $ACTION != connect && $ACTION != disconnect && $ACTION != forget ]]; then
    printf 'Usage: bluetooth-device.sh <pair|connect|disconnect|forget> <address>\n' >&2
    exit 2
fi

if [[ ! $ADDRESS =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
    printf 'Invalid Bluetooth address\n' >&2
    exit 2
fi

power_on() {
    if [[ $(timeout 2 bluetoothctl show 2>/dev/null) != *"Powered: yes"* ]]; then
        "$SCRIPT_DIR/bluetooth-power.sh" on || true
    fi
}

trust_device() {
    timeout 5 bluetoothctl trust "$ADDRESS" >/dev/null 2>&1 || true
}

case "$ACTION" in
    pair)
        power_on
        timeout 25 bluetoothctl pair "$ADDRESS" >/dev/null 2>&1 || true
        trust_device
        timeout 20 bluetoothctl connect "$ADDRESS" >/dev/null 2>&1 || true
        ;;
    connect)
        power_on
        trust_device
        timeout 20 bluetoothctl connect "$ADDRESS" >/dev/null 2>&1 || true
        ;;
    disconnect)
        timeout 10 bluetoothctl disconnect "$ADDRESS" >/dev/null 2>&1 || true
        ;;
    forget)
        power_on
        timeout 10 bluetoothctl disconnect "$ADDRESS" >/dev/null 2>&1 || true
        timeout 10 bluetoothctl remove "$ADDRESS" >/dev/null 2>&1 || true
        ;;
esac
