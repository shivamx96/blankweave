#!/usr/bin/env bash
#
# Toggle between Catppuccin Mocha (dark) and Latte (light) across all themed apps.
# State is stored in ~/.local/share/hyprarch/theme

DOTS_DIR="$HOME/.local/share/hyprarch"
STATE_FILE="$DOTS_DIR/theme"

# Read current theme (default: dark)
CURRENT="dark"
[ -f "$STATE_FILE" ] && CURRENT=$(cat "$STATE_FILE")

if [ "$CURRENT" = "dark" ]; then
    TARGET="light"
else
    TARGET="dark"
fi

# --- Color maps ---
# Mocha (dark) -> Latte (light) pairs
# Order matters: replace longer/more-specific values first to avoid partial matches
declare -a COLORS=(
    # base
    "1e1e2e:eff1f5"
    # mantle
    "181825:e6e9ef"
    # crust
    "11111b:dce0e8"
    # surface0
    "313244:ccd0da"
    # surface1
    "45475a:bcc0cc"
    # text
    "cdd6f4:4c4f69"
    # subtext
    "a6adc8:6c6f85"
    # lavender
    "b4befe:7287fd"
    # mauve
    "cba6f7:8839ef"
    # pink
    "f5c2e7:ea76cb"
    # rosewater
    "f5e0dc:dc8a78"
    # red
    "f38ba8:d20f39"
    # peach
    "fab387:fe640b"
    # green
    "a6e3a1:40a02b"
    # teal
    "94e2d5:179299"
    # blue
    "89b4fa:1e66f5"
    # sky
    "89dceb:04a5e5"
)

swap_colors() {
    local file="$1"
    local staged_file
    [ -f "$file" ] || return

    # Hyprland watches its Lua config and may reload after every write. Do all
    # placeholder substitutions off to the side, then expose only the finished
    # file with one atomic rename so it can never parse an intermediate value.
    staged_file=$(mktemp --tmpdir="$(dirname "$file")" ".$(basename "$file").XXXXXX") || return 1
    cp --preserve=mode "$file" "$staged_file" || {
        rm -f "$staged_file"
        return 1
    }

    for pair in "${COLORS[@]}"; do
        local mocha="${pair%%:*}"
        local latte="${pair##*:}"

        if [ "$TARGET" = "light" ]; then
            # dark -> light: replace mocha with latte
            # Use a temporary placeholder to avoid double-replacement
            sed -i "s/${mocha}/PLACEHOLDER_${mocha}/gi" "$staged_file"
        else
            # light -> dark: replace latte with mocha
            sed -i "s/${latte}/PLACEHOLDER_${latte}/gi" "$staged_file"
        fi
    done

    # Now replace all placeholders with the target colors
    for pair in "${COLORS[@]}"; do
        local mocha="${pair%%:*}"
        local latte="${pair##*:}"

        if [ "$TARGET" = "light" ]; then
            sed -i "s/PLACEHOLDER_${mocha}/${latte}/gi" "$staged_file"
        else
            sed -i "s/PLACEHOLDER_${latte}/${mocha}/gi" "$staged_file"
        fi
    done

    mv -f "$staged_file" "$file"
}

# Update fuzzel icon theme
update_fuzzel_icons() {
    local file="$DOTS_DIR/fuzzel/fuzzel.ini"
    [ -f "$file" ] || return

    if [ "$TARGET" = "light" ]; then
        sed -i 's/icon-theme=Papirus-Dark/icon-theme=Papirus-Light/' "$file"
    else
        sed -i 's/icon-theme=Papirus-Light/icon-theme=Papirus-Dark/' "$file"
    fi
}

# --- Apply to all themed configs ---
swap_colors "$DOTS_DIR/dunst/dunstrc"
swap_colors "$DOTS_DIR/hypr/hyprland.lua"
swap_colors "$DOTS_DIR/fuzzel/fuzzel.ini"

update_fuzzel_icons

# Touch symlinks so inotify-based apps (Ghostty, etc.) detect the change
CONFIG_DIR="$HOME/.config"
for link in "$CONFIG_DIR/ghostty/config" "$CONFIG_DIR/dunst/dunstrc" "$CONFIG_DIR/fuzzel/fuzzel.ini"; do
    [ -L "$link" ] && touch -h "$link" 2>/dev/null
done

# --- Save new state ---
echo "$TARGET" > "$STATE_FILE"

# --- Set system color-scheme (portal / GTK / browsers) ---
if [ "$TARGET" = "light" ]; then
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
    gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita'
    GTK_DARK=0
else
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
    GTK_DARK=1
fi

# Write GTK settings.ini — GTK3 apps on Hyprland (no GNOME settings daemon)
# read from this file rather than gsettings
mkdir -p "$HOME/.config/gtk-3.0"
cat > "$HOME/.config/gtk-3.0/settings.ini" << EOF
[Settings]
gtk-application-prefer-dark-theme=$GTK_DARK
gtk-theme-name=Adwaita
EOF

mkdir -p "$HOME/.config/gtk-4.0"
cat > "$HOME/.config/gtk-4.0/settings.ini" << EOF
[Settings]
gtk-application-prefer-dark-theme=$GTK_DARK
gtk-theme-name=Adwaita
EOF

# --- Reload services ---
# Quickshell watches the shared theme state file and updates live.
# Dunst: kill it; it auto-restarts on next notification
killall dunst 2>/dev/null
# Hyprland: reload config
hyprctl reload 2>/dev/null

# --- Notify ---
if [ "$TARGET" = "light" ]; then
    notify-send -t 2000 "Theme" "Switched to Catppuccin Latte (light)"
else
    notify-send -t 2000 "Theme" "Switched to Catppuccin Mocha (dark)"
fi
