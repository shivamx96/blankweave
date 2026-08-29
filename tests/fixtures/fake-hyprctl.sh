#!/usr/bin/env bash

# Stand-in for hyprctl: answers `monitors -j` from FAKE_HYPRCTL_MONITORS and
# records every `eval` request, one per line, in FAKE_HYPRCTL_LOG.

set -euo pipefail

case "${1:-}" in
    monitors)
        cat "$FAKE_HYPRCTL_MONITORS"
        ;;
    eval)
        printf '%s\n' "${2:-}" >> "$FAKE_HYPRCTL_LOG"
        printf 'ok\n'
        ;;
    *)
        printf 'unknown request\n' >&2
        exit 1
        ;;
esac
