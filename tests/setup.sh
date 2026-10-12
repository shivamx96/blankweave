#!/usr/bin/env bash

set -euo pipefail

repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
export BLANKWEAVE_SETUP_TEST_ALLOW_ROOT=1
export XDG_STATE_HOME=$test_root/state

cleanup() {
    if [[ -n $test_root && -d $test_root ]]; then
        rm -rf -- "$test_root"
    fi
}
trap cleanup EXIT HUP INT TERM

# shellcheck source=scripts/setup-config.sh
source "$repository/scripts/setup-config.sh"
# shellcheck source=scripts/installer-config.sh
source "$repository/scripts/installer-config.sh"

valid_config=$test_root/valid.conf
printf '%s\n' \
    'version=1' \
    'theme=moss' \
    'mode=light' \
    'git_identity=configure' \
    'git_name=Ada Lovelace' \
    'git_email=ada@example.com' \
    'ssh_key=generate' > "$valid_config"
setup_config_load "$valid_config"
[[ $SETUP_THEME == moss ]]
[[ $SETUP_MODE == light ]]
[[ $SETUP_GIT_IDENTITY == configure ]]
[[ $SETUP_GIT_NAME == 'Ada Lovelace' ]]
[[ $SETUP_GIT_EMAIL == ada@example.com ]]
[[ $SETUP_SSH_KEY == generate ]]

for invalid_config in \
    $'version=2\ntheme=moss\nmode=dark\ngit_identity=skip\ngit_name=\ngit_email=\nssh_key=skip' \
    $'version=1\ntheme=../../bad\nmode=dark\ngit_identity=skip\ngit_name=\ngit_email=\nssh_key=skip' \
    $'version=1\ntheme=moss\nmode=sepia\ngit_identity=skip\ngit_name=\ngit_email=\nssh_key=skip' \
    $'version=1\ntheme=moss\nmode=dark\ngit_identity=configure\ngit_name=\ngit_email=bad\nssh_key=skip' \
    $'version=1\ntheme=moss\nmode=dark\ngit_identity=skip\ngit_name=\ngit_email=\nssh_key=upload' \
    $'version=1\ntheme=moss\nmode=dark\ngit_identity=skip\ngit_name=\ngit_email=\nssh_key=skip\nfuture=true'; do
    printf '%s\n' "$invalid_config" > "$test_root/invalid.conf"
    if setup_config_load "$test_root/invalid.conf" 2>/dev/null; then
        printf 'Invalid setup config unexpectedly passed:\n%s\n' "$invalid_config" >&2
        exit 1
    fi
done

fake_apply=$test_root/fake-apply
# The fixture expands these variables in its own process.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf '\''%s\n'\'' "$1" "$BLANKWEAVE_SETUP_THEME" "$BLANKWEAVE_SETUP_MODE" > "$HOME/apply-called"' > "$fake_apply"
chmod +x "$fake_apply"

replay_home=$test_root/replay-home
replay_config=$replay_home/config/blankweave
mkdir -p "$replay_config"
printf '%s\n' 'version=1' 'profiles=desktop development' > "$replay_config/install.conf"
cp "$valid_config" "$replay_config/setup.conf"
chmod 600 "$replay_config/install.conf" "$replay_config/setup.conf"
install_before=$(sha256sum "$replay_config/install.conf")
setup_before=$(sha256sum "$replay_config/setup.conf")
HOME=$replay_home \
XDG_CONFIG_HOME=$replay_home/config \
BLANKWEAVE_SETUP_APPLY_COMMAND=$fake_apply \
    "$repository/scripts/setup.sh" --non-interactive > "$test_root/replay.out"
[[ -s $replay_home/apply-called ]]
mapfile -t replay_apply < "$replay_home/apply-called"
[[ ${replay_apply[1]} == moss ]]
[[ ${replay_apply[2]} == light ]]
[[ $(sha256sum "$replay_config/install.conf") == "$install_before" ]]
[[ $(sha256sum "$replay_config/setup.conf") == "$setup_before" ]]
grep -q 'Profiles:     desktop development' "$test_root/replay.out"
grep -q 'Git identity: Ada Lovelace <ada@example.com>' "$test_root/replay.out"

missing_home=$test_root/missing-home
mkdir -p "$missing_home"
if HOME=$missing_home XDG_CONFIG_HOME=$missing_home/config \
    "$repository/scripts/setup.sh" --non-interactive > /dev/null 2>&1; then
    printf 'Non-interactive setup unexpectedly accepted missing configs.\n' >&2
    exit 1
fi

