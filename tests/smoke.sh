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

repository_version=$(head -n 1 "$repository/VERSION")
repository_release=unreleased
if release=$("$repository/scripts/verify-release.sh" "$repository" HEAD 2>/dev/null); then
    repository_release=$release
fi

version_output=$(
    HOME="$test_root/home" \
        XDG_STATE_HOME="$test_root/state" \
        "$repository/bin/blankweave" version
)
grep -Fxq "blankweave $repository_version ($repository_release)" <<< "$version_output"
grep -Fq 'installed:  not-recorded / not-recorded (not-recorded)' <<< "$version_output"
grep -Fq 'rollback floor: 0.1.0' <<< "$version_output"

grep -Fq 'Usage: blankweave doctor [--full|--normal] [--report]' <<< "$(
    HOME="$test_root/home" \
        XDG_STATE_HOME="$test_root/state" \
        "$repository/bin/blankweave" doctor --help
)"

grep -Fq 'Usage: blankweave update [--check|--dry-run]' <<< "$(
    HOME="$test_root/home" \
        XDG_STATE_HOME="$test_root/state" \
        "$repository/bin/blankweave" update --help
)"
grep -Fq 'Usage: blankweave rollback' <<< "$(
    HOME="$test_root/home" \
        XDG_STATE_HOME="$test_root/state" \
        "$repository/bin/blankweave" rollback --help
)"
grep -Fq 'Usage: blankweave setup [--non-interactive]' <<< "$(
    HOME="$test_root/home" \
        XDG_STATE_HOME="$test_root/state" \
        "$repository/bin/blankweave" setup --help
)"

# The old command name hands over to the new one so an installed
# `hyprarch update` can exec the fetched revision.
grep -Fxq "blankweave $repository_version ($repository_release)" \
    <<< "$(HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" "$repository/bin/hyprarch" version)"

if "$repository/bin/blankweave" unknown > /dev/null 2>&1; then
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
mkdir -p "$migration_repository/scripts"
cp -R "$repository/migrations" "$migration_repository/"
cp "$repository/scripts/release-version.sh" "$migration_repository/scripts/"
cp "$repository/VERSION" "$repository/MIN_ROLLBACK_VERSION" "$migration_repository/"
git -C "$migration_repository" init --quiet
git -C "$migration_repository" config user.name 'Blankweave CI'
git -C "$migration_repository" config user.email 'ci@blankweave.invalid'
git -C "$migration_repository" add .
git -C "$migration_repository" commit --quiet -m 'test fixture'

# The git-widget cache migration predates the rename and clears the old
# cache directory; a fresh install finds nothing there, an upgraded one has
# already had it relocated, so the fixture uses the path it actually clears.
mkdir -p "$test_root/cache/hyprarch"
touch "$test_root/cache/hyprarch/git-prs.json"
touch "$test_root/cache/hyprarch/git-login"

HOME="$test_root/home" \
    XDG_CACHE_HOME="$test_root/cache" \
    XDG_STATE_HOME="$test_root/state" \
    "$repository/scripts/run-migrations.sh" "$migration_repository"

state_dir=$test_root/state/blankweave
[[ $(< "$state_dir/repository") == "$migration_repository" ]]
[[ $(< "$state_dir/installed-revision") == "$(git -C "$migration_repository" rev-parse HEAD)" ]]
[[ $(< "$state_dir/installed-version") == "$(< "$repository/VERSION")" ]]
[[ $(< "$state_dir/installed-release-tag") == unreleased ]]
[[ -f "$state_dir/migrations-applied" ]]
[[ ! -e "$test_root/cache/hyprarch/git-prs.json" ]]
[[ ! -e "$test_root/cache/hyprarch/git-login" ]]

printf 'CLI and migration smoke tests passed.\n'
