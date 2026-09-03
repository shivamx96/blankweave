#!/usr/bin/env bash

set -u

action=${1:-toggle}
runtime_root=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
voxtype_runtime=$runtime_root/voxtype
blankweave_runtime=$runtime_root/blankweave
mode_file=$blankweave_runtime/voxtype-output-mode
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

case $action in
    stop|cancel)
        exec voxtype record "$action"
        ;;
    start|toggle)
        ;;
    *)
        printf 'Usage: %s [start|stop|toggle|cancel]\n' "${0##*/}" >&2
        exit 2
        ;;
esac

# Toggle preserves the route chosen when recording began.
if [[ $action == toggle && -r $voxtype_runtime/state ]]; then
    state=$(< "$voxtype_runtime/state")
    if [[ $state != idle ]]; then
        exec voxtype record toggle
    fi
fi

mkdir -p "$blankweave_runtime"
rm -f -- "$mode_file"

focus_result=2
if [[ -n ${BLANKWEAVE_VOXTYPE_FOCUS:-} ]]; then
    "$script_dir/voxtype-focus.py" </dev/null
    focus_result=$?
elif active_window=$(hyprctl -j activewindow 2>/dev/null); then
    timeout 0.7s "$script_dir/voxtype-focus.py" <<< "$active_window"
    focus_result=$?
fi

if [[ $focus_result -eq 1 ]]; then
    printf 'clipboard\n' > "$mode_file"
    exec voxtype record "$action" --clipboard
fi

# Missing AT-SPI data is deliberately not treated as a missing field. Apps
# that do expose accessibility get the Flow-style clipboard fallback; opaque
# apps keep normal typing and surface a one-click recovery preview afterward.
if [[ $focus_result -eq 2 ]]; then
    printf 'unverified\n' > "$mode_file"
fi
exec voxtype record "$action"
