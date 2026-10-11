#!/usr/bin/env bash

set -euo pipefail

repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
hypr=$repository/defaults/hypr

# XWayland stays unscaled so games see the display's native resolution.
grep -q 'force_zero_scaling = true' "$hypr/hyprland.lua"

# Games keep rendering while another workspace is on screen; the class match
# covers every Steam game window (steam_app_<appid>).
grep -q 'match = { class = "^steam_app_\[0-9\]+$" }' "$hypr/windowrules.lua"
awk '/render-unfocused-steam-games/,/\}\)/' "$hypr/windowrules.lua" | grep -q 'render_unfocused = true'

# The Lua files at least parse; the compositor validates the rest on install.
if command -v luac > /dev/null 2>&1; then
    for lua_file in "$hypr"/*.lua; do
        luac -p "$lua_file"
    done
fi
