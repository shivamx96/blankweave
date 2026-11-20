#!/usr/bin/env bash

set -euo pipefail

repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
hypr=$repository/defaults/hypr

# XWayland stays unscaled so games see the display's native resolution.
grep -q 'force_zero_scaling = true' "$hypr/hyprland.lua"

# Recovery and input wake options belong to misc, beside existing booleans.
for option in allow_session_lock_restore key_press_enables_dpms mouse_move_enables_dpms; do
    awk '/    misc = {/,/    },/' "$hypr/hyprland.lua" | grep -q "$option = true"
done

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

python3 "$repository/tests/hyprland-motion.py"
grep -q 'switch:on:Lid Switch' "$hypr/keybindings.lua"
grep -q 'switch:off:Lid Switch' "$hypr/keybindings.lua"

# Lock visuals must use the rendered font/time; the minute clock never forks.
if grep -q 'cmd\[.*date.*%H\|cmd\[.*date.*%I' "$hypr/hyprlock.conf"; then exit 1; fi
grep -Fq "text = \$lock_time" "$hypr/hyprlock.conf"
grep -Fq "capslock_color = \$warning" "$hypr/hyprlock.conf"
grep -Fq "fail_text = Incorrect password — attempt \$ATTEMPTS" "$hypr/hyprlock.conf"
