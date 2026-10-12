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
