#!/usr/bin/env bash

# Waybar custom module for brightness (works with brightnessctl and ddcutil)
# Outputs JSON: {"text":"icon  50%","tooltip":"Brightness: 50%\nBackend: backlight"}

PERCENT=$(~/.local/share/hyprarch/shell/brightness.sh get 2>/dev/null)

if [ -z "$PERCENT" ] || [ "$PERCENT" = "0" ]; then
    echo '{"text":"","tooltip":"Brightness control not available"}'
    exit 0
fi

# Pick icon based on level
if [ "$PERCENT" -le 33 ]; then
    ICON="󰃞"
elif [ "$PERCENT" -le 66 ]; then
    ICON="󰃟"
else
    ICON="󰃠"
fi

# Detect backend for tooltip
if ls /sys/class/backlight/*/brightness &>/dev/null 2>&1; then
    BACKEND="backlight"
else
    BACKEND="none"
fi

printf '{"text":"%s  %s%%","tooltip":"Brightness: %s%%\\nBackend: %s"}' \
    "$ICON" "$PERCENT" "$PERCENT" "$BACKEND"
