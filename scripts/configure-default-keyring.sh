#!/usr/bin/env bash

set -euo pipefail

data_home=${XDG_DATA_HOME:-$HOME/.local/share}
keyring_dir=$data_home/keyrings
default_file=$keyring_dir/default

is_plaintext_keyring() {
    local keyring_file="$1"
    local first_line

    [[ -f "$keyring_file" ]] || return 1
    IFS= read -r first_line < "$keyring_file" || true
    [[ "$first_line" == '[keyring]' ]]
}

write_default() {
    local keyring_name="$1"
    local staged

    staged=$(mktemp "$keyring_dir/.default.XXXXXX")
    printf '%s\n' "$keyring_name" > "$staged"
    chmod 600 "$staged"
    mv -f "$staged" "$default_file"
}

mkdir -p "$keyring_dir"
chmod 700 "$keyring_dir"

# An explicit default is ready only when its collection is stored without a
# keyring password. GNOME Keyring uses the key-file format for that case; an
# encrypted collection starts with the binary GnomeKeyring header instead.
if [[ -f "$default_file" ]]; then
    IFS= read -r default_name < "$default_file" || default_name=
    if [[ "$default_name" =~ ^[A-Za-z0-9_.-]+$ ]] \
        && is_plaintext_keyring "$keyring_dir/$default_name.keyring"; then
        chmod 600 "$default_file" "$keyring_dir/$default_name.keyring"
        printf 'Passwordless default keyring is ready: %s\n' "$default_name"
        exit 0
    fi
fi

# Seahorse normally keeps an existing collection named Login. Once its
# password has been changed to empty, make that collection the explicit
# default without renaming it or disturbing any of its saved secrets.
if is_plaintext_keyring "$keyring_dir/login.keyring"; then
    write_default login
    chmod 600 "$keyring_dir/login.keyring"
    printf 'Passwordless Login keyring is now the default.\n'
    exit 0
fi

shopt -s nullglob
existing_keyrings=("$keyring_dir"/*.keyring)
shopt -u nullglob

if (( ${#existing_keyrings[@]} > 0 )); then
    cat >&2 <<'EOF'
Existing encrypted keyring preserved. To make it work with automatic login:
  1. Open Passwords and Keys (seahorse).
  2. Right-click Login and choose Change Password.
  3. Enter the current password, then leave the new password empty.
  4. Run the Blankweave update again.
EOF
    exit 2
fi

# A fresh install has no secrets to migrate. Provision the passwordless
# collection before the first graphical session so applications never create
# a competing encrypted Login collection.
keyring_name=Default_keyring
keyring_file=$keyring_dir/$keyring_name.keyring
staged=$(mktemp "$keyring_dir/.keyring.XXXXXX")
cat > "$staged" <<EOF
[keyring]
display-name=Default keyring
ctime=$(date +%s)
mtime=0
lock-on-idle=false
lock-after=false
EOF
chmod 600 "$staged"
mv -f "$staged" "$keyring_file"
write_default "$keyring_name"

printf 'Created passwordless default keyring.\n'
