#!/usr/bin/env bash
#
# Install the parts of the active theme that need root: the Papirus folder
# colour and the Plymouth boot splash. Everything else a theme carries is
# applied by the user's theme-apply.sh, which also stages the rendered splash
# under ~/.local/share/hyprarch/plymouth/hyprarch/ for this script to copy.
#
# Runs from install.sh on every apply and from `hyprarch theme sync`; each
# step compares before it acts, so a run with nothing to do touches nothing
# and never rebuilds the initramfs.
#
# Usage:
#   theme-system.sh <user-home> [<config-dir>]

set -euo pipefail

ICONS_DIR=${HYPRARCH_ICONS_DIR:-/usr/share/icons}
PLYMOUTH_DIR=${HYPRARCH_PLYMOUTH_DIR:-/usr/share/plymouth/themes/hyprarch}
BOOT_ENTRIES=${HYPRARCH_BOOT_ENTRIES:-/boot/loader/entries}
PLYMOUTH_FILES=(hyprarch.plymouth hyprarch.script logo.png progress_bar.png progress_box.png)
PAPIRUS_THEMES=(Papirus Papirus-Dark Papirus-Light)

die() {
    printf 'theme-system: %s\n' "$*" >&2
    exit 1
}

[[ $# -eq 1 || $# -eq 2 ]] || die "usage: theme-system.sh <user-home> [<config-dir>]"
user_home=$1
config_dir=${2:-$user_home/.config}
state=$config_dir/hyprarch/theme.json
stage=$user_home/.local/share/hyprarch/plymouth/hyprarch

[[ -r $state ]] || die "no theme state at $state; apply the theme first"
[[ -w $(dirname "$PLYMOUTH_DIR") ]] || die "needs root: run through sudo or hyprarch theme sync"

current_folder_color() {
    local link
    link=$(readlink "$1/48x48/places/folder.svg" 2> /dev/null) || return 1
    link=${link#folder-}
    printf '%s\n' "${link%.svg}"
}

sync_folders() {
    local color theme current

    color=$(jq -r '.folderColor // empty' "$state")
    [[ -n $color ]] || return 0
    [[ $color =~ ^[a-z]+$ ]] || die "invalid folder colour: $color"
    if ! command -v papirus-folders > /dev/null; then
        printf 'papirus-folders is not installed; folder colours left as they are.\n'
        return 0
    fi

    # Papirus-Dark and Papirus-Light carry their own places/ symlinks, so the
    # colour is applied to each installed variant, and only when it differs:
    # papirus-folders rewrites every size and refreshes the icon caches.
    for theme in "${PAPIRUS_THEMES[@]}"; do
        [[ -d $ICONS_DIR/$theme ]] || continue
        current=$(current_folder_color "$ICONS_DIR/$theme") || current=""
        [[ $current == "$color" ]] && continue
        printf 'Folder colour for %s: %s -> %s\n' "$theme" "${current:-unset}" "$color"
        XDG_DATA_DIRS=$(dirname "$ICONS_DIR") papirus-folders -C "$color" -t "$theme" > /dev/null
    done
}

sync_boot_splash() {
    local file changed=false

    for file in "${PLYMOUTH_FILES[@]}"; do
        if [[ ! -f $stage/$file ]]; then
            printf 'Boot splash stage is incomplete (%s missing); left as it is.\n' "$file"
            return 0
        fi
    done
    if ! command -v plymouth-set-default-theme > /dev/null; then
        printf 'Plymouth is not installed; boot splash skipped.\n'
        return 0
    fi

    for file in "${PLYMOUTH_FILES[@]}"; do
        cmp -s "$stage/$file" "$PLYMOUTH_DIR/$file" || changed=true
    done
    if [[ $changed == false ]]; then
        printf 'Boot splash already current.\n'
        return 0
    fi

    printf 'Installing the boot splash and rebuilding the initramfs...\n'
    mkdir -p "$PLYMOUTH_DIR"
    for file in "${PLYMOUTH_FILES[@]}"; do
        install -m 0644 "$stage/$file" "$PLYMOUTH_DIR/$file"
    done
    plymouth-set-default-theme -R hyprarch
}

# The console behind the splash is painted with the kernel's vt.default_*
# colours from the boot entry; keep them on the theme's dark canvas.
sync_console_colors() {
    local canvas red green blue entry wanted

    canvas=$(jq -r '.modes.dark.colors.canvas // empty' "$state")
    [[ $canvas =~ ^#[0-9A-Fa-f]{6} ]] || return 0
    red=$((16#${canvas:1:2}))
    green=$((16#${canvas:3:2}))
    blue=$((16#${canvas:5:2}))
    wanted="vt.default_red=$red vt.default_grn=$green vt.default_blu=$blue"

    [[ -d $BOOT_ENTRIES ]] || return 0
    for entry in "$BOOT_ENTRIES"/*.conf; do
        [[ -f $entry ]] || continue
        grep -q 'vt\.default_red=' "$entry" || continue
        grep -Fq "$wanted" "$entry" && continue
        printf 'Console colours in %s: %s\n' "$(basename "$entry")" "$wanted"
        sed -i -E "s/vt\.default_red=[0-9]+ vt\.default_grn=[0-9]+ vt\.default_blu=[0-9]+/$wanted/" "$entry"
    done
}

sync_folders
sync_boot_splash
sync_console_colors
