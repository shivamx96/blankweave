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

fake_bin=$test_root/bin
system_root=$test_root/root
command_log=$test_root/commands.log
mkdir -p "$fake_bin" "$system_root/etc/sddm.conf.d"
touch "$system_root/etc/sddm.conf.d/autologin.conf"
touch "$system_root/etc/sddm.conf.d/preserved.conf"

cat > "$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$BLANKWEAVE_TEST_LOG"
EOF
cat > "$fake_bin/pacman" <<'EOF'
#!/usr/bin/env bash
printf 'pacman %s\n' "$*" >> "$BLANKWEAVE_TEST_LOG"
exit 0
EOF
chmod +x "$fake_bin/systemctl" "$fake_bin/pacman"

PATH="$fake_bin:$PATH" \
    BLANKWEAVE_SYSTEM_ROOT="$system_root" \
    BLANKWEAVE_TEST_LOG="$command_log" \
    "$repository/scripts/configure-console-autologin.sh" blankweave

dropin=$system_root/etc/systemd/system/getty@tty1.service.d/autologin.conf
grep -Fxq '[Service]' "$dropin"
grep -Fxq 'ExecStart=' "$dropin"
grep -Fxq "ExecStart=-/usr/bin/agetty --skip-login --nonewline --noissue --autologin blankweave --noreset --noclear - \${TERM}" "$dropin"
[[ $(stat -c %a "$dropin") == 644 ]]
[[ $(od -An -tx1 "$system_root/etc/issue.d/blankweave-cursor.issue" | tr -d ' \n') == 1b5b3f3235680a ]]
[[ ! -e $system_root/etc/sddm.conf.d/autologin.conf ]]
[[ -e $system_root/etc/sddm.conf.d/preserved.conf ]]

grep -Fxq 'systemctl disable sddm.service' "$command_log"
grep -Fxq 'systemctl daemon-reload' "$command_log"
grep -Fxq 'systemctl enable getty@tty1.service' "$command_log"
grep -Fxq 'pacman -Q -- sddm' "$command_log"
grep -Fxq 'pacman -R --noconfirm sddm' "$command_log"
if grep -Eq 'systemctl .*--now|systemctl (stop|restart) ' "$command_log"; then
    printf 'The live display-manager session must not be stopped during apply.\n' >&2
    exit 1
fi

# Invalid names cannot reach system configuration or a shell command line.
if PATH="$fake_bin:$PATH" \
    BLANKWEAVE_SYSTEM_ROOT="$system_root" \
    BLANKWEAVE_TEST_LOG="$command_log" \
    "$repository/scripts/configure-console-autologin.sh" 'bad;name' 2> /dev/null; then
    printf 'Invalid automatic-login username unexpectedly passed.\n' >&2
    exit 1
fi

# The deployed profile follows UWSM's guarded tty1 integration and the lock
# screen remains available without being forced at graphical-session startup.
grep -Fxq 'if uwsm check may-start; then' "$repository/defaults/shell/profile"
grep -Fxq "    exec uwsm start -e -D Hyprland hyprland.desktop >> \"\$session_log\" 2>&1" "$repository/defaults/shell/profile"
if grep -Fq 'start-hyprland' "$repository/defaults/shell/profile"; then
    printf 'The profile still bypasses direct UWSM session startup.\n' >&2
    exit 1
fi
if grep -Fq 'hyprlock' "$repository/defaults/hypr/autostart.lua"; then
    printf 'Hyprlock is still forced at graphical-session startup.\n' >&2
    exit 1
fi
if grep -Fq 'blankweave-lock' "$repository/defaults/hypr/hyprlock.conf"; then
    printf 'Hyprlock still selects the removed compatibility PAM service.\n' >&2
    exit 1
fi

# Once Hyprland owns DRM, its first startup helper clears the tty1 text buffer
# that would otherwise be exposed briefly on the way to shutdown Plymouth.
tty_fixture=$test_root/tty1
: > "$tty_fixture"
# shellcheck source=defaults/shell/clear-boot-console.sh
source "$repository/defaults/shell/clear-boot-console.sh"
clear_boot_console "$tty_fixture"
[[ $(od -An -tx1 "$tty_fixture" | tr -d ' \n') == 1b5b3f32356c1b5b324a1b5b334a1b5b48 ]]
grep -Fq 'clear-boot-console.sh' "$repository/defaults/hypr/autostart.lua"

printf 'Console automatic-login configuration tests passed.\n'
