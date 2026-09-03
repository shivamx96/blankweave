#!/usr/bin/env bash

set -euo pipefail

MODEL_NAME=ggml-small.en.bin
MODEL_URL=${VOXTYPE_MODEL_URL:-https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL_NAME}
MODEL_SHA256=${VOXTYPE_MODEL_SHA256:-c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d}
DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
MODEL_DIR=$DATA_HOME/voxtype/models
STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
MODEL_PATH=$MODEL_DIR/$MODEL_NAME

model_valid() {
    [[ -f $MODEL_PATH ]] \
        && printf '%s  %s\n' "$MODEL_SHA256" "$MODEL_PATH" | sha256sum --check --status
}

enable_voxtype() {
    local daemon_state state_file staged

    command -v voxtype >/dev/null 2>&1 || {
        printf 'VoxType is not installed.\n' >&2
        return 1
    }
    command -v curl >/dev/null 2>&1 || {
        printf 'curl is required to download the local speech model.\n' >&2
        return 1
    }

    if ! model_valid; then
        mkdir -p "$MODEL_DIR"
        staged=$(mktemp "$MODEL_DIR/.${MODEL_NAME}.XXXXXX")
        cleanup_staged() {
            rm -f -- "$staged"
        }
        trap cleanup_staged RETURN
        curl --fail --silent --show-error --location --retry 3 --output "$staged" "$MODEL_URL"
        printf '%s  %s\n' "$MODEL_SHA256" "$staged" | sha256sum --check --status || {
            printf 'Downloaded VoxType model failed checksum verification.\n' >&2
            return 1
        }
        chmod 0644 "$staged"
        mv -f "$staged" "$MODEL_PATH"
        trap - RETURN
    fi

    voxtype setup quickshell --force
    mkdir -p "$STATE_HOME/blankweave"
    if [[ ! -e $STATE_HOME/blankweave/voxtype-last-transcript.json ]]; then
        printf '{}\n' > "$STATE_HOME/blankweave/voxtype-last-transcript.json"
        chmod 600 "$STATE_HOME/blankweave/voxtype-last-transcript.json"
    fi
    systemctl --user enable voxtype.service
    if systemctl --user is-active --quiet voxtype.service; then
        daemon_state=idle
        state_file=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/voxtype/state
        if [[ -r $state_file ]]; then
            daemon_state=$(< "$state_file")
        fi
        if [[ $daemon_state != recording && $daemon_state != transcribing \
            && $daemon_state != streaming ]]; then
            systemctl --user restart voxtype.service
        fi
    else
        systemctl --user start voxtype.service
    fi
}

disable_voxtype() {
    # Package profiles are additive, so disabling the feature deliberately
    # keeps the package, model, and user override for a cheap future re-enable.
    systemctl --user disable --now voxtype.service 2>/dev/null || true
}

case ${1:-} in
    enable) enable_voxtype ;;
    disable) disable_voxtype ;;
    *)
        printf 'Usage: %s enable|disable\n' "${0##*/}" >&2
        exit 2
        ;;
esac
