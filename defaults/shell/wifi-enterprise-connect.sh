#!/usr/bin/env bash

# Create an 802.1X PEAP/MSCHAPv2 profile. The password is read from stdin so it
# never appears in argv or /proc; SSID and identity are non-secret arguments.

set -e

SSID=${1:-}
IDENTITY=${2:-}

if [[ -z $SSID || -z $IDENTITY ]]; then
    printf 'Usage: wifi-enterprise-connect.sh <ssid> <identity>\n' >&2
    exit 2
fi

IFS= read -r PASSWORD
UUID=$(uuidgen)

cleanup() {
    nmcli connection delete uuid "$UUID" >/dev/null 2>&1 || true
}
trap cleanup ERR

nmcli connection add \
    type wifi \
    con-name "$SSID" \
    ssid "$SSID" \
    connection.uuid "$UUID" \
    wifi-sec.key-mgmt wpa-eap \
    802-1x.eap peap \
    802-1x.phase2-auth mschapv2 \
    802-1x.identity "$IDENTITY" \
    802-1x.auth-timeout 8 \
    >/dev/null

printf 'set 802-1x.password %s\nsave\nquit\n' "$PASSWORD" \
    | nmcli connection edit uuid "$UUID" >/dev/null
nmcli connection up uuid "$UUID" >/dev/null

trap - ERR
