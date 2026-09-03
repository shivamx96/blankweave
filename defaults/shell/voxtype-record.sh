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
    python3 "$script_dir/voxtype-focus.py" </dev/null
    focus_result=$?
elif active_window=$(hyprctl -j activewindow 2>/dev/null); then
    timeout 0.7s python3 "$script_dir/voxtype-focus.py" <<< "$active_window"
    focus_result=$?
fi

case $focus_result in
    0)
        exec voxtype record "$action"
        ;;
    1)
        printf 'clipboard\n' > "$mode_file"
        exec voxtype record "$action" --clipboard
        ;;
    *)
        # Missing AT-SPI data, helper failures, and timeouts are all unknown.
        # Keep normal typing, retain the text, and offer one-click recovery.
        printf 'unverified\n' > "$mode_file"
        exec voxtype record "$action"
        ;;
esac
