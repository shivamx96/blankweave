#!/usr/bin/env bash

set -euo pipefail

repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)

cleanup() {
    if [[ -n "$test_root" && -d "$test_root" ]]; then
        rm -rf -- "$test_root"
    fi
}
trap cleanup EXIT HUP INT TERM

export HOME=$test_root/home
export XDG_STATE_HOME=$test_root/state
export XDG_RUNTIME_DIR=$test_root/runtime
mkdir -p "$XDG_RUNTIME_DIR"
mkdir -p "$HOME"

# Sourcing exposes the recovery primitives without running the CLI dispatcher.
# shellcheck source=bin/blankweave
source "$repository/bin/blankweave"
# shellcheck source=scripts/release-version.sh
source "$repository/scripts/release-version.sh"

fixture=$test_root/repository
git -C "$test_root" init --quiet --initial-branch=main repository
git -C "$fixture" config user.name 'Blankweave CI'
git -C "$fixture" config user.email 'ci@blankweave.invalid'
mkdir -p "$fixture/bin" "$fixture/scripts"
cat > "$fixture/install.sh" <<'EOF'
#!/usr/bin/env bash
printf 'fixture apply policy=%s\n' "${BLANKWEAVE_PACKAGE_POLICY:-upgrade}"
[[ "${BLANKWEAVE_FIXTURE_FAIL:-}" != 1 ]]
EOF
cat > "$fixture/bin/blankweave" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$fixture/scripts/doctor.sh" <<'EOF'
#!/usr/bin/env bash
[[ ${2:-} == --normal && ${3:-} == --report ]]
# Use the production sign-in checks for update preflight and postflight.
# shellcheck disable=SC1090
source <(sed '/^main "\$@"$/d' "$BLANKWEAVE_FIXTURE_DOCTOR_SOURCE")
REPORT=true
check_console_session
check_keyring
(( FAILED == 0 ))
EOF
export BLANKWEAVE_FIXTURE_DOCTOR_SOURCE=$repository/scripts/doctor.sh
export BLANKWEAVE_SYSTEM_ROOT=$test_root/system-root
mkdir -p "$BLANKWEAVE_SYSTEM_ROOT/etc/blankweave"
printf 'no\n' > "$BLANKWEAVE_SYSTEM_ROOT/etc/blankweave/signin.conf"
cp "$repository/scripts/release-version.sh" "$fixture/scripts/release-version.sh"
chmod +x "$fixture/install.sh" "$fixture/bin/blankweave" "$fixture/scripts/doctor.sh"
printf '0.1.0\n' > "$fixture/VERSION"
printf '0.1.0\n' > "$fixture/MIN_ROLLBACK_VERSION"
printf 'old\n' > "$fixture/value"
git -C "$fixture" add .
git -C "$fixture" commit --quiet -m old
previous=$(git -C "$fixture" rev-parse HEAD)
git -C "$fixture" tag -a v0.1.0 -m 'Blankweave 0.1.0'
printf '0.2.0\n' > "$fixture/VERSION"
printf 'new\n' > "$fixture/value"
git -C "$fixture" commit --quiet -am new
target=$(git -C "$fixture" rev-parse HEAD)
git -C "$fixture" tag -a v0.2.0 -m 'Blankweave 0.2.0'

recovery_write "$previous" 0.1.0 "$target" 0.2.0 prepared 42
[[ $(recovery_read schema) == 1 ]]
[[ $(recovery_read previous_revision) == "$previous" ]]
[[ $(recovery_read previous_version) == 0.1.0 ]]
[[ $(recovery_read target_revision) == "$target" ]]
[[ $(recovery_read target_version) == 0.2.0 ]]
[[ $(recovery_read status) == prepared ]]
[[ $(recovery_read snapper_pre) == 42 ]]
[[ $(stat -c %a "$RECOVERY_DIR") == 700 ]]
[[ $(stat -c %a "$RECOVERY_STATE") == 600 ]]

recovery_update_status apply-failed
[[ $(recovery_read status) == apply-failed ]]
restore_checkout "$fixture" "$previous"
[[ $(git -C "$fixture" rev-parse HEAD) == "$previous" ]]
[[ $(< "$fixture/value") == old ]]

git -C "$fixture" reset --hard "$target" > /dev/null
printf 'dirty\n' > "$fixture/value"
if (restore_checkout "$fixture" "$previous") > /dev/null 2>&1; then
    printf 'Checkout recovery unexpectedly discarded a dirty worktree.\n' >&2
    exit 1
fi
git -C "$fixture" reset --hard "$target" > /dev/null

if (recovery_write invalid 0.1.0 "$target" 0.2.0 prepared) > /dev/null 2>&1; then
    printf 'Recovery state unexpectedly accepted an invalid revision.\n' >&2
    exit 1
fi
if (recovery_write "$previous" release "$target" 0.2.0 prepared) > /dev/null 2>&1; then
    printf 'Recovery state unexpectedly accepted an invalid release version.\n' >&2
    exit 1
