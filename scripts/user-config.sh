#!/usr/bin/env bash

# Config entry points belong to the user unless they are Blankweave's exact
# symlink or an unchanged legacy generated file. Never follow a foreign link.
user_config_link() {
    local source_file=$1 target_file=$2 legacy_file managed=false
    shift 2
    mkdir -p "$(dirname "$target_file")"
    if [[ -L $target_file ]]; then
        if [[ $(readlink -m -- "$target_file") == "$source_file" ]]; then
            return 0
        fi
    elif [[ ! -e $target_file ]]; then
        managed=true
    elif [[ -f $target_file ]]; then
        for legacy_file in "$@"; do
            if cmp -s -- "$target_file" "$legacy_file"; then
                managed=true
                break
            fi
        done
    fi
    if [[ $managed == true ]]; then
        rm -f -- "$target_file"
        ln -s -- "$source_file" "$target_file"
    else
        printf 'Keeping user config: %s\n' "$target_file"
    fi
}

user_config_seed() {
    local source_file=$1 target_file=$2
    mkdir -p "$(dirname "$target_file")"
    if [[ ! -e $target_file && ! -L $target_file ]]; then
        cp -- "$source_file" "$target_file"
    fi
}

# Keep the legacy portion byte-for-byte stable: it identifies generated entry
# points from before overrides existed without claiming a user's edited file.
user_config_hyprland_entry() {
    local voice_enabled=$1
    cat <<'EOF'
local home = os.getenv("HOME")

require(home .. "/.local/share/blankweave/hypr/hyprland")
require(home .. "/.config/hypr/env")
require(home .. "/.config/hypr/monitors")

-- Monitor arrangement chosen in the bar's display panel. The file is written
-- only by monitor-layout.sh and is absent until a position has been picked;
-- a broken or missing file must never keep the compositor from starting.
pcall(dofile, home .. "/.config/blankweave/monitors.lua")
EOF
    if [[ $voice_enabled == true ]]; then
        cat <<'EOF'

require(home .. "/.local/share/blankweave/hypr/voxtype")
EOF
    fi
}

user_config_install_hyprland_entry() (
    local dots_dir=$1 config_dir=$2 voice_enabled=$3 staging
    staging=$(mktemp -d)
    trap 'rm -rf -- "$staging"' EXIT
    user_config_hyprland_entry false > "$staging/legacy.lua"
    user_config_hyprland_entry true > "$staging/legacy-voice.lua"
    user_config_hyprland_entry "$voice_enabled" > "$staging/entry.lua"
    cat >> "$staging/entry.lua" <<'EOF'

-- Personal settings load last, after hardware, theme, display and profile defaults.
require(home .. "/.local/share/blankweave/hypr/user-overrides")
EOF
    local entry_staged
    entry_staged=$(mktemp "$dots_dir/hypr/.entry.lua.XXXXXX")
    install -m 0644 "$staging/entry.lua" "$entry_staged"
    mv -f -- "$entry_staged" "$dots_dir/hypr/entry.lua"
    user_config_link "$dots_dir/hypr/entry.lua" "$config_dir/hypr/hyprland.lua" \
        "$staging/legacy.lua" "$staging/legacy-voice.lua"
)

user_config_install_zsh() (
    local source_file=$1 target_file=$2 staged
    local marker='### ANY CUSTOM CONFIGS GO BELOW THIS LINE'
    if [[ -L $target_file || -e $target_file ]] \
        && { [[ -L $target_file || ! -f $target_file ]] || ! grep -qFx "$marker" "$target_file"; }; then
        printf 'Keeping user config: %s\n' "$target_file"
        return 0
    fi
    staged=$(mktemp "$(dirname "$target_file")/.blankweave-zsh.XXXXXX")
    trap 'rm -f -- "$staged"' EXIT
    if [[ -f $target_file ]]; then
        # Preserve the old custom tail exactly, including trailing newlines.
        sed -n "1,/$marker/p" "$source_file" > "$staged"
        sed "1,/$marker/d" "$target_file" >> "$staged"
    else
        cp -- "$source_file" "$staged"
    fi
    chmod 0644 "$staged"
    mv -f -- "$staged" "$target_file"
)
