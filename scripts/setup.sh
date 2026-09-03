#!/usr/bin/env bash

set -euo pipefail

PROGRAM_NAME='blankweave setup'
REPOSITORY=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
BLANKWEAVE_CONFIG_DIR=$CONFIG_HOME/blankweave
INSTALL_CONFIG=$BLANKWEAVE_CONFIG_DIR/install.conf
SETUP_CONFIG=$BLANKWEAVE_CONFIG_DIR/setup.conf
THEME_STATE=$BLANKWEAVE_CONFIG_DIR/theme.json
CAPABILITIES=
NON_INTERACTIVE=false
TTY_FD=

die() {
    printf '%s: %s\n' "$PROGRAM_NAME" "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: blankweave setup [--non-interactive]

Guide a first install or reconfigure an existing Blankweave machine. Choices
are reviewed before the installer runs and saved under ~/.config/blankweave/.

  --non-interactive  Validate and apply existing install.conf and setup.conf.
EOF
}

profile_enabled() {
    local requested=$1 profile

    for profile in "${INSTALLER_PROFILES[@]}"; do
        [[ $profile == "$requested" ]] && return 0
    done
    return 1
}

prompt_line() {
    local prompt=$1 default=${2:-}

    printf '%s' "$prompt" >&$TTY_FD
    IFS= read -r REPLY <&$TTY_FD || die 'input ended before setup was complete'
    [[ -n $REPLY ]] || REPLY=$default
}

prompt_yes_no() {
    local prompt=$1 default=$2 suffix answer

    if [[ $default == yes ]]; then
        suffix=' [Y/n]: '
    else
        suffix=' [y/N]: '
    fi
    while true; do
        prompt_line "$prompt$suffix"
        answer=${REPLY,,}
        [[ -n $answer ]] || answer=$default
        case "$answer" in
            y|yes) REPLY=yes; return 0 ;;
            n|no) REPLY=no; return 0 ;;
            *) printf 'Please answer yes or no.\n' >&$TTY_FD ;;
        esac
    done
}

available_themes() {
    local parent directory id
    local -A found=()

    for parent in "$REPOSITORY/defaults/themes" "$BLANKWEAVE_CONFIG_DIR/themes"; do
        [[ -d $parent ]] || continue
        for directory in "$parent"/*; do
            [[ -r $directory/theme.json ]] || continue
            id=${directory##*/}
            [[ $id =~ ^[a-z0-9][a-z0-9-]*$ ]] || continue
            found[$id]=1
        done
    done
    printf '%s\n' "${!found[@]}" | LC_ALL=C sort
}

theme_available() {
    local requested=$1 theme

    while IFS= read -r theme; do
        [[ $theme == "$requested" ]] && return 0
    done < <(available_themes)
    return 1
}

load_initial_choices() {
    local existing_theme existing_mode existing_name existing_email

    installer_config_load "$INSTALL_CONFIG" "$CAPABILITIES"
    setup_config_load "$SETUP_CONFIG"

    if [[ ! -e $SETUP_CONFIG ]]; then
        if command -v jq >/dev/null 2>&1 && [[ -r $THEME_STATE ]]; then
            existing_theme=$(jq -r '.theme // empty' "$THEME_STATE" 2>/dev/null || true)
            existing_mode=$(jq -r '.mode // empty' "$THEME_STATE" 2>/dev/null || true)
            [[ -z $existing_theme ]] || SETUP_THEME=$existing_theme
            [[ -z $existing_mode ]] || SETUP_MODE=$existing_mode
        fi
        existing_name=$(git config --global --get user.name 2>/dev/null || true)
        existing_email=$(git config --global --get user.email 2>/dev/null || true)
        if [[ -n $existing_name && -n $existing_email ]]; then
            SETUP_GIT_IDENTITY=configure
            SETUP_GIT_NAME=$existing_name
            SETUP_GIT_EMAIL=$existing_email
        fi
    fi
}

choose_profiles() {
    local profile default
    local -a selected=()

    printf '\nOptional features and application profiles\n' >&$TTY_FD
    for profile in "${INSTALLER_AVAILABLE_PROFILES[@]}"; do
        if profile_enabled "$profile"; then default=yes; else default=no; fi
        prompt_yes_no "  Enable $profile?" "$default"
        [[ $REPLY == yes ]] && selected+=("$profile")
    done
    INSTALLER_PROFILES=("${selected[@]}")
}