fi
blankweave_release_version_greater 0.2.0 0.1.0
blankweave_release_version_greater_or_equal 0.1.0 0.1.0
if blankweave_release_version_greater 0.1.0 0.1.0 \
    || blankweave_release_version_greater_or_equal 0.1.0 0.2.0; then
    printf 'Semantic release comparison produced an invalid result.\n' >&2
    exit 1
fi

plan=$(validate_install_plan "$repository")
grep -Eq '^Install plan: capabilities=.* profiles=.* packages=[0-9]+ aur=[0-9]+ providers=[0-9]+$' <<< "$plan"

mkdir -p "$test_root/invalid-config/blankweave"
printf '%s\n' 'version=1' 'profiles=not-a-profile' \
    > "$test_root/invalid-config/blankweave/install.conf"
if (XDG_CONFIG_HOME="$test_root/invalid-config" validate_install_plan "$repository") > /dev/null 2>&1; then
    printf 'An invalid target install config unexpectedly passed preflight.\n' >&2
    exit 1
fi

if (
    sudo() {
        return 1
    }
    create_post_snapshot 42 "$target"
) > /dev/null 2>&1; then
    printf 'A failed Snapper post-snapshot unexpectedly passed.\n' >&2
    exit 1
fi

# Exercise the public update modes and rollback against a local remote. The
# target-plan and snapshot seams keep the fixture focused on Git/state safety.
origin=$test_root/origin.git
git init --bare --quiet "$origin"
git -C "$fixture" remote add origin "$origin"
printf 'unreleased\n' > "$fixture/value"
git -C "$fixture" commit --quiet -am 'unreleased main work'
main_tip=$(git -C "$fixture" rev-parse HEAD)
git -C "$fixture" push --quiet -u origin HEAD:main
git -C "$fixture" push --quiet --tags origin
git -C "$fixture" reset --hard "$previous" > /dev/null
git -C "$fixture" branch --set-upstream-to=origin/main main > /dev/null

EXPECTED_REMOTES=("$origin")
configured_repository() {
    printf '%s\n' "$fixture"
}
require_normal_user() {
    :
}
validate_target_plan() {
    printf 'Install plan: fixture\n'
}
create_pre_snapshot() {
    SNAPSHOT_NUMBER=
}
sudo() {
    :
}

# Never acquire a real host inhibitor or inspect host package state.
systemd-inhibit() {
    [[ $1 == --what=shutdown:sleep:idle && $2 == --who=Blankweave ]]
    shift 4
    "$@"
}
pacman() { printf 'linux 1 -> 2\nmesa 1 -> 2\nhyprland 1 -> 2\nquickshell 1 -> 2\n'; }
export -f systemd-inhibit
for flags in '--to v0.2.0 --reapply' '--to v99.0.0' '--to' '--to v0.1.0' '--check --dry-run'; do
    # Intentional word splitting exercises CLI argument combinations.
    # shellcheck disable=SC2086
    if (command_update $flags) > "$test_root/invalid-option" 2>&1; then exit 1; fi
done
check_output=$(command_update --check --to v0.2.0 --yes)
grep -Fq 'main has unreleased commits; the newest release is v0.2.0' <<< "$check_output"
grep -Fq '1 update(s) available' <<< "$check_output"
grep -Fq '0.1.0' <<< "$check_output"
grep -Fq '0.2.0' <<< "$check_output"
[[ $(git -C "$fixture" rev-parse HEAD) == "$previous" ]]

dry_output=$(command_update --dry-run --to v0.2.0 --yes)
grep -Fq 'Install plan: fixture' <<< "$dry_output"
grep -Fq 'Dry run complete' <<< "$dry_output"
[[ $(git -C "$fixture" rev-parse HEAD) == "$previous" ]]

apply_output=$(command_update --to v0.2.0 --yes)
grep -Fq 'Blankweave v0.2.0 update complete' <<< "$apply_output"
[[ $(git -C "$fixture" rev-parse HEAD) == "$target" ]]
[[ $(recovery_read status) == complete ]]
grep -Eq '^PASS +tty1 sign-in' "$RECOVERY_DIR/postflight-report.txt"
grep -Eq '^PASS +default keyring' "$RECOVERY_DIR/postflight-report.txt"

[[ $(git -C "$fixture" rev-parse origin/main) == "$main_tip" ]]
grep -Fq 'already up to date' <<< "$(command_update --check)"
if (command_update --to v0.1.0) > "$test_root/downgrade" 2>&1; then exit 1; fi
grep -Fq 'rollback' "$test_root/downgrade"
reapply_output=$(command_update --reapply --yes)
grep -Fq 'fixture apply policy=upgrade' <<< "$reapply_output"
[[ $(recovery_read previous_revision) == "$previous" ]]
grep -Fq '[KERNEL]' <<< "$reapply_output"
grep -Fq '[GPU/mesa]' <<< "$reapply_output"
grep -Fq '[HYPRLAND]' <<< "$reapply_output"
grep -Fq '[QUICKSHELL]' <<< "$reapply_output"
grep -Fq -- '--reapply' <<< "$(command_update)"

