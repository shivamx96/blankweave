#!/usr/bin/env bash
set -euo pipefail
# Called by the root apply only after all read-only prerequisites pass.
scripts=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=${BLANKWEAVE_SYSTEM_ROOT:-}
user_home=${2:-$(getent passwd "$1" | cut -d: -f6)}
[[ -n $user_home ]] || { printf 'Cannot resolve sign-in policy home.\n' >&2; exit 1; }
[[ ! -e $root/etc/blankweave/signin.conf ]] || exit 0
[[ ! -s ${BLANKWEAVE_USER_STATE_HOME:-$user_home/.local/state}/blankweave/installed-revision ]] || exit 0
# shellcheck source=scripts/setup-config.sh
source "$scripts/setup-config.sh"
# shellcheck source=scripts/root-encryption.sh
source "$scripts/root-encryption.sh"
setup_config_load "$user_home/.config/blankweave/setup.conf"
policy=$SETUP_AUTOMATIC_SIGNIN
if [[ -z $policy ]]; then
    if root_is_encrypted; then policy=yes; else
        policy=no
        printf 'Root encryption unconfirmed: defaulting to password-required sign-in.\n'
    fi
fi
mkdir -p "$root/etc/blankweave"
printf '%s\n' "$policy" > "$root/etc/blankweave/signin.conf"
chmod 644 "$root/etc/blankweave/signin.conf"
