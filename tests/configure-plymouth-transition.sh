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
mkdir -p "$fake_bin"
cat > "$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$BLANKWEAVE_TEST_LOG"
EOF
chmod +x "$fake_bin/systemctl"

PATH="$fake_bin:$PATH" \
    BLANKWEAVE_SYSTEM_ROOT="$system_root" \
    BLANKWEAVE_TEST_LOG="$command_log" \
    "$repository/scripts/configure-plymouth-transition.sh"

dropin=$system_root/etc/systemd/system/plymouth-quit.service.d/blankweave.conf
grep -Fxq '[Service]' "$dropin"
grep -Fxq 'ExecStart=' "$dropin"
grep -Fxq 'ExecStart=-/usr/bin/plymouth deactivate' "$dropin"
grep -Fxq 'ExecStart=-/usr/bin/plymouth quit --retain-splash' "$dropin"
[[ $(stat -c %a "$dropin") == 644 ]]
grep -Fxq 'systemctl unmask plymouth-quit.service plymouth-quit-wait.service' "$command_log"
grep -Fxq 'systemctl daemon-reload' "$command_log"

checksum=$(sha256sum "$dropin")
PATH="$fake_bin:$PATH" \
    BLANKWEAVE_SYSTEM_ROOT="$system_root" \
    BLANKWEAVE_TEST_LOG="$command_log" \
    "$repository/scripts/configure-plymouth-transition.sh" > /dev/null
[[ $(sha256sum "$dropin") == "$checksum" ]]

printf 'Plymouth transition configuration tests passed.\n'
