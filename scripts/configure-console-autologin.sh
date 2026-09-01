#!/usr/bin/env bash

set -euo pipefail

[[ $# -eq 1 ]] || {
    printf 'usage: configure-console-autologin.sh <username>\n' >&2
    exit 1
}

username=$1
system_root=${BLANKWEAVE_SYSTEM_ROOT:-}

[[ "$username" =~ ^[a-z_][a-z0-9_-]*$ ]] || {
    printf 'Invalid automatic-login username: %s\n' "$username" >&2
    exit 1
}
[[ -z "$system_root" || "$system_root" == /* ]] || {
    printf 'BLANKWEAVE_SYSTEM_ROOT must be an absolute path.\n' >&2
    exit 1
}

dropin_dir=$system_root/etc/systemd/system/getty@tty1.service.d
dropin_file=$dropin_dir/autologin.conf
issue_dir=$system_root/etc/issue.d
staged=

cleanup() {
    [[ -z "$staged" || ! -e "$staged" ]] || rm -f -- "$staged"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$dropin_dir"
staged=$(mktemp "$dropin_dir/.autologin.XXXXXX")
cat > "$staged" <<EOF
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --skip-login --nonewline --noissue --autologin $username --noreset --noclear - \${TERM}
EOF
chmod 0644 "$staged"
mv -f "$staged" "$dropin_file"
staged=

# The boot command line hides the VT cursor during the graphical handoff.
# tty1 suppresses issue files, while ordinary recovery gettys print this small
# terminal sequence and restore their visible cursor.
mkdir -p "$issue_dir"
printf '\033[?25h\n' > "$issue_dir/blankweave-cursor.issue"
chmod 0644 "$issue_dir/blankweave-cursor.issue"

# Disable SDDM for the next boot, but never stop it during an apply: the
# installer is normally running inside the graphical session SDDM launched.
systemctl disable sddm.service 2>/dev/null || true
rm -f -- "$system_root/etc/sddm.conf.d/autologin.conf"
if [[ -d "$system_root/etc/sddm.conf.d" ]]; then
    rmdir --ignore-fail-on-non-empty "$system_root/etc/sddm.conf.d"
fi

systemctl daemon-reload
systemctl enable getty@tty1.service

# Package manifests are additive, so removing SDDM from base.txt alone would
# leave it installed on upgrades. Remove only SDDM itself; retain any packages
# that pacman originally installed as its dependencies.
if pacman -Q -- sddm &> /dev/null; then
    pacman -R --noconfirm sddm
fi

printf 'TTY1 automatic login is configured for %s; it takes effect next boot.\n' "$username"
