#!/usr/bin/env bash
set -euo pipefail

installer_preflight() {
    local root=${1:-} tool variable value failed=false
    printf '\nChecking installation prerequisites...\n'
    if [[ ! -r $root/etc/arch-release ]]; then
        printf '  FAIL: Blankweave requires an installed Arch Linux system.\n' >&2
        failed=true
    fi
    if [[ ! -d $root/sys/firmware/efi ]]; then
        printf '  FAIL: Boot this machine in UEFI mode before installing Blankweave.\n' >&2
        failed=true
    fi
    for tool in sudo pacman git; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            printf '  FAIL: Required command is missing: %s\n' "$tool" >&2
            failed=true
        fi
    done
    if [[ -e $root/var/lib/pacman/db.lck ]]; then
        printf '  FAIL: Pacman is locked. Let the other package operation finish before retrying.\n' >&2
        failed=true
    fi
    for variable in "$root"/sys/firmware/efi/efivars/SecureBoot-*; do
        [[ -r $variable ]] || continue
        value=$(od -An -t u1 -j 4 -N 1 "$variable" | tr -d '[:space:]')
        if [[ $value == 1 ]]; then
            printf '  FAIL: Disable Secure Boot in firmware; Blankweave does not yet provide a signed boot loader.\n' >&2
            failed=true
        fi
    done
    [[ $failed == false ]] || return 1
    printf 'Basic prerequisites passed. Package downloads require a working Internet connection.\n'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    installer_preflight
fi
