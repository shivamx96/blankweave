#!/usr/bin/env bash

set -euo pipefail

clear_boot_console() {
    local tty="$1"

    [[ -w "$tty" ]] || return 0

    # Hyprland already owns the display when this runs. Clear tty1's hidden
    # text and scrollback buffers now so the compositor-to-Plymouth shutdown
    # handoff reveals only the theme-coloured console canvas.
    printf '\033[?25l\033[2J\033[3J\033[H' > "$tty"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    clear_boot_console /dev/tty1
fi
