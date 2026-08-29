#!/usr/bin/env bash

MAX_LENGTH=40

get_icon() {
    case "$1" in
        zen)                icon="󰈹 " ;;
        helium)             icon=" " ;;
        chrome-*-Default)   icon=" " ;;   # a web app in Helium's app mode
        dev.zed.Zed)        icon=" " ;;
        com.mitchellh.ghostty) icon=" " ;;
        jetbrains-idea)     icon=" " ;;
        obsidian)           icon="  " ;;
        *)                  icon="" ;;
    esac
    echo "$icon"
}

format_title() {
    local class="$1" title="$2"

    case "$class" in
        zen)
            title="${title% — Zen Browser}" ;;
        helium)
            title="${title% - Helium}" ;;
        dev.zed.Zed)
            title="${title% - Zed}" ;;
        jetbrains-idea)
            # "project – file" → keep as-is
            ;;
    esac

    echo "$title"
}

handle_window() {
    local json="$1"
    local class title icon text

    class=$(echo "$json" | jq -r '.class // empty')
    title=$(echo "$json" | jq -r '.title // empty')

    [ -z "$class" ] && { printf '{"text":""}\n'; return; }

    icon=$(get_icon "$class")
    title=$(format_title "$class" "$title")

    # Truncate
    if [ "${#title}" -gt "$MAX_LENGTH" ]; then
        title="${title:0:$((MAX_LENGTH - 1))}…"
    fi

    if [ -n "$icon" ]; then
        text="$icon  $title"
    else
        text="$title"
    fi

    printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
        "$text" "$title" "$class"
}

handle_window "$(hyprctl activewindow -j)"

socat -U - "UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" | while read -r line; do
    case "$line" in
        activewindow\>*|activewindowv2\>*|windowtitle\>*)
            handle_window "$(hyprctl activewindow -j)" ;;
    esac
done
