#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
export BLANKWEAVE_SYSTEM_ROOT=$test_root/root
export BLANKWEAVE_TEST_LOG=$test_root/commands
mkdir -p "$test_root/bin" "$BLANKWEAVE_SYSTEM_ROOT/etc/systemd/logind.conf.d"
export PATH="$test_root/bin:$PATH"
cat > "$test_root/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BLANKWEAVE_TEST_LOG"
[[ "$*" == 'kill --kill-whom=main --signal=HUP systemd-logind.service' ]]
STUB
chmod +x "$test_root/bin/systemctl"
printf 'unrelated\n' > "$BLANKWEAVE_SYSTEM_ROOT/etc/systemd/logind.conf"
printf 'other\n' > "$BLANKWEAVE_SYSTEM_ROOT/etc/systemd/logind.conf.d/99-other.conf"
"$repository/scripts/configure-logind-power-key.sh"
dropin=$BLANKWEAVE_SYSTEM_ROOT/etc/systemd/logind.conf.d/50-blankweave.conf
printf '[Login]\nHandlePowerKey=ignore\nHandlePowerKeyLongPress=poweroff\n' > "$test_root/expected"
cmp "$test_root/expected" "$dropin"
[[ $(stat -c %a "$dropin") == 644 ]]
inode=$(stat -c %i "$dropin")
"$repository/scripts/configure-logind-power-key.sh"
[[ $(stat -c %i "$dropin") == "$inode" && $(wc -l < "$BLANKWEAVE_TEST_LOG") == 1 ]]
printf 'drift\n' > "$dropin"
"$repository/scripts/configure-logind-power-key.sh"
cmp "$test_root/expected" "$dropin"
[[ $(wc -l < "$BLANKWEAVE_TEST_LOG") == 2 ]]
[[ $(cat "$BLANKWEAVE_SYSTEM_ROOT/etc/systemd/logind.conf") == unrelated ]]
[[ $(cat "$BLANKWEAVE_SYSTEM_ROOT/etc/systemd/logind.conf.d/99-other.conf") == other ]]
if BLANKWEAVE_SYSTEM_ROOT=relative "$repository/scripts/configure-logind-power-key.sh" 2>/dev/null; then exit 1; fi
printf 'Logind power-key configuration tests passed.\n'
