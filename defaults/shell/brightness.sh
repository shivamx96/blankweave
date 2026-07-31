#!/usr/bin/env bash

# Brightness control via brightnessctl (any panel exposing /sys/class/backlight).
# External monitors have no backlight device — see TODO.md for the ddcutil backend.
# Usage: brightness.sh up [step] | down [step] | set <value> | get | dim <max> | restore

SAVE_FILE="/tmp/brightness-saved"
DIM_FLAG="/tmp/brightness-dimmed"

detect_backend() {
    if ls /sys/class/backlight/*/brightness &>/dev/null 2>&1; then
        echo "backlight"
    else
        echo "none"
    fi
}

BACKEND=$(detect_backend)

get_percent() {
    case $BACKEND in
        backlight)
            local cur max
            cur=$(brightnessctl get)
            max=$(brightnessctl max)
            echo $((cur * 100 / max))
            ;;
        *) echo 0 ;;
    esac
}

set_percent() {
    local val=$1
    (( val > 100 )) && val=100
    (( val < 5 )) && val=5
    case $BACKEND in
        backlight) brightnessctl set "${val}%" -q ;;
    esac
}

show_popup() {
    local percent=$1
    local bars=$((percent / 5))
    local empty=$((20 - bars))
    local bar
    bar=$(printf '█%.0s' $(seq 1 "$bars"))$(printf '░%.0s' $(seq 1 "$empty"))
    notify-send -t 1200 "󰃟 Brightness" "$bar\n$percent%" \
        -h string:x-canonical-private-synchronous:brightness
}

CMD=${1:-get}
STEP=${2:-5}

case $CMD in
    up)
        current=$(get_percent)
        new=$((current + STEP))
        (( new > 100 )) && new=100
        set_percent $new
        show_popup $new
        ;;
    down)
        current=$(get_percent)
        new=$((current - STEP))
        (( new < 5 )) && new=5
        set_percent $new
        show_popup $new
        ;;
    set)
        set_percent "$STEP"
        ;;
    get)
        get_percent
        ;;
    save)
        get_percent > "$SAVE_FILE"
        ;;
    dim)
        # Idle dim: never *raise* brightness. Sitting below the target (e.g. 5% when the
        # target is 10%) used to make the screen brighter when the session went idle.
        current=$(get_percent)
        # Only capture the pre-dim value on the first dim of an idle period — a second
        # dim without an intervening restore would otherwise save the dimmed value and
        # strand the screen dark.
        if [ ! -f "$DIM_FLAG" ]; then
            echo "$current" > "$SAVE_FILE"
            touch "$DIM_FLAG"
        fi
        (( STEP < current )) && set_percent "$STEP"
        ;;
    restore)
        if [ -f "$SAVE_FILE" ]; then
            set_percent "$(cat "$SAVE_FILE")"
        fi
        rm -f "$DIM_FLAG"
        ;;
esac
