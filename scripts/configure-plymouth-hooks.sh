#!/usr/bin/env bash
# Put Plymouth in the only safe part of mkinitcpio's hook order: after the
# init implementation (udev or systemd), and before any encrypted-root hook.

set -euo pipefail

config=${1:-/etc/mkinitcpio.conf}

die() {
    printf 'configure-plymouth-hooks: %s\n' "$*" >&2
    exit 1
}

[[ -f $config ]] || die "not found: $config"

mapfile -t hook_lines < <(grep -nE '^[[:space:]]*HOOKS[[:space:]]*=' "$config" || true)
[[ ${#hook_lines[@]} -eq 1 ]] || die "expected exactly one active HOOKS array in $config"

line_number=${hook_lines[0]%%:*}
line=${hook_lines[0]#*:}
if [[ ! $line =~ ^([[:space:]]*HOOKS[[:space:]]*=[[:space:]]*\()([^\)]*)(\)[[:space:]]*(#.*)?)$ ]]; then
    die "unsupported HOOKS syntax on line $line_number of $config"
fi

prefix=${BASH_REMATCH[1]}
body=${BASH_REMATCH[2]}
suffix=${BASH_REMATCH[3]}
read -r -a hooks <<< "$body"

anchor=""
for hook in "${hooks[@]}"; do
    if [[ $hook == systemd ]]; then
        anchor=systemd
        break
    elif [[ $hook == udev ]]; then
        anchor=udev
    fi
done
[[ -n $anchor ]] || die "HOOKS must contain udev or systemd"

ordered=()
inserted=false
for hook in "${hooks[@]}"; do
    [[ $hook == plymouth ]] && continue
    ordered+=("$hook")
    if [[ $hook == "$anchor" ]]; then
        ordered+=(plymouth)
        inserted=true
    fi
done
[[ $inserted == true ]] || die "could not place Plymouth after $anchor"

new_line="$prefix${ordered[*]}$suffix"
if [[ $new_line == "$line" ]]; then
    printf 'Plymouth hook order already current.\n'
    exit 0
fi

staged=$(mktemp "$(dirname "$config")/.mkinitcpio.conf.blankweave.XXXXXX")
cleanup() {
    rm -f -- "$staged"
}
trap cleanup EXIT HUP INT TERM

awk -v target="$line_number" -v replacement="$new_line" \
    'NR == target { print replacement; next } { print }' "$config" > "$staged"
chmod --reference="$config" "$staged"
chown --reference="$config" "$staged"
mv -f -- "$staged" "$config"
trap - EXIT HUP INT TERM

printf 'Placed Plymouth after %s in %s.\n' "$anchor" "$config"
