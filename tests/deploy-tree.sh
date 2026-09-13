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

# shellcheck source=scripts/deploy-tree.sh
source "$repository/scripts/deploy-tree.sh"

# shellcheck disable=SC2016 # The installer variables are matched literally.
grep -Fq 'blankweave_deploy_tree "$REPO_DIR/defaults/quickshell" "$DOTS_DIR/quickshell"' \
    "$repository/install.sh"
# shellcheck disable=SC2016 # The installer variables are matched literally.
if grep -Fq 'rm -rf "$DOTS_DIR/quickshell"' "$repository/install.sh"; then
    printf 'The installer still deletes the live Quickshell tree.\n' >&2
    exit 1
fi

source_tree=$test_root/source
destination=$test_root/live/quickshell
mkdir -p "$source_tree/Modules" "$destination/Old"
printf 'new shell\n' > "$source_tree/shell.qml"
printf 'new module\n' > "$source_tree/Modules/Panel.qml"
printf 'old shell\n' > "$destination/shell.qml"
printf 'stale module\n' > "$destination/Old/Stale.qml"

blankweave_deploy_tree "$source_tree" "$destination"

diff -ru "$source_tree" "$destination"
[[ ! -e $destination/Old/Stale.qml ]]
if find "$test_root/live" -maxdepth 1 -name '.quickshell.deploy.*' | grep -q .; then
    printf 'Deployment left a staged directory behind.\n' >&2
    exit 1
fi

# A missing destination is installed as one complete tree as well.
second_destination=$test_root/second/quickshell
blankweave_deploy_tree "$source_tree" "$second_destination"
diff -ru "$source_tree" "$second_destination"

# Invalid input fails without touching the live destination.
if blankweave_deploy_tree "$test_root/missing" "$destination" 2>/dev/null; then
    printf 'A missing source unexpectedly deployed.\n' >&2
    exit 1
fi
grep -Fxq 'new shell' "$destination/shell.qml"

printf 'Atomic tree deployment tests passed.\n'
