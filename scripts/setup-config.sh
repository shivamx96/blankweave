#!/usr/bin/env bash

# Safe parser for ~/.config/blankweave/setup.conf. This file records only
# non-secret first-run choices and is intentionally never sourced or evaluated.

SETUP_CONFIG_VERSION=1
SETUP_THEME=obsidian
SETUP_MODE=dark
SETUP_GIT_IDENTITY=skip
SETUP_GIT_NAME=
SETUP_GIT_EMAIL=
SETUP_SSH_KEY=skip

setup_config_error() {
    printf 'Invalid Blankweave setup config: %s\n' "$*" >&2
    return 1
}

setup_config_trim() {
    local value="$1"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    REPLY=$value
}

setup_config_valid_text() {
    local value="$1"
    local maximum="$2"

    (( ${#value} <= maximum )) && [[ ! $value =~ [[:cntrl:]] ]]
}

setup_config_validate() {
    [[ $SETUP_THEME =~ ^[a-z0-9][a-z0-9-]*$ ]] || {
        setup_config_error "invalid theme id: $SETUP_THEME"
        return 1
    }
    [[ $SETUP_MODE == dark || $SETUP_MODE == light ]] || {
        setup_config_error "mode must be dark or light"
        return 1
    }
    [[ $SETUP_GIT_IDENTITY == configure || $SETUP_GIT_IDENTITY == skip ]] || {
        setup_config_error "git_identity must be configure or skip"
        return 1
    }
    setup_config_valid_text "$SETUP_GIT_NAME" 200 || {
        setup_config_error "git_name contains control characters or is too long"
        return 1
    }
    setup_config_valid_text "$SETUP_GIT_EMAIL" 254 || {
        setup_config_error "git_email contains control characters or is too long"
        return 1
    }
    if [[ -n $SETUP_GIT_EMAIL && ! $SETUP_GIT_EMAIL =~ ^[^[:space:]@]+@[^[:space:]@]+$ ]]; then
        setup_config_error "git_email is not a valid email address"
        return 1
    fi
    if [[ $SETUP_GIT_IDENTITY == configure && ( -z $SETUP_GIT_NAME || -z $SETUP_GIT_EMAIL ) ]]; then
        setup_config_error "git_name and git_email are required when git_identity=configure"
        return 1
    fi
    [[ $SETUP_SSH_KEY == generate || $SETUP_SSH_KEY == skip ]] || {
        setup_config_error "ssh_key must be generate or skip"
        return 1
    }
    if [[ $SETUP_SSH_KEY == generate && -z $SETUP_GIT_EMAIL ]]; then
        setup_config_error "git_email is required when ssh_key=generate"
        return 1
    fi
}

setup_config_load() {
    local config_file="$1"
    local line key value
    local config_version=
    local -A seen=()

    SETUP_THEME=obsidian
    SETUP_MODE=dark
    SETUP_GIT_IDENTITY=skip
    SETUP_GIT_NAME=
    SETUP_GIT_EMAIL=
    SETUP_SSH_KEY=skip

    if [[ ! -e $config_file && ! -L $config_file ]]; then
        return 0
    fi
    [[ -f $config_file && -r $config_file ]] || {
        setup_config_error "$config_file is not a readable regular file"
        return 1
    }

    while IFS= read -r line || [[ -n $line ]]; do
        line=${line%$'\r'}
        setup_config_trim "$line"
        line=$REPLY
        [[ -z $line || $line == \#* ]] && continue
        [[ $line == *=* ]] || {
            setup_config_error "expected key=value, found: $line"
            return 1
        }

        key=${line%%=*}
        value=${line#*=}
        setup_config_trim "$key"
        key=$REPLY
        setup_config_trim "$value"
        value=$REPLY
        [[ -n $key ]] || {
            setup_config_error "key cannot be empty"
            return 1
        }
        [[ -z ${seen[$key]+set} ]] || {
            setup_config_error "$key is defined more than once"
            return 1
        }
        seen[$key]=1

        case "$key" in
            version) config_version=$value ;;
            theme) SETUP_THEME=$value ;;
            mode) SETUP_MODE=$value ;;
            git_identity) SETUP_GIT_IDENTITY=$value ;;
            git_name) SETUP_GIT_NAME=$value ;;
            git_email) SETUP_GIT_EMAIL=$value ;;
            ssh_key) SETUP_SSH_KEY=$value ;;
            *)
                setup_config_error "unknown key: $key"
                return 1
                ;;
        esac
    done < "$config_file"

    [[ -n ${seen[version]+set} ]] || {
        setup_config_error "version is required"
        return 1
    }
    [[ $config_version == "$SETUP_CONFIG_VERSION" ]] || {
        setup_config_error "unsupported version: $config_version"
        return 1
    }
    for key in theme mode git_identity git_name git_email ssh_key; do
        [[ -n ${seen[$key]+set} ]] || {
            setup_config_error "$key is required"
            return 1
        }
    done
    setup_config_validate
}
