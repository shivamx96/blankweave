#!/usr/bin/env bash

set -euo pipefail

repository=$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)

cleanup() {
    if [[ -n $test_root && -d $test_root ]]; then
        rm -rf -- "$test_root"
    fi
}
trap cleanup EXIT HUP INT TERM

fake_bin=$test_root/fake-bin
mkdir -p "$fake_bin"
ln -s "$repository/tests/fixtures/fake-log.sh" "$fake_bin/awww"

home=$test_root/home
config=$home/.config/blankweave
extras=$config/wallpapers
theme_dir=$home/.local/share/blankweave/themes/obsidian
mkdir -p "$extras" "$theme_dir" "$home/.cache"

theme_png=$theme_dir/obsidian-dark.png
extra_a=$extras/extra-a.png
extra_b=$extras/extra-b.png
touch -- "$theme_png"

printf '{"wallpaper":"%s"}\n' "$theme_png" > "$config/theme.json"

export HOME=$home
export XDG_CONFIG_HOME=$home/.config
export FAKE_LOG=$test_root/side-effects.log
export PATH=$fake_bin:$PATH
export LC_ALL=C
: > "$FAKE_LOG"

script=$repository/defaults/shell/wallpaper.sh
cache=$home/.cache/blankweave-wallpaper

bash "$script" theme
[[ $(< "$cache") == "$theme_png" ]]
grep -Fq "awww img $theme_png" "$FAKE_LOG"

# With no extras, cycling restores the theme wallpaper instead of failing.
: > "$FAKE_LOG"
bash "$script" cycle
[[ $(< "$cache") == "$theme_png" ]]
grep -Fq "awww img $theme_png" "$FAKE_LOG"

touch -- "$extra_a" "$extra_b"
bash "$script" theme
: > "$FAKE_LOG"
bash "$script" cycle
[[ $(< "$cache") == "$extra_a" ]]
bash "$script" cycle
[[ $(< "$cache") == "$extra_b" ]]
bash "$script" cycle
[[ $(< "$cache") == "$theme_png" ]]

# random with extras stays inside the cycle list.
: > "$FAKE_LOG"
bash "$script" random
chosen=$(< "$cache")
[[ $chosen == "$theme_png" || $chosen == "$extra_a" || $chosen == "$extra_b" ]]

# Without a theme wallpaper, extras still cycle.
rm -f -- "$config/theme.json" "$theme_png"
bash "$script" cycle
[[ $(< "$cache") == "$extra_a" || $(< "$cache") == "$extra_b" ]]

# Neither extras nor a theme is an error, not a trip through a missing pack.
rm -f -- "$extra_a" "$extra_b"
if bash "$script" cycle 2>/dev/null; then
    printf 'cycle with no wallpapers unexpectedly succeeded.\n' >&2
    exit 1
fi

printf 'Wallpaper tests passed.\n'
