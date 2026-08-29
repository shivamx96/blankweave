#!/usr/bin/env bash

set -euo pipefail

case "${1:-}" in
    auth)
        case "${2:-}" in
            token)
                exit 0
                ;;
            status)
                printf '%s\n' "${FAKE_GH_LOGIN:-test-user}"
                ;;
        esac
        ;;
    search)
        printf '[]\n'
        ;;
esac
