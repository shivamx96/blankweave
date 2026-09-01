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

esp=$test_root/esp
entries=$esp/loader/entries
fake_bin=$test_root/bin
efi_state=$test_root/efi-state
efi_log=$test_root/efi-log
mkdir -p "$entries" "$fake_bin"

printf 'fixture Limine EFI executable\n' > "$test_root/BOOTX64.EFI"
for artifact in vmlinuz-linux intel-ucode.img initramfs-linux.img vmlinuz-linux-lts initramfs-linux-lts.img; do
    printf '%s\n' "$artifact" > "$esp/$artifact"
done

printf '%s\n' \
    'title Arch Linux (linux)' \
    'linux /vmlinuz-linux' \
    'initrd /intel-ucode.img' \
    'initrd /initramfs-linux.img' \
    'options cryptdevice=UUID=encrypted:root root=/dev/mapper/root rw quiet splash' \
    > "$entries/arch.conf"
printf '%s\n' \
    'title Arch Linux (linux-lts)' \
    'linux /vmlinuz-linux-lts' \
    'initrd /initramfs-linux-lts.img' \
    'options cryptdevice=UUID=encrypted:root root=/dev/mapper/root rw quiet splash' \
    > "$entries/arch-lts.conf"
printf '%s\n' \
    'title Existing foreign BLS entry' \
    'efi /EFI/foreign/loader.efi' \
    > "$entries/foreign.conf"

printf '%s\n' \
    'BootCurrent: 0004' \
    'Timeout: 1 seconds' \
    'BootOrder: 0004,0000,0006,0009,0005,0002,0003,2001' \
    $'Boot0000* Windows Boot Manager\tHD(1,GPT,windows)/\\EFI\\Microsoft\\Boot\\bootmgfw.efi' \
    $'Boot0002* UEFI: PXE IPv4 Realtek\tPciRoot()/IPv4()' \
    $'Boot0003* UEFI: PXE IPv6 Realtek\tPciRoot()/IPv6()' \
    $'Boot0004* Linux Boot Manager\tHD(1,GPT,blankweave)/\\EFI\\systemd\\systemd-bootx64.efi' \
    $'Boot0006* Ubuntu\tHD(1,GPT,ubuntu)/\\EFI\\ubuntu\\shimx64.efi' \
    $'Boot0009* My Custom Linux\tHD(1,GPT,custom)/\\EFI\\custom\\loader.efi' \
    $'Boot2001* EFI USB Device\tRC' \
    $'Boot0005* UEFI OS\tHD(1,GPT,blankweave)/\\EFI\\BOOT\\BOOTX64.EFI' \
    > "$efi_state"

cat > "$fake_bin/efibootmgr" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
    -v)
        cat "$FAKE_EFI_STATE"
        ;;
    --create-only)
        label= loader=
        while (( $# > 0 )); do
            case "$1" in
                --label) label=$2; shift 2 ;;
                --loader) loader=$2; shift 2 ;;
                *) shift ;;
            esac
        done
        printf 'create-only %s %s\n' "$label" "$loader" >> "$FAKE_EFI_LOG"
        cp "$FAKE_EFI_STATE" "$FAKE_EFI_STATE.tmp"
        printf 'Boot0007* %s\tHD(1,GPT,blankweave)/%s\n' "$label" "$loader" \
            >> "$FAKE_EFI_STATE.tmp"
        mv "$FAKE_EFI_STATE.tmp" "$FAKE_EFI_STATE"
        ;;
    --bootorder)
        printf 'bootorder %s\n' "$2" >> "$FAKE_EFI_LOG"
        awk -v replacement="BootOrder: $2" \
            '/^BootOrder:/ {$0=replacement} {print}' "$FAKE_EFI_STATE" \
            > "$FAKE_EFI_STATE.tmp"
        mv "$FAKE_EFI_STATE.tmp" "$FAKE_EFI_STATE"
        ;;
    *)
        printf 'unexpected efibootmgr arguments: %s\n' "$*" >&2
        exit 1
        ;;
esac
EOF

cat > "$fake_bin/findmnt" <<'EOF'
#!/usr/bin/env bash
printf '/dev/nvme1n1p1\n'
EOF

cat > "$fake_bin/lsblk" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    *PKNAME*) printf 'nvme1n1\n' ;;
    *PARTN*) printf '1\n' ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$fake_bin"/*

run_configure() {
    PATH="$fake_bin:/usr/bin" \
    FAKE_EFI_STATE="$efi_state" \
    FAKE_EFI_LOG="$efi_log" \
    BLANKWEAVE_LIMINE_TEST=true \
    BLANKWEAVE_TEST_SECURE_BOOT="${BLANKWEAVE_TEST_SECURE_BOOT:-false}" \
    BLANKWEAVE_ESP_PATH="$esp" \
    BLANKWEAVE_DEFAULT_ENTRY_ID=arch.conf \
    BLANKWEAVE_LIMINE_SOURCE="$test_root/BOOTX64.EFI" \
    BLANKWEAVE_EFIBOOTMGR="$fake_bin/efibootmgr" \
    BLANKWEAVE_FINDMNT="$fake_bin/findmnt" \
    BLANKWEAVE_LSBLK="$fake_bin/lsblk" \
        "$repository/scripts/configure-limine.sh"
}

