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

isolated_bin=$test_root/isolated-bin
mkdir -p "$isolated_bin"
ln -s "$(command -v jq)" "$isolated_bin/jq"

repos_payload=$(PATH="$isolated_bin" /usr/bin/bash \
    "$repository/defaults/shell/git-repos.sh" "$test_root/missing-projects")
[[ $(jq -r '.ideAvailable' <<< "$repos_payload") == false ]]

ln -s /usr/bin/true "$isolated_bin/idea"
repos_payload=$(PATH="$isolated_bin" /usr/bin/bash \
    "$repository/defaults/shell/git-repos.sh" "$test_root/missing-projects")
[[ $(jq -r '.ideAvailable' <<< "$repos_payload") == true ]]

fake_bin=$test_root/fake-bin
mkdir -p "$fake_bin"
ln -s "$repository/tests/fixtures/fake-gh.sh" "$fake_bin/gh"

for login in first-user second-user; do
    prs_payload=$(FAKE_GH_LOGIN="$login" \
        XDG_CACHE_HOME="$test_root/cache" \
        PATH="$fake_bin:$PATH" \
        "$repository/defaults/shell/git-prs.sh" --max-age 0)
    [[ $(jq -r '.login' <<< "$prs_payload") == "$login" ]]
    [[ $(jq -r '.authenticated' <<< "$prs_payload") == true ]]
done

cache_count=$(find "$test_root/cache/hyprarch" -type f -name 'git-prs-*.json' | wc -l)
[[ "$cache_count" -eq 2 ]]

printf 'Git widget script tests passed.\n'
