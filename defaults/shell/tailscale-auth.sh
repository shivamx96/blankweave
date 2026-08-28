#!/usr/bin/env bash

set -uo pipefail

action=${1:-}
operator=${2:-${USER:-}}

if ! command -v tailscale >/dev/null 2>&1; then
    printf '%s\n' 'Tailscale is not installed' >&2
    exit 127
fi

if [ -z "$operator" ] || ! id -u "$operator" >/dev/null 2>&1; then
    printf '%s\n' 'Could not determine the desktop user' >&2
    exit 2
fi

case "$action" in
    login)
        pkexec tailscale up \
            --json \
            --qr=false \
            --operator="$operator" \
            --timeout=180s \
            | jq --unbuffered -r '
                if .AuthURL then "auth-url\t" + .AuthURL
                elif .Error then "error\t" + .Error
                elif .BackendState then "state\t" + .BackendState
                else empty
                end
            '
        ;;
    connect)
        if tailscale up --timeout=30s 2>/dev/null; then
            printf 'state\tRunning\n'
        else
            pkexec tailscale up --operator="$operator" --timeout=30s
            printf 'state\tRunning\n'
        fi
        ;;
    disconnect)
        if ! tailscale down 2>/dev/null; then
            pkexec tailscale down
        fi
        printf 'state\tStopped\n'
        ;;
    logout)
        if ! tailscale logout 2>/dev/null; then
            pkexec tailscale logout
        fi
        printf 'state\tNeedsLogin\n'
        ;;
    *)
        printf 'Usage: %s {login|connect|disconnect|logout} [operator]\n' "$0" >&2
        exit 2
        ;;
esac
