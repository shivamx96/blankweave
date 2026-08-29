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

expect_failure() {
    if "$@" 2> /dev/null; then
        printf 'Expected failure: %s\n' "$*" >&2
        exit 1
    fi
}

# Every desktop side effect goes through a logging stand-in so the test can
# never touch the developer's real session.
fake_bin=$test_root/fake-bin
mkdir -p "$fake_bin"
for command in gsettings dunstctl hyprctl awww; do
    ln -s "$repository/tests/fixtures/fake-log.sh" "$fake_bin/$command"
done
ln -s "$repository/tests/fixtures/fake-gdbus.sh" "$fake_bin/gdbus"

home=$test_root/home
data=$home/.local/share/hyprarch
mkdir -p "$data" "$home/.config"
for directory in dunst fuzzel ghostty hypr plymouth shell themes; do
    cp -R "$repository/defaults/$directory" "$data/"
done

export HOME=$home
export XDG_CONFIG_HOME=$home/.config
export FAKE_LOG=$test_root/side-effects.log
export PATH=$fake_bin:$PATH
export WAYLAND_DISPLAY=wayland-test
export HYPRLAND_INSTANCE_SIGNATURE=test
# The root-owned parts are looked up, never written, here; point the lookups
# at an empty sandbox so the developer's machine never leaks into a result.
export HYPRARCH_ICONS_DIR=$test_root/icons
export HYPRARCH_PLYMOUTH_DIR=$test_root/plymouth
: > "$FAKE_LOG"

script=$data/shell/theme-apply.sh
state=$XDG_CONFIG_HOME/hyprarch/theme.json
dunstrc=$data/dunst/dunstrc
fuzzel=$data/fuzzel/fuzzel.ini
ghostty=$data/ghostty/config
hyprlock=$data/hypr/hyprlock-theme.conf
hypr_theme=$XDG_CONFIG_HOME/hyprarch/theme.lua
plymouth=$data/plymouth/hyprarch/hyprarch.script

assert_rendered() {
    local file
    for file in "$dunstrc" "$fuzzel" "$ghostty" "$hyprlock" "$hypr_theme" "$plymouth"; do
        [[ -f $file ]]
        if grep -q '{{' "$file"; then
            printf 'Unrendered placeholder in %s\n' "$file" >&2
            exit 1
        fi
    done
}

# A fresh apply resolves the bundled default in dark mode and renders every
# consumer in its own colour notation.
"$script"
assert_rendered
[[ $(jq -r '.theme' "$state") == obsidian ]]
[[ $(jq -r '.mode' "$state") == dark ]]
[[ $(jq -r '.name' "$state") == Obsidian ]]
[[ $(jq -r '.colors.accent' "$state") == '#3b82f6' ]]
[[ $(jq -r '.wallpaper' "$state") == "$data/themes/obsidian/obsidian-dark.png" ]]
[[ -f $(jq -r '.wallpaper' "$state") ]]
grep -Fxq 'background = "#0b111c"' "$dunstrc"
grep -Fxq 'frame_color = "#4f75ad"' "$dunstrc"
grep -Fq "foreground='#8798ae'" "$dunstrc"
grep -Fxq 'background=0b111ce6' "$fuzzel"
grep -Fxq 'selection=3b82f625' "$fuzzel"
grep -Fxq 'icon-theme=Papirus-Dark' "$fuzzel"
grep -Fxq 'theme = light:Catppuccin Latte,dark:Catppuccin Mocha' "$ghostty"
grep -Fxq "\$accent = rgba(3b82f6ff)" "$hyprlock"
grep -Fxq "\$input_border = rgba(33476aff) rgba(3b82f6ff) rgba(67a6ffff) 90deg" "$hyprlock"
grep -Fxq "\$placeholder = <span foreground=\"##8798ae\">Password</span>" "$hyprlock"
grep -Eq "^\\\$background_contrast = 0\\.98$" "$hyprlock"
grep -Fq 'active_border = { "rgba(3b82f6ff)", "rgba(67a6ffff)" },' "$hypr_theme"
grep -Fq 'inactive_border = "rgba(33476aff)",' "$hypr_theme"
grep -Fq 'cursor_theme = "Bibata-Modern-Ice",' "$hypr_theme"
grep -Fxq 'Window.SetBackgroundTopColor(0.02, 0.031, 0.059);' "$plymouth"
grep -Fxq 'Window.SetBackgroundBottomColor(0.02, 0.031, 0.059);' "$plymouth"
cmp -s "$data/plymouth/hyprarch/logo.png" "$data/themes/obsidian/plymouth/logo.png"
grep -Fxq 'gtk-application-prefer-dark-theme=1' "$XDG_CONFIG_HOME/gtk-3.0/settings.ini"
grep -Fxq 'gtk-icon-theme-name=Papirus-Dark' "$XDG_CONFIG_HOME/gtk-3.0/settings.ini"
grep -Fxq 'gtk-cursor-theme-name=Bibata-Modern-Ice' "$XDG_CONFIG_HOME/gtk-4.0/settings.ini"
grep -Fxq 'gsettings set org.gnome.desktop.interface icon-theme Papirus-Dark' "$FAKE_LOG"
grep -Fxq 'gsettings set org.gnome.desktop.interface cursor-theme Bibata-Modern-Ice' "$FAKE_LOG"
grep -Fxq 'hyprctl setcursor Bibata-Modern-Ice 24' "$FAKE_LOG"
grep -Fxq 'gtk-application-prefer-dark-theme=1' "$XDG_CONFIG_HOME/gtk-4.0/settings.ini"
grep -Fxq 'gsettings set org.gnome.desktop.interface color-scheme prefer-dark' "$FAKE_LOG"
grep -Fq "awww img $data/themes/obsidian/obsidian-dark.png" "$FAKE_LOG"
grep -Fxq 'hyprctl reload' "$FAKE_LOG"
grep -Fxq "dunstctl reload $dunstrc" "$FAKE_LOG"
grep -Fq 'gdbus call --session --dest com.mitchellh.ghostty --object-path /com/mitchellh/ghostty --method org.gtk.Actions.Activate reload-config [] {}' "$FAKE_LOG"
[[ $(< "$home/.cache/hyprarch-wallpaper") == "$data/themes/obsidian/obsidian-dark.png" ]]

