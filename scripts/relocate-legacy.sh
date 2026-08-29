#!/usr/bin/env bash
#
# Move a hyprarch-era home layout to its blankweave names. Runs from
# install.sh before anything is deployed, so the theme selection, shell
# preferences, monitor layout, installer choices, user wallpapers, and the
# managed checkout all survive the rename. Every step is a rename of a whole
# directory that only happens when the new name is still free, so the script
# is idempotent and never merges or overwrites.
#
# Usage:
#   relocate-legacy.sh <user-home>

set -euo pipefail

[[ $# -eq 1 ]] || { printf 'usage: relocate-legacy.sh <user-home>\n' >&2; exit 1; }
home=$1
config_home=${XDG_CONFIG_HOME:-$home/.config}
state_home=${XDG_STATE_HOME:-$home/.local/state}
cache_home=${XDG_CACHE_HOME:-$home/.cache}

relocate() {
    local old=$1 new=$2

    [[ -e $old ]] || return 0
    if [[ -e $new ]]; then
        printf 'relocate-legacy: %s already exists; leaving %s in place\n' "$new" "$old" >&2
        return 0
    fi
    mkdir -p "$(dirname "$new")"
    mv -- "$old" "$new"
    printf 'Moved %s -> %s\n' "$old" "$new"
}

relocate "$home/.local/share/hyprarch" "$home/.local/share/blankweave"
relocate "$config_home/hyprarch" "$config_home/blankweave"
relocate "$state_home/hyprarch" "$state_home/blankweave"
relocate "$cache_home/hyprarch" "$cache_home/blankweave"
relocate "$cache_home/hyprarch-wallpaper" "$cache_home/blankweave-wallpaper"
relocate "$cache_home/hyprarch-current-wallpaper" "$cache_home/blankweave-current-wallpaper"

# The old command and the profile line that pointed into the old data dir.
rm -f -- "$home/.local/bin/hyprarch"
if [[ -f $home/.zprofile ]] && grep -qF '/.local/share/hyprarch/shell/profile' "$home/.zprofile"; then
    sed -i '\|/\.local/share/hyprarch/shell/profile|d' "$home/.zprofile"
fi
