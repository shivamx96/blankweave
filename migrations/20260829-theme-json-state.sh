#!/usr/bin/env bash

set -euo pipefail

data_dir=$HOME/.local/share/hyprarch

# The dark/light choice now lives in ~/.config/hyprarch/theme.json, written by
# theme-apply.sh. The installer ran it before this migration and it seeded the
# mode from the old plain-text file, so that file is now only a stale duplicate.
# The Hyprlock variants and the sed-based toggle were replaced by rendering
# from one template; their deployed copies are never removed by a plain copy.
rm -f -- \
    "$data_dir/theme" \
    "$data_dir/hypr/hyprlock-theme-dark.conf" \
    "$data_dir/hypr/hyprlock-theme-light.conf" \
    "$data_dir/shell/theme-toggle.sh"
