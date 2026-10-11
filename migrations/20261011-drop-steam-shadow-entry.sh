#!/usr/bin/env bash

set -euo pipefail

applications_dir=${XDG_DATA_HOME:-$HOME/.local/share}/applications
entry=$applications_dir/steam.desktop

# A development revision of the HiDPI change shadowed Steam's desktop entry
# with one that launched through shell/xwayland-launch.sh. Steam dropped the
# scaling switch that wrapper set, so the wrapper is gone and the entry would
# now point at a missing executable while still hiding the packaged launcher.
# Only Blankweave's own tagged entry is removed; a user's launcher is theirs.
if [[ -f $entry && ! -L $entry ]] && grep -qsx 'X-Blankweave-Entry=steam' "$entry"; then
    rm -f -- "$entry"
fi
