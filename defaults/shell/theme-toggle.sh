#!/usr/bin/env bash
#
# Toggle between the Hyprarch dark/light shell palettes and the corresponding
# legacy application themes. State is stored in ~/.local/share/hyprarch/theme.

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
# Dark -> light pairs. The later entries retain Catppuccin mappings for apps
# that have not yet moved to the native Hyprarch palette.
# Order matters: replace longer/more-specific values first to avoid partial matches
declare -a COLORS=(
    # Hyprarch shell surfaces
    "05080f:edf4ff"
    "0b111c:f8fbff"
    "111a2a:f7fbff"
    "f4f8ff:081426"
    "8798ae:607087"
    "67a6ff:1d4ed8"
    "4f75ad:8ab4ed"
    "33476a:bdd3f3"
    "607da6:91add4"
    "3ddc97:07894f"
    "f4bf50:b46608"
    "ff6b8a:d52149"
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

update_hyprlock_theme() {
    local source_file="$DOTS_DIR/hypr/hyprlock-theme-${TARGET}.conf"
    local target_file="$DOTS_DIR/hypr/hyprlock-theme.conf"
    local staged_file

    [ -f "$source_file" ] || return
    staged_file=$(mktemp --tmpdir="$(dirname "$target_file")" ".$(basename "$target_file").XXXXXX") || return 1
    cp --preserve=mode "$source_file" "$staged_file" || {
        rm -f "$staged_file"
        return 1
    }
    mv -f "$staged_file" "$target_file"
}

# --- Apply to all themed configs ---
swap_colors "$DOTS_DIR/dunst/dunstrc"
swap_colors "$DOTS_DIR/hypr/hyprland.lua"
swap_colors "$DOTS_DIR/fuzzel/fuzzel.ini"

update_fuzzel_icons
update_hyprlock_theme

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
# Reload Dunst in place so the new palette applies without discarding history.
dunstctl reload "$DOTS_DIR/dunst/dunstrc" 2>/dev/null || killall dunst 2>/dev/null
# Hyprland: reload config
hyprctl reload 2>/dev/null
