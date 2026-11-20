#!/usr/bin/env bash
# Never source the host's login files or contact its session manager.
# Shell snippets and displayed recovery commands expand in the child/recovery shell.
# shellcheck disable=SC2016
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin"
cat > "$test_root/bin/uwsm" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$FIXTURE/commands"
case "$*" in
    'check may-start')
        # Even a noisy refusal must not break the graphical handoff.
        if [ "$MAY_START" != 0 ]; then echo refused; echo refused >&2; fi
        exit "$MAY_START" ;;
    'start -e -D Hyprland hyprland.desktop')
        [ "$MOZ_ENABLE_WAYLAND:$QT_QPA_PLATFORM:$SDL_VIDEODRIVER:$EDITOR:$TERMINAL" = '1:wayland:wayland:nano:ghostty' ] || exit 99
        printf 'controller preamble\n'
        printf 'controller stderr\n' >&2
        exit "$START_STATUS" ;;
    *) exit 98 ;;
esac
STUB
cat > "$test_root/bin/date" <<'STUB'
#!/bin/sh
[ "$*" = +%s ] || exit 97
if [ -e "$FIXTURE/clock" ]; then
    printf '%s\n' "$((1000 + DURATION))"
else
    : > "$FIXTURE/clock"
    printf '1000\n'
fi
STUB
cat > "$test_root/bin/systemctl" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$FIXTURE/queries"
case "$*" in
    '--user show wayland-wm@hyprland.desktop.service --property=ActiveEnterTimestampMonotonic --value')
        case "$READINESS" in
            ready|failed) printf '999999999999999\n' ;;
            stale) printf '1\n' ;;
            missing) exit 1 ;;
            *) printf '0\n' ;;
        esac ;;
    '--user show wayland-wm@hyprland.desktop.service --property=Result --value')
        if [ "$READINESS" = failed ]; then printf 'exit-code\n'; else printf 'success\n'; fi ;;
    *) exit 96 ;;
esac
STUB
chmod +x "$test_root/bin/"*

