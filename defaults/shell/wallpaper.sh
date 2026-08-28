#!/usr/bin/env bash

# Wallpaper manager for awww

WALLPAPER_DIR="$HOME/.local/share/hyprarch/wallpapers"
CURRENT_WALLPAPER="$HOME/.cache/hyprarch-wallpaper"
THEME_FILE="$HOME/.local/share/hyprarch/theme"

# Create wallpaper directory if it doesn't exist
mkdir -p "$WALLPAPER_DIR"

# Function to set wallpaper
set_wallpaper() {
    local wallpaper="$1"

    if [ ! -f "$wallpaper" ]; then
        echo "Wallpaper not found: $wallpaper"
        return 1
    fi

    # Publish the lock-screen source before waiting for the wallpaper daemon.
    # This keeps Hyprlock deterministic during session startup.
    printf '%s\n' "$wallpaper" > "$CURRENT_WALLPAPER"
    ln -sfn "$wallpaper" "$HOME/.cache/hyprarch-current-wallpaper"

    # Wait for awww daemon to be ready
    for i in $(seq 1 10); do
        awww query 2>/dev/null && break
        sleep 0.5
    done

    # Set wallpaper with transition
    awww img "$wallpaper" --transition-type wipe --transition-duration 1
}

# Return the wallpaper paired with the persisted shell theme.
theme_wallpaper() {
    local theme="dark"
    local wallpaper

    [ -f "$THEME_FILE" ] && read -r theme < "$THEME_FILE"

    if [ "$theme" = "light" ]; then
        wallpaper="$WALLPAPER_DIR/hyprarch-porcelain-blue-light.png"
    else
        wallpaper="$WALLPAPER_DIR/hyprarch-obsidian-blue-dark.png"
    fi

    if [ -f "$wallpaper" ]; then
        printf '%s\n' "$wallpaper"
    else
        random_wallpaper
    fi
}

# Function to get random wallpaper
random_wallpaper() {
    shopt -s nullglob
    local wallpapers=("$WALLPAPER_DIR"/*.{jpg,jpeg,png,JPG,JPEG,PNG})
    shopt -u nullglob

    if [ ${#wallpapers[@]} -eq 0 ]; then
        echo "No wallpapers found in $WALLPAPER_DIR" >&2
        return 1
    fi

    local random_idx=$((RANDOM % ${#wallpapers[@]}))
    echo "${wallpapers[$random_idx]}"
}

# Function to cycle wallpapers
cycle_wallpaper() {
    shopt -s nullglob
    local wallpapers=("$WALLPAPER_DIR"/*.{jpg,jpeg,png,JPG,JPEG,PNG})
    shopt -u nullglob

    if [ ${#wallpapers[@]} -eq 0 ]; then
        echo "No wallpapers found in $WALLPAPER_DIR" >&2
        return 1
    fi

    local current="$(cat "$CURRENT_WALLPAPER" 2>/dev/null)"
    local next_idx=0

    for i in "${!wallpapers[@]}"; do
        if [ "${wallpapers[$i]}" = "$current" ]; then
            next_idx=$(( (i + 1) % ${#wallpapers[@]} ))
            break
        fi
    done

    set_wallpaper "${wallpapers[$next_idx]}"
}

# Main logic
case "${1:-random}" in
    set)
        set_wallpaper "$2"
        ;;
    random)
        wp=$(random_wallpaper) || exit 1
        set_wallpaper "$wp"
        ;;
    theme)
        wp=$(theme_wallpaper) || exit 1
        set_wallpaper "$wp"
        ;;
    cycle)
        cycle_wallpaper
        ;;
    *)
        echo "Usage: $0 {set <path>|random|theme|cycle}"
        exit 1
        ;;
esac
