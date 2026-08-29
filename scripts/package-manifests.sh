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
    local host="$2"
    local kind="$3"
    local destination="$4"
    local profile suffix base_manifest host_manifest
    declare -n resolved_packages_ref="$destination"

    # ShellCheck cannot observe that this nameref clears the caller's array.
    # shellcheck disable=SC2034
    resolved_packages_ref=()
    case "$kind" in
        repository)
            suffix=.txt
            base_manifest=$repository/packages/base.txt
            host_manifest=$repository/hosts/$host/packages.txt
            ;;
        aur)
            suffix=.aur.txt
            base_manifest=$repository/packages/aur.txt
            host_manifest=$repository/hosts/$host/aur.txt
            ;;
        providers)
            suffix=.providers.txt
            base_manifest=$repository/packages/providers.txt
            host_manifest=$repository/hosts/$host/providers.txt
            ;;
        *)
            printf 'Unknown package manifest kind: %s\n' "$kind" >&2
            return 1
            ;;
    esac

    append_package_manifest "$base_manifest" "$destination"
    append_package_manifest "$host_manifest" "$destination"
    for profile in "${INSTALLER_PROFILES[@]}"; do
        append_package_manifest \
            "$repository/packages/profiles/$profile$suffix" "$destination"
        append_package_manifest \
            "$repository/hosts/$host/profiles/$profile$suffix" "$destination"
    done
}
