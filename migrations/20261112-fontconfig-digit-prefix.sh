#!/usr/bin/env bash
set -euo pipefail

legacy=${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig/conf.d/local.conf
# Only the exact symlink installed by Blankweave is ours, even if dangling.
# Do not follow a foreign link, adopt a regular file, or remove its target.
if [[ -L $legacy && $(readlink -- "$legacy") == "$HOME/.local/share/blankweave/fontconfig/local.conf" ]]; then
    rm -- "$legacy"
fi
