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

laptop_capabilities='gpu-intel audio-intel battery internal-display internal-backlight bluetooth gaming'
desktop_capabilities='gpu-nvidia ddc-display bluetooth gaming'
amd_capabilities='gpu-amd ddc-display gaming'

installer_config_load "$test_root/missing.conf" "$laptop_capabilities"
assert_profiles 'desktop development communication'
resolve_package_manifests "$repository" "$laptop_capabilities" repository packages
assert_contains seahorse "${packages[@]}"
assert_excludes sddm "${packages[@]}"
assert_contains intel-media-driver "${packages[@]}"
assert_contains intel-gpu-tools "${packages[@]}"
assert_contains nvtop "${packages[@]}"
assert_contains playerctl "${packages[@]}"
assert_contains brightnessctl "${packages[@]}"
assert_contains bluez "${packages[@]}"
assert_contains upower "${packages[@]}"
assert_contains docker "${packages[@]}"
assert_excludes steam "${packages[@]}"
resolve_package_manifests "$repository" "$laptop_capabilities" aur aur_packages
resolve_package_manifests "$repository" "$laptop_capabilities" providers provider_packages

installer_config_load "$test_root/missing.conf" "$desktop_capabilities"
assert_profiles 'desktop development communication gaming'
resolve_package_manifests "$repository" "$desktop_capabilities" repository packages
assert_contains nvidia-open-dkms "${packages[@]}"
assert_contains cuda "${packages[@]}"
assert_contains nvtop "${packages[@]}"
assert_contains ddcutil "${packages[@]}"
assert_excludes brightnessctl "${packages[@]}"
assert_excludes upower "${packages[@]}"
assert_contains steam "${packages[@]}"
resolve_package_manifests "$repository" "$desktop_capabilities" aur aur_packages
resolve_package_manifests "$repository" "$desktop_capabilities" providers provider_packages

installer_config_load "$test_root/missing.conf" "$amd_capabilities"
assert_profiles 'desktop development communication gaming'
resolve_package_manifests "$repository" "$amd_capabilities" repository packages
assert_contains mesa "${packages[@]}"
assert_contains vulkan-radeon "${packages[@]}"
assert_contains lib32-vulkan-radeon "${packages[@]}"
assert_contains nvtop "${packages[@]}"
assert_excludes nvidia-open-dkms "${packages[@]}"

config_file=$test_root/install.conf
printf '%s\n' \
    '# Explicit order is normalized.' \
    'version = 1' \
    'profiles = gaming desktop gaming' > "$config_file"
installer_config_load "$config_file" "$laptop_capabilities"
assert_profiles 'desktop gaming'

resolve_package_manifests "$repository" "$laptop_capabilities" repository packages
assert_contains firefox "${packages[@]}"
assert_contains steam "${packages[@]}"
assert_contains lib32-vulkan-intel "${packages[@]}"
assert_excludes docker "${packages[@]}"

resolve_package_manifests "$repository" "$laptop_capabilities" aur aur_packages
assert_contains zen-browser-bin "${aur_packages[@]}"
assert_contains proton-ge-custom-bin "${aur_packages[@]}"
assert_excludes slack-desktop "${aur_packages[@]}"

resolve_package_manifests "$repository" "$laptop_capabilities" providers provider_packages
assert_contains pipewire-jack "${provider_packages[@]}"
assert_excludes iptables "${provider_packages[@]}"
assert_excludes jdk21-openjdk "${provider_packages[@]}"

printf '%s\n' 'version=1' 'profiles=' > "$config_file"
installer_config_load "$config_file" "$laptop_capabilities"
assert_profiles ''
resolve_package_manifests "$repository" "$laptop_capabilities" repository packages
assert_excludes firefox "${packages[@]}"
assert_excludes docker "${packages[@]}"

for invalid_config in \
    $'version=2\nprofiles=desktop' \
    $'version=1\nprofiles=unknown' \
    $'version=1\nprofiles=desktop\nfuture=true'; do
    printf '%s\n' "$invalid_config" > "$config_file"
    if installer_config_load "$config_file" "$laptop_capabilities" 2> /dev/null; then
        printf 'Invalid config unexpectedly passed: %s\n' "$invalid_config" >&2
        exit 1
    fi
done

printf 'Installer config and package profile tests passed.\n'
