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

run_configure() {
    HOME="$1" XDG_DATA_HOME="$1/data" \
        "$repository/scripts/configure-default-keyring.sh"
}

# Fresh installs receive a passwordless default collection, and a repeated
# apply leaves both files unchanged.
fresh_home=$test_root/fresh
mkdir -p "$fresh_home"
run_configure "$fresh_home"

fresh_dir=$fresh_home/data/keyrings
[[ $(< "$fresh_dir/default") == Default_keyring ]]
grep -Fxq '[keyring]' "$fresh_dir/Default_keyring.keyring"
grep -Fxq 'display-name=Default keyring' "$fresh_dir/Default_keyring.keyring"
[[ $(stat -c %a "$fresh_dir") == 700 ]]
[[ $(stat -c %a "$fresh_dir/default") == 600 ]]
[[ $(stat -c %a "$fresh_dir/Default_keyring.keyring") == 600 ]]
fresh_checksum=$(sha256sum "$fresh_dir/default" "$fresh_dir/Default_keyring.keyring")
run_configure "$fresh_home"
[[ $(sha256sum "$fresh_dir/default" "$fresh_dir/Default_keyring.keyring") == "$fresh_checksum" ]]

# An encrypted legacy keyring is never replaced or made secondary silently.
legacy_home=$test_root/legacy
legacy_dir=$legacy_home/data/keyrings
mkdir -p "$legacy_dir"
printf 'GnomeKeyring\n\r\0\nlegacy fixture\n' > "$legacy_dir/login.keyring"
legacy_checksum=$(sha256sum "$legacy_dir/login.keyring")
if run_configure "$legacy_home" > "$test_root/legacy.out" 2> "$test_root/legacy.err"; then
    printf 'Encrypted legacy keyring unexpectedly reported ready.\n' >&2
    exit 1
else
    status=$?
    [[ "$status" -eq 2 ]]
fi
[[ $(sha256sum "$legacy_dir/login.keyring") == "$legacy_checksum" ]]
[[ ! -e "$legacy_dir/default" ]]
[[ ! -e "$legacy_dir/Default_keyring.keyring" ]]
grep -Fq 'Existing encrypted keyring preserved.' "$test_root/legacy.err"

# After Seahorse changes Login to an empty password, the plaintext collection
# is retained and selected as the default without touching its items.
migrated_home=$test_root/migrated
migrated_dir=$migrated_home/data/keyrings
mkdir -p "$migrated_dir"
cat > "$migrated_dir/login.keyring" <<'EOF'
[keyring]
display-name=Login

[item1]
display-name=Preserved fixture secret
EOF
migrated_checksum=$(sha256sum "$migrated_dir/login.keyring")
run_configure "$migrated_home"
[[ $(< "$migrated_dir/default") == login ]]
[[ $(sha256sum "$migrated_dir/login.keyring") == "$migrated_checksum" ]]

printf 'Default keyring configuration tests passed.\n'
