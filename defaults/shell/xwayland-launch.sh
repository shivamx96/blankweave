#!/usr/bin/env bash
#
# Run an XWayland application with its scale matched to the focused monitor.
#
# Hyprland's xwayland:force_zero_scaling leaves XWayland windows unscaled so
# they stay sharp on a HiDPI display, which means an application that cannot
# read the compositor's scale draws at 1x. Steam is the main one left: it has
# no Wayland mode, and the Proton games it starts inherit its environment.
# This wrapper reads the focused monitor's scale and exports it in the forms
# those clients understand, then replaces itself with the command.
#
# Usage: xwayland-launch.sh <command> [arguments...]

set -euo pipefail

if [[ $# -eq 0 ]]; then
    printf 'Usage: xwayland-launch.sh <command> [arguments...]\n' >&2
    exit 2
fi

monitor_scale() {
    local scale
    command -v hyprctl > /dev/null 2>&1 || return 1
    command -v jq > /dev/null 2>&1 || return 1
    # Prefer the focused monitor; fall back to the first one listed.
    scale=$(hyprctl monitors -j 2> /dev/null \
        | jq -r '(map(select(.focused == true)) + .)[0].scale // empty' 2> /dev/null) || return 1
    [[ $scale =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 1
    printf '%s\n' "$scale"
}

scale=$(monitor_scale) || scale=1
cursor_base=${XCURSOR_SIZE:-24}
[[ $cursor_base =~ ^[0-9]+$ ]] || cursor_base=24

# Steam's own scaling switch accepts a fractional factor. The X cursor is
# drawn by the client at XCURSOR_SIZE physical pixels, so it grows with the
# scale while Wayland clients keep the session's logical size.
STEAM_FORCE_DESKTOPUI_SCALING=$scale
XCURSOR_SIZE=$(awk -v base="$cursor_base" -v scale="$scale" \
    'BEGIN { printf "%d", base * scale + 0.5 }')
export STEAM_FORCE_DESKTOPUI_SCALING XCURSOR_SIZE

exec "$@"