# The rendered configs are complete files, not just colour lines.
grep -Fxq 'font = Atkinson Hyperlegible Next 11' "$dunstrc"
grep -Fxq 'match-mode=fzf' "$fuzzel"
grep -Fxq 'font-family = JetBrains Mono Nerd Font' "$ghostty"

# Toggling keeps the theme and flips only the mode, everywhere at once.
: > "$FAKE_LOG"
"$script" toggle
assert_rendered
[[ $(jq -r '.theme' "$state") == obsidian ]]
[[ $(jq -r '.mode' "$state") == light ]]
[[ $(jq -r '.label' "$state") == Porcelain ]]
grep -Fxq 'background = "#f8fbff"' "$dunstrc"
grep -Fxq 'icon-theme=Papirus-Light' "$fuzzel"
grep -Fxq "\$accent = rgba(1d4ed8ff)" "$hyprlock"
grep -Fq 'active_border = { "rgba(2563ebff)", "rgba(1d4ed8ff)" },' "$hypr_theme"
grep -Fq 'cursor_theme = "Bibata-Modern-Classic",' "$hypr_theme"
grep -Fxq 'gtk-application-prefer-dark-theme=0' "$XDG_CONFIG_HOME/gtk-3.0/settings.ini"
grep -Fxq 'gtk-cursor-theme-name=Bibata-Modern-Classic' "$XDG_CONFIG_HOME/gtk-3.0/settings.ini"
grep -Fxq 'hyprctl setcursor Bibata-Modern-Classic 24' "$FAKE_LOG"
grep -Fxq 'gsettings set org.gnome.desktop.interface color-scheme prefer-light' "$FAKE_LOG"
grep -Fq "awww img $data/themes/obsidian/porcelain-light.png" "$FAKE_LOG"

# Ghostty is D-Bus activatable, so when it is not running the reload must not
# be sent or it would launch a terminal.
: > "$FAKE_LOG"
FAKE_GDBUS_OWNED=false "$script" toggle
grep -Fq 'NameHasOwner com.mitchellh.ghostty' "$FAKE_LOG"
expect_failure grep -Fq 'Activate reload-config' "$FAKE_LOG"
"$script" toggle

# The wallpaper script hands the boot-time restore the theme's wallpaper.
bash "$data/shell/wallpaper.sh" theme > /dev/null
[[ $(< "$home/.cache/hyprarch-wallpaper") == "$data/themes/obsidian/porcelain-light.png" ]]

# Applying with no state honours the pre-theme mode file so an update never
# flips an existing light-mode install back to dark.
rm -f "$state"
printf 'light\n' > "$data/theme"
"$script"
[[ $(jq -r '.mode' "$state") == light ]]
rm -f "$data/theme"

