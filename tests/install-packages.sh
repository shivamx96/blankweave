#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
# shellcheck source=scripts/package-manifests.sh
source "$repository/scripts/package-manifests.sh"
# shellcheck source=scripts/install-packages.sh
source "$repository/scripts/install-packages.sh"

mkdir -p "$test_root/packages/profiles"
printf 'core\n' > "$test_root/packages/base.txt"
printf 'theme\n' > "$test_root/packages/aur.txt"
printf 'provider\n' > "$test_root/packages/profiles/development.providers.txt"
printf 'core\neditor\nnotes\n' > "$test_root/packages/profiles/development.txt"
printf 'lmstudio-bin\nafter-failure\ntheme\n' > "$test_root/packages/profiles/development.aur.txt"
INSTALLER_PROFILES=(development)
SUDO_USER=fixture
failed_target=aur/lmstudio-bin
package_log=$test_root/commands

pacman() {
    if [[ $1 == -Q ]]; then [[ ${*: -1} != "${missing_target:-}" ]]; return; fi
    printf 'pacman %s\n' "$*" >> "$package_log"
    [[ " $* " != *" $failed_target "* ]]
}
paru() {
    printf 'paru %s\n' "$*" >> "$package_log"
    if [[ " $* " == *" $failed_target "* ]]; then
        printf 'sha256sums: FAILED\n' >&2
        return 17
    fi
}
sudo() { shift 3; "$@"; }
warn() { printf 'Warning: %s\n' "$*"; }
verify_packages_installed() {
    shift
    local package
    for package in "$@"; do pacman -Q -- "$package" || return 1; done
}

install_manifest_packages "$test_root" '' aur > "$test_root/output" 2>&1
[[ ${OPTIONAL_PACKAGE_FAILURES[*]} == aur/lmstudio-bin ]]
grep -q 'aur/after-failure' "$package_log"
[[ $(grep -c 'aur/theme' "$package_log") == 1 ]]
grep -q 'sha256sums: FAILED' "$test_root/output"
print_optional_package_retries > "$test_root/retries"
grep -q 'paru -S --needed --noprovides aur/lmstudio-bin' "$test_root/retries"
if grep -Eq 'skipchecksums|skipinteg' "$package_log"; then exit 1; fi

# Repository apps are isolated too, and duplicates of required targets stay required.
failed_target=editor
install_manifest_packages "$test_root" '' repository > /dev/null
[[ ${OPTIONAL_PACKAGE_FAILURES[*]} == 'aur/lmstudio-bin repository/editor' ]]
grep -q 'pacman .*notes' "$package_log"
[[ $(grep -c 'pacman .*core' "$package_log") == 1 ]]

# Required AUR/core packages and deliberate providers fail the whole phase.
for pair in 'aur aur/theme' 'repository core' 'providers provider'; do
    read -r kind failed_target <<< "$pair"
    : > "$package_log"
    if install_manifest_packages "$test_root" '' "$kind" > /dev/null 2>&1; then
        printf 'Required package failure was ignored: %s\n' "$pair" >&2
        exit 1
    fi
    [[ $(wc -l < "$package_log") == 1 ]]
done

# A successful package-manager command is insufficient if the target is absent.
failed_target=none
missing_target=core
if install_manifest_packages "$test_root" '' repository >/dev/null 2>&1; then exit 1; fi
missing_target=after-failure
OPTIONAL_PACKAGE_FAILURES=()
install_manifest_packages "$test_root" '' aur >/dev/null
[[ ${OPTIONAL_PACKAGE_FAILURES[*]} == aur/after-failure ]]
printf 'Required and optional package installation tests passed.\n'
