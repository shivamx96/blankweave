#!/usr/bin/env bash

set -euo pipefail

config_dir=${XDG_CONFIG_HOME:-$HOME/.config}
data_dir=$HOME/.local/share/blankweave

# The native Quickshell launcher replaced Fuzzel, so the installer no longer
# deploys the config or the symlink to it. Redeployment cannot remove either,
# and the leftover link would dangle once the rendered ini is gone.
if [[ -L $config_dir/fuzzel/fuzzel.ini ]]; then
    link_target=$(readlink -- "$config_dir/fuzzel/fuzzel.ini")
    if [[ $link_target == "$data_dir/fuzzel/fuzzel.ini" ]]; then
        rm -f -- "$config_dir/fuzzel/fuzzel.ini"
        rmdir -- "$config_dir/fuzzel" 2> /dev/null || true
    fi
fi

# A user's own file at that path is theirs to keep; only the managed copy goes.
rm -rf -- "$data_dir/fuzzel"
rm -f -- "$data_dir/shell/power-menu.sh"
