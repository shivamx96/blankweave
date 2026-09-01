#!/usr/bin/env bash
# Put Plymouth in the only safe part of mkinitcpio's hook order: after the
# init implementation (udev or systemd), and before any encrypted-root hook.
# Also ensure early CPU microcode loading immediately after autodetect.

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
has_autodetect=false
for hook in "${hooks[@]}"; do
    [[ $hook == autodetect ]] && has_autodetect=true
    if [[ $hook == systemd ]]; then
        anchor=systemd
    elif [[ $hook == udev && $anchor != systemd ]]; then
        anchor=udev
    fi
done
[[ -n $anchor ]] || die "HOOKS must contain udev or systemd"

ordered=()
plymouth_inserted=false
microcode_inserted=false
for hook in "${hooks[@]}"; do
    [[ $hook == plymouth || $hook == microcode ]] && continue
    ordered+=("$hook")
    if [[ $hook == "$anchor" ]]; then
        ordered+=(plymouth)
        plymouth_inserted=true
        if [[ $has_autodetect == false ]]; then
            ordered+=(microcode)
            microcode_inserted=true
        fi
    elif [[ $hook == autodetect ]]; then
        ordered+=(microcode)
        microcode_inserted=true
    fi
done
[[ $plymouth_inserted == true ]] || die "could not place Plymouth after $anchor"
[[ $microcode_inserted == true ]] || die 'could not place the microcode hook'

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

printf 'Placed Plymouth and CPU microcode hooks in %s.\n' "$config"
