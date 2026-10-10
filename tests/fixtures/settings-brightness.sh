#!/usr/bin/env bash
set -euo pipefail
state=${SETTINGS_BRIGHTNESS_DIR:?}
mkdir -p "$state"
mode=$(cat "$state/mode" 2>/dev/null || printf normal)
case "$1" in
    scenario) printf '%s' "$2" > "$state/mode" ;;
    status)
        connector=$2
        [[ -n $connector ]] || exit 2
        if [[ $connector == eDP-1 ]]; then backend=backlight; fallback=60
        else backend=ddc; fallback=40; fi
        percentage=$(cat "$state/$connector" 2>/dev/null || printf '%s' "$fallback")
        case "$mode" in
            offline) exit 1 ;;
            malformed) percentage=200 ;;
            wrong-connector) connector=UNKNOWN ;;
            slow) sleep 0.2 ;;
        esac
        printf '{"percentage":%s,"backend":"%s","connector":"%s"}\n' "$percentage" "$backend" "$connector"
        ;;
    set)
        [[ -n $3 ]] || exit 2
        printf '%s %s\n' "$3" "$2" >> "$state/commands"
        sleep 0.1
        case "$mode" in
            fail-set) exit 1 ;;
            ignored) exit 0 ;;
        esac
        printf '%s' "$2" > "$state/$3"
        ;;
    *) exit 2 ;;
esac
