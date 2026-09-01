#!/usr/bin/env bash

set -euo pipefail

repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)

cleanup() {
    if [[ -n $test_root && -d $test_root ]]; then
        rm -rf -- "$test_root"
    fi
}
trap cleanup EXIT HUP INT TERM

# shellcheck source=scripts/release-version.sh
source "$repository/scripts/release-version.sh"

fixture=$test_root/repository
git -C "$test_root" init --quiet --initial-branch=main repository
git -C "$fixture" config user.name 'Blankweave CI'
git -C "$fixture" config user.email 'ci@blankweave.invalid'
printf '1.2.3\n' > "$fixture/VERSION"
printf '1.0.0\n' > "$fixture/MIN_ROLLBACK_VERSION"
git -C "$fixture" add .
git -C "$fixture" commit --quiet -m 'release fixture'
revision=$(git -C "$fixture" rev-parse HEAD)

[[ $(blankweave_release_version_at "$fixture" "$revision") == 1.2.3 ]]
[[ $(blankweave_release_floor_at "$fixture" "$revision") == 1.0.0 ]]
if blankweave_release_tag_at "$fixture" "$revision" > /dev/null 2>&1; then
    printf 'An untagged commit unexpectedly passed release validation.\n' >&2
    exit 1
fi

git -C "$fixture" tag v1.2.3
if blankweave_release_tag_at "$fixture" "$revision" > /dev/null 2>&1; then
    printf 'A lightweight tag unexpectedly passed release validation.\n' >&2
    exit 1
fi
git -C "$fixture" tag -d v1.2.3 > /dev/null
git -C "$fixture" tag -a v1.2.3 -m 'Blankweave 1.2.3'
[[ $(blankweave_release_tag_at "$fixture" "$revision") == v1.2.3 ]]
[[ $("$repository/scripts/verify-release.sh" "$fixture" "$revision") == v1.2.3 ]]

blankweave_release_version_greater 1.2.3 1.2.2
blankweave_release_version_greater 1.10.0 1.9.9
blankweave_release_version_greater_or_equal 1.2.3 1.2.3
if blankweave_release_version_greater 1.2.3 1.2.3 \
    || blankweave_release_version_greater_or_equal 1.2.2 1.2.3 \
    || blankweave_release_version_valid 01.2.3; then
    printf 'Semantic release comparison or validation produced an invalid result.\n' >&2
    exit 1
fi

printf '1.2.4-dev\n' > "$fixture/VERSION"
git -C "$fixture" add VERSION
git -C "$fixture" commit --quiet -m 'invalid development version'
invalid_revision=$(git -C "$fixture" rev-parse HEAD)
if blankweave_release_version_at "$fixture" "$invalid_revision" > /dev/null 2>&1; then
    printf 'A non-stable VERSION unexpectedly passed release validation.\n' >&2
    exit 1
fi

printf 'Release version tests passed.\n'
