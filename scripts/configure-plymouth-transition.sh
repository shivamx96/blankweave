#!/usr/bin/env bash

set -euo pipefail

[[ $# -eq 0 ]] || {
    printf 'usage: configure-plymouth-transition.sh\n' >&2
    exit 1
}

system_root=${BLANKWEAVE_SYSTEM_ROOT:-}
[[ -z "$system_root" || "$system_root" == /* ]] || {
    printf 'BLANKWEAVE_SYSTEM_ROOT must be an absolute path.\n' >&2
    exit 1
}

dropin_dir=$system_root/etc/systemd/system/plymouth-quit.service.d
dropin_file=$dropin_dir/blankweave.conf
staged=

cleanup() {
    [[ -z "$staged" || ! -e "$staged" ]] || rm -f -- "$staged"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$dropin_dir"
staged=$(mktemp "$dropin_dir/.blankweave.XXXXXX")
cat > "$staged" <<'EOF'
[Service]
ExecStart=
ExecStart=-/usr/bin/plymouth deactivate
ExecStart=-/usr/bin/plymouth quit --retain-splash
EOF
chmod 0644 "$staged"
mv -f "$staged" "$dropin_file"
staged=

# A former display-manager setup may mask these units so it can own the
# handoff. With direct getty/UWSM startup, restore the upstream synchronization
# point and retain Plymouth's final framebuffer until Hyprland replaces it.
systemctl unmask plymouth-quit.service plymouth-quit-wait.service
systemctl daemon-reload

printf 'Plymouth framebuffer retention is configured for the next boot.\n'
