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

    printf '\n[1/4] Applications and features\n' >&$TTY_FD
    printf 'Core desktop and detected hardware support are always included.\n' >&$TTY_FD
    printf 'Disabling a profile does not uninstall its existing applications.\n' >&$TTY_FD
    for profile in "${INSTALLER_AVAILABLE_PROFILES[@]}"; do
        case "$profile" in
            desktop) printf '\n  Desktop: browsers, notes, and personal utilities.\n' >&$TTY_FD ;;
            development) printf '\n  Development: editors, containers, languages, and coding tools.\n' >&$TTY_FD ;;
            communication) printf '\n  Communication: messaging and local file sharing.\n' >&$TTY_FD ;;
            gaming) printf '\n  Gaming: Steam, Proton, overlays, and compatible GPU support.\n' >&$TTY_FD ;;
            voice-dictation) printf '\n  Voice dictation: local speech recognition with a downloaded model.\n' >&$TTY_FD ;;
        esac
        if profile_enabled "$profile"; then default=yes; else default=no; fi
        prompt_yes_no "  Enable $profile?" "$default"
        [[ $REPLY == yes ]] && selected+=("$profile")
    done
    INSTALLER_PROFILES=("${selected[@]}")
}

choose_theme() {
    local theme

    printf '\n[2/4] Appearance\nAvailable themes:\n' >&$TTY_FD
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
    printf '\n[3/4] Git and SSH (optional)\n' >&$TTY_FD
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
    local -a repository_packages=() aur_packages=() providers=()

    resolve_package_manifests "$REPOSITORY" "$CAPABILITIES" repository repository_packages
    resolve_package_manifests "$REPOSITORY" "$CAPABILITIES" aur aur_packages
    resolve_package_manifests "$REPOSITORY" "$CAPABILITIES" providers providers

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

    printf '\n[4/4] Setup review\n'
    printf '  Capabilities: %s (detected)\n' "${CAPABILITIES:-none}"
    printf '  Profiles:     %s\n' "${INSTALLER_PROFILES[*]:-none}"
    printf '  Theme:        %s / %s\n' "$SETUP_THEME" "$SETUP_MODE"
    printf '  Git identity: %s\n' "$git_summary"
    printf '  SSH key:      %s\n' "$ssh_summary"
    printf '  Packages:     %s repository targets, %s AUR targets, %s provider targets\n' \
        "${#repository_packages[@]}" "${#aur_packages[@]}" "${#providers[@]}"
    printf '                Includes installed targets; dependencies and sizes are resolved during installation.\n'
    printf '\nApplying installs packages and configures the desktop, services, boot manager,\n'
    printf 'and automatic login. Administrator authentication is required.\n'
    printf 'Installation includes a full system upgrade. AUR builds and model downloads can take longer.\n'
}

print_packages() {
    local kind
    local -a packages=()
    for kind in repository aur providers; do
        resolve_package_manifests "$REPOSITORY" "$CAPABILITIES" "$kind" packages
        printf '\n%s package targets:\n' "$kind"
        if (( ${#packages[@]} )); then
            printf '  %s\n' "${packages[@]}"
        else
            printf '  None\n'
        fi
    done
}

review_choices() {
    while true; do
        print_review
        printf '\nEnter profiles, theme, or git to revise a section; packages to inspect the plan.\n' >&$TTY_FD
        prompt_line 'Apply these choices? [y/N/profiles/theme/git/packages]: ' no
        case "${REPLY,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            profiles) choose_profiles ;;
            theme) choose_theme ;;
            git) choose_git ;;
            packages) print_packages ;;
            *) printf 'Choose yes, no, profiles, theme, git, or packages.\n' >&$TTY_FD ;;
        esac
    done
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

run_installation() {
    local log_directory log_file install_status

    log_directory=${XDG_STATE_HOME:-$HOME/.local/state}/blankweave/setup
    mkdir -p "$log_directory"
    log_file=$(mktemp "$log_directory/install-$(date +%Y%m%d-%H%M%S).XXXXXX.log")
    printf '\nInstalling Blankweave. Output is saved to:\n  %s\n\n' "$log_file"
    # apply_setup returns the external installer's status; pipefail also catches
    # failures to write the log, rather than reporting a successful setup.
    if apply_setup 2>&1 | tee "$log_file"; then
        printf '\nSetup completed. Log: %s\n' "$log_file"
        printf 'After restarting your session, open Settings with Super+, and the launcher with Super+Space.\n'
        printf 'Check system health with: %q doctor\n' "$REPOSITORY/bin/blankweave"
    else
        install_status=$?
        printf '\nSetup did not complete (exit %s). Some changes may already be applied.\n' "$install_status" >&2
        printf 'Saved choices are available for retry; see the error in:\n  %s\n' "$log_file" >&2
        printf 'After resolving it, retry with:\n  %q setup --non-interactive\n' "$REPOSITORY/bin/blankweave" >&2
        return "$install_status"
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
    # shellcheck source=scripts/package-manifests.sh
    source "$REPOSITORY/scripts/package-manifests.sh"
    # Injected apply commands exercise setup without requiring an installed host.
    if [[ -z ${BLANKWEAVE_SETUP_APPLY_COMMAND:-} ]]; then
        "$REPOSITORY/scripts/installer-preflight.sh"
    fi
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
        printf 'Choose applications, appearance, and optional Git/SSH settings, then review.\n' >&$TTY_FD
        printf 'Press Enter to keep the displayed choice. Nothing is applied until you confirm.\n' >&$TTY_FD
        if [[ -f $INSTALL_CONFIG || -f $SETUP_CONFIG ]]; then
            printf 'Existing choices have been loaded as defaults.\n' >&$TTY_FD
        fi
        choose_profiles
        choose_theme
        choose_git
    fi

    theme_available "$SETUP_THEME" || die "theme is not available: $SETUP_THEME"
    setup_config_validate
    if [[ $NON_INTERACTIVE == false ]]; then
        if ! review_choices; then
            printf 'Setup cancelled; no choices or system configuration were changed.\n'
            return 0
        fi
        theme_available "$SETUP_THEME" || die "theme is not available: $SETUP_THEME"
        setup_config_validate
        save_choices
    else
        print_review
    fi
    run_installation
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