choose_theme() {
    local theme

    printf '\nAvailable themes:\n' >&$TTY_FD
    while IFS= read -r theme; do
        printf '  - %s\n' "$theme" >&$TTY_FD
    done < <(available_themes)
    while true; do
        prompt_line "Theme [$SETUP_THEME]: " "$SETUP_THEME"
        if theme_available "$REPLY"; then
            SETUP_THEME=$REPLY
            break
        fi
        printf 'Choose one of the listed theme IDs.\n' >&$TTY_FD
    done
    while true; do
        prompt_line "Mode (dark/light) [$SETUP_MODE]: " "$SETUP_MODE"
        case "$REPLY" in
            dark|light) SETUP_MODE=$REPLY; break ;;
            *) printf 'Mode must be dark or light.\n' >&$TTY_FD ;;
        esac
    done
}

choose_git() {
    local default=no

    [[ $SETUP_GIT_IDENTITY == configure ]] && default=yes
    prompt_yes_no $'\nConfigure the global Git name and email?' "$default"
    if [[ $REPLY == yes ]]; then
        SETUP_GIT_IDENTITY=configure
        while true; do
            prompt_line "Git name${SETUP_GIT_NAME:+ [$SETUP_GIT_NAME]}: " "$SETUP_GIT_NAME"
            SETUP_GIT_NAME=$REPLY
            if [[ -n $SETUP_GIT_NAME ]]; then
                break
            fi
            printf 'Git name cannot be empty.\n' >&$TTY_FD
        done
        while true; do
            prompt_line "Git email${SETUP_GIT_EMAIL:+ [$SETUP_GIT_EMAIL]}: " "$SETUP_GIT_EMAIL"
            SETUP_GIT_EMAIL=$REPLY
            if [[ $SETUP_GIT_EMAIL =~ ^[^[:space:]@]+@[^[:space:]@]+$ ]]; then
                break
            fi
            printf 'Enter a valid email address.\n' >&$TTY_FD
        done
    else
        SETUP_GIT_IDENTITY=skip
        SETUP_GIT_NAME=
        SETUP_GIT_EMAIL=
    fi

    if [[ -f $HOME/.ssh/id_ed25519 ]]; then
        SETUP_SSH_KEY=skip
        printf 'An Ed25519 SSH key already exists; Blankweave will leave it unchanged.\n' >&$TTY_FD
        return
    fi
    prompt_yes_no 'Generate a local Ed25519 key for GitHub?' no
    if [[ $REPLY == yes ]]; then
        SETUP_SSH_KEY=generate
        while [[ ! $SETUP_GIT_EMAIL =~ ^[^[:space:]@]+@[^[:space:]@]+$ ]]; do
            prompt_line 'Email to use as the SSH key comment: '
            SETUP_GIT_EMAIL=$REPLY
            [[ $SETUP_GIT_EMAIL =~ ^[^[:space:]@]+@[^[:space:]@]+$ ]] \
                || printf 'Enter a valid email address.\n' >&$TTY_FD
        done
    else
        SETUP_SSH_KEY=skip
    fi
}

print_review() {
    local git_summary ssh_summary

    if [[ $SETUP_GIT_IDENTITY == configure ]]; then
        git_summary="$SETUP_GIT_NAME <$SETUP_GIT_EMAIL>"
    else
        git_summary='leave unchanged'
    fi
    if [[ -f $HOME/.ssh/id_ed25519 ]]; then
        ssh_summary='keep existing key'
    elif [[ $SETUP_SSH_KEY == generate ]]; then
        ssh_summary='generate ~/.ssh/id_ed25519 locally'
    else
        ssh_summary='skip'
    fi

    printf '\nSetup review\n'
    printf '  Capabilities: %s (detected)\n' "${CAPABILITIES:-none}"
    printf '  Profiles:     %s\n' "${INSTALLER_PROFILES[*]:-none}"
    printf '  Theme:        %s / %s\n' "$SETUP_THEME" "$SETUP_MODE"
    printf '  Git identity: %s\n' "$git_summary"
    printf '  SSH key:      %s\n' "$ssh_summary"
    printf '\nThe installer will now install packages and reconcile system/user configuration.\n'
}

