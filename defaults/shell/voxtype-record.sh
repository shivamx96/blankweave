#!/usr/bin/env bash

set -u

action=${1:-toggle}
runtime_root=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
voxtype_runtime=$runtime_root/voxtype
blankweave_runtime=$runtime_root/blankweave
mode_file=$blankweave_runtime/voxtype-output-mode
pending_file=$blankweave_runtime/voxtype-pending-start
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

case $action in
    stop|cancel|start|start-clipboard|toggle)
        ;;
    *)
        printf 'Usage: %s [start|start-clipboard|stop|toggle|cancel]\n' "${0##*/}" >&2
        exit 2
        ;;
esac

mkdir -p "$blankweave_runtime" || exit 1
# Only hold the lock while reserving a start or issuing a provider command.
# In particular, a release must be able to cancel the slow focus probe.
exec {record_lock}> "$blankweave_runtime/voxtype-record.lock"
flock -x "$record_lock" || exit 1

record() {
    # Commands acknowledge a daemon request; they do not run for the duration
    # of recording. A stuck client must not block subsequent stop/cancel calls.
    # Keep the lock in this shell only, never in provider descendants.
    (
        exec {record_lock}>&-
        timeout --kill-after=1s 5s voxtype record "$@"
    )
    local result=$?
    if [[ $result == 124 || $result == 137 ]]; then
        printf 'VoxType did not acknowledge the request in time. Check dictation status and retry stop or cancel.\n' >&2
    fi
    return "$result"
}

if [[ $action == stop || $action == cancel ]]; then
    rm -f -- "$pending_file"
    record "$action"
    exit $?
fi

# A second toggle during preparation means stop, not another delayed start.
if [[ $action == toggle && -r $pending_file ]]; then
    pending=$(< "$pending_file")
    if [[ $pending =~ ^[0-9]+: ]] && kill -0 -- "${pending%%:*}" 2>/dev/null; then
        rm -f -- "$pending_file"
        exit 0
    fi
    rm -f -- "$pending_file"
fi

# Toggle preserves the route chosen when recording began.
if [[ $action == toggle && -r $voxtype_runtime/state ]]; then
    state=$(< "$voxtype_runtime/state")
    if [[ $state != idle ]]; then
        record toggle
        exit $?
    fi
fi

# An overlapping start supersedes the older probe. The token also prevents an
# older process's cleanup from cancelling a newer recording request.
token="$BASHPID:$RANDOM:$RANDOM"
printf '%s\n' "$token" > "$pending_file"
cleanup() {
    flock -x "$record_lock"
    if [[ -r $pending_file && $(< "$pending_file") == "$token" ]]; then
        rm -f -- "$pending_file"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
flock -u "$record_lock"

# Settings has no editable destination. Use an explicit clipboard route and
# retain the same delivery metadata as the focus-based keyboard shortcut.
focus_result=2
if [[ $action == start-clipboard ]]; then
    focus_result=1
elif [[ -n ${BLANKWEAVE_VOXTYPE_FOCUS:-} ]]; then
    python3 "$script_dir/voxtype-focus.py" </dev/null
    focus_result=$?
elif active_window=$(hyprctl -j activewindow 2>/dev/null); then
    timeout 0.7s python3 "$script_dir/voxtype-focus.py" <<< "$active_window"
    focus_result=$?
fi

flock -x "$record_lock" || exit 1
[[ -r $pending_file && $(< "$pending_file") == "$token" ]] || exit 0
rm -f -- "$mode_file"
if [[ $action == start-clipboard ]]; then
    printf 'clipboard\n' > "$mode_file"
    record start --clipboard --no-auto-submit
    exit $?
fi

case $focus_result in
    0)
        record "$action"
        ;;
    1)
        printf 'clipboard\n' > "$mode_file"
        record "$action" --clipboard
        ;;
    *)
        # Missing AT-SPI data, helper failures, and timeouts are all unknown.
        # Keep normal typing, retain the text, and offer one-click recovery.
        printf 'unverified\n' > "$mode_file"
        record "$action"
        ;;
esac
