#!/usr/bin/env bash

# Required targets fail closed. Optional profile targets are attempted separately
# so a broken upstream app never prevents unrelated packages from being installed.
OPTIONAL_PACKAGE_FAILURES=()

install_package_targets() {
    local kind=$1
    shift
    (( $# )) || return 0
    case "$kind" in
        repository|providers) pacman -S --noconfirm --needed "$@" ;;
        aur)
            local package
            local -a targets=()
            for package in "$@"; do targets+=("aur/$package"); done
            sudo -H -u "$SUDO_USER" paru -S --noconfirm --needed --noprovides "${targets[@]}"
            ;;
        *) return 1 ;;
    esac
}

install_manifest_packages() {
    local repository=$1 capabilities=$2 kind=$3 package required_package is_required
    local -a required=() selected=()
    resolve_package_manifests "$repository" "$capabilities" "$kind" required required || return $?
    resolve_package_manifests "$repository" "$capabilities" "$kind" selected || return $?

    # Provider choices are deliberate dependency decisions even when supplied by
    # a profile. Do not let a later optional install pick a different provider.
    [[ $kind != providers ]] || required=("${selected[@]}")
    if (( ${#required[@]} )); then
        printf '\nInstalling required %s packages (%s targets)...\n' "$kind" "${#required[@]}"
        install_package_targets "$kind" "${required[@]}" || return $?
        verify_packages_installed "$kind" "${required[@]}" || return $?
    fi

    for package in "${selected[@]}"; do
        is_required=false
        for required_package in "${required[@]}"; do
            [[ $package != "$required_package" ]] || is_required=true
        done
        [[ $is_required == false ]] || continue
        printf '\nInstalling optional %s package: %s\n' "$kind" "$package"
        if install_package_targets "$kind" "$package" && pacman -Q -- "$package" >/dev/null 2>&1; then
            continue
        fi
        OPTIONAL_PACKAGE_FAILURES+=("$kind/$package")
        warn "Optional package $package failed; continuing. Its download/build checks were not bypassed."
    done
}

print_optional_package_retries() {
    local target
    (( ${#OPTIONAL_PACKAGE_FAILURES[@]} )) || return 0
    printf '\nOptional packages needing attention (%s):\n' "${#OPTIONAL_PACKAGE_FAILURES[@]}"
    printf 'Check the package error above. Retry after fixing the cause or after an upstream update:\n'
    for target in "${OPTIONAL_PACKAGE_FAILURES[@]}"; do
        case "$target" in
            aur/*) printf '  paru -S --needed --noprovides %q\n' "$target" ;;
            repository/*) printf '  sudo pacman -S --needed -- %q\n' "${target#*/}" ;;
        esac
    done
    printf 'For a checksum mismatch, do not skip verification. A clean download may fix a corrupt cache; otherwise the upstream package needs correction.\n'
}

# Resolve every selected missing target as one transaction before managed files
# are deployed. Disable downloads: rollback uses only the existing sync DB/cache.
install_rollback_packages() (
    local repository=$1 capabilities=$2 kind package config transaction
    local -a selected=() missing=()
    for kind in providers repository aur; do
        resolve_package_manifests "$repository" "$capabilities" "$kind" selected || return
        for package in "${selected[@]}"; do
            if ! pacman -Q -- "$package" >/dev/null 2>&1; then
                missing+=("$package")
            fi
        done
    done
    (( ${#missing[@]} )) || return 0
    printf 'Rollback: installing only missing manifest packages from local cache: %s\n' "${missing[*]}"
    config=$(mktemp /tmp/blankweave-rollback-pacman.XXXXXX) || return
    trap 'rm -f -- "$config"' EXIT
    # Preserve repository configuration, replacing any configured downloader.
    awk '
        /^[[:space:]]*XferCommand[[:space:]]*=/ { next }
        { print }
        /^\[options\]/ { print "XferCommand = /usr/bin/false" }
    ' /etc/pacman.conf > "$config"
    if ! transaction=$(pacman --config "$config" -Sp --needed --print-format '%n' -- "${missing[@]}"); then
        printf 'Rollback stopped: missing packages cannot be resolved from local databases/cache. No managed configuration was applied.\n' >&2
        return 1
    fi
    while IFS= read -r package; do
        [[ -n $package ]] || continue
        if pacman -Q -- "$package" >/dev/null 2>&1; then
            printf 'Rollback stopped: installing missing packages would change installed package %s. Run a normal full update instead.\n' "$package" >&2
            return 1
        fi
    done <<< "$transaction"
    if ! pacman --config "$config" -S --needed --noconfirm -- "${missing[@]}"; then
        printf 'Rollback stopped: missing packages (or dependencies) could not be installed from local databases/cache. No managed configuration was applied. Restore the package cache or complete a normal full update before retrying.\n' >&2
        return 1
    fi
    verify_packages_installed rollback "${missing[@]}"
)
