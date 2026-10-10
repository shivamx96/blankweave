#!/usr/bin/env bash
set -euo pipefail
case ${1:-} in
    list)
        printf '[{"id":"obsidian","name":"Obsidian"},{"id":"moss","name":"Moss"},{"id":"invalid","invalid":true}]\n'
        ;;
    status)
        if [[ -f ${SETTINGS_SYNC_STATE:-/nonexistent} ]]; then
            printf '{"system":{"folders":false,"bootSplash":false,"pending":false}}\n'
        else
            printf '{"system":{"folders":true,"bootSplash":true,"pending":true}}\n'
        fi
        ;;
    set)
        [[ ${2:-} == moss ]]
        ;;
    mode)
        # Exercise a failed apply without ever touching the real desktop.
        exit 1
        ;;
    sync-success)
        printf 'blankweave-theme-sync:folders\nblankweave-theme-sync:boot-splash\n'
        sleep 0.1
        touch "$SETTINGS_SYNC_STATE"
        printf 'blankweave-theme-sync:complete\n'
        ;;
    sync-cancel) exit 126 ;;
    sync-denied) exit 127 ;;
    sync-fail)
        printf 'blankweave-theme-sync:boot-splash\n'
        exit 1
        ;;
    sync-incomplete)
        printf 'blankweave-theme-sync:complete\n'
        ;;
    *) exit 2 ;;
esac
