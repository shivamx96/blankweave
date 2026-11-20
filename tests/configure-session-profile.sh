#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
export BLANKWEAVE_SYSTEM_ROOT=$test_root/root
"$repository/scripts/configure-session-profile.sh"
profile=$BLANKWEAVE_SYSTEM_ROOT/etc/profile.d/blankweave-session.sh
[[ $(stat -c %a "$profile") == 644 ]]
[[ $(stat -c %u "$profile") == "$EUID" ]]
inode=$(stat -c %i "$profile")
"$repository/scripts/configure-session-profile.sh"
[[ $(stat -c %i "$profile") == "$inode" ]]
# shellcheck disable=SC2016
grep -Fq '. "$HOME/.local/share/blankweave/shell/profile"' "$profile"
chmod 0600 "$profile"
"$repository/scripts/configure-session-profile.sh"
[[ $(stat -c %a "$profile") == 644 ]]
printf 'broken hook\n' > "$profile"
"$repository/scripts/configure-session-profile.sh"
sh -n "$profile"
mkdir -p "$test_root/home/.local/share/blankweave/shell" "$test_root/other"
printf 'printf "managed profile\\n"\n' > "$test_root/home/.local/share/blankweave/shell/profile"
[[ $(HOME="$test_root/home" sh -c '. "$1"' sh "$profile") == 'managed profile' ]]
HOME="$test_root/other" sh -c '. "$1"' sh "$profile" > "$test_root/other-output" 2>&1
[[ ! -s $test_root/other-output ]]
# A zsh login whose .zprofile already sources the managed profile is left to
# it, so exports made there still precede the session start.
if command -v zsh >/dev/null 2>&1; then
    printf 'source %s/.local/share/blankweave/shell/profile\n' "$test_root/home" > "$test_root/home/.zprofile"
    # shellcheck disable=SC2016
    HOME="$test_root/home" zsh -f -c 'emulate sh -c ". \"$1\""' zsh "$profile" > "$test_root/zsh-output" 2>&1
    [[ ! -s $test_root/zsh-output ]]
    rm "$test_root/home/.zprofile"
    # shellcheck disable=SC2016
    [[ $(HOME="$test_root/home" zsh -f -c 'emulate sh -c ". \"$1\""' zsh "$profile") == 'managed profile' ]]
fi
if BLANKWEAVE_SYSTEM_ROOT=relative "$repository/scripts/configure-session-profile.sh" 2>/dev/null; then exit 1; fi
printf 'Session profile.d configuration tests passed.\n'
