#!/usr/bin/env bash
set -euo pipefail
command -v zsh >/dev/null || { echo 'SKIP zsh keys: zsh unavailable'; exit 0; }
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
for terminal in xterm-ghostty xterm-256color linux; do
    if ! infocmp "$terminal" >/dev/null 2>&1; then
        echo "SKIP zsh keys: $terminal terminfo unavailable"
        continue
    fi
    HOME="$temporary" ZDOTDIR="$temporary" TERM="$terminal" zsh -f -c '
        source "$1"
        for map in emacs viins; do
            for sequence widget in \
                $'"'"'\e[H'"'"' beginning-of-line $'"'"'\eOH'"'"' beginning-of-line \
                $'"'"'\e[F'"'"' end-of-line $'"'"'\eOF'"'"' end-of-line \
                $'"'"'\e[1~'"'"' beginning-of-line $'"'"'\e[4~'"'"' end-of-line \
                $'"'"'\e[3~'"'"' delete-char \
                $'"'"'\e[1;5D'"'"' backward-word $'"'"'\e[1;5C'"'"' forward-word \
                $'"'"'\e[3;5~'"'"' kill-word $'"'"'\x08'"'"' backward-kill-word \
                $'"'"'\e[5~'"'"' history-search-backward $'"'"'\e[6~'"'"' history-search-forward; do
                actual=$(bindkey -M "$map" "$sequence")
                [[ $actual == *" $widget" ]] || { print -u2 -- "$TERM $map: $actual expected $widget"; exit 1; }
            done
        done
    ' test "$repository/defaults/shell/zsh-keys.zsh"
done
echo 'Zsh key tests passed.'
