#!/usr/bin/env bash

INSTALL_STAGES=(
    'CHECKING PREREQUISITES'
    'DETECTING HARDWARE CAPABILITIES'
    'INSTALLING AUR HELPER'
    'INSTALLING PACKAGES'
    'ENABLING SERVICES'
    'CONFIGURING DEFAULT KEYRING'
    'CONFIGURING CONSOLE AUTO-LOGIN'
    'COPYING DEFAULTS'
    'GENERATING USER CONFIGS'
    'SYMLINKING CONFIGS'
    'SETTING UP ZSH'
    'FIXING OWNERSHIP'
    'APPLYING THEME'
    'CONFIGURING VOICE DICTATION'
    'SYNCING WEB APPS'
    'CONFIGURING NVIDIA'
    'CONFIGURING PLYMOUTH'
    'CONFIGURING LIMINE BOOT MANAGER'
    'CONFIGURING GIT AND SSH'
    'APPLYING MIGRATIONS'
    'DONE'
)
INSTALL_CURRENT_STAGE='Starting installer'
INSTALL_STARTED_AT=$SECONDS
INSTALL_STAGE_STARTED_AT=$SECONDS
INSTALL_STAGE_NUMBER=0

section() {
    local label=$1 index
    for index in "${!INSTALL_STAGES[@]}"; do
        [[ ${INSTALL_STAGES[index]} == "$label" ]] || continue
        if (( INSTALL_STAGE_NUMBER > 0 )); then
            printf 'Stage finished in %ss.\n' "$((SECONDS - INSTALL_STAGE_STARTED_AT))"
        fi
        INSTALL_STAGE_NUMBER=$((index + 1))
        INSTALL_CURRENT_STAGE=$label
        INSTALL_STAGE_STARTED_AT=$SECONDS
        printf '\n[%s/%s] %s | elapsed %ss\n\n' "$INSTALL_STAGE_NUMBER" \
            "${#INSTALL_STAGES[@]}" "$label" "$((SECONDS - INSTALL_STARTED_AT))"
        return 0
    done
    printf 'Unknown installer stage: %s\n' "$label" >&2
    return 1
}

install_progress_exit() {
    local status=$1
    if (( status != 0 )); then
        printf '\nInstallation stopped during: %s (exit %s, elapsed %ss).\n' \
            "$INSTALL_CURRENT_STAGE" "$status" "$((SECONDS - INSTALL_STARTED_AT))" >&2
        printf 'Resolve the error above before retrying. Earlier changes may already be applied.\n' >&2
    fi
}