# An interactive cancellation must happen before either config or theme state
# is written. `script` supplies the pseudo-terminal that setup intentionally
# requires for its confirmation prompts.
cancel_home=$test_root/cancel-home
mkdir -p "$cancel_home"
printf '\n\n\n\n\n\n\nn\nn\nn\n' | \
    HOME=$cancel_home \
    XDG_CONFIG_HOME=$cancel_home/config \
    BLANKWEAVE_SETUP_APPLY_COMMAND=$fake_apply \
    script -qec "'$repository/scripts/setup.sh'" /dev/null > /dev/null
[[ ! -e $cancel_home/config/blankweave/install.conf ]]
[[ ! -e $cancel_home/config/blankweave/setup.conf ]]
[[ ! -e $cancel_home/config/blankweave/theme.json ]]
[[ ! -e $cancel_home/apply-called ]]

guided_home=$test_root/guided-home
mkdir -p "$guided_home"
printf '\n\n\n\n\nmoss\nlight\ny\nAda Lovelace\nada@example.com\ny\ny\n' | \
    HOME=$guided_home \
    XDG_CONFIG_HOME=$guided_home/config \
    BLANKWEAVE_SETUP_APPLY_COMMAND=$fake_apply \
    script -qec "'$repository/scripts/setup.sh'" /dev/null > /dev/null
guided_config=$guided_home/config/blankweave
[[ -s $guided_home/apply-called ]]
[[ $(stat -c %a "$guided_config/install.conf") == 600 ]]
[[ $(stat -c %a "$guided_config/setup.conf") == 600 ]]
installer_config_load "$guided_config/install.conf" 'gpu-intel battery gaming'
setup_config_load "$guided_config/setup.conf"
[[ $SETUP_THEME == moss ]]
[[ $SETUP_MODE == light ]]
[[ $SETUP_GIT_IDENTITY == configure ]]
[[ $SETUP_GIT_NAME == 'Ada Lovelace' ]]
[[ $SETUP_GIT_EMAIL == ada@example.com ]]
[[ $SETUP_SSH_KEY == generate ]]
mapfile -t guided_apply < "$guided_home/apply-called"
[[ ${guided_apply[1]} == moss ]]
[[ ${guided_apply[2]} == light ]]

# The review can revisit a section without restarting or saving partial choices.
edit_home=$test_root/edit-home
mkdir -p "$edit_home"
printf '\n\n\n\n\nmoss\nlight\nn\nn\npackages\ntheme\nobsidian\ndark\ny\n' | \
    HOME=$edit_home \
    XDG_CONFIG_HOME=$edit_home/config \
    BLANKWEAVE_SETUP_APPLY_COMMAND=$fake_apply \
    script -qec "'$repository/scripts/setup.sh'" /dev/null > "$test_root/edit.out"
setup_config_load "$edit_home/config/blankweave/setup.conf"
[[ $SETUP_THEME == obsidian && $SETUP_MODE == dark ]]
mapfile -t edited_apply < "$edit_home/apply-called"
[[ ${edited_apply[1]} == obsidian && ${edited_apply[2]} == dark ]]
grep -q 'repository package targets:' "$test_root/edit.out"
grep -q 'aur package targets:' "$test_root/edit.out"
grep -q 'lmstudio-bin' "$test_root/edit.out"

# Failure output must survive, retain the exit status, and offer a retry using
# saved choices. Both stdout and stderr belong in a private log.
failure_apply=$test_root/failure-apply
printf '%s\n' '#!/usr/bin/env bash' \
    'echo "fixture installer output"' \
    'echo "fixture installer error" >&2' \
    'exit 23' > "$failure_apply"
chmod +x "$failure_apply"
failure_status=0
HOME=$replay_home XDG_CONFIG_HOME=$replay_home/config \
    XDG_STATE_HOME=$test_root/failure-state \
    BLANKWEAVE_SETUP_APPLY_COMMAND=$failure_apply \
    "$repository/scripts/setup.sh" --non-interactive > "$test_root/failure.out" 2>&1 \
    || failure_status=$?
[[ $failure_status == 23 ]]
failure_logs=("$test_root/failure-state/blankweave/setup/"*.log)
[[ ${#failure_logs[@]} == 1 && -f ${failure_logs[0]} ]]
[[ $(stat -c %a "${failure_logs[0]}") == 600 ]]
grep -q 'fixture installer output' "${failure_logs[0]}"
grep -q 'fixture installer error' "${failure_logs[0]}"
grep -q 'setup --non-interactive' "$test_root/failure.out"
grep -q 'Some changes may already be applied' "$test_root/failure.out"
[[ $(sha256sum "$replay_config/install.conf") == "$install_before" ]]
[[ $(sha256sum "$replay_config/setup.conf") == "$setup_before" ]]

printf 'Guided setup and setup config tests passed.\n'
