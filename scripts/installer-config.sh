#!/usr/bin/env bash

# Safe parser for ~/.config/blankweave/install.conf. This file is sourced by the
# installer and intentionally never sources or evaluates the user's config.

INSTALLER_CONFIG_VERSION=1
INSTALLER_AVAILABLE_PROFILES=(desktop development communication gaming)
INSTALLER_PROFILES=()

installer_config_error() {
    printf 'Invalid Blankweave installer config: %s\n' "$*" >&2
    return 1
}

installer_config_trim() {
    local value="$1"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    REPLY=$value
}

installer_config_defaults() {
    local host="$1"

    INSTALLER_PROFILES=(desktop development communication)
    if [[ "$host" == pc ]]; then
        INSTALLER_PROFILES+=(gaming)
    fi
}

installer_config_profile_known() {
    local requested="$1"
    local available

    for available in "${INSTALLER_AVAILABLE_PROFILES[@]}"; do
        [[ "$requested" == "$available" ]] && return 0
    done
    return 1
}

installer_config_load() {
    local config_file="$1"
    local host="$2"
    local line key value profile available
    local config_version=
    local profiles_value=
    local version_seen=false
    local profiles_seen=false
    local -a requested_profiles=()

    if [[ ! -e "$config_file" && ! -L "$config_file" ]]; then
        installer_config_defaults "$host"
        return 0
    fi
    [[ -f "$config_file" && -r "$config_file" ]] || {
        installer_config_error "$config_file is not a readable regular file"
        return 1
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
        line=${line%$'\r'}
        installer_config_trim "$line"
        line=$REPLY
        [[ -z "$line" || "$line" == \#* ]] && continue
        [[ "$line" == *=* ]] || {
            installer_config_error "expected key=value, found: $line"
            return 1
        }

        key=${line%%=*}
        value=${line#*=}
        installer_config_trim "$key"
        key=$REPLY
        installer_config_trim "$value"
        value=$REPLY

        case "$key" in
            version)
                [[ "$version_seen" == false ]] || {
                    installer_config_error "version is defined more than once"
                    return 1
                }
                version_seen=true
                config_version=$value
                ;;
            profiles)
                [[ "$profiles_seen" == false ]] || {
                    installer_config_error "profiles is defined more than once"
                    return 1
                }
                profiles_seen=true
                profiles_value=$value
                ;;
            *)
                installer_config_error "unknown key: $key"
                return 1
                ;;
        esac
    done < "$config_file"

    [[ "$version_seen" == true ]] || {
        installer_config_error "version is required"
        return 1
    }
    [[ "$config_version" == "$INSTALLER_CONFIG_VERSION" ]] || {
        installer_config_error "unsupported version: $config_version"
        return 1
    }
    [[ "$profiles_seen" == true ]] || {
        installer_config_error "profiles is required"
        return 1
    }

    read -r -a requested_profiles <<< "$profiles_value"
    for profile in "${requested_profiles[@]}"; do
        installer_config_profile_known "$profile" || {
            installer_config_error "unknown profile: $profile"
            return 1
        }
    done

    INSTALLER_PROFILES=()
    for available in "${INSTALLER_AVAILABLE_PROFILES[@]}"; do
        for profile in "${requested_profiles[@]}"; do
            if [[ "$profile" == "$available" ]]; then
                INSTALLER_PROFILES+=("$available")
                break
            fi
        done
    done
}

installer_profile_enabled() {
    local requested="$1"
    local profile

    for profile in "${INSTALLER_PROFILES[@]}"; do
        [[ "$requested" == "$profile" ]] && return 0
    done
    return 1
}
