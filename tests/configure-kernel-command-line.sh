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

configure=$repository/scripts/configure-kernel-command-line.sh
entries=$test_root/entries
mkdir -p "$entries"

cat > "$entries/arch.conf" <<'EOF'
title Arch Linux
linux /vmlinuz-linux
options root=PARTUUID=abc rw rootflags=subvol=@
EOF
cat > "$entries/fallback.conf" <<'EOF'
title Arch Linux fallback
linux /vmlinuz-linux
options root=PARTUUID=abc rw quiet splash quiet loglevel=7 systemd.show_status=true udev.log_priority=7 vt.global_cursor_default=1 vt.default_blu=46 vt.default_red=30 vt.default_grn=30
EOF
cat > "$entries/windows.conf" <<'EOF'
title Windows
efi /EFI/Microsoft/Boot/bootmgfw.efi
EOF
windows_checksum=$(sha256sum "$entries/windows.conf")

"$configure" "$entries" > /dev/null

managed='quiet splash loglevel=3 systemd.show_status=false rd.systemd.show_status=false udev.log_level=3 rd.udev.log_level=3 vt.global_cursor_default=0'
grep -Fxq "options root=PARTUUID=abc rw rootflags=subvol=@ $managed vt.default_red=0 vt.default_grn=0 vt.default_blu=0" "$entries/arch.conf"
grep -Fxq "options root=PARTUUID=abc rw $managed vt.default_red=30 vt.default_grn=30 vt.default_blu=46" "$entries/fallback.conf"
[[ $(sha256sum "$entries/windows.conf") == "$windows_checksum" ]]
[[ $(grep -oE '(^| )quiet( |$)' "$entries/fallback.conf" | wc -l) -eq 1 ]]
[[ $(grep -o 'loglevel=' "$entries/fallback.conf" | wc -l) -eq 1 ]]

# A second pass is byte-for-byte idempotent.
checksum=$(sha256sum "$entries"/*.conf)
"$configure" "$entries" > /dev/null
[[ $(sha256sum "$entries"/*.conf) == "$checksum" ]]

# Reject an ambiguous entry before modifying any otherwise-valid entry.
broken=$test_root/broken
mkdir -p "$broken"
cp "$entries/arch.conf" "$broken/arch.conf"
cat > "$broken/ambiguous.conf" <<'EOF'
title Ambiguous
options root=/dev/a rw
options root=/dev/b rw
EOF
before=$(sha256sum "$broken/arch.conf")
if "$configure" "$broken" > /dev/null 2>&1; then
    printf 'An entry with multiple options lines unexpectedly passed.\n' >&2
    exit 1
fi
[[ $(sha256sum "$broken/arch.conf") == "$before" ]]

mkdir -p "$test_root/empty"
"$configure" "$test_root/empty" > /dev/null

printf 'Kernel command-line configuration tests passed.\n'
