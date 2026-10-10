#!/usr/bin/env bash
set -euo pipefail
case ${1:-} in
    list)
        printf '[{"id":"obsidian","name":"Obsidian"},{"id":"moss","name":"Moss"},{"id":"invalid","invalid":true}]\n'
        ;;
    status)
        printf '{"system":{"pending":true}}\n'
        ;;
    set)
        [[ ${2:-} == moss ]]
        ;;
    mode)
        # Exercise a failed apply without ever touching the real desktop.
        exit 1
        ;;
    *) exit 2 ;;
esac
