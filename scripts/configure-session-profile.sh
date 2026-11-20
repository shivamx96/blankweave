#!/usr/bin/env bash
set -euo pipefail
system_root=${BLANKWEAVE_SYSTEM_ROOT:-}
[[ $# -eq 0 && ( -z $system_root || $system_root == /* ) ]] || {
    printf 'Usage: configure-session-profile.sh (BLANKWEAVE_SYSTEM_ROOT must be absolute)\n' >&2
    exit 1
}
profile_dir=$system_root/etc/profile.d
mkdir -p "$profile_dir"
staged=$(mktemp "$profile_dir/.blankweave-session.XXXXXX")
trap 'rm -f -- "$staged"' EXIT
cat > "$staged" <<'PROFILE'
# Blankweave: other accounts without a managed profile are unaffected.
if [ -n "${HOME:-}" ] && [ -r "$HOME/.local/share/blankweave/shell/profile" ]; then
    # /etc/profile runs before the user's own startup files. A zsh login whose
    # .zprofile already sources the managed profile keeps starting the session
    # from there, after the user's exports, so those still reach the desktop.
    if [ -n "${ZSH_VERSION:-}" ] &&
        grep -qs 'blankweave/shell/profile' "${ZDOTDIR:-$HOME}/.zprofile"; then
        :
    else
        . "$HOME/.local/share/blankweave/shell/profile"
    fi
fi
PROFILE
chmod 0644 "$staged"
# The installer runs as root, so both the staged file and destination are root-owned.
if [[ -f $profile_dir/blankweave-session.sh && ! -L $profile_dir/blankweave-session.sh ]] \
    && [[ $(stat -c %u:%g:%a "$profile_dir/blankweave-session.sh") == "$EUID:$(id -g):644" ]] \
    && cmp -s "$staged" "$profile_dir/blankweave-session.sh"; then
    exit 0
fi
mv -f -- "$staged" "$profile_dir/blankweave-session.sh"
