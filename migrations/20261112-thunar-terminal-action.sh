#!/usr/bin/env bash

set -euo pipefail

actions=${XDG_CONFIG_HOME:-$HOME/.config}/Thunar/uca.xml
stock='<command>exo-open --working-directory %f --launch TerminalEmulator</command>'
managed='<command>ghostty --working-directory=%f</command>'

# Thunar copies its packaged "Open Terminal Here" action into the user's file
# on first run and stamps it with a unique id, so the installer's
# byte-identical adoption never matches a profile that has already opened
# Thunar. The stock command needs exo, which the rice does not install, so the
# action silently does nothing. Repoint only that exact command; a user who
# installed exo or edited the action keeps what they have.
if [[ -f $actions && ! -L $actions ]] && ! command -v exo-open >/dev/null 2>&1 \
    && grep -qF -- "$stock" "$actions"; then
    content=$(< "$actions")
    staged=$(mktemp "$actions.XXXXXX")
    trap 'rm -f -- "$staged"' EXIT
    printf '%s\n' "${content//"$stock"/"$managed"}" > "$staged"
    chmod --reference="$actions" "$staged"
    mv -f -- "$staged" "$actions"
    trap - EXIT
fi
