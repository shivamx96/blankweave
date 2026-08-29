#!/usr/bin/env bash

set -euo pipefail

repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)

cleanup() {
    if [[ -n "$test_root" && -d "$test_root" ]]; then
        rm -rf -- "$test_root"
    fi
}
trap cleanup EXIT HUP INT TERM

home=$test_root/home
mkdir -p "$home/.local/share/hyprarch/repository/.git" \
    "$home/.local/share/hyprarch/wallpapers" \
    "$home/.config/hyprarch/themes/ember" \
    "$home/.local/state/hyprarch" \
    "$home/.cache/hyprarch" \
    "$home/.local/bin"
printf '{"theme":"moss","mode":"light"}\n' > "$home/.config/hyprarch/theme.json"
touch "$home/.local/share/hyprarch/wallpapers/mine.png" \
    "$home/.local/state/hyprarch/migrations-applied" \
    "$home/.cache/hyprarch/git-prs.json" \
    "$home/.local/bin/hyprarch"
printf '/old/wallpaper.png\n' > "$home/.cache/hyprarch-wallpaper"
printf 'export EDITOR=vim\nsource %s/.local/share/hyprarch/shell/profile\nexport FOO=bar\n' "$home" > "$home/.zprofile"

"$repository/scripts/relocate-legacy.sh" "$home" > /dev/null

[[ -d $home/.local/share/blankweave/repository/.git ]]
[[ -f $home/.local/share/blankweave/wallpapers/mine.png ]]
[[ ! -e $home/.local/share/hyprarch ]]
[[ $(jq -r '.theme' "$home/.config/blankweave/theme.json") == moss ]]
[[ -d $home/.config/blankweave/themes/ember ]]
[[ ! -e $home/.config/hyprarch ]]
[[ -f $home/.local/state/blankweave/migrations-applied ]]
[[ -f $home/.cache/blankweave/git-prs.json ]]
[[ $(< "$home/.cache/blankweave-wallpaper") == /old/wallpaper.png ]]
[[ ! -e $home/.local/bin/hyprarch ]]
[[ $(< "$home/.zprofile") == $'export EDITOR=vim\nexport FOO=bar' ]]

# Running again, or on a home that was never hyprarch, changes nothing.
before=$(find "$home" | sort)
"$repository/scripts/relocate-legacy.sh" "$home" > /dev/null
[[ $(find "$home" | sort) == "$before" ]]

# An existing new-name directory is never overwritten by a stale old one.
mkdir -p "$home/.config/hyprarch"
printf 'stale\n' > "$home/.config/hyprarch/theme.json"
"$repository/scripts/relocate-legacy.sh" "$home" 2> /dev/null
[[ $(jq -r '.theme' "$home/.config/blankweave/theme.json") == moss ]]
[[ -f $home/.config/hyprarch/theme.json ]]

printf 'Legacy relocation tests passed.\n'
