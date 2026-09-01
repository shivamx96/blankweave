#!/usr/bin/env bash

set -euo pipefail

entries_dir=${1:-/boot/loader/entries}

die() {
    printf 'configure-kernel-command-line: %s\n' "$*" >&2
    exit 1
}

[[ -d "$entries_dir" ]] || die "not found: $entries_dir"

shopt -s nullglob
entries=("$entries_dir"/*.conf)
shopt -u nullglob

if (( ${#entries[@]} == 0 )); then
    printf 'No systemd-boot entries found in %s.\n' "$entries_dir"
    exit 0
fi

# Validate every Linux entry before modifying any of them. Type #1 entries for
# other operating systems may legitimately have no options line and are left
# untouched.
for entry in "${entries[@]}"; do
    mapfile -t option_lines < <(grep -nE '^[[:space:]]*options([[:space:]]+|$)' "$entry" || true)
    (( ${#option_lines[@]} <= 1 )) \
        || die "expected at most one options line in $entry"
done

for entry in "${entries[@]}"; do
    mapfile -t option_lines < <(grep -nE '^[[:space:]]*options([[:space:]]+|$)' "$entry" || true)
    if (( ${#option_lines[@]} == 0 )); then
        continue
    fi

    line_number=${option_lines[0]%%:*}
    line=${option_lines[0]#*:}
    if [[ ! "$line" =~ ^([[:space:]]*options)[[:space:]]*(.*)$ ]]; then
        die "unsupported options syntax on line $line_number of $entry"
    fi
    prefix=${BASH_REMATCH[1]}
    body=${BASH_REMATCH[2]}
    read -r -a tokens <<< "$body"

    retained=()
    red=
    green=
    blue=
    for token in "${tokens[@]}"; do
        case "$token" in
            quiet|splash|loglevel=*|systemd.show_status=*|rd.systemd.show_status=*|\
                udev.log_level=*|rd.udev.log_level=*|udev.log_priority=*|\
                rd.udev.log_priority=*|vt.global_cursor_default=*)
                ;;
            vt.default_red=*)
                value=${token#*=}
                if [[ "$value" =~ ^[0-9]+$ ]] && (( 10#$value <= 255 )); then
                    red=$((10#$value))
                fi
                ;;
            vt.default_grn=*)
                value=${token#*=}
                if [[ "$value" =~ ^[0-9]+$ ]] && (( 10#$value <= 255 )); then
                    green=$((10#$value))
                fi
                ;;
            vt.default_blu=*)
                value=${token#*=}
                if [[ "$value" =~ ^[0-9]+$ ]] && (( 10#$value <= 255 )); then
                    blue=$((10#$value))
                fi
                ;;
            *)
                retained+=("$token")
                ;;
        esac
    done

    tokens=(
        "${retained[@]}"
        quiet
        splash
        loglevel=3
        systemd.show_status=false
        rd.systemd.show_status=false
        udev.log_level=3
        rd.udev.log_level=3
        vt.global_cursor_default=0
        "vt.default_red=${red:-0}"
        "vt.default_grn=${green:-0}"
        "vt.default_blu=${blue:-0}"
    )
    new_line="$prefix ${tokens[*]}"
    [[ "$new_line" == "$line" ]] && continue

    staged=$(mktemp "$(dirname "$entry")/.loader-entry.XXXXXX")
    cleanup() {
        rm -f -- "$staged"
    }
    trap cleanup EXIT HUP INT TERM

    awk -v target="$line_number" -v replacement="$new_line" \
        'NR == target { print replacement; next } { print }' "$entry" > "$staged"
    chmod --reference="$entry" "$staged"
    chown --reference="$entry" "$staged"
    mv -f -- "$staged" "$entry"
    trap - EXIT HUP INT TERM

    printf 'Quiet Plymouth command line configured in %s.\n' "$(basename "$entry")"
done
