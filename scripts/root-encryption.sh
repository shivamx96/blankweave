#!/usr/bin/env bash

# Input is the TYPE column of `lsblk --inverse --raw` for the root device.
# Inverse traversal includes every backing device, including LVM layers.
root_ancestors_encrypted() {
    local type found=false
    while IFS= read -r type; do
        [[ $type == crypt ]] && found=true
    done
    [[ $found == true ]]
}

root_is_encrypted() {
    local source types
    source=$(findmnt -n -o SOURCE --target / 2>/dev/null) || return 1
    source=${source%%\[*} # Btrfs SOURCE may include [/subvolume].
    [[ $source == /dev/* ]] || return 1
    types=$(lsblk --inverse --raw --noheadings --output TYPE -- "$source" 2>/dev/null) || return 1
    root_ancestors_encrypted <<< "$types"
}
