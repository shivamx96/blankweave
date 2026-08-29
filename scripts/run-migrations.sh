#!/usr/bin/env bash

set -euo pipefail

repository=${1:?repository path is required}
state_home=${XDG_STATE_HOME:-$HOME/.local/state}
state_dir=$state_home/hyprarch
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
write_state_file "$state_dir/installed-revision" "$(git -C "$repository" rev-parse HEAD)"
