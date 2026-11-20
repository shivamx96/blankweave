#!/bin/sh
# Hyprlock 0.9 has no lock-state text variable, so its label polls this. It
# runs every two seconds on every monitor for as long as the screen is locked:
# keep it to one read-only compositor query and no interpreter start-up.
if hyprctl -j devices 2>/dev/null | grep -Eq '"capsLock": *true'; then
    printf 'Caps Lock is on\n'
fi
exit 0
