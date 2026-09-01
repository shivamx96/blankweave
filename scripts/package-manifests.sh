#!/usr/bin/env bash

append_package_manifest() {
    local manifest="$1"
    local destination="$2"
    local line package existing
    local duplicate
    declare -n manifest_packages_ref="$destination"

    [[ -f "$manifest" ]] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        read -r package <<< "$line"
        [[ -n "$package" ]] || continue
        [[ "$package" =~ ^[a-zA-Z0-9@._+-]+$ ]] || {
            printf 'Invalid package name in %s: %s\n' "$manifest" "$package" >&2
            return 1
        }

        duplicate=false
        for existing in "${manifest_packages_ref[@]}"; do
            if [[ "$existing" == "$package" ]]; then
                duplicate=true
                break
            fi
        done
        [[ "$duplicate" == true ]] || manifest_packages_ref+=("$package")
    done < "$manifest"
}

resolve_package_manifests() {
    local repository="$1"
    local capabilities="$2"
    local kind="$3"
    local destination="$4"
    local profile capability suffix base_manifest capability_manifest
    declare -n resolved_packages_ref="$destination"

    # ShellCheck cannot observe that this nameref clears the caller's array.
    # shellcheck disable=SC2034
    resolved_packages_ref=()
    case "$kind" in
        repository)
            suffix=.txt
            base_manifest=$repository/packages/base.txt
            ;;
        aur)
            suffix=.aur.txt
            base_manifest=$repository/packages/aur.txt
            ;;
        providers)
            suffix=.providers.txt
            base_manifest=$repository/packages/providers.txt
            ;;
        *)
            printf 'Unknown package manifest kind: %s\n' "$kind" >&2
            return 1
            ;;
    esac

    append_package_manifest "$base_manifest" "$destination"
    for capability in $capabilities; do
        [[ $capability =~ ^[a-z0-9][a-z0-9-]*$ ]] || {
            printf 'Invalid hardware capability: %s\n' "$capability" >&2
            return 1
        }
        case $kind in
            repository) capability_manifest=$repository/packages/capabilities/$capability/packages.txt ;;
            aur) capability_manifest=$repository/packages/capabilities/$capability/aur.txt ;;
            providers) capability_manifest=$repository/packages/capabilities/$capability/providers.txt ;;
        esac
        append_package_manifest "$capability_manifest" "$destination"
    done
    for profile in "${INSTALLER_PROFILES[@]}"; do
        append_package_manifest \
            "$repository/packages/profiles/$profile$suffix" "$destination"
        for capability in $capabilities; do
            append_package_manifest \
                "$repository/packages/capabilities/$capability/profiles/$profile$suffix" \
                "$destination"
        done
    done
}
