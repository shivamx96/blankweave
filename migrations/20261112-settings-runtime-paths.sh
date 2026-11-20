#!/usr/bin/env bash
# Coordination files contain no preferences. Remove only known obsolete names.
set -euo pipefail
config=${XDG_CONFIG_HOME:-$HOME/.config}/blankweave
# Do not traverse a user-supplied replacement for the config directory.
[[ -d $config && ! -L $config ]] || exit 0
for name in .monitor-layout.lock .keyboard.lock .pointer.lock .shortcuts.lock \
    .night-light.lock interface.lock gtk-settings.lock default-apps.lock \
    notifications.lock webapps.lock wallpaper.lock system-bell.lock startup.lock \
    system-diagnostics.lock backup-provider.lock; do
    [[ ! -f $config/$name && ! -L $config/$name ]] || rm -f -- "$config/$name"
done
for domain in vpn sharing datetime printers disk-usage drives disk-health installed permissions updates firmware assistive accounts backup restore snapshots hibernate; do
    for prefix in operations worker; do
        name=$prefix-$domain.lock
        [[ ! -f $config/$name && ! -L $config/$name ]] || rm -f -- "$config/$name"
    done
done
# Remove known scratch leaves, never recursively remove a directory with unknown files.
for name in .monitor-mode-preview.json .mode-preview.log \
    night-light-runtime/hypr/hyprsunset.conf runtime/blankweave/notifications-state.json; do
    parent=$config/${name%/*}
    safe=true
    while [[ $parent != "$config" && $parent == "$config/"* ]]; do
        if [[ -L $parent ]]; then safe=false; break; fi
        parent=${parent%/*}
    done
    $safe || continue
    [[ ! -f $config/$name && ! -L $config/$name ]] || rm -f -- "$config/$name"
done
for name in night-light-runtime/hypr night-light-runtime runtime/blankweave runtime; do
    parent=$config/$name
    safe=true
    while [[ $parent != "$config" && $parent == "$config/"* ]]; do
        if [[ -L $parent ]]; then safe=false; break; fi
        parent=${parent%/*}
    done
    $safe && rmdir -- "$config/$name" 2>/dev/null || true
done