systemd_checksum=$(sha256sum "$entries"/*.conf)
run_configure > "$test_root/first-run.log"
config=$esp/EFI/blankweave/limine.conf
loader=$esp/EFI/blankweave/limine-x64.efi
cmp -s "$test_root/BOOTX64.EFI" "$loader"
grep -Fxq 'timeout: 5' "$config"
grep -Fxq 'quiet: no' "$config"
grep -Fxq 'default_entry: 1' "$config"
grep -Fxq '    path: boot():/vmlinuz-linux' "$config"
grep -Fxq '    module_path: boot():/intel-ucode.img' "$config"
grep -Fxq '    module_path: boot():/initramfs-linux.img' "$config"
grep -Fxq '    cmdline: cryptdevice=UUID=encrypted:root root=/dev/mapper/root rw quiet splash' "$config"
grep -Fxq '/Blankweave recovery (systemd-boot)' "$config"
grep -Fxq '    entry: Linux Boot Manager' "$config"
grep -Fxq '/Windows Boot Manager' "$config"
grep -Fxq '/Ubuntu' "$config"
grep -Fxq '/My Custom Linux' "$config"
grep -Fxq '/Boot from USB (EFI USB Device)' "$config"
grep -Fxq '    entry: EFI USB Device' "$config"
if grep -Fq 'PXE' "$config" || grep -Fq '/UEFI OS' "$config"; then
    printf 'A generic firmware device was imported as an operating system.\n' >&2
    exit 1
fi
[[ $(grep -n '^/Arch Linux' "$config" | head -n 1 | cut -d: -f1) -lt \
   $(grep -n '^/Arch Linux' "$config" | tail -n 1 | cut -d: -f1) ]]
grep -Fxq 'BootOrder: 0007,0004,0000,0006,0009,0005,0002,0003,2001' "$efi_state"
grep -Fq 'create-only Blankweave Boot Manager' "$efi_log"
grep -Fxq 'bootorder 0007,0004,0000,0006,0009,0005,0002,0003,2001' "$efi_log"
[[ $(sha256sum "$entries"/*.conf) == "$systemd_checksum" ]]

# Reconciliation is byte-for-byte idempotent and does not duplicate NVRAM.
before=$(sha256sum "$config" "$loader" "$efi_state" "$efi_log")
run_configure > "$test_root/second-run.log"
[[ $(sha256sum "$config" "$loader" "$efi_state" "$efi_log") == "$before" ]]

# Persistent generic USB firmware records are useful menu targets but do not
# prove a USB is currently inserted. A Linux-only firmware order still shows
# its kernel, recovery, and USB choices, but keeps the shorter timeout.
sed -i 's/^BootOrder:.*/BootOrder: 0007,0004,0005,0002,0003,2001/' "$efi_state"
run_configure > "$test_root/linux-only.log"
grep -Fxq 'timeout: 3' "$config"
grep -Fxq 'quiet: no' "$config"
grep -Fxq '/Boot from USB (EFI USB Device)' "$config"
if grep -Fq '/Windows Boot Manager' "$config"; then
    printf 'An OS outside BootOrder remained in the generated menu.\n' >&2
    exit 1
fi
before=$(sha256sum "$config" "$loader" "$efi_state" "$efi_log")

# Disabled Secure Boot must be a successful validation result, while enabled
# Secure Boot fails before changing the already-valid deployment.
if BLANKWEAVE_TEST_SECURE_BOOT=true run_configure > "$test_root/secure-boot.log" 2>&1; then
    printf 'Enabled Secure Boot unexpectedly passed unsigned Limine validation.\n' >&2
    exit 1
fi
grep -Fq 'Secure Boot is enabled' "$test_root/secure-boot.log"
[[ $(sha256sum "$config" "$loader" "$efi_state" "$efi_log") == "$before" ]]

# A malformed Linux entry fails before replacing a known-good configuration.
config_checksum=$(sha256sum "$config")
printf '%s\n' \
    'title Broken' \
    'linux /vmlinuz-linux' \
    'initrd /initramfs-linux.img' \
    > "$entries/broken.conf"
if run_configure > /dev/null 2>&1; then
    printf 'A Linux entry without a command line unexpectedly passed.\n' >&2
    exit 1
fi
[[ $(sha256sum "$config") == "$config_checksum" ]]
rm "$entries/broken.conf"

# A stale entry left behind by a removed kernel is omitted while another
# complete Linux entry remains bootable.
mv "$esp/initramfs-linux-lts.img" "$test_root/initramfs-linux-lts.img"
run_configure > "$test_root/stale-entry.log" 2>&1
if grep -Fq '/Arch Linux (linux-lts)' "$config"; then
    printf 'A Linux entry with a missing initrd was retained.\n' >&2
    exit 1
fi
mv "$test_root/initramfs-linux-lts.img" "$esp/initramfs-linux-lts.img"
run_configure > /dev/null
config_checksum=$(sha256sum "$config")

# Duplicate targetable firmware labels are rejected because Limine resolves
# efi_boot_entry entries by description rather than by Boot#### number.
printf '%s\n' $'Boot0008* Ubuntu\tHD(1,GPT,other)/\\EFI\\ubuntu\\shimx64.efi' >> "$efi_state"
sed -i 's/^BootOrder: /BootOrder: 0008,0006,/' "$efi_state"
if run_configure > /dev/null 2>&1; then
    printf 'Duplicate Ubuntu firmware labels unexpectedly passed.\n' >&2
    exit 1
fi
[[ $(sha256sum "$config") == "$config_checksum" ]]

printf 'Limine configuration tests passed.\n'
