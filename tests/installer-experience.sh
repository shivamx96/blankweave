#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
# shellcheck source=scripts/installer-preflight.sh
source "$repository/scripts/installer-preflight.sh"
# Avoid depending on which package tools are installed on the test host.
command() {
    [[ $1 == -v && ${2:-} != "${missing_tool:-}" ]]
}
mkdir -p "$test_root/etc" "$test_root/sys/firmware/efi/efivars" "$test_root/var/lib/pacman"
touch "$test_root/etc/arch-release"
printf '\0\0\0\0\0' > "$test_root/sys/firmware/efi/efivars/SecureBoot-fixture"
installer_preflight "$test_root" > /dev/null
printf '\0\0\0\0\1' > "$test_root/sys/firmware/efi/efivars/SecureBoot-fixture"
if installer_preflight "$test_root" > "$test_root/output" 2>&1; then exit 1; fi
grep -q 'Disable Secure Boot' "$test_root/output"
printf '\0\0\0\0\0' > "$test_root/sys/firmware/efi/efivars/SecureBoot-fixture"
touch "$test_root/var/lib/pacman/db.lck"
if installer_preflight "$test_root" > "$test_root/output" 2>&1; then exit 1; fi
grep -q 'Pacman is locked' "$test_root/output"
rm "$test_root/var/lib/pacman/db.lck"
missing_tool=sudo
if installer_preflight "$test_root" > "$test_root/output" 2>&1; then exit 1; fi
grep -q 'Required command is missing: sudo' "$test_root/output"
missing_tool=
rm "$test_root/etc/arch-release"
if installer_preflight "$test_root" > "$test_root/output" 2>&1; then exit 1; fi
grep -q 'requires an installed Arch' "$test_root/output"

# Failure reports must name the active stage and preserve the original exit code.
status=0
(
    # shellcheck source=scripts/install-progress.sh
    source "$repository/scripts/install-progress.sh"
    trap 'install_progress_exit "$?"' EXIT
    section 'CHECKING PREREQUISITES'
    section 'INSTALLING PACKAGES'
    exit 23
) > "$test_root/progress" 2>&1 || status=$?
[[ $status == 23 ]]
grep -q '\[4/21\] INSTALLING PACKAGES' "$test_root/progress"
grep -q 'stopped during: INSTALLING PACKAGES (exit 23' "$test_root/progress"
printf 'Installer prerequisite and progress tests passed.\n'