# A recovery release from before the package policy would upgrade the system:
# without a terminal that needs explicit consent, and nothing changes without it.
git() {
    if [[ " $* " == *' show '* && $* == *:install.sh ]]; then return 0; fi
    command git "$@"
}
if (command_rollback) < /dev/null > "$test_root/legacy-rollback.log" 2>&1; then
    printf 'Rollback to a legacy installer proceeded without consent.\n' >&2
    exit 1
fi
grep -Fq 'rerun with --allow-upgrade' "$test_root/legacy-rollback.log"
[[ $(command git -C "$fixture" rev-parse HEAD) == "$target" ]]
[[ $(recovery_read status) == complete ]]
unset -f git

rollback_output=$(command_rollback)
grep -Fq 'fixture apply policy=missing-only' <<< "$rollback_output"
grep -Fq 'Managed configuration is restored to 0.1.0' <<< "$rollback_output"
grep -Fq 'Arch packages and completed one-time migrations were not reversed.' <<< "$rollback_output"
[[ $(git -C "$fixture" rev-parse HEAD) == "$previous" ]]
[[ $(recovery_read status) == rolled-back ]]

if (BLANKWEAVE_FIXTURE_FAIL=1 command_update) > "$test_root/failed-update.log" 2>&1; then
    printf 'A failing installer unexpectedly produced a successful update.\n' >&2
    exit 1
fi
grep -Fq 'checkout restored' "$test_root/failed-update.log"
[[ $(git -C "$fixture" rev-parse HEAD) == "$previous" ]]
[[ $(recovery_read status) == apply-failed ]]

RECOVERY_DIR=$test_root/empty-recovery
RECOVERY_STATE=$RECOVERY_DIR/state
mkdir -p "$RECOVERY_DIR"
if (command_rollback) > "$test_root/empty-recovery.log" 2>&1; then
    printf 'Rollback unexpectedly accepted an empty recovery directory.\n' >&2
    exit 1
fi
grep -Fq 'no rollback point is recorded' "$test_root/empty-recovery.log"
grep -Fq 'The next tagged update will create one before applying changes' \
    "$test_root/empty-recovery.log"

# Missing inhibitor falls back to a direct apply with a useful warning.
(
    # Invoked indirectly by apply_repository.
    # shellcheck disable=SC2329
    command() {
        if [[ $1 == -v && $2 == systemd-inhibit ]]; then return 1; fi
        builtin command "$@"
    }
    apply_repository "$fixture"
) > "$test_root/no-inhibitor" 2>&1
grep -q 'systemd-inhibit unavailable' "$test_root/no-inhibitor"
grep -q 'fixture apply policy=upgrade' "$test_root/no-inhibitor"

# PTY confirmation is tested independently of Git: decline, accept, --yes.
export -f confirm_update
printf 'n\n' | script -qec 'bash -c "confirm_update false"' /dev/null > "$test_root/prompt" && exit 1
grep -q 'Apply this update?' "$test_root/prompt"
printf 'yes\n' | script -qec 'bash -c "confirm_update false"' /dev/null >/dev/null
script -qec 'bash -c "confirm_update true"' /dev/null > "$test_root/yes"
if grep -q 'Apply this update?' "$test_root/yes"; then exit 1; fi
confirm_update false </dev/null

# The modules directory and uname are the host-dependent seams for the restart
# marker; a container may have no /usr/lib/modules at all.
KERNEL_MODULES_DIR=$test_root/modules
mkdir -p "$KERNEL_MODULES_DIR/blankweave-fixture-kernel"
uname() { printf 'blankweave-fixture-missing-kernel\n'; }
export XDG_RUNTIME_DIR=$test_root/runtime
mkdir -p "$XDG_RUNTIME_DIR"
record_restart_required > "$test_root/restart"
grep -q 'Restart required' "$test_root/restart"
[[ -s $XDG_RUNTIME_DIR/blankweave/restart-required ]]
uname() { printf 'blankweave-fixture-kernel\n'; }
rm "$XDG_RUNTIME_DIR/blankweave/restart-required"
record_restart_required
[[ ! -e $XDG_RUNTIME_DIR/blankweave/restart-required ]]

# An explicit intermediate release remains selectable when the newest release
# would exclude the installed release from its rollback floor.
git -C "$fixture" reset --hard "$main_tip" >/dev/null
printf '0.3.0\n' > "$fixture/VERSION"
printf '0.3.0\n' > "$fixture/MIN_ROLLBACK_VERSION"
git -C "$fixture" commit --quiet -am 'newer release with raised floor'
git -C "$fixture" tag -a v0.3.0 -m release
git -C "$fixture" push --quiet origin main --tags
git -C "$fixture" reset --hard "$previous" >/dev/null
if (command_update --check) > "$test_root/floor-rejection" 2>&1; then exit 1; fi
grep -Fq 'target requires rollback floor 0.3.0' "$test_root/floor-rejection"
intermediate=$(command_update --check --to v0.2.0 --yes)
grep -Fq 'v0.2.0' <<< "$intermediate"
[[ $(git -C "$fixture" rev-parse HEAD) == "$previous" ]]
printf 'Update recovery tests passed.\n'
