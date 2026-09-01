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

home=$test_root/home
state=$test_root/state
system_root=$test_root/root
fake_bin=$test_root/bin
mkdir -p \
    "$home/.config/hypr" \
    "$home/.local/share/keyrings" \
    "$state/blankweave" \
    "$system_root/etc/systemd/system/getty@tty1.service.d" \
    "$system_root/etc/systemd/system/plymouth-quit.service.d" \
    "$system_root/etc/issue.d" \
    "$system_root/etc/pam.d" \
    "$system_root/boot/loader/entries" \
    "$fake_bin"

for config in hyprland.lua env.lua monitors.lua hypridle.conf hyprlock.conf; do
    touch "$home/.config/hypr/$config"
done
touch "$home/.zprofile"
printf 'Default_keyring\n' > "$home/.local/share/keyrings/default"
printf '[keyring]\ndisplay-name=Default keyring\n' \
    > "$home/.local/share/keyrings/Default_keyring.keyring"
# The literal unit template variable must survive in the fixture.
# shellcheck disable=SC2016
printf '%s\n' \
    '[Service]' \
    'ExecStart=' \
    'ExecStart=-/sbin/agetty --autologin test --noclear - $TERM' \
    > "$system_root/etc/systemd/system/getty@tty1.service.d/autologin.conf"
printf '\033[?25h' > "$system_root/etc/issue.d/blankweave-cursor.issue"
printf '%s\n' \
    '[Service]' \
    'ExecStart=' \
    'ExecStart=-/usr/bin/plymouth deactivate' \
    'ExecStart=-/usr/bin/plymouth quit --retain-splash' \
    > "$system_root/etc/systemd/system/plymouth-quit.service.d/blankweave.conf"
printf 'HOOKS=(base systemd plymouth autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)\n' \
    > "$system_root/etc/mkinitcpio.conf"
printf '%s\n' \
    'title Arch Linux' \
    'linux /vmlinuz-linux' \
    'options root=UUID=redacted rw quiet splash loglevel=3' \
    > "$system_root/boot/loader/entries/arch.conf"
printf 'NAME=Arch Linux\nPRETTY_NAME="Arch Linux"\n' > "$system_root/etc/os-release"
git -C "$repository" rev-parse HEAD > "$state/blankweave/installed-revision"

for executable in blankweave-doctor-fixture hyprland; do
    ln -s /usr/bin/true "$fake_bin/$executable"
done

cat > "$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$fake_bin/systemctl"

cat > "$fake_bin/pacman" <<'EOF'
#!/usr/bin/env bash
printf '%s 1.0-1\n' "$2"
EOF
chmod +x "$fake_bin/pacman"

run_doctor() {
    PATH="$fake_bin:/usr/bin" \
        HOME="$home" \
        XDG_CONFIG_HOME="$home/.config" \
        XDG_STATE_HOME="$state" \
        XDG_SESSION_TYPE=wayland \
        XDG_CURRENT_DESKTOP=Hyprland \
        BLANKWEAVE_USER_HOME="$home" \
        BLANKWEAVE_SYSTEM_ROOT="$system_root" \
        BLANKWEAVE_SYSFS_ROOT="$system_root/sys" \
        BLANKWEAVE_TEST_CPU_VENDOR=GenuineIntel \
        BLANKWEAVE_TEST_LSPCI_OUTPUT='' \
        BLANKWEAVE_TEST_LSUSB_OUTPUT='' \
        BLANKWEAVE_TEST_DDC_DISPLAY=false \
        BLANKWEAVE_DOCTOR_COMMANDS=blankweave-doctor-fixture \
        "$repository/scripts/doctor.sh" "$repository" "$@"
}

output=$(run_doctor)
grep -Eq '^PASS  +repository ' <<< "$output"
grep -Fq 'PASS  runtime commands' <<< "$output"
grep -Fq 'PASS  tty1 automatic login' <<< "$output"
grep -Fq 'PASS  Plymouth handoff' <<< "$output"
grep -Fq 'PASS  initramfs microcode' <<< "$output"
grep -Fq 'PASS  CPU microcode package' <<< "$output"
grep -Fq '0 failures' <<< "$output"

report=$(run_doctor --report)
grep -Fq 'Sanitized report' <<< "$report"
grep -Fq 'hyprlock: 1.0-1' <<< "$report"
grep -Fq 'intel-ucode: 1.0-1' <<< "$report"
grep -Fq 'serial numbers omitted' <<< "$report"
if grep -Fq "$home" <<< "$report"; then
    printf 'Sanitized report exposed the fixture home path.\n' >&2
    exit 1
fi

rm "$fake_bin/blankweave-doctor-fixture"
if run_doctor > "$test_root/failure.log" 2>&1; then
    printf 'Doctor unexpectedly passed with a missing core command.\n' >&2
    exit 1
fi
grep -Fq 'FAIL  runtime commands' "$test_root/failure.log"
grep -Fq 'missing: blankweave-doctor-fixture' "$test_root/failure.log"

if run_doctor --unknown > /dev/null 2>&1; then
    printf 'Doctor unexpectedly accepted an unknown argument.\n' >&2
    exit 1
else
    [[ $? -eq 2 ]]
fi

printf 'Doctor tests passed.\n'
