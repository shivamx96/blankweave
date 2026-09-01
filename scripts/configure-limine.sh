#!/usr/bin/env bash

set -euo pipefail

PROGRAM_NAME=blankweave-limine
LIMINE_LABEL='Blankweave Boot Manager'
RECOVERY_LABEL='Linux Boot Manager'
LIMINE_LOADER='\EFI\blankweave\limine-x64.efi'
LIMINE_SOURCE=${BLANKWEAVE_LIMINE_SOURCE:-/usr/share/limine/BOOTX64.EFI}
BOOTCTL=${BLANKWEAVE_BOOTCTL:-bootctl}
EFIBOOTMGR=${BLANKWEAVE_EFIBOOTMGR:-efibootmgr}
FINDMNT=${BLANKWEAVE_FINDMNT:-findmnt}
LSBLK=${BLANKWEAVE_LSBLK:-lsblk}
TEST_MODE=${BLANKWEAVE_LIMINE_TEST:-false}

declare -a ENTRY_FILES=()
declare -a ORDERED_FILES=()
declare -a FOREIGN_LABELS=()
declare -A ENTRY_TITLE=()
declare -A ENTRY_KERNEL=()
declare -A ENTRY_INITRDS=()
declare -A ENTRY_CMDLINE=()

die() {
    printf '%s: %s\n' "$PROGRAM_NAME" "$*" >&2
    exit 1
}

trim() {
    local value=$1

    value=${value#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}
    printf '%s\n' "$value"
}

secure_boot_enabled() {
    local variable value

    for variable in /sys/firmware/efi/efivars/SecureBoot-*; do
        [[ -r $variable ]] || continue
        value=$(od -An -t u1 -j 4 -N 1 "$variable" 2>/dev/null | tr -d '[:space:]')
        [[ $value == 1 ]]
        return
    done
    return 1
}

resolve_esp() {
    local detected=

    if [[ -n ${BLANKWEAVE_ESP_PATH:-} ]]; then
        detected=$BLANKWEAVE_ESP_PATH
    elif command -v "$BOOTCTL" > /dev/null 2>&1; then
        detected=$($BOOTCTL --print-esp-path 2>/dev/null || true)
    fi
    [[ -n $detected ]] || detected=/boot
    [[ -d $detected ]] || die "EFI System Partition path does not exist: $detected"
    printf '%s\n' "${detected%/}"
}

validate_esp() {
    local esp=$1 filesystem

    [[ -w $esp ]] || die "EFI System Partition is not writable: $esp"
    [[ $TEST_MODE == true ]] && return
    [[ $EUID -eq 0 ]] || die 'run as root'
    [[ -d /sys/firmware/efi ]] || die 'Limine migration requires UEFI firmware'
    mountpoint -q "$esp" || die "EFI System Partition is not mounted: $esp"
    filesystem=$($FINDMNT -n -o FSTYPE --target "$esp" 2>/dev/null || true)
    case "$filesystem" in
        vfat|fat|msdos) ;;
        *) die "expected a FAT EFI System Partition at $esp, found ${filesystem:-unknown}" ;;
    esac
    secure_boot_enabled && die 'Secure Boot is enabled; signed Limine support is not configured'
}

