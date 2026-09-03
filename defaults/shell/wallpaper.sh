#!/usr/bin/env bash

# Wallpaper manager for awww.
#
# Login and theme switches restore the active theme's wallpaper. Super+Shift+W
# cycles that wallpaper together with extras the user dropped in
# ~/.config/blankweave/wallpapers, which the installer never touches.

USER_WALLPAPER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/blankweave/wallpapers"
CURRENT_WALLPAPER="$HOME/.cache/blankweave-wallpaper"
THEME_STATE="${XDG_CONFIG_HOME:-$HOME/.config}/blankweave/theme.json"

mkdir -p "$USER_WALLPAPER_DIR"

# Function to set wallpaper
set_wallpaper() {
    local wallpaper="$1"

    if [ ! -f "$wallpaper" ]; then
        echo "Wallpaper not found: $wallpaper"
        return 1
    fi

    # Publish the lock-screen source before waiting for the wallpaper daemon.
    # This keeps Hyprlock deterministic during session startup.
    mkdir -p "$(dirname "$CURRENT_WALLPAPER")"
    printf '%s\n' "$wallpaper" > "$CURRENT_WALLPAPER"
    ln -sfn "$wallpaper" "$HOME/.cache/blankweave-current-wallpaper"

    # Wait for awww daemon to be ready
    for i in $(seq 1 10); do
        awww query 2>/dev/null && break
        sleep 0.5
    done

    # Set wallpaper with transition
    awww img "$wallpaper" --transition-type wipe --transition-duration 1
}

# The wallpaper the session is meant to show: the last one set, or the
# theme's default when nothing has been set yet.
current_wallpaper() {
    local wallpaper=""

    [ -f "$CURRENT_WALLPAPER" ] && read -r wallpaper < "$CURRENT_WALLPAPER"
    if [ -n "$wallpaper" ] && [ -f "$wallpaper" ]; then
        printf '%s\n' "$wallpaper"
    else
        theme_wallpaper
    fi
}

# Repaint the current wallpaper on one output (or all of them) without a
# transition. awww only paints the outputs that exist when `img` runs and its
# cache is keyed by connector name, so a newly connected monitor would
# otherwise stay black. Called from Hyprland's monitor.added hook.
restore_wallpaper() {
    local output="$1"
    local wallpaper

    # No daemon means the session is still starting; `theme` paints
    # everything once it is up, so there is nothing to restore yet.
    awww query >/dev/null 2>&1 || return 0

    wallpaper=$(current_wallpaper) || return 1

    if [ -n "$output" ]; then
        # The compositor announces the monitor before the daemon has a
        # surface for it, so wait until awww lists the output.
        for _ in $(seq 1 10); do
            awww query 2>/dev/null | grep -q "^: $output: " && break
            sleep 0.5
        done
        awww img "$wallpaper" --outputs "$output" --transition-type none
    else
        awww img "$wallpaper" --transition-type none
    fi
}

# Return the active theme's wallpaper, resolved by theme-apply.sh.
theme_wallpaper() {
    local wallpaper=""

    if [ -r "$THEME_STATE" ]; then
        wallpaper=$(jq -r '.wallpaper // empty' "$THEME_STATE" 2>/dev/null)
    fi

    if [ -n "$wallpaper" ] && [ -f "$wallpaper" ]; then
        printf '%s\n' "$wallpaper"
        return 0
    fi

    return 1
}

# User extras, then skip a duplicate of the theme wallpaper if the user
# copied it into the extras folder.
user_wallpapers() {
    shopt -s nullglob
    local files=("$USER_WALLPAPER_DIR"/*.{jpg,jpeg,png,JPG,JPEG,PNG})
    shopt -u nullglob
    if ((${#files[@]} > 0)); then
        printf '%s\n' "${files[@]}"
    fi
}

# Theme wallpaper first so an empty extras folder is a no-op cycle, then
# any user extras.
cycle_wallpapers() {
    local theme user

    theme=$(theme_wallpaper) || theme=
    if [ -n "$theme" ]; then
        printf '%s\n' "$theme"
    fi
    while IFS= read -r user; do
        [ -n "$user" ] || continue
        [ "$user" = "$theme" ] && continue
        printf '%s\n' "$user"
    done < <(user_wallpapers)
}

random_wallpaper() {
    local wallpapers=()

    mapfile -t wallpapers < <(cycle_wallpapers)
    if ((${#wallpapers[@]} == 0)); then
        echo "No wallpapers available" >&2
        return 1
    fi

    local random_idx=$((RANDOM % ${#wallpapers[@]}))
    echo "${wallpapers[$random_idx]}"
}

cycle_wallpaper() {
    local wallpapers=() current next_idx=0 i

    mapfile -t wallpapers < <(cycle_wallpapers)
    if ((${#wallpapers[@]} == 0)); then
        echo "No wallpapers available" >&2
        return 1
    fi

    current=$(cat "$CURRENT_WALLPAPER" 2>/dev/null)
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
    restore)
        restore_wallpaper "$2"
        ;;
    *)
        echo "Usage: $0 {set <path>|random|theme|cycle|restore [output]}"
        exit 1
        ;;
esac
