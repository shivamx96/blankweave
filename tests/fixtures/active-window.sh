#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1" >> "$ACTIVE_WINDOW_QUERY_LOG"
case "$1" in
    empty) printf '{}\n' ;;
    focused) printf '{"address":"0xabc123"}\n' ;;
    delayed-empty) sleep 0.1; printf '{}\n' ;;
    delayed-focused) sleep 0.1; printf '{"address":"0xabc123"}\n' ;;
    failed) exit 1 ;;
    malformed) printf 'not json\n' ;;
    invalid-address) printf '{"address":"0xabc123junk"}\n' ;;
    *) exit 2 ;;
esac
