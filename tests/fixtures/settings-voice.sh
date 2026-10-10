#!/usr/bin/env bash
set -euo pipefail
case ${1:-} in
    health) printf 'active\n' ;;
    watch) printf '{"alt":"idle","model":"fixture-model","device":"default","backend":"whisper"}\n'; sleep 30 ;;
    fail) printf 'intentional failure\n' >&2; exit 1 ;;
    *) printf '%s\n' "$1" >> "$SETTINGS_VOICE_LOG" ;;
esac