new_fixture() {
    fixture="$test_root/$shell_name-$1"
    mkdir -p "$fixture/home" "$fixture/state/blankweave" "$fixture/runtime"
    : > "$fixture/commands"
}
run_profile() {
    env -i HOME="$fixture/home" PATH="$test_root/bin:/usr/bin:/bin" \
        XDG_STATE_HOME="$fixture/state" XDG_RUNTIME_DIR="$fixture/runtime" \
        PROFILE="$repository/defaults/shell/profile" FIXTURE="$fixture" \
        MAY_START="$1" START_STATUS="$2" DURATION="$3" READINESS="${4:-none}" \
        "$shell_path" -f -c '. "$PROFILE"; . "$PROFILE"; printf "shell survived\n"' \
        > "$fixture/output" 2> "$fixture/errors"
    [[ ! -s "$fixture/errors" ]]
}
assert_failure() {
    grep -Fq 'Blankweave: the desktop could not start.' "$fixture/output"
    grep -Fxq 'shell survived' "$fixture/output"
    grep -Fxq 'controller preamble' "$fixture/output"
    grep -Fxq 'controller stderr' "$fixture/output"
    grep -Fxq 'journalctl --user -b -p warning' "$fixture/output"
    grep -Fxq 'blankweave doctor' "$fixture/output"
    grep -Fxq 'blankweave rollback' "$fixture/output"
    grep -Fxq 'start_desktop' "$fixture/output"
    grep -Fq 'Ctrl+Alt+F2' "$fixture/output"
    [[ $(head -c 16 "$fixture/output" | od -An -tx1 | tr -d ' \n') == 1b5b3f3235681b5b324a1b5b48426c61 ]]
    compgen -G "$fixture/runtime/blankweave-session-failed-*" >/dev/null
    [[ $(stat -c %a "$fixture/state/blankweave/uwsm-session.log") == 600 ]]
}
for shell_name in sh bash zsh; do
    shell_path=$(command -v "$shell_name") || { printf 'Missing required test shell: %s\n' "$shell_name" >&2; exit 1; }
    new_fixture healthy
    printf 'previous log\n' > "$fixture/state/blankweave/uwsm-session.log"
    printf 'older log\n' > "$fixture/state/blankweave/uwsm-session.log.1"
    run_profile 0 0 180
    [[ ! -s "$fixture/output" ]]
    [[ ! -e "$fixture/queries" ]]
    [[ $(cat "$fixture/state/blankweave/uwsm-session.log.1") == 'previous log' ]]
    [[ $(cat "$fixture/state/blankweave/uwsm-session.log") == $'controller preamble\ncontroller stderr' ]]
    if compgen -G "$fixture/runtime/blankweave-session-failed-*" >/dev/null; then
        printf 'Healthy session left a failure marker.\n' >&2
        exit 1
    fi
    # A fresh login after healthy logout must start again.
    rm "$fixture/clock"
    run_profile 0 0 180
    [[ $(wc -l < "$fixture/commands") == 4 && ! -s "$fixture/output" ]]

    # A session that ran and then ended non-zero (a late crash, or a
    # controller that reports the stop signal) restarts like a clean one.
    new_fixture late-nonzero
    run_profile 0 1 180
    [[ ! -s "$fixture/output" && ! -e "$fixture/queries" ]]
    if compgen -G "$fixture/runtime/blankweave-session-failed-*" >/dev/null; then
        printf 'A late non-zero exit left a failure marker.\n' >&2
        exit 1
    fi

    new_fixture nonzero
    run_profile 0 1 30
    assert_failure
    # The printed retry command clears the guard and logs in again.
    env -i HOME="$fixture/home" PATH="$test_root/bin:/usr/bin:/bin" \
        XDG_STATE_HOME="$fixture/state" XDG_RUNTIME_DIR="$fixture/runtime" \
        PROFILE="$repository/defaults/shell/profile" FIXTURE="$fixture" SHELL=/bin/true \
        "$shell_path" -f -c '. "$PROFILE"; start_desktop' > "$fixture/retry" 2>&1
    if compgen -G "$fixture/runtime/blankweave-session-failed-*" >/dev/null; then
        printf 'start_desktop left the failure marker.\n' >&2
        exit 1
    fi
    [[ ! -s "$fixture/retry" ]]
    : > "$fixture/commands"
    new_fixture nonzero-again
    run_profile 0 1 30
    assert_failure
    # A later tty1 login explains the missing desktop; other consoles stay quiet.
    env -i HOME="$fixture/home" PATH="$test_root/bin:/usr/bin:/bin" XDG_VTNR=1 \
        XDG_STATE_HOME="$fixture/state" XDG_RUNTIME_DIR="$fixture/runtime" \
        PROFILE="$repository/defaults/shell/profile" FIXTURE="$fixture" \
        "$shell_path" -f -c '. "$PROFILE"' > "$fixture/output" 2> "$fixture/errors"
    grep -Fq 'Run start_desktop to try again' "$fixture/output"
    [[ ! -s "$fixture/errors" ]]
    # A completely fresh shell/environment must honor the on-disk guard.
    run_profile 0 0 180
    [[ $(cat "$fixture/output") == 'shell survived' ]]
    [[ $(wc -l < "$fixture/commands") == 2 ]]
    # Also model exec $SHELL / a nested login shell with the exported guard.
    env -i HOME="$fixture/home" PATH="$test_root/bin:/usr/bin:/bin" \
        XDG_STATE_HOME="$fixture/state" XDG_RUNTIME_DIR="$fixture/runtime" \
        PROFILE="$repository/defaults/shell/profile" FIXTURE="$fixture" \
        BLANKWEAVE_SESSION_FAILED=1 "$shell_path" -f -c \
        '. "$PROFILE"; exec "$1" -f -c '\''. "$PROFILE"; echo shell survived'\''' shell "$shell_path" \
        > "$fixture/output" 2> "$fixture/errors"
    [[ $(cat "$fixture/output") == 'shell survived' && ! -s "$fixture/errors" ]]
    [[ $(wc -l < "$fixture/commands") == 2 ]]

    for readiness in none stale missing failed; do
        new_fixture "short-$readiness"
        run_profile 0 0 2 "$readiness"
        assert_failure
    done
    new_fixture short-nonzero
    run_profile 0 7 2 ready
    assert_failure
    new_fixture deliberate-quick-stop
    run_profile 0 0 2 ready
    [[ ! -s "$fixture/output" ]]
    if compgen -G "$fixture/runtime/blankweave-session-failed-*" >/dev/null; then
        printf 'Healthy session left a failure marker.\n' >&2
        exit 1
    fi
    new_fixture ten-second-boundary
    run_profile 0 0 10
    [[ ! -s "$fixture/output" && ! -e "$fixture/queries" ]]
    new_fixture refused
    run_profile 1 0 180
    [[ $(cat "$fixture/output") == 'shell survived' ]]
    [[ $(cat "$fixture/commands") == 'check may-start' ]]
    [[ ! -e "$fixture/state/blankweave/uwsm-session.log" ]]
    printf 'Session profile tests passed under %s.\n' "$shell_name"
