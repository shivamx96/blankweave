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

# First-run choices and ownership are exercised without the privileged engine.
"$repository/tests/installer-choices.sh" < /dev/null

# shellcheck source=scripts/root-encryption.sh
source "$repository/scripts/root-encryption.sh"
for layout in $'lvm\ncrypt\npart\ndisk' $'crypt\nlvm\npart\ndisk' $'crypt\npart\ndisk'; do
    root_ancestors_encrypted <<< "$layout"
done
for layout in $'part\ndisk' '' $'lvm\npart\ndisk' unknown; do
    if root_ancestors_encrypted <<< "$layout"; then exit 1; fi
done
findmnt() { printf '%s\n' "${fixture_source:-/dev/mapper/root[/@]}"; }
lsblk() { printf '%s\n' "$fixture_types"; }
fixture_types=$'lvm\ncrypt\npart\ndisk'
root_is_encrypted
fixture_types=$'part\ndisk'
if root_is_encrypted; then exit 1; fi
fixture_source=overlay
if root_is_encrypted; then exit 1; fi
unset -f findmnt lsblk

# Preflight removes even a dangling leftover before reporting other failures.
mkdir -p "$test_root/etc/sudoers.d"
ln -s "$test_root/absent" "$test_root/etc/sudoers.d/blankweave-install"
# No elevation is needed in fixtures; stub only the exact cleanup operation.
sudo() { [[ $1 == rm && $2 == -f && $3 == -- ]]; rm -f -- "$4"; }
installer_preflight "$test_root" > /dev/null 2>&1 || true
[[ ! -L $test_root/etc/sudoers.d/blankweave-install ]]
grep -Fq 'configure-limine.sh" --check' "$repository/scripts/installer-preflight.sh"
grep -Fq 'configure-kernel-command-line.sh" --check' "$repository/scripts/installer-preflight.sh"

# The narrowed rule is validated only as a temporary file, never installed.
printf 'fixture ALL=(root) NOPASSWD: /usr/bin/pacman\n' > "$test_root/sudoers"
if builtin command -v visudo >/dev/null; then
    visudo -cf "$test_root/sudoers" > /dev/null
else
    printf 'SKIP: visudo unavailable; sudoers syntax not validated.\n'
fi

# Exercise the preflight boot gate with harmless check-only stand-ins.
mkdir "$test_root/check-scripts"
for name in configure-limine configure-kernel-command-line; do
    cat > "$test_root/check-scripts/$name.sh" <<'EOF_FIXTURE'
#!/bin/sh
[ "$1" = --check ] || exit 99
printf '%s\n' "$0 $1" >> "$CHECK_CALLS"
[ "${CHECK_UNSUPPORTED:-no}" != yes ]
EOF_FIXTURE
    chmod +x "$test_root/check-scripts/$name.sh"
done
export CHECK_CALLS=$test_root/check-calls
installer_check_boot_layout "$test_root/check-scripts"
[[ $(wc -l < "$CHECK_CALLS") == 2 ]]
if CHECK_UNSUPPORTED=yes installer_check_boot_layout "$test_root/check-scripts" > "$test_root/unsupported-check" 2>&1; then exit 1; fi
grep -q 'GRUB and UKI-only layouts are unsupported' "$test_root/unsupported-check"

# Output is a pure function; never invoke the privileged installer.
source "$repository/scripts/install-finish.sh"
install_welcome yes > "$test_root/welcome"
grep -Fxq 'Restart now: systemctl reboot' "$test_root/welcome"
grep -Fxq 'Your disk passphrase is the login.' "$test_root/welcome"
[[ $(grep -c '^Super+' "$test_root/welcome") == 5 ]]
[[ $(tail -n 1 "$test_root/welcome") == 'If something looks wrong: blankweave doctor' ]]
install_welcome no > "$test_root/welcome"
grep -Fxq 'You will sign in with your account password.' "$test_root/welcome"
if grep -q 'passphrase' "$test_root/welcome"; then exit 1; fi
install_update_summary false > "$test_root/update-summary"
[[ $(wc -l < "$test_root/update-summary") == 1 ]]
if grep -Eq 'Super\+|legacy|passphrase' "$test_root/update-summary"; then exit 1; fi
install_update_summary true > "$test_root/update-summary"
grep -q 'legacy .conf session' "$test_root/update-summary"
