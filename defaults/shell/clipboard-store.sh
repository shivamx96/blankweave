#!/usr/bin/env bash
# stdin belongs to cliphist: never read clipboard payload into the shell.
if [[ ${CLIPBOARD_STATE:-} == sensitive ]]; then
    exit 0
fi
if types=$(wl-paste --list-types </dev/null 2>/dev/null); then
    while IFS= read -r type; do
        if [[ $type == x-kde-passwordManagerHint ]]; then
            if hint=$(wl-paste --type x-kde-passwordManagerHint </dev/null 2>/dev/null) && [[ $hint == secret ]]; then
                exit 0
            fi
            break
        fi
    done <<< "$types"
fi
# Preserve cliphist's configured limits (defaults: 750 items, dedupe search 100).
exec cliphist store