write_atomic() {
    local destination=$1 mode=$2 staged

    mkdir -p "$(dirname "$destination")"
    staged=$(mktemp "$(dirname "$destination")/.blankweave-setup.XXXXXX")
    printf '%s' "$REPLY" > "$staged"
    chmod "$mode" "$staged"
    mv -f "$staged" "$destination"
}

save_choices() {
    REPLY=$(printf '%s\n' \
        '# Blankweave installer choices. Core and detected hardware are always included.' \
        'version=1' \
        "profiles=${INSTALLER_PROFILES[*]}")
    REPLY+=$'\n'
    write_atomic "$INSTALL_CONFIG" 600

    REPLY=$(printf '%s\n' \
        '# Non-secret choices recorded by blankweave setup. This file is parsed, not sourced.' \
        'version=1' \
        "theme=$SETUP_THEME" \
        "mode=$SETUP_MODE" \
        "git_identity=$SETUP_GIT_IDENTITY" \
        "git_name=$SETUP_GIT_NAME" \
        "git_email=$SETUP_GIT_EMAIL" \
        "ssh_key=$SETUP_SSH_KEY")
    REPLY+=$'\n'
    write_atomic "$SETUP_CONFIG" 600
}

apply_setup() {
    if [[ -n ${BLANKWEAVE_SETUP_APPLY_COMMAND:-} ]]; then
        BLANKWEAVE_SETUP_THEME=$SETUP_THEME \
        BLANKWEAVE_SETUP_MODE=$SETUP_MODE \
            "$BLANKWEAVE_SETUP_APPLY_COMMAND" "$REPOSITORY"
    else
        BLANKWEAVE_SETUP_THEME=$SETUP_THEME \
        BLANKWEAVE_SETUP_MODE=$SETUP_MODE \
            "$REPOSITORY/bin/blankweave" _apply "$REPOSITORY"
    fi
}

main() {
    case "${1:-}" in
        '') ;;
        --non-interactive) NON_INTERACTIVE=true ;;
        --help|-h) usage; return 0 ;;
        *) die 'accepts only --non-interactive' ;;
    esac
    (( $# <= 1 )) || die 'accepts only one option'
    if (( EUID == 0 )) && [[ ${BLANKWEAVE_SETUP_TEST_ALLOW_ROOT:-} != 1 ]]; then
        die 'run this command as your normal user'
    fi

    # shellcheck source=scripts/installer-config.sh
    source "$REPOSITORY/scripts/installer-config.sh"
    # shellcheck source=scripts/setup-config.sh
    source "$REPOSITORY/scripts/setup-config.sh"
    # shellcheck source=scripts/hardware-capabilities.sh
    source "$REPOSITORY/scripts/hardware-capabilities.sh"
    hardware_capabilities_detect
    CAPABILITIES=$(hardware_capabilities_list)

    if [[ $NON_INTERACTIVE == true ]]; then
        [[ -r $INSTALL_CONFIG ]] || die "$INSTALL_CONFIG is required for --non-interactive"
        [[ -r $SETUP_CONFIG ]] || die "$SETUP_CONFIG is required for --non-interactive"
        installer_config_load "$INSTALL_CONFIG" "$CAPABILITIES"
        setup_config_load "$SETUP_CONFIG"
    else
        if ! (: </dev/tty) 2>/dev/null; then
            die 'an interactive terminal is required (or use --non-interactive with existing configs)'
        fi
        exec {TTY_FD}<>/dev/tty
        load_initial_choices
        printf 'Blankweave guided setup\nDetected capabilities: %s\n' \
            "${CAPABILITIES:-none}" >&$TTY_FD
        choose_profiles
        choose_theme
        choose_git
    fi

    theme_available "$SETUP_THEME" || die "theme is not available: $SETUP_THEME"
    setup_config_validate
    print_review
    if [[ $NON_INTERACTIVE == false ]]; then
        prompt_yes_no 'Apply these choices?' no
        if [[ $REPLY != yes ]]; then
            printf 'Setup cancelled; no choices or system configuration were changed.\n'
            return 0
        fi
        save_choices
    fi
    apply_setup
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
