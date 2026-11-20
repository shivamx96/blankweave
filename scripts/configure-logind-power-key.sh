#!/usr/bin/env bash
set -euo pipefail

system_root=${BLANKWEAVE_SYSTEM_ROOT:-}
[[ $# -eq 0 && ( -z "$system_root" || "$system_root" == /* ) ]] || {
    printf 'Usage: configure-logind-power-key.sh (BLANKWEAVE_SYSTEM_ROOT must be absolute)\n' >&2
    exit 1
}
dropin_dir=$system_root/etc/systemd/logind.conf.d
dropin_file=$dropin_dir/50-blankweave.conf
staged=
trap '[[ -z "$staged" ]] || rm -f -- "$staged"' EXIT
mkdir -p "$dropin_dir"
staged=$(mktemp "$dropin_dir/.power-key.XXXXXX")
cat > "$staged" <<'POLICY'
[Login]
HandlePowerKey=ignore
HandlePowerKeyLongPress=poweroff
POLICY
chmod 0644 "$staged"
if [[ -f "$dropin_file" ]] && cmp -s "$staged" "$dropin_file"; then
    exit 0
fi
mv -f -- "$staged" "$dropin_file"
staged=
# systemd-logind.service(8): SIGHUP reloads configuration. Never restart it:
# restarting logind can terminate the graphical session running this installer.
systemctl kill --kill-whom=main --signal=HUP systemd-logind.service \
    || printf 'Power key policy saved; it takes effect after the next restart.\n' >&2
