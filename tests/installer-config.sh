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

laptop_capabilities='cpu-intel gpu-intel audio-intel battery internal-display internal-backlight bluetooth wifi gaming'
desktop_capabilities='cpu-amd gpu-nvidia ddc-display bluetooth gaming'
amd_capabilities='cpu-amd gpu-amd ddc-display gaming'

installer_config_load "$test_root/missing.conf" "$laptop_capabilities"
assert_profiles 'desktop development communication'
resolve_package_manifests "$repository" "$laptop_capabilities" repository packages
assert_contains seahorse "${packages[@]}"
for shell_package in nano zsh zsh-autosuggestions zsh-syntax-highlighting zsh-completions zsh-history-substring-search fzf zoxide wireless-regdb; do
    assert_contains "$shell_package" "${packages[@]}"
done

# All fontconfig families are required even without an optional desktop profile.
for font_package in ttf-atkinson-hyperlegible ttf-jetbrains-mono ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji noto-fonts-cjk; do
    grep -Fxq "$font_package" "$repository/packages/base.txt"
done
assert_excludes sddm "${packages[@]}"
assert_contains intel-media-driver "${packages[@]}"
assert_contains intel-ucode "${packages[@]}"
assert_contains linux-firmware "${packages[@]}"
assert_contains intel-gpu-tools "${packages[@]}"
assert_contains nvtop "${packages[@]}"
assert_contains playerctl "${packages[@]}"
assert_contains brightnessctl "${packages[@]}"
assert_contains bluez "${packages[@]}"
assert_contains upower "${packages[@]}"
assert_contains docker "${packages[@]}"
assert_excludes steam "${packages[@]}"
resolve_package_manifests "$repository" "$laptop_capabilities" aur aur_packages
for shell_package in zsh-theme-powerlevel10k fzf-tab-git oh-my-zsh-git; do
    assert_contains "$shell_package" "${aur_packages[@]}"
done

resolve_package_manifests "$repository" "$laptop_capabilities" providers provider_packages

installer_config_load "$test_root/missing.conf" "$desktop_capabilities"
assert_profiles 'desktop development communication gaming'
resolve_package_manifests "$repository" "$desktop_capabilities" repository packages
assert_excludes wireless-regdb "${packages[@]}"
assert_contains nvidia-open-dkms "${packages[@]}"
assert_contains amd-ucode "${packages[@]}"
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
assert_contains amd-ucode "${packages[@]}"
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

printf '%s\n' 'version=1' 'profiles=voice-dictation' > "$config_file"
installer_config_load "$config_file" "$laptop_capabilities"
assert_profiles 'voice-dictation'
resolve_package_manifests "$repository" "$laptop_capabilities" repository packages
assert_contains wtype "${packages[@]}"
assert_contains at-spi2-core "${packages[@]}"
assert_contains python-gobject "${packages[@]}"
resolve_package_manifests "$repository" "$laptop_capabilities" aur aur_packages
assert_contains voxtype-bin "${aur_packages[@]}"

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


# File-manager runtime support is mandatory even with every profile deselected.
printf 'version=1\nprofiles=\n' > "$config_file"
installer_config_load "$config_file" "$laptop_capabilities"
resolve_package_manifests "$repository" "$laptop_capabilities" repository packages
for package in mpv loupe papers gvfs gvfs-mtp udisks2 tumbler ffmpegthumbnailer webp-pixbuf-loader; do
    assert_contains "$package" "${packages[@]}"
done
assert_excludes gvfs-smb "${packages[@]}"
printf 'version=1\nprofiles=desktop\n' > "$config_file"
installer_config_load "$config_file" "$laptop_capabilities"
resolve_package_manifests "$repository" "$laptop_capabilities" repository packages
assert_contains gvfs-smb "${packages[@]}"

printf 'Installer config and package profile tests passed.\n'

# Installer seeds in the normal user's context after deployment. Runtime writer
# cases (missing, explicit, unrelated, symlink) run in default-apps.sh.
# shellcheck disable=SC2016
grep -Fq 'python3 "$DOTS_DIR/shell/default-apps.py" seed' "$repository/install.sh"

# Required cache retention must not depend on an optional profile.
grep -Fxq pacman-contrib "$repository/packages/base.txt"
if rg -q '^pacman-contrib$' "$repository/packages/profiles"; then exit 1; fi
grep -Fq 'systemctl enable paccache.timer' "$repository/install.sh"

# Choice initialization must precede package changes, and optional defaults
# must pass through the per-item ledger rather than unconditional mutations.
[[ $(grep -n '^installer_choices_init$' "$repository/install.sh" | cut -d: -f1) -lt $(grep -n '^section "INSTALLING PACKAGES"' "$repository/install.sh" | cut -d: -f1) ]]
grep -Fq 'installer_seed docker installer_seed_service docker.service' "$repository/install.sh"
# shellcheck disable=SC2016
grep -Fq 'installer_seed docker-group usermod -aG docker "$SUDO_USER"' "$repository/install.sh"
# shellcheck disable=SC2016
grep -Fq 'installer_seed login-shell chsh -s /usr/bin/zsh "$SUDO_USER"' "$repository/install.sh"
grep -Fq 'installer_seed tailscaled installer_seed_service tailscaled.service' "$repository/install.sh"
