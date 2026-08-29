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

version_output=$(
    HOME="$test_root/home" \
        XDG_STATE_HOME="$test_root/state" \
        "$repository/bin/hyprarch" version
)
grep -Fxq "hyprarch $(head -n 1 "$repository/VERSION")" <<< "$version_output"
grep -Fq 'installed:  not-recorded' <<< "$version_output"

if "$repository/bin/hyprarch" unknown > /dev/null 2>&1; then
    printf 'Unknown CLI commands must fail.\n' >&2
    exit 1
else
    exit_code=$?
    [[ "$exit_code" -eq 2 ]] || {
        printf 'Unknown CLI command returned %s, expected 2.\n' "$exit_code" >&2
        exit 1
    }
fi

migration_repository=$test_root/repository
mkdir -p "$migration_repository"
cp -R "$repository/migrations" "$migration_repository/"
git -C "$migration_repository" init --quiet
git -C "$migration_repository" config user.name 'Hyprarch CI'
git -C "$migration_repository" config user.email 'ci@hyprarch.invalid'
git -C "$migration_repository" add migrations
git -C "$migration_repository" commit --quiet -m 'test fixture'

XDG_STATE_HOME="$test_root/state" \
    "$repository/scripts/run-migrations.sh" "$migration_repository"

state_dir=$test_root/state/hyprarch
[[ $(< "$state_dir/repository") == "$migration_repository" ]]
[[ $(< "$state_dir/installed-revision") == "$(git -C "$migration_repository" rev-parse HEAD)" ]]
[[ -f "$state_dir/migrations-applied" ]]

printf 'CLI and migration smoke tests passed.\n'
