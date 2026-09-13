#!/usr/bin/env bash

# Replace a managed code tree without ever leaving its destination path absent.
# The source is copied to a sibling first, then renameat2's atomic exchange puts
# the complete new tree in place. This matters for live file watchers such as
# Quickshell, which otherwise reload while shell.qml has been deleted.

blankweave_deploy_tree() (
    set -euo pipefail

    [[ $# -eq 2 ]] || {
        printf 'blankweave_deploy_tree requires source and destination paths\n' >&2
        return 2
    }

    local source=$1
    local destination=$2
    local parent=${destination%/*}
    local name=${destination##*/}
    local staged=

    [[ -d $source && ! -L $source ]] || {
        printf 'Deployment source is not a directory: %s\n' "$source" >&2
        return 1
    }
    [[ -n $parent && -n $name && $destination != "$parent" ]] || {
        printf 'Deployment destination is invalid: %s\n' "$destination" >&2
        return 1
    }

    # shellcheck disable=SC2329 # Invoked by the EXIT trap.
    cleanup_deploy_tree() {
        [[ -z $staged || ! -e $staged ]] || rm -rf -- "$staged"
    }
    trap cleanup_deploy_tree EXIT

    mkdir -p -- "$parent"
    staged=$(mktemp -d "$parent/.$name.deploy.XXXXXX")
    cp -a -- "$source/." "$staged/"

    if [[ -e $destination || -L $destination ]]; then
        # Both paths share a parent filesystem. --no-copy ensures this remains
        # one atomic rename operation instead of degrading to copy-and-delete.
        mv --exchange --no-copy -T -- "$staged" "$destination"
        rm -rf -- "$staged"
    else
        mv --no-copy -T -- "$staged" "$destination"
    fi
    staged=
)
