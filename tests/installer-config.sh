#!/usr/bin/env bash

set -euo pipefail

repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)

cleanup() {
    if [[ -n "$test_root" && -d "$test_root" ]]; then
        rm -rf -- "$test_root"
    fi
}
trap cleanup EXIT HUP INT TERM

# shellcheck source=scripts/installer-config.sh
source "$repository/scripts/installer-config.sh"
# shellcheck source=scripts/package-manifests.sh
source "$repository/scripts/package-manifests.sh"

packages=()
aur_packages=()
provider_packages=()

assert_profiles() {
    local expected="$1"
    [[ "${INSTALLER_PROFILES[*]}" == "$expected" ]] || {
        printf 'Expected profiles "%s", found "%s".\n' \
            "$expected" "${INSTALLER_PROFILES[*]}" >&2
        exit 1
    }
}

assert_contains() {
    local needle="$1"
    shift
    local item

    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    printf 'Expected resolved packages to contain %s.\n' "$needle" >&2
    exit 1
}

assert_excludes() {
    local needle="$1"
    shift
    local item

    for item in "$@"; do
        if [[ "$item" == "$needle" ]]; then
            printf 'Expected resolved packages to exclude %s.\n' "$needle" >&2
            exit 1
        fi
    done
}

installer_config_load "$test_root/missing.conf" laptop
assert_profiles 'desktop development communication'
resolve_package_manifests "$repository" laptop repository packages
[[ "${#packages[@]}" -eq 80 ]]
assert_contains intel-media-driver "${packages[@]}"
assert_contains docker "${packages[@]}"
assert_excludes steam "${packages[@]}"
resolve_package_manifests "$repository" laptop aur aur_packages
[[ "${#aur_packages[@]}" -eq 11 ]]
resolve_package_manifests "$repository" laptop providers provider_packages
[[ "${#provider_packages[@]}" -eq 3 ]]

installer_config_load "$test_root/missing.conf" pc
assert_profiles 'desktop development communication gaming'
resolve_package_manifests "$repository" pc repository packages
[[ "${#packages[@]}" -eq 91 ]]
assert_contains nvidia-open-dkms "${packages[@]}"
assert_contains cuda "${packages[@]}"
assert_contains steam "${packages[@]}"
resolve_package_manifests "$repository" pc aur aur_packages
[[ "${#aur_packages[@]}" -eq 13 ]]
resolve_package_manifests "$repository" pc providers provider_packages
[[ "${#provider_packages[@]}" -eq 3 ]]

config_file=$test_root/install.conf
printf '%s\n' \
    '# Explicit order is normalized.' \
    'version = 1' \
    'profiles = gaming desktop gaming' > "$config_file"
installer_config_load "$config_file" laptop
assert_profiles 'desktop gaming'

resolve_package_manifests "$repository" laptop repository packages
assert_contains firefox "${packages[@]}"
assert_contains steam "${packages[@]}"
assert_contains lib32-vulkan-intel "${packages[@]}"
assert_excludes docker "${packages[@]}"

resolve_package_manifests "$repository" laptop aur aur_packages
assert_contains zen-browser-bin "${aur_packages[@]}"
assert_contains proton-ge-custom-bin "${aur_packages[@]}"
assert_excludes slack-desktop "${aur_packages[@]}"

resolve_package_manifests "$repository" laptop providers provider_packages
assert_contains pipewire-jack "${provider_packages[@]}"
assert_excludes iptables "${provider_packages[@]}"
assert_excludes jdk21-openjdk "${provider_packages[@]}"

printf '%s\n' 'version=1' 'profiles=' > "$config_file"
installer_config_load "$config_file" laptop
assert_profiles ''
resolve_package_manifests "$repository" laptop repository packages
assert_excludes firefox "${packages[@]}"
assert_excludes docker "${packages[@]}"

for invalid_config in \
    $'version=2\nprofiles=desktop' \
    $'version=1\nprofiles=unknown' \
    $'version=1\nprofiles=desktop\nfuture=true'; do
    printf '%s\n' "$invalid_config" > "$config_file"
    if installer_config_load "$config_file" laptop 2> /dev/null; then
        printf 'Invalid config unexpectedly passed: %s\n' "$invalid_config" >&2
        exit 1
    fi
done

printf 'Installer config and package profile tests passed.\n'
