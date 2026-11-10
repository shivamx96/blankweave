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
    "$system_root/boot/EFI/blankweave" \
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
    'initrd /initramfs-linux.img' \
    'options root=UUID=redacted rw quiet splash loglevel=3' \
    > "$system_root/boot/loader/entries/arch.conf"
touch "$system_root/boot/vmlinuz-linux" "$system_root/boot/initramfs-linux.img"
printf 'fixture Limine EFI executable\n' \
    > "$system_root/boot/EFI/blankweave/limine-x64.efi"
printf '%s\n' \
    'timeout: 3' \
    'quiet: yes' \
    'default_entry: 1' \
    '/Arch Linux' \
    '    protocol: linux' \
    '    path: boot():/vmlinuz-linux' \
    '    module_path: boot():/initramfs-linux.img' \
    '    cmdline: root=UUID=redacted rw quiet splash loglevel=3' \
    '/Blankweave recovery (systemd-boot)' \
    '    protocol: efi_boot_entry' \
    '    entry: Linux Boot Manager' \
    > "$system_root/boot/EFI/blankweave/limine.conf"
printf 'NAME=Arch Linux\nPRETTY_NAME="Arch Linux"\n' > "$system_root/etc/os-release"
git -C "$repository" rev-parse HEAD > "$state/blankweave/installed-revision"

for executable in blankweave-doctor-fixture intel_gpu_top; do
    ln -s /usr/bin/true "$fake_bin/$executable"
done

cat > "$fake_bin/hyprland" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == --version ]]; then
    printf 'Hyprland %s built from fixture\n' "${BLANKWEAVE_TEST_INSTALLED_HYPRLAND:-0.57.1}"
fi
EOF
cat > "$fake_bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
case ${1:-} in
    version)
        [[ ${BLANKWEAVE_TEST_HYPRLAND_MODE:-current} != offline ]] || exit 1
        printf '{"version":"%s"}\n' "${BLANKWEAVE_TEST_RUNNING_HYPRLAND:-0.57.1}"
        ;;
    deprecated-config)
        case ${BLANKWEAVE_TEST_HYPRLAND_MODE:-current} in
            old) exit 1 ;;
            unsupported) printf 'unknown request\n' ;;
            malformed) printf '{"unexpected":true}\n' ;;
            deprecated) printf '["misc:layers_hog_keyboard_focus: use layers:layers_hog_keyboard_focus", "private fixture detail\\nflattened"]\n' ;;
            *) printf '[]\n' ;;
        esac
        ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$fake_bin/hyprland" "$fake_bin/hyprctl"

cat > "$fake_bin/getcap" <<'EOF'
#!/usr/bin/env bash
if [[ ${BLANKWEAVE_TEST_GETCAP_MODE:-configured} == configured ]]; then
    printf '%s cap_perfmon=ep\n' "$1"
fi
EOF
chmod +x "$fake_bin/getcap"

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

cat > "$fake_bin/efibootmgr" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' \
    'BootCurrent: 0007' \
    'BootOrder: 0007,0004,0000' \
    $'Boot0000* Windows Boot Manager\tHD(1,GPT,windows)/\\EFI\\Microsoft\\Boot\\bootmgfw.efi' \
    $'Boot0004* Linux Boot Manager\tHD(1,GPT,blankweave)/\\EFI\\systemd\\systemd-bootx64.efi' \
    $'Boot0007* Blankweave Boot Manager\tHD(1,GPT,blankweave)/\\EFI\\blankweave\\limine-x64.efi'
EOF
chmod +x "$fake_bin/efibootmgr"

cat > "$fake_bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BLANKWEAVE_TEST_SUDO_LOG"
if [[ ${1:-} == --non-interactive ]]; then
    shift
fi
export BLANKWEAVE_TEST_ALLOW_BOOT_HELPER=true
export BLANKWEAVE_TEST_BOOT_ACCESSIBLE=true
exec "$@"
EOF
chmod +x "$fake_bin/sudo"

