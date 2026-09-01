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
printf 'fixture apply\n'
[[ "${BLANKWEAVE_FIXTURE_FAIL:-}" != 1 ]]
EOF
cat > "$fixture/bin/blankweave" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$fixture/scripts/doctor.sh" <<'EOF'
#!/usr/bin/env bash
printf 'fixture doctor\n'
EOF
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

check_output=$(command_update --check)
grep -Fq '1 update(s) available' <<< "$check_output"
grep -Fq '0.1.0' <<< "$check_output"
grep -Fq '0.2.0' <<< "$check_output"
[[ $(git -C "$fixture" rev-parse HEAD) == "$previous" ]]

dry_output=$(command_update --dry-run)
grep -Fq 'Install plan: fixture' <<< "$dry_output"
grep -Fq 'Dry run complete' <<< "$dry_output"
[[ $(git -C "$fixture" rev-parse HEAD) == "$previous" ]]

apply_output=$(command_update)
grep -Fq 'Blankweave v0.2.0 update complete' <<< "$apply_output"
[[ $(git -C "$fixture" rev-parse HEAD) == "$target" ]]
[[ $(recovery_read status) == complete ]]

rollback_output=$(command_rollback)
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

printf 'Update recovery tests passed.\n'