# Every bundled theme must resolve and render in both modes, so a palette
# missing a token or a wallpaper can never ship.
for theme_file in "$data"/themes/*/theme.json; do
    theme_id=$(basename "$(dirname "$theme_file")")
    for theme_mode in dark light; do
        "$script" set "$theme_id"
        "$script" mode "$theme_mode"
        assert_rendered
        [[ $(jq -r '.theme' "$state") == "$theme_id" ]]
        [[ $(jq -r '.mode' "$state") == "$theme_mode" ]]
        [[ -f $(jq -r '.wallpaper' "$state") ]]
        [[ $(jq -r '.colors | length' "$state") -ge 20 ]]
        [[ -f $(jq -r '.plymouth.logo' "$state") ]]
        [[ -f $(jq -r '.plymouth.progressBar' "$state") ]]
        [[ $(jq -r '.folderColor' "$state") =~ ^[a-z]+$ ]]
        [[ $(jq -r '.modes.dark.colors.canvas' "$state") =~ ^#[0-9a-f]{6}$ ]]
    done
done
"$script" set obsidian
"$script" mode light

# A user theme under ~/.config shadows the bundled set and is listed as such.
user_theme=$XDG_CONFIG_HOME/hyprarch/themes/ember
mkdir -p "$user_theme"
jq '.name = "Ember"
    | .description = "Test theme"
    | .modes.dark.colors.accent = "#ff5500"
    | .modes.dark.colors.accentBright = "#ff7733"
    | .modes.dark.wallpaper = "/nonexistent/ember.png"' \
    "$data/themes/obsidian/theme.json" > "$user_theme/theme.json"
: > "$FAKE_LOG"
"$script" set ember
assert_rendered
[[ $(jq -r '.theme' "$state") == ember ]]
[[ $(jq -r '.mode' "$state") == light ]]
"$script" mode dark
[[ $(jq -r '.mode' "$state") == dark ]]
[[ $(jq -r '.colors.accent' "$state") == '#ff5500' ]]
grep -Fxq 'highlight = "#ff7733"' "$dunstrc"
grep -Fxq 'match=ff7733ff' "$fuzzel"
grep -Fq 'active_border = { "rgba(ff5500ff)", "rgba(ff7733ff)" },' "$hypr_theme"
# A missing wallpaper never blocks the palette change.
expect_failure grep -Fq 'awww img /nonexistent' "$FAKE_LOG"

listing=$("$script" list)
bundled_themes=("$data"/themes/*/theme.json)
[[ $(jq -r 'length' <<< "$listing") == $(( ${#bundled_themes[@]} + 1 )) ]]
[[ $(jq -r '.[] | select(.id == "ember") | .source' <<< "$listing") == user ]]
[[ $(jq -r '.[] | select(.id == "obsidian") | .source' <<< "$listing") == bundled ]]
[[ $(jq -r '.[] | select(.id == "obsidian") | .modes | length' <<< "$listing") == 2 ]]
[[ $(jq -r '.[] | select(.id == "ember") | .modes[] | select(.mode == "dark") | .accent' <<< "$listing") == '#ff5500' ]]
[[ $(jq -r '.theme' <<< "$("$script" status)") == ember ]]
# Nothing root-owned is present in the sandbox, so nothing can be pending.
[[ $(jq -r '.system.pending' <<< "$("$script" status)") == false ]]

# Invalid requests fail before anything is touched.
before=$(cat "$state" "$dunstrc")
expect_failure "$script" set nope
expect_failure "$script" set '../escape'
expect_failure "$script" mode purple
expect_failure "$script" bogus
[[ $(cat "$state" "$dunstrc") == "$before" ]]

# A theme missing a companion token is rejected with a message naming it.
broken=$XDG_CONFIG_HOME/hyprarch/themes/nocursor
mkdir -p "$broken"
jq 'del(.modes.dark.cursorTheme)' "$data/themes/obsidian/theme.json" > "$broken/theme.json"
if "$script" set nocursor 2> "$test_root/nocursor.err"; then
    printf 'A theme missing cursorTheme must be rejected.\n' >&2
    exit 1
fi
grep -Fq 'missing: cursorTheme' "$test_root/nocursor.err"

# A theme missing a palette token is rejected rather than rendered with holes.
broken=$XDG_CONFIG_HOME/hyprarch/themes/broken
mkdir -p "$broken"
jq 'del(.modes.dark.colors.accent)' "$data/themes/obsidian/theme.json" > "$broken/theme.json"
if "$script" set broken 2> "$test_root/broken.err"; then
    printf 'A theme missing a colour token must be rejected.\n' >&2
    exit 1
fi
grep -Fq 'missing colours: accent' "$test_root/broken.err"
[[ $(jq -r '.theme' "$state") == ember ]]

# An unknown placeholder in a template aborts the render and leaves no
# staged output behind the previously rendered file.
printf '\nbogus = "{{colors.nothing}}"\n' >> "$data/dunst/dunstrc.tmpl"
if "$script" 2> "$test_root/placeholder.err"; then
    printf 'An unknown placeholder must fail the render.\n' >&2
    exit 1
fi
grep -Fq 'unknown placeholder: colors.nothing' "$test_root/placeholder.err"
grep -Fxq 'highlight = "#ff7733"' "$dunstrc"
[[ -z $(find "$data/dunst" -name '.dunstrc.*') ]]

printf 'Theme apply tests passed.\n'