run_doctor() {
    PATH="$fake_bin:/usr/bin" \
        HOME="$home" \
        XDG_CONFIG_HOME="$home/.config" \
        XDG_STATE_HOME="$state" \
        XDG_SESSION_TYPE=wayland \
        XDG_CURRENT_DESKTOP=Hyprland \
        HYPRLAND_INSTANCE_SIGNATURE="${BLANKWEAVE_TEST_HYPRLAND_SESSION-fixture}" \
        BLANKWEAVE_USER_HOME="$home" \
        BLANKWEAVE_SYSTEM_ROOT="$system_root" \
        BLANKWEAVE_SYSFS_ROOT="$system_root/sys" \
        BLANKWEAVE_TEST_CPU_VENDOR=GenuineIntel \
        BLANKWEAVE_TEST_LSPCI_OUTPUT="${BLANKWEAVE_TEST_LSPCI_OUTPUT:-}" \
        BLANKWEAVE_TEST_LSUSB_OUTPUT='' \
        BLANKWEAVE_TEST_DDC_DISPLAY=false \
        BLANKWEAVE_TEST_BOOT_ACCESSIBLE="${BLANKWEAVE_TEST_BOOT_ACCESSIBLE:-true}" \
        BLANKWEAVE_DOCTOR_BOOT_HELPER="$repository/scripts/doctor.sh" \
        BLANKWEAVE_DOCTOR_SUDO="$fake_bin/sudo" \
        BLANKWEAVE_TEST_SUDO_LOG="$test_root/sudo.log" \
        BLANKWEAVE_DOCTOR_COMMANDS=blankweave-doctor-fixture \
        "$repository/scripts/doctor.sh" "$repository" "$@"
}

output=$(run_doctor)
grep -Eq '^PASS  +repository ' <<< "$output"
grep -Fq 'PASS  runtime commands' <<< "$output"
grep -Fq 'PASS  tty1 automatic login' <<< "$output"
grep -Fq 'PASS  Plymouth handoff' <<< "$output"
grep -Fq 'PASS  initramfs microcode' <<< "$output"
grep -Fq 'PASS  Limine EFI executable' <<< "$output"
grep -Fq 'PASS  Limine BLS handoff' <<< "$output"
grep -Fq 'PASS  UEFI boot order' <<< "$output"
grep -Fq 'PASS  bootloader recovery' <<< "$output"
grep -Fq 'PASS  CPU microcode package' <<< "$output"
grep -Fq '0 failures' <<< "$output"
grep -Fq 'running and installed 0.57.1' <<< "$output"
grep -Eq '^PASS +Hyprland deprecations +none reported' <<< "$output"

different_version=$(BLANKWEAVE_TEST_RUNNING_HYPRLAND=0.56.0 run_doctor)
grep -Eq '^WARN +Hyprland runtime +running 0.56.0; installed 0.57.1' <<< "$different_version"
for mode in old unsupported malformed; do
    unavailable=$(BLANKWEAVE_TEST_HYPRLAND_MODE=$mode run_doctor)
    grep -Eq '^SKIP +Hyprland deprecations' <<< "$unavailable"
    grep -Fq '0 failures' <<< "$unavailable"
done
offline=$(BLANKWEAVE_TEST_HYPRLAND_MODE=offline run_doctor)
grep -Eq '^SKIP +Hyprland runtime +running compositor version unavailable' <<< "$offline"
no_session=$(BLANKWEAVE_TEST_HYPRLAND_SESSION='' run_doctor)
grep -Eq '^SKIP +Hyprland runtime +graphical session or IPC tools unavailable' <<< "$no_session"
deprecated=$(BLANKWEAVE_TEST_HYPRLAND_MODE=deprecated run_doctor)
grep -Eq '^WARN +Hyprland deprecations +2 deprecated options' <<< "$deprecated"
grep -Fq 'use layers:layers_hog_keyboard_focus' <<< "$deprecated"
grep -Fq 'private fixture detail flattened' <<< "$deprecated"
private_report=$(BLANKWEAVE_TEST_HYPRLAND_MODE=deprecated run_doctor --report)
grep -Fq '2 deprecated options' <<< "$private_report"
if grep -Fq 'private fixture detail' <<< "$private_report"; then
    printf 'Doctor report leaked a deprecation notice\n' >&2
    exit 1
fi

mkdir -p "$home/.config/blankweave"
saved_rules=$home/.config/blankweave/monitors.lua
# Syntax checking must never execute saved rules.
printf 'error("must not execute")\n' > "$saved_rules"
valid_layout=$(run_doctor)
grep -Eq '^PASS +saved monitor rules +Lua syntax valid' <<< "$valid_layout"
printf 'hl.monitor({ broken =\n' > "$saved_rules"
cp "$saved_rules" "$test_root/invalid-monitor.lua"
invalid_layout=$(run_doctor)
grep -Eq '^WARN +saved monitor rules +monitors.lua has invalid Lua syntax' <<< "$invalid_layout"
cmp "$saved_rules" "$test_root/invalid-monitor.lua"
rm "$saved_rules"
ln -s "$test_root/missing-layout" "$saved_rules"
unreadable_layout=$(run_doctor)
grep -Eq '^WARN +saved monitor rules +monitors.lua is unreadable' <<< "$unreadable_layout"
rm "$saved_rules"

