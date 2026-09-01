#!/usr/bin/env bash

set -euo pipefail

repository=${1:?repository path is required}
state_home=${XDG_STATE_HOME:-$HOME/.local/state}
state_dir=$state_home/blankweave
ledger=$state_dir/migrations-applied
lock_file=$state_dir/migrations.lock

write_state_file() {
    local target="$1"
    local value="$2"
    local staged

    staged=$(mktemp "$state_dir/.state.XXXXXX")
    printf '%s\n' "$value" > "$staged"
    chmod 600 "$staged"
    mv -f "$staged" "$target"
}

mkdir -p "$state_dir"
chmod 700 "$state_dir"
touch "$ledger"
chmod 600 "$ledger"

exec 9> "$lock_file"
flock 9

shopt -s nullglob
migrations=("$repository"/migrations/*.sh)
shopt -u nullglob

for migration in "${migrations[@]}"; do
    migration_id=$(basename "$migration")
    if [[ ! "$migration_id" =~ ^[0-9]{8}-[a-z0-9][a-z0-9-]*\.sh$ ]]; then
        printf 'Invalid migration filename: %s\n' "$migration_id" >&2
        exit 1
    fi
    if grep -Fxq "$migration_id" "$ledger"; then
        continue
    fi

    printf 'Applying migration %s...\n' "$migration_id"
    "$migration"
    printf '%s\n' "$migration_id" >> "$ledger"
done

write_state_file "$state_dir/repository" "$repository"
installed_revision=$(git -C "$repository" rev-parse HEAD)
# shellcheck source=scripts/release-version.sh
source "$repository/scripts/release-version.sh"
installed_version=$(blankweave_release_version_at "$repository" "$installed_revision") || {
    printf 'Invalid Blankweave VERSION at %s\n' "${installed_revision:0:12}" >&2
    exit 1
}
installed_tag=$(blankweave_release_tag_at \
    "$repository" "$installed_revision" 2>/dev/null || printf 'unreleased\n')
write_state_file "$state_dir/installed-revision" "$installed_revision"
write_state_file "$state_dir/installed-version" "$installed_version"
write_state_file "$state_dir/installed-release-tag" "$installed_tag"
