#!/usr/bin/env bash

set -euo pipefail

repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)

cleanup() {
    if [[ -n $test_root && -d $test_root ]]; then
        rm -rf -- "$test_root"
    fi
}
trap cleanup EXIT HUP INT TERM

configure=$repository/scripts/configure-plymouth-hooks.sh
config=$test_root/mkinitcpio.conf

assert_hooks() {
    local expected=$1
    grep -Fxq "$expected" "$config"
}

# Busybox initramfs: insert after udev and before the encrypted-root hook.
printf '%s\n' \
    'MODULES=()' \
    'HOOKS=(base udev autodetect keyboard block encrypt filesystems fsck)' > "$config"
"$configure" "$config" > /dev/null
assert_hooks 'HOOKS=(base udev plymouth autodetect microcode keyboard block encrypt filesystems fsck)'

# Existing but unsafe placement is repaired, not duplicated.
printf '%s\n' \
    'MODULES=()' \
    'HOOKS=(base udev autodetect keyboard block encrypt plymouth filesystems fsck)' > "$config"
"$configure" "$config" > /dev/null
assert_hooks 'HOOKS=(base udev plymouth autodetect microcode keyboard block encrypt filesystems fsck)'
[[ $(grep -o 'plymouth' "$config" | wc -l) -eq 1 ]]

# systemd initramfs uses the same Plymouth hook, placed before sd-encrypt.
printf '%s\n' \
    'MODULES=()' \
    'HOOKS=(base systemd autodetect keyboard sd-vconsole block sd-encrypt filesystems fsck) # managed' > "$config"
"$configure" "$config" > /dev/null
assert_hooks 'HOOKS=(base systemd plymouth autodetect microcode keyboard sd-vconsole block sd-encrypt filesystems fsck) # managed'

# Existing microcode placement is normalized without duplicating the hook.
printf '%s\n' \
    'MODULES=()' \
    'HOOKS=(base microcode udev plymouth autodetect modconf kms block filesystems)' > "$config"
"$configure" "$config" > /dev/null
assert_hooks 'HOOKS=(base udev plymouth autodetect microcode modconf kms block filesystems)'
[[ $(grep -o 'microcode' "$config" | wc -l) -eq 1 ]]

# Fallback images without autodetect still receive early microcode.
printf '%s\n' 'HOOKS=(base udev modconf kms block filesystems)' > "$config"
"$configure" "$config" > /dev/null
assert_hooks 'HOOKS=(base udev plymouth microcode modconf kms block filesystems)'

# A second pass must not rewrite an already-correct file.
checksum=$(sha256sum "$config")
"$configure" "$config" > /dev/null
[[ $(sha256sum "$config") == "$checksum" ]]

# Unknown initramfs layouts fail closed instead of claiming success.
printf '%s\n' 'HOOKS=(base autodetect block filesystems)' > "$config"
if "$configure" "$config" > /dev/null 2>&1; then
    printf 'Expected a HOOKS array without udev/systemd to be rejected.\n' >&2
    exit 1
fi

printf 'Plymouth hook configuration tests passed.\n'
