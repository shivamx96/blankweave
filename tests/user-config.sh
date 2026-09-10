#!/usr/bin/env bash
set -euo pipefail

repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
# shellcheck source=scripts/user-config.sh
source "$repository/scripts/user-config.sh"

user_home=$test_root/home
dots=$user_home/.local/share/blankweave
config=$user_home/.config
mkdir -p "$dots/hypr" "$config/hypr"

# Fresh install, repeated apply, regular user files, external links (including
# dangling and relative links), and directories must all retain their ownership.
printf 'managed\n' > "$dots/config"
user_config_link "$dots/config" "$config/app/config"
user_config_link "$dots/config" "$config/app/config"
[[ $(readlink "$config/app/config") == "$dots/config" ]]
rm "$config/app/config"
printf 'personal\n' > "$config/app/config"
user_config_link "$dots/config" "$config/app/config"
[[ ! -L $config/app/config && $(< "$config/app/config") == personal ]]
rm "$config/app/config"
ln -s ../personal "$config/app/config"
user_config_link "$dots/config" "$config/app/config"
[[ $(readlink "$config/app/config") == ../personal ]]
printf 'external\n' > "$config/personal"
user_config_link "$dots/config" "$config/app/config"
[[ $(< "$config/personal") == external ]]
rm "$config/app/config"
mkdir "$config/app/config"
user_config_link "$dots/config" "$config/app/config"
[[ -d $config/app/config && ! -L $config/app/config ]]

# Only exact old generated defaults may be adopted. Modified hardware config
# remains active, even when the machine's selected hardware default changes.
cp "$repository/defaults/hardware/env-intel.lua" "$config/hypr/env.lua"
user_config_link "$dots/hypr/hardware-env.lua" "$config/hypr/env.lua" \
    "$repository/defaults/hardware"/env-*.lua
[[ -L $config/hypr/env.lua ]]
rm "$config/hypr/env.lua"
printf 'custom hardware\n' > "$config/hypr/env.lua"
user_config_link "$dots/hypr/hardware-env.lua" "$config/hypr/env.lua" \
    "$repository/defaults/hardware"/env-*.lua
[[ $(< "$config/hypr/env.lua") == 'custom hardware' ]]

# This fixture is the previously deployed entry point, independent of the new
# generator; adoption must work when the voice profile changes during update.
cp "$repository/tests/fixtures/legacy-hyprland.lua" "$config/hypr/hyprland.lua"
user_config_install_hyprland_entry "$dots" "$config" true
[[ $(readlink "$config/hypr/hyprland.lua") == "$dots/hypr/entry.lua" ]]
grep -Fq '/hypr/voxtype' "$config/hypr/hyprland.lua"
user_config_install_hyprland_entry "$dots" "$config" false
if grep -Fq '/hypr/voxtype' "$config/hypr/hyprland.lua"; then
    printf 'Deselected voice bindings were retained.\n' >&2
    exit 1
fi
rm "$config/hypr/hyprland.lua"
cp "$repository/tests/fixtures/legacy-hyprland.lua" "$config/hypr/hyprland.lua"
printf '\nrequire(home .. "/.local/share/blankweave/hypr/voxtype")\n' >> "$config/hypr/hyprland.lua"
user_config_install_hyprland_entry "$dots" "$config" false
[[ -L $config/hypr/hyprland.lua ]]
rm "$config/hypr/hyprland.lua"
printf 'custom compositor\n' > "$config/hypr/hyprland.lua"
user_config_install_hyprland_entry "$dots" "$config" true
[[ $(< "$config/hypr/hyprland.lua") == 'custom compositor' ]]

# Seeds never replace existing content or dangling dotfile-manager symlinks.
overrides=$config/blankweave/overrides
for file in "$repository/defaults/overrides/"*; do
    user_config_seed "$file" "$overrides/$(basename "$file")"
done
printf 'font-size = 17\n' > "$overrides/ghostty.conf"
user_config_seed "$repository/defaults/overrides/ghostty.conf" "$overrides/ghostty.conf"
[[ $(< "$overrides/ghostty.conf") == 'font-size = 17' ]]
rm "$overrides/dunst.conf"
ln -s ./missing.conf "$overrides/dunst.conf"
user_config_seed "$repository/defaults/overrides/dunst.conf" "$overrides/dunst.conf"
[[ $(readlink "$overrides/dunst.conf") == ./missing.conf ]]

# Execute the real generated loader in Lua with stand-in compositor modules.
# User settings must beat theme, hardware, display and optional voice defaults.
cp "$repository/defaults/hypr/user-overrides.lua" "$dots/hypr/"
cat > "$test_root/load.lua" <<'EOF'
local home = os.getenv("HOME")
local order = {}
function require(path)
    if path:match("/user%-overrides$") then
        return dofile(path .. ".lua")
    end
    table.insert(order, path)
    override_value = path
end
dofile(home .. "/.local/share/blankweave/hypr/entry.lua")
assert(#order == 4)
assert(order[4]:match("/voxtype$"))
assert(override_value == "personal")
EOF
printf 'override_value = "display"\n' > "$config/blankweave/monitors.lua"
printf 'override_value = "personal"\n' > "$overrides/hyprland.lua"
HOME="$user_home" lua "$test_root/load.lua"
printf 'this is invalid lua!\n' > "$overrides/hyprland.lua"
if HOME="$user_home" lua "$test_root/load.lua" > /dev/null 2>&1; then
    printf 'Invalid override was silently ignored.\n' >&2
    exit 1
fi
printf 'error("broken override")\n' > "$overrides/hyprland.lua"
if HOME="$user_home" lua "$test_root/load.lua" > /dev/null 2>&1; then
    printf 'Override runtime error was silently ignored.\n' >&2
    exit 1
fi
rm "$overrides/hyprland.lua"
HOME="$user_home" lua "$dots/hypr/user-overrides.lua"

# Zsh updates preserve the legacy custom tail verbatim. Fully custom files and
# external symlinks remain untouched, and the new separate override is seeded.
zshrc=$user_home/.zshrc
user_config_install_zsh "$repository/defaults/shell/.zshrc" "$zshrc"
printf 'alias personal="true"\n\n\n' >> "$zshrc"
sed '1,/### ANY CUSTOM CONFIGS GO BELOW THIS LINE/d' "$zshrc" > "$test_root/tail"
user_config_install_zsh "$repository/defaults/shell/.zshrc" "$zshrc"
sed '1,/### ANY CUSTOM CONFIGS GO BELOW THIS LINE/d' "$zshrc" > "$test_root/new-tail"
# The template's final separator is part of its legacy custom section; avoid
# accumulating it on each apply.
cmp "$test_root/tail" "$test_root/new-tail"
printf 'my shell\n' > "$zshrc"
user_config_install_zsh "$repository/defaults/shell/.zshrc" "$zshrc"
[[ $(< "$zshrc") == 'my shell' ]]
rm "$zshrc"
ln -s ./missing.zsh "$zshrc"
user_config_install_zsh "$repository/defaults/shell/.zshrc" "$zshrc"
[[ $(readlink "$zshrc") == ./missing.zsh ]]

printf 'User configuration tests passed.\n'
