#!/usr/bin/env bash

# Display brightness through the kernel backlight API (internal panels) or
# DDC/CI VCP 0x10 (external monitors). DDC buses are discovered from the DRM
# connector because /dev/i2c-* numbering is not stable across boots.
#
# Usage:
#   brightness.sh status|get [connector]
#   brightness.sh up|down [step] [connector]
#   brightness.sh set <percent> [connector]
#   brightness.sh dim <maximum> [connector]
#   brightness.sh save|restore [connector]

RUNTIME_BASE="${XDG_RUNTIME_DIR:-/tmp}/hyprarch"
BACKLIGHT_ROOT="${HYPRARCH_BACKLIGHT_ROOT:-/sys/class/backlight}"
mkdir -p "$RUNTIME_BASE" 2>/dev/null || true

CMD=${1:-get}
ARG=${2:-}
CONNECTOR=${3:-}

case "$CMD" in
    get|status|save|restore)
        CONNECTOR=$ARG
        ;;
esac

STATE_KEY=${CONNECTOR:-default}
STATE_KEY=${STATE_KEY//[^a-zA-Z0-9_.-]/_}
SAVE_FILE="$RUNTIME_BASE/brightness-${STATE_KEY}.saved"
DIM_FLAG="$RUNTIME_BASE/brightness-${STATE_KEY}.dimmed"
BUS_CACHE="$RUNTIME_BASE/brightness-${STATE_KEY}.bus"
MAX_CACHE="$RUNTIME_BASE/brightness-${STATE_KEY}.max"

has_backlight() {
    compgen -G "$BACKLIGHT_ROOT/*/brightness" >/dev/null
}

discover_ddc_bus() {
    local cached detection bus

    if [[ -r $BUS_CACHE ]]; then
        read -r cached < "$BUS_CACHE"
        if [[ $cached =~ ^[0-9]+$ && -e /dev/i2c-$cached ]]; then
            printf '%s\n' "$cached"
            return 0
        fi
    fi

    command -v ddcutil >/dev/null 2>&1 || return 1
    detection=$(timeout 8 ddcutil detect --brief 2>/dev/null) || return 1
    bus=$(awk -v target="$CONNECTOR" '
        /I2C bus:/ {
            current = $NF
            sub(/^.*i2c-/, "", current)
            if (first == "")
                first = current
        }
        /DRM connector:/ {
            drm = $NF
            if (target == "" || drm == target || drm ~ ("-" target "$")) {
                print current
                found = 1
                exit
            }
        }
        END {
            if (!found && target == "" && first != "")
                print first
        }
    ' <<< "$detection")

    [[ $bus =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "$bus" > "$BUS_CACHE"
    printf '%s\n' "$bus"
}

BACKEND=none
DDC_BUS=""

if has_backlight && [[ -z $CONNECTOR || $CONNECTOR == eDP-* || $CONNECTOR == LVDS-* || $CONNECTOR == DSI-* ]]; then
    BACKEND=backlight
elif DDC_BUS=$(discover_ddc_bus); then
    BACKEND=ddc
fi

read_ddc_values() {
    local bus=$1 output
    output=$(timeout 6 ddcutil --bus "$bus" getvcp 10 --brief 2>/dev/null) || return 1
    awk '$1 == "VCP" && $2 == "10" && $3 == "C" { print $4, $5; exit }' <<< "$output"
}

get_raw_values() {
    local current maximum values

    case "$BACKEND" in
        backlight)
            current=$(brightnessctl get 2>/dev/null) || return 1
            maximum=$(brightnessctl max 2>/dev/null) || return 1
            ;;
        ddc)
            values=$(read_ddc_values "$DDC_BUS") || {
                # A cached bus can become stale after a display topology change.
                rm -f "$BUS_CACHE"
                rm -f "$MAX_CACHE"
                DDC_BUS=$(discover_ddc_bus) || return 1
                values=$(read_ddc_values "$DDC_BUS") || return 1
            }
            read -r current maximum <<< "$values"
            if [[ $maximum =~ ^[0-9]+$ && $maximum -gt 0 ]]; then
                printf '%s\n' "$maximum" > "$MAX_CACHE"
            fi
            ;;
        *)
            return 1
            ;;
    esac

    [[ $current =~ ^[0-9]+$ && $maximum =~ ^[0-9]+$ && $maximum -gt 0 ]] || return 1
    printf '%s %s\n' "$current" "$maximum"
}

get_percent() {
    local current maximum
    read -r current maximum < <(get_raw_values) || return 1
    printf '%d\n' "$(((current * 100 + maximum / 2) / maximum))"
}

set_percent() {
    local percent=$1 current maximum raw

    [[ $percent =~ ^[0-9]+$ ]] || return 1
    ((percent > 100)) && percent=100
    ((percent < 5)) && percent=5

    case "$BACKEND" in
        backlight)
            brightnessctl set "${percent}%" -q
            ;;
        ddc)
            if [[ -r $MAX_CACHE ]]; then
                read -r maximum < "$MAX_CACHE"
            fi
            if [[ ! $maximum =~ ^[0-9]+$ || $maximum -le 0 ]]; then
                read -r current maximum < <(get_raw_values) || return 1
            fi
            raw=$(((percent * maximum + 50) / 100))
            timeout 6 ddcutil --bus "$DDC_BUS" --noverify setvcp 10 "$raw" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

show_popup() {
    local percent=$1 bars empty bar
    bars=$((percent / 5))
    empty=$((20 - bars))
    bar=$(printf '█%.0s' $(seq 1 "$bars"))$(printf '░%.0s' $(seq 1 "$empty"))
    notify-send -t 1200 "󰃟 Brightness" "$bar\n$percent%" \
        -h string:x-canonical-private-synchronous:brightness
}

case "$CMD" in
    status)
        percent=$(get_percent) || exit 1
        printf '{"percentage":%d,"backend":"%s","connector":"%s"}\n' \
            "$percent" "$BACKEND" "$CONNECTOR"
        ;;
    get)
        get_percent
        ;;
    up|down)
        step=${ARG:-5}
        [[ $step =~ ^[0-9]+$ ]] || exit 1
        current=$(get_percent) || exit 1
        if [[ $CMD == up ]]; then
            next=$((current + step))
            ((next > 100)) && next=100
        else
            next=$((current - step))
            ((next < 5)) && next=5
        fi
        if set_percent "$next"; then
            show_popup "$next"
        fi
        ;;
    set)
        set_percent "$ARG"
        ;;
    save)
        get_percent > "$SAVE_FILE"
        ;;
    dim)
        target=${ARG:-10}
        [[ $target =~ ^[0-9]+$ ]] || exit 1
        current=$(get_percent) || exit 1
        if [[ ! -f $DIM_FLAG ]]; then
            printf '%s\n' "$current" > "$SAVE_FILE"
            touch "$DIM_FLAG"
        fi
        ((target < current)) && set_percent "$target"
        ;;
    restore)
        if [[ -r $SAVE_FILE ]]; then
            read -r saved < "$SAVE_FILE"
            set_percent "$saved"
        fi
        rm -f "$DIM_FLAG"
        ;;
    *)
        printf 'Unknown brightness command: %s\n' "$CMD" >&2
        exit 2
        ;;
esac
