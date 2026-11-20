#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
sandbox=$(mktemp -d)
trap 'rm -rf -- "$sandbox"' EXIT
mkdir -p "$sandbox/runtime/gcr"
python3 - "$sandbox/runtime/gcr/ssh" <<'PYSOCKET'
import socket, sys
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])
s.close()
PYSOCKET
# Only the profile's environment prefix is evaluated, with session startup gated.
for shell in sh bash zsh; do
    for mode in unset custom empty; do
        # shellcheck disable=SC2016
        env -u SSH_AUTH_SOCK HOME="$sandbox" XDG_RUNTIME_DIR="$sandbox/runtime" \
            "$shell" -c '
                case "$2" in custom) SSH_AUTH_SOCK=/personal/agent;; empty) SSH_AUTH_SOCK=;; esac
                blankweave_profile_sourced=1
                . "$1/defaults/shell/profile"
                case "$2" in
                    unset) test "$SSH_AUTH_SOCK" = "$XDG_RUNTIME_DIR/gcr/ssh";;
                    custom) test "$SSH_AUTH_SOCK" = /personal/agent;;
                    empty) test -z "$SSH_AUTH_SOCK";;
                esac
            ' fixture "$repository" "$mode"
    done
done
source "$repository/scripts/installer-choices.sh"
CHOICES_DIR=$sandbox/choices
mkdir -p "$CHOICES_DIR"
calls=0
fixture_enable() { calls=$((calls + 1)); }
installer_seed ssh-agent fixture_enable
installer_seed ssh-agent fixture_enable
[[ $calls == 1 && -f $CHOICES_DIR/ssh-agent ]]
grep -Fq 'installer_seed ssh-agent installer_seed_ssh_agent' "$repository/install.sh"
grep -Fq 'systemctl --user enable gcr-ssh-agent.socket' "$repository/scripts/installer-choices.sh"
printf 'SSH agent seed-once and profile environment tests passed.\n'