done

# Use a real bash login shell with host startup files disabled. Explicitly
# source the sandboxed global hook, as /etc/profile does on Arch.
BLANKWEAVE_SYSTEM_ROOT="$test_root/system" "$repository/scripts/configure-session-profile.sh"
hook=$test_root/system/etc/profile.d/blankweave-session.sh
shell_name=bash
shell_path=$(command -v bash)
new_fixture bash-login
mkdir -p "$fixture/home/.local/share/blankweave/shell"
cp "$repository/defaults/shell/profile" "$fixture/home/.local/share/blankweave/shell/profile"
env -i HOME="$fixture/home" PATH="$test_root/bin:/usr/bin:/bin" \
    XDG_STATE_HOME="$fixture/state" XDG_RUNTIME_DIR="$fixture/runtime" \
    FIXTURE="$fixture" MAY_START=1 START_STATUS=0 DURATION=180 \
    bash --noprofile --norc --login -c '. "$1"; . "$1"; type start_desktop >/dev/null' bash "$hook" \
    > "$fixture/output" 2> "$fixture/errors"
[[ ! -s $fixture/output && ! -s $fixture/errors ]]
[[ $(cat "$fixture/commands") == 'check may-start' ]]
new_fixture other-account
env -i HOME="$fixture/home" PATH="$test_root/bin:/usr/bin:/bin" \
    bash --noprofile --norc --login -c '. "$1"; . "$1"; test -z "${blankweave_profile_sourced:-}"; ! type start_desktop >/dev/null 2>&1' bash "$hook" \
    > "$fixture/output" 2> "$fixture/errors"
[[ ! -s $fixture/output && ! -s $fixture/errors && ! -s $fixture/commands ]]
printf 'Bash login hook and other-account isolation tests passed.\n'

# Arch's /etc/zsh/zprofile uses emulate sh -c to source /etc/profile.
# Reproduce that shell mode without reading any host startup file.
new_fixture zsh-global-hook
mkdir -p "$fixture/home/.local/share/blankweave/shell"
cp "$repository/defaults/shell/profile" "$fixture/home/.local/share/blankweave/shell/profile"
env -i HOME="$fixture/home" PATH="$test_root/bin:/usr/bin:/bin" \
    XDG_STATE_HOME="$fixture/state" XDG_RUNTIME_DIR="$fixture/runtime" \
    FIXTURE="$fixture" MAY_START=1 START_STATUS=0 DURATION=180 HOOK="$hook" \
    zsh -f -c 'emulate sh -c "$1"; . "$HOOK"; type start_desktop >/dev/null' zsh '. "$HOOK"' \
    > "$fixture/output" 2> "$fixture/errors"
[[ ! -s $fixture/output && ! -s $fixture/errors ]]
[[ $(cat "$fixture/commands") == 'check may-start' ]]
printf 'Arch zsh profile emulation test passed.\n'

for profile_shell in sh bash zsh; do
    command -v "$profile_shell" >/dev/null || continue
    new_fixture "environment-$profile_shell"
    env -i HOME="$fixture/home" PATH="$test_root/bin:/usr/bin:/bin" FIXTURE="$fixture" MAY_START=1 \
        "$profile_shell" -c '. "$1"; test "$EDITOR:$VISUAL" = nano:nano; test "$BROWSER" = "\"$HOME/.local/share/blankweave/shell/open-default.sh\" browser"' shell "$repository/defaults/shell/profile"
    env -i HOME="$fixture/home" PATH="$test_root/bin:/usr/bin:/bin" FIXTURE="$fixture" MAY_START=1 EDITOR=custom VISUAL=gui BROWSER=personal \
        "$profile_shell" -c '. "$1"; test "$EDITOR:$VISUAL:$BROWSER" = custom:gui:personal' shell "$repository/defaults/shell/profile"
    env -i HOME="$fixture/home" PATH="$test_root/bin:/usr/bin:/bin" FIXTURE="$fixture" MAY_START=1 EDITOR=custom \
        "$profile_shell" -c '. "$1"; test "$VISUAL" = custom' shell "$repository/defaults/shell/profile"
done
printf 'Editor, visual editor and browser environment tests passed.\n'