validate_boot_path() {
    local esp=$1 path=$2 label=$3

    [[ $path == /* ]] || die "$label path is not absolute: $path"
    [[ $path != *$'\n'* && $path != *$'\r'* ]] || die "$label path contains a line break"
    # shellcheck disable=SC2016
    [[ $path != *'${'* ]] || die "$label path contains a Limine macro expression: $path"
    [[ "/${path#/}/" != *'/../'* && "/${path#/}/" != *'/./'* ]] \
        || die "$label path contains traversal components: $path"
    [[ -f "$esp$path" ]]
}

parse_bls_entry() {
    local esp=$1 file=$2 raw key value title='' kernel='' options='' backslash
    local title_count=0 kernel_count=0 options_count=0
    local -a initrds=()

    while IFS= read -r raw || [[ -n $raw ]]; do
        raw=$(trim "${raw%$'\r'}")
        [[ -n $raw && $raw != \#* ]] || continue
        key=${raw%%[[:space:]]*}
        value=$(trim "${raw#"$key"}")
        case "${key,,}" in
            title)
                title_count=$((title_count + 1))
                title=$value
                ;;
            linux)
                kernel_count=$((kernel_count + 1))
                kernel=$value
                ;;
            initrd)
                initrds+=("$value")
                ;;
            options)
                options_count=$((options_count + 1))
                options=$value
                ;;
        esac
    done < "$file"

    # Foreign BLS entries and UKIs remain systemd-boot recovery entries. Limine
    # imports only direct Linux entries with an explicit kernel.
    (( kernel_count > 0 )) || return 2
    (( kernel_count == 1 )) || die "$file contains more than one linux line"
    (( title_count <= 1 )) || die "$file contains more than one title line"
    (( options_count == 1 )) || die "$file must contain exactly one options line"
    (( ${#initrds[@]} > 0 )) || die "$file does not declare an initrd"
    [[ -n $kernel && -n $options ]] || die "$file has an empty kernel or command line"
    # Limine expands ${NAME} macros in configuration values. BLS entries do
    # not have an escaping convention we can translate losslessly, so reject
    # that unusual input instead of silently changing a kernel command line.
    # shellcheck disable=SC2016
    [[ $options != *$'\n'* && $options != *'${'* ]] \
        || die "$file contains a command line Limine cannot reproduce safely"

    [[ -n $title ]] || title=${file##*/}
    title=${title%.conf}
    [[ $title != *$'\n'* && $title != *$'\r'* ]] || die "$file has an invalid title"
    printf -v backslash '\134'
    # shellcheck disable=SC2016
    [[ $title != /* && $title != +* && $title != *'${'* && $title != *"$backslash"* ]] \
        || die "$file has a title that cannot be represented safely in Limine"
    if ! validate_boot_path "$esp" "$kernel" kernel; then
        printf 'Warning: skipping %s because its kernel is unavailable: %s\n' \
            "$file" "$kernel" >&2
        return 3
    fi
    for value in "${initrds[@]}"; do
        if ! validate_boot_path "$esp" "$value" initrd; then
            printf 'Warning: skipping %s because an initrd is unavailable: %s\n' \
                "$file" "$value" >&2
            return 3
        fi
    done

    ENTRY_FILES+=("$file")
    ENTRY_TITLE[$file]=$title
    ENTRY_KERNEL[$file]=$kernel
    ENTRY_CMDLINE[$file]=$options
    ENTRY_INITRDS[$file]=$(printf '%s\n' "${initrds[@]}")
}

default_bls_id() {
    local entries_dir=$1 loader_conf default_pattern candidate

    if [[ -n ${BLANKWEAVE_DEFAULT_ENTRY_ID:-} ]]; then
        printf '%s\n' "$BLANKWEAVE_DEFAULT_ENTRY_ID"
        return
    fi
    if command -v "$BOOTCTL" > /dev/null 2>&1 && command -v jq > /dev/null 2>&1; then
        candidate=$($BOOTCTL list --json=short 2>/dev/null \
            | jq -r '.[] | select(.type == "type1" and .isDefault == true) | .id' \
            | head -n 1 || true)
        if [[ -n $candidate ]]; then
            printf '%s\n' "$candidate"
            return
        fi
    fi

    loader_conf=${entries_dir%/entries}/loader.conf
    if [[ -r $loader_conf ]]; then
        default_pattern=$(sed -n -E 's/^[[:space:]]*default[[:space:]]+//p' "$loader_conf" \
            | head -n 1)
        if [[ -n $default_pattern ]]; then
            for candidate in "${ENTRY_FILES[@]}"; do
                # This is an intentional shell pattern match against loader.conf,
                # not command execution or filesystem expansion.
                # shellcheck disable=SC2053
                if [[ ${candidate##*/} == $default_pattern ]]; then
                    printf '%s\n' "${candidate##*/}"
                    return
                fi
            done
        fi
    fi

    for candidate in "${ENTRY_FILES[@]}"; do
        if [[ ${candidate##*/} == *_linux.conf || ${candidate##*/} == linux.conf ]]; then
            printf '%s\n' "${candidate##*/}"
            return
        fi
    done
    printf '%s\n' "${ENTRY_FILES[0]##*/}"
}

discover_linux_entries() {
    local esp=$1 entries_dir=$2 file default_id
    local -a sorted=()

    [[ -d $entries_dir ]] || die "Boot Loader Specification entries are missing: $entries_dir"
    while IFS= read -r -d '' file; do
        if parse_bls_entry "$esp" "$file"; then
            continue
        else
            case $? in
                2|3) ;;
                *) die "could not parse $file" ;;
            esac
        fi
    done < <(find "$entries_dir" -maxdepth 1 -type f -name '*.conf' -print0 \
        | LC_ALL=C sort -z)
    (( ${#ENTRY_FILES[@]} > 0 )) || die 'no direct Linux boot entries were found'

    default_id=$(default_bls_id "$entries_dir")
    for file in "${ENTRY_FILES[@]}"; do
        if [[ ${file##*/} == "$default_id" ]]; then
            ORDERED_FILES+=("$file")
            break
        fi
    done
    for file in "${ENTRY_FILES[@]}"; do
        [[ ${file##*/} == "$default_id" ]] || sorted+=("$file")
    done
    ORDERED_FILES+=("${sorted[@]}")

    declare -A titles=()
    for file in "${ORDERED_FILES[@]}"; do
        [[ -z ${titles[${ENTRY_TITLE[$file]}]:-} ]] \
            || die "duplicate Linux boot title: ${ENTRY_TITLE[$file]}"
        titles[${ENTRY_TITLE[$file]}]=1
    done
}

firmware_output() {
    command -v "$EFIBOOTMGR" > /dev/null 2>&1 || die 'efibootmgr is unavailable'
    "$EFIBOOTMGR" -v 2>/dev/null || die 'could not read UEFI boot entries'
}

foreign_entry_supported() {
    local label=$1 line=$2 lower_label=${1,,} lower_line=${2,,}
    local LC_ALL=C
    local backslash efi_marker

    printf -v backslash '\134'
    efi_marker=${backslash}efi${backslash}

    # Import arbitrary operating systems by capability, not by a distro-name
    # list: the active Boot#### entry must point at an EFI executable. Generic
    # firmware fallbacks and hardware launchers are intentionally omitted.
    case "$lower_label" in
        'blankweave boot manager'|'linux boot manager'|'uefi os'|uefi:*|efi:*) return 1 ;;
    esac
    [[ $line == *$'\t'* && $lower_line == *"$efi_marker"* && $lower_line == *'.efi'* ]] \
        || return 1
    [[ $label != *[![:print:]]* ]] || return 1
    [[ $label != *'$'* && $label != *'#'* && $label != *'/'* && $label != *"$backslash"* ]] \
        || return 1
}

discover_firmware_entries() {
    local output=$1 order line id active rest label normalized
    local -A in_order=()
    local -A labels_seen=()

    order=$(sed -n 's/^BootOrder:[[:space:]]*//p' <<< "$output" | head -n 1)
    [[ -n $order ]] || die 'UEFI BootOrder is unavailable'
    while IFS= read -r id; do
        [[ $id =~ ^[0-9A-Fa-f]{4}$ ]] || die "invalid UEFI boot number in BootOrder: $id"
        in_order[${id^^}]=1
    done < <(tr ',' '\n' <<< "$order")

    while IFS= read -r line; do
        [[ $line =~ ^Boot([0-9A-Fa-f]{4})(\*)?[[:space:]] ]] || continue
        id=${BASH_REMATCH[1]^^}
        active=${BASH_REMATCH[2]:-}
        [[ $active == '*' && -n ${in_order[$id]:-} ]] || continue
        rest=${line#Boot????}
        rest=${rest#\*}
        rest=$(trim "$rest")
        label=${rest%%$'\t'*}
        label=$(trim "$label")
        [[ -n $label ]] || continue
        normalized=${label,,}

        if [[ $label == "$RECOVERY_LABEL" || $label == "$LIMINE_LABEL" ]] \
            || foreign_entry_supported "$label" "$line"; then
            if [[ -n ${labels_seen[$normalized]:-} ]]; then
                die "duplicate active UEFI boot label cannot be targeted safely: $label"
            fi
            labels_seen[$normalized]=$id
        fi

        [[ $label == "$RECOVERY_LABEL" || $label == "$LIMINE_LABEL" ]] && continue
        foreign_entry_supported "$label" "$line" && FOREIGN_LABELS+=("$label")
    done <<< "$output"

    # A rejected final firmware record is an ordinary discovery result, not
    # the status of this operation. Without an explicit success here, `set -e`
    # exits silently on common layouts whose last record is UEFI OS or PXE.
    return 0
}

recovery_entry_available() {
    local output=$1 order line id rest label count=0
    local -A in_order=()

    order=$(sed -n 's/^BootOrder:[[:space:]]*//p' <<< "$output" | head -n 1)
    while IFS= read -r id; do
        in_order[${id^^}]=1
    done < <(tr ',' '\n' <<< "$order")

    while IFS= read -r line; do
        [[ $line =~ ^Boot([0-9A-Fa-f]{4})\*[[:space:]] ]] || continue
        id=${BASH_REMATCH[1]^^}
        [[ -n ${in_order[$id]:-} ]] || continue
        rest=${line#Boot????\*}
        rest=$(trim "$rest")
        label=${rest%%$'\t'*}
        [[ $(trim "$label") == "$RECOVERY_LABEL" ]] && count=$((count + 1))
    done <<< "$output"
    (( count == 1 ))
}

write_config() {
    local target=$1 firmware=$2 staged file initrd label

    mkdir -p "$(dirname "$target")"
    staged=$(mktemp "$(dirname "$target")/.limine.conf.blankweave.XXXXXX")
    {
        printf '%s\n' \
            '# Generated by Blankweave. Refresh with: sudo /usr/local/lib/blankweave/configure-limine' \
            'timeout: 3' \
            'quiet: yes' \
            'terse: yes' \
            'default_entry: 1' \
            'remember_last_entry: no' \
            'editor_enabled: no' \
            'interface_branding: Blankweave'
        for file in "${ORDERED_FILES[@]}"; do
            printf '\n/%s\n' "${ENTRY_TITLE[$file]}"
            printf '    comment: Imported from a systemd-boot BLS entry\n'
            printf '    protocol: linux\n'
            printf '    path: boot():%s\n' "${ENTRY_KERNEL[$file]}"
            while IFS= read -r initrd; do
                [[ -n $initrd ]] && printf '    module_path: boot():%s\n' "$initrd"
            done <<< "${ENTRY_INITRDS[$file]}"
            printf '    cmdline: %s\n' "${ENTRY_CMDLINE[$file]}"
        done
        if recovery_entry_available "$firmware"; then
            printf '\n/Blankweave recovery (systemd-boot)\n'
            printf '    protocol: efi_boot_entry\n'
            printf '    entry: %s\n' "$RECOVERY_LABEL"
        fi
        for label in "${FOREIGN_LABELS[@]}"; do
            printf '\n/%s\n' "$label"
            printf '    protocol: efi_boot_entry\n'
            printf '    entry: %s\n' "$label"
        done
    } > "$staged"
    chmod 0644 "$staged"
    if [[ -r $target ]] && cmp -s "$staged" "$target"; then
        rm -f "$staged"
    else
        mv -f "$staged" "$target"
    fi
}

install_efi_binary() {
    local target=$1 staged

    [[ -r $LIMINE_SOURCE ]] || die "Limine EFI executable is missing: $LIMINE_SOURCE"
    mkdir -p "$(dirname "$target")"
    staged=$(mktemp "$(dirname "$target")/.limine-x64.efi.blankweave.XXXXXX")
    install -m 0644 "$LIMINE_SOURCE" "$staged"
    if [[ -r $target ]] && cmp -s "$staged" "$target"; then
        rm -f "$staged"
    else
        mv -f "$staged" "$target"
    fi
}

entry_ids_for_label() {
    local output=$1 requested=$2 line id rest label

    while IFS= read -r line; do
        [[ $line =~ ^Boot([0-9A-Fa-f]{4})(\*)?[[:space:]] ]] || continue
        id=${BASH_REMATCH[1]^^}
        rest=${line#Boot????}
        rest=${rest#\*}
        rest=$(trim "$rest")
        label=$(trim "${rest%%$'\t'*}")
        [[ ${label,,} == "${requested,,}" ]] && printf '%s\n' "$id"
    done <<< "$output"
    return 0
}

register_limine() {
    local esp=$1 output=$2 source disk_name partition id line lower order new_order
    local -a ids=()
    local -a order_ids=()

    mapfile -t ids < <(entry_ids_for_label "$output" "$LIMINE_LABEL")
    (( ${#ids[@]} <= 1 )) || die "multiple UEFI entries are named $LIMINE_LABEL"
    if (( ${#ids[@]} == 1 )); then
        id=${ids[0]}
    else
        source=$($FINDMNT -n -o SOURCE --target "$esp" 2>/dev/null || true)
        [[ $source == /dev/* ]] || die "could not resolve the EFI System Partition device for $esp"
        disk_name=$($LSBLK -n -o PKNAME "$source" 2>/dev/null | head -n 1)
        partition=$($LSBLK -n -o PARTN "$source" 2>/dev/null | head -n 1)
        [[ -n $disk_name && $partition =~ ^[0-9]+$ ]] \
            || die "could not resolve disk and partition for $source"
        # Create the variable without changing BootOrder. Only the final
        # validated entry is promoted below, so an interrupted migration leaves
        # the already-working boot manager in control.
        "$EFIBOOTMGR" --create-only --disk "/dev/$disk_name" --part "$partition" \
            --label "$LIMINE_LABEL" --loader "$LIMINE_LOADER" > /dev/null
        output=$(firmware_output)
        mapfile -t ids < <(entry_ids_for_label "$output" "$LIMINE_LABEL")
        (( ${#ids[@]} == 1 )) || die "could not create the $LIMINE_LABEL UEFI entry"
        id=${ids[0]}
    fi

    line=$(grep -E "^Boot${id}(\\*)?[[:space:]]" <<< "$output" | head -n 1)
    lower=${line,,}
    [[ $lower == *'\efi\blankweave\limine-x64.efi'* ]] \
        || die "the $LIMINE_LABEL entry points to an unexpected loader"

    order=$(sed -n 's/^BootOrder:[[:space:]]*//p' <<< "$output" | head -n 1)
    IFS=',' read -r -a order_ids <<< "$order"
    new_order=$id
    for partition in "${order_ids[@]}"; do
        partition=${partition^^}
        [[ $partition == "$id" ]] || new_order+=",$partition"
    done
    if [[ ${order_ids[0]^^} != "$id" ]]; then
        "$EFIBOOTMGR" --bootorder "$new_order" > /dev/null
    fi
    printf 'Limine is registered as UEFI Boot%s; existing entries were preserved.\n' "$id"
}

main() {
    local esp entries_dir target_dir firmware

    esp=$(resolve_esp)
    validate_esp "$esp"
    entries_dir=${BLANKWEAVE_BLS_ENTRIES_DIR:-$esp/loader/entries}
    target_dir=${BLANKWEAVE_LIMINE_DIR:-$esp/EFI/blankweave}

    discover_linux_entries "$esp" "$entries_dir"
    firmware=$(firmware_output)
    discover_firmware_entries "$firmware"
    install_efi_binary "$target_dir/limine-x64.efi"
    write_config "$target_dir/limine.conf" "$firmware"
    register_limine "$esp" "$firmware"
}

main "$@"
