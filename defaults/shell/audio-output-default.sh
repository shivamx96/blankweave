#!/usr/bin/env bash

# Select a PipeWire sink and move real application streams onto it.

NODE_ID=${1:-}
SINK_NAME=${2:-}

if [[ -z $NODE_ID || -z $SINK_NAME ]]; then
    printf 'Usage: audio-output-default.sh <node-id> <sink-name>\n' >&2
    exit 2
fi

timeout 2 wpctl set-default "$NODE_ID" 2>/dev/null || true
timeout 2 pactl set-default-sink "$SINK_NAME" 2>/dev/null || true

timeout 2 pactl list sink-inputs 2>/dev/null | awk '
    /^Sink Input #/ { id = substr($3, 2) }
    /application\.name = / {
        app = $0
        sub(/.*application\.name = "/, "", app)
        sub(/"$/, "", app)
        if (app != "EasyEffects") print id
    }
' | while read -r input; do
    [[ -n $input ]] && timeout 2 pactl move-sink-input "$input" "$SINK_NAME" 2>/dev/null || true
done
