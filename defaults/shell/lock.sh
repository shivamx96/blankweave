#!/usr/bin/env bash
# Direct manual locking must work even without Hypridle's logind listener.
set -euo pipefail

lock_dir=${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}}/blankweave-lock
umask 077
mkdir -p -- "$lock_dir"
# Return immediately to Quickshell/Hypridle. Hold the guard through startup and
# the lock client's lifetime, so simultaneous requests cannot start two clients.
(
    flock -n 9 || exit 0
    pidof hyprlock >/dev/null || hyprlock
) 9>"$lock_dir/launch.lock" </dev/null >/dev/null 2>&1 &
