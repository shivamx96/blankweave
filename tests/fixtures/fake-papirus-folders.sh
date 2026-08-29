#!/usr/bin/env bash
#
# Stand-in for papirus-folders. Logs the invocation to $FAKE_LOG and repoints
# the theme's folder.svg symlink the way the real tool does, so a test can see
# the colour take effect through the same readlink theme-system.sh uses.

set -euo pipefail

printf 'papirus-folders %s\n' "$*" >> "${FAKE_LOG:?FAKE_LOG must be set}"

color=""
theme=Papirus
while [[ $# -gt 0 ]]; do
    case $1 in
        -C|--color) color=$2; shift 2 ;;
        -t|--theme) theme=$2; shift 2 ;;
        *) shift ;;
    esac
done

IFS=: read -r data_dir _ <<< "${XDG_DATA_DIRS:-/usr/share}"
places=$data_dir/icons/$theme/48x48/places
[[ -d $places ]] || { printf 'fake papirus-folders: no theme at %s\n' "$places" >&2; exit 1; }
ln -sfn "folder-$color.svg" "$places/folder.svg"