intel_gpu='00:02.0 VGA compatible controller: Intel Corporation Meteor Lake-P [Intel Arc Graphics]'
gpu_output=$(BLANKWEAVE_TEST_LSPCI_OUTPUT="$intel_gpu" run_doctor)
grep -Fq 'PASS  Intel GPU telemetry      CAP_PERFMON is configured' <<< "$gpu_output"
gpu_warning=$(
    BLANKWEAVE_TEST_LSPCI_OUTPUT="$intel_gpu" \
        BLANKWEAVE_TEST_GETCAP_MODE=missing \
        run_doctor
)
grep -Fq 'WARN  Intel GPU telemetry      CAP_PERFMON is missing; run blankweave update' \
    <<< "$gpu_warning"

restricted_boot_output=$(BLANKWEAVE_TEST_BOOT_ACCESSIBLE=false run_doctor)
grep -Fq 'SKIP  kernel command line      /boot is not accessible to the current user' \
    <<< "$restricted_boot_output"
grep -Fq 'SKIP  Limine EFI executable    /boot requires privileged inspection' \
    <<< "$restricted_boot_output"
grep -Fq 'SKIP  Limine Linux entries     /boot requires privileged inspection' \
    <<< "$restricted_boot_output"
grep -Fq 'SKIP  Limine BLS handoff       /boot requires privileged inspection' \
    <<< "$restricted_boot_output"
grep -Fq 'SKIP  bootloader recovery      firmware entry exists; /boot requires privileged inspection' \
    <<< "$restricted_boot_output"
grep -Fq '0 failures' <<< "$restricted_boot_output"
[[ ! -e $test_root/sudo.log ]]

full_boot_output=$(BLANKWEAVE_TEST_BOOT_ACCESSIBLE=false run_doctor --full)
grep -Fq 'PASS  kernel command line' <<< "$full_boot_output"
grep -Fq 'PASS  Limine EFI executable' <<< "$full_boot_output"
grep -Fq 'PASS  Limine BLS handoff' <<< "$full_boot_output"
grep -Fq 'PASS  bootloader recovery' <<< "$full_boot_output"
grep -Fq '0 failures' <<< "$full_boot_output"
grep -Fxq -- "--non-interactive $repository/scripts/doctor.sh --boot-only" \
    "$test_root/sudo.log"

mv "$system_root/boot" "$system_root/boot.available"
if run_doctor > "$test_root/missing-boot.log" 2>&1; then
    printf 'Doctor unexpectedly accepted a missing /boot tree.\n' >&2
    exit 1
fi
grep -Fq 'FAIL  Limine EFI executable' "$test_root/missing-boot.log"
grep -Fq 'FAIL  Limine Linux entries' "$test_root/missing-boot.log"
grep -Fq 'FAIL  Limine BLS handoff' "$test_root/missing-boot.log"
mv "$system_root/boot.available" "$system_root/boot"

report=$(run_doctor --report)
grep -Fq 'Sanitized report' <<< "$report"
grep -Fq 'hyprlock: 1.0-1' <<< "$report"
grep -Fq 'intel-ucode: 1.0-1' <<< "$report"
grep -Fq 'limine: 1.0-1' <<< "$report"
grep -Fq 'serial numbers omitted' <<< "$report"
if grep -Fq "$home" <<< "$report"; then
    printf 'Sanitized report exposed the fixture home path.\n' >&2
    exit 1
fi

cp "$system_root/boot/EFI/blankweave/limine.conf" "$test_root/limine.conf.good"
sed -i 's/root=UUID=redacted/root=UUID=drifted/' \
    "$system_root/boot/EFI/blankweave/limine.conf"
if run_doctor > "$test_root/boot-drift.log" 2>&1; then
    printf 'Doctor unexpectedly accepted a drifted Limine kernel command line.\n' >&2
    exit 1
fi
grep -Fq 'FAIL  Limine BLS handoff' "$test_root/boot-drift.log"
mv "$test_root/limine.conf.good" "$system_root/boot/EFI/blankweave/limine.conf"

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

if run_doctor --full --normal > /dev/null 2>&1; then
    printf 'Doctor unexpectedly combined full and normal scan modes.\n' >&2
    exit 1
else
    [[ $? -eq 2 ]]
fi

printf 'Doctor tests passed.\n'
