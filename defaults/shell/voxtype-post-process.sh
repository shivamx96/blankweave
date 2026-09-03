#!/usr/bin/env bash

set -u
umask 077

runtime_root=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
state_root=${XDG_STATE_HOME:-${HOME:?}/.local/state}/blankweave
mode_file=$runtime_root/blankweave/voxtype-output-mode
state_file=$state_root/voxtype-last-transcript.json

# The sentinel keeps command substitution from stripping legitimate trailing
# newlines. VoxType receives exactly the text it supplied on stdin.
with_sentinel=$(cat; printf '\034')
transcript=${with_sentinel%$'\034'}
delivery='type'
if [[ -r $mode_file ]]; then
    requested_delivery=$(< "$mode_file")
    if [[ $requested_delivery == clipboard || $requested_delivery == unverified ]]; then
        delivery=$requested_delivery
    fi
fi
rm -f -- "$mode_file"

if mkdir -p "$state_root" 2>/dev/null; then
    created_at=$(date +%s%3N 2>/dev/null || printf '%s000' "$(date +%s)")
    if payload=$(jq -cn \
        --arg text "$transcript" \
        --arg delivery "$delivery" \
        --argjson createdAt "$created_at" \
        '{text: $text, delivery: $delivery, createdAt: $createdAt}' 2>/dev/null); then
        printf '%s\n' "$payload" > "$state_file" 2>/dev/null || true
    fi
fi

printf '%s' "$transcript"
