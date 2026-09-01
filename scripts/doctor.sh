#!/usr/bin/env bash

set -uo pipefail

PROGRAM_NAME=blankweave
SYSTEM_ROOT=${BLANKWEAVE_SYSTEM_ROOT:-}
USER_HOME=${BLANKWEAVE_USER_HOME:-$HOME}
STATE_HOME=${XDG_STATE_HOME:-$USER_HOME/.local/state}
CONFIG_HOME=${XDG_CONFIG_HOME:-$USER_HOME/.config}
REPORT=false
PASSED=0
WARNED=0
FAILED=0
SKIPPED=0

usage() {
    cat <<'EOF'
Usage: blankweave doctor [--report]

Run read-only health checks. --report adds sanitized system and package
versions suitable for sharing in a bug report.
EOF
}

emit() {
    local level="$1"
    local label="$2"
    local detail=${3:-}

    if [[ -n "$detail" ]]; then
        printf '%-4s  %-24s %s\n' "$level" "$label" "$detail"
    else
        printf '%-4s  %s\n' "$level" "$label"
    fi
}

pass() {
    PASSED=$((PASSED + 1))
    emit PASS "$1" "${2:-}"
}

warn() {
    WARNED=$((WARNED + 1))
    emit WARN "$1" "${2:-}"
}

fail() {
    FAILED=$((FAILED + 1))
    emit FAIL "$1" "${2:-}"
}

skip() {
    SKIPPED=$((SKIPPED + 1))
    emit SKIP "$1" "${2:-}"
}

root_path() {
    printf '%s%s\n' "$SYSTEM_ROOT" "$1"
}

trim_space() {
    local value=$1

    value=${value#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}
    printf '%s\n' "$value"
}

short_revision() {
    local repository="$1"
    git -C "$repository" rev-parse --short=12 HEAD 2>/dev/null || printf 'unknown\n'
}

check_repository() {
    local repository="$1"
    local installed_file=$STATE_HOME/blankweave/installed-revision
    local repository_revision installed_revision

    if [[ ! -d "$repository/.git" || ! -f "$repository/install.sh" || ! -x "$repository/bin/blankweave" ]]; then
        fail repository 'managed checkout is incomplete'
        return
    fi

    repository_revision=$(short_revision "$repository")
    pass repository "$repository_revision"

    if [[ -n "$(git -C "$repository" status --porcelain 2>/dev/null)" ]]; then
        warn 'repository state' 'managed checkout has local changes'
    else
        pass 'repository state' 'clean'
    fi

    if [[ ! -r "$installed_file" ]]; then
        warn 'installed revision' 'not recorded; run blankweave update'
        return
    fi

    IFS= read -r installed_revision < "$installed_file"
    if [[ "$installed_revision" == "$(git -C "$repository" rev-parse HEAD 2>/dev/null)" ]]; then
        pass 'installed revision' "${installed_revision:0:12}"
    else
        warn 'installed revision' "differs from checkout ($repository_revision)"
    fi
}

check_commands() {
    local executable
    local required_value=${BLANKWEAVE_DOCTOR_COMMANDS:-Hyprland uwsm qs hyprlock hypridle awww-daemon dunst ghostty fuzzel jq playerctl}
    local -a required=()
    local -a missing=()

    read -r -a required <<< "$required_value"
    for executable in "${required[@]}"; do
        command -v "$executable" > /dev/null 2>&1 || missing+=("$executable")
    done

    if (( ${#missing[@]} == 0 )); then
        pass 'runtime commands' 'core desktop commands are available'
    else
        fail 'runtime commands' "missing: ${missing[*]}"
    fi
}

check_user_configuration() {
    local file
    local -a required=(
        "$CONFIG_HOME/hypr/hyprland.lua"
        "$CONFIG_HOME/hypr/env.lua"
        "$CONFIG_HOME/hypr/monitors.lua"
        "$CONFIG_HOME/hypr/hypridle.conf"
        "$CONFIG_HOME/hypr/hyprlock.conf"
        "$USER_HOME/.zprofile"
    )
    local -a missing=()

    for file in "${required[@]}"; do
        [[ -r "$file" ]] || missing+=("${file#"$USER_HOME/"}")
    done

    if (( ${#missing[@]} == 0 )); then
        pass 'user configuration' 'managed entry points are readable'
    else
        fail 'user configuration' "missing: ${missing[*]}"
    fi

    if command -v hyprland > /dev/null 2>&1 && [[ -r "$CONFIG_HOME/hypr/hyprland.lua" ]]; then
        if hyprland --verify-config --config "$CONFIG_HOME/hypr/hyprland.lua" > /dev/null 2>&1; then
            pass 'Hyprland configuration' 'valid'
        else
            fail 'Hyprland configuration' 'validation failed'
        fi
    else
        skip 'Hyprland configuration' 'validator or configuration unavailable'
    fi
}

check_console_session() {
    local autologin cursor_issue legacy_pam

    autologin=$(root_path /etc/systemd/system/getty@tty1.service.d/autologin.conf)
    cursor_issue=$(root_path /etc/issue.d/blankweave-cursor.issue)
    legacy_pam=$(root_path /etc/pam.d/blankweave-lock)

    if [[ -r "$autologin" ]] && grep -Fq -- '--autologin' "$autologin"; then
        pass 'tty1 automatic login' 'configured'
    else
        fail 'tty1 automatic login' 'getty override is missing or invalid'
    fi

    if [[ -r "$cursor_issue" ]]; then
        pass 'recovery console' 'tty cursor restoration is installed'
    else
        warn 'recovery console' 'cursor restoration snippet is missing'
    fi

    if [[ -e "$legacy_pam" || -L "$legacy_pam" ]]; then
        fail 'Hyprlock PAM' 'obsolete blankweave-lock service remains'
    else
        pass 'Hyprlock PAM' 'uses the packaged service'
    fi
}

check_keyring() {
    local default_file=$USER_HOME/.local/share/keyrings/default
    local default_name=
    local keyring_file

    if [[ -r "$default_file" ]]; then
        IFS= read -r default_name < "$default_file"
    fi

    if [[ -z "$default_name" ]]; then
        fail 'default keyring' 'selection is missing'
        return
    fi

    if [[ ! "$default_name" =~ ^[A-Za-z0-9_.-]+$ ]]; then
        fail 'default keyring' 'selection contains an invalid collection name'
        return
    fi

    keyring_file=$USER_HOME/.local/share/keyrings/$default_name.keyring
    if [[ -r "$keyring_file" ]] && head -n 1 "$keyring_file" | grep -Fxq '[keyring]'; then
        pass 'default keyring' 'passwordless collection is selected'
    else
        fail 'default keyring' 'selected collection is absent or encrypted'
    fi
}

check_plymouth() {
    local dropin hooks entries entry options
    local entries_checked=0
    local entries_invalid=0

    dropin=$(root_path /etc/systemd/system/plymouth-quit.service.d/blankweave.conf)
    hooks=$(root_path /etc/mkinitcpio.conf)
    entries=$(root_path /boot/loader/entries)

    if [[ -r "$dropin" ]] && grep -Fq 'quit --retain-splash' "$dropin"; then
        pass 'Plymouth handoff' 'retain-splash override is installed'
    else
        fail 'Plymouth handoff' 'systemd override is missing or invalid'
    fi

    if [[ -r "$hooks" ]]; then
        if grep -E '^[[:space:]]*HOOKS=.*[([:space:]]plymouth[)[:space:]]' "$hooks" > /dev/null; then
            pass 'initramfs Plymouth' 'hook is configured'
        else
            fail 'initramfs Plymouth' 'hook is absent from mkinitcpio.conf'
        fi
        if grep -E '^[[:space:]]*HOOKS=.*[([:space:]]microcode[)[:space:]]' "$hooks" > /dev/null; then
            pass 'initramfs microcode' 'early loading is configured'
        else
            fail 'initramfs microcode' 'hook is absent from mkinitcpio.conf'
        fi
    else
        skip 'initramfs Plymouth' 'mkinitcpio.conf is not readable'
        skip 'initramfs microcode' 'mkinitcpio.conf is not readable'
    fi

    if [[ -d "$entries" ]]; then
        while IFS= read -r -d '' entry; do
            options=$(grep -E '^[[:space:]]*options[[:space:]]' "$entry" || true)
            [[ -n "$options" ]] || continue
            entries_checked=$((entries_checked + 1))
            if [[ " $options " != *' quiet '* || " $options " != *' splash '* ]]; then
                entries_invalid=$((entries_invalid + 1))
            fi
        done < <(find "$entries" -maxdepth 1 -type f -name '*.conf' -print0 2>/dev/null)

        if (( entries_checked == 0 )); then
            skip 'kernel command line' 'no readable Linux loader entries'
        elif (( entries_invalid == 0 )); then
            pass 'kernel command line' "$entries_checked Linux entries are quiet"
        else
            fail 'kernel command line' "$entries_invalid of $entries_checked Linux entries lack quiet splash"
        fi
    else
        skip 'kernel command line' 'systemd-boot entries are not readable'
    fi
}

check_bootloader() {
    local executable config entries entry kernel cmdline initrd output order first line prefix label id lower
    local linux_entries=0 recovery_entries=0 source_entries=0 handoff_drift=0 available
    local limine_path_valid=true
    local -a limine_ids=() initrds=()

    executable=$(root_path /boot/EFI/blankweave/limine-x64.efi)
    config=$(root_path /boot/EFI/blankweave/limine.conf)
    entries=$(root_path /boot/loader/entries)

    if [[ -r $executable ]]; then
        pass 'Limine EFI executable' 'installed on the EFI System Partition'
    else
        fail 'Limine EFI executable' 'managed loader is missing'
    fi
    if [[ -r $config ]]; then
        linux_entries=$(grep -Ec '^[[:space:]]+protocol:[[:space:]]+linux[[:space:]]*$' "$config" || true)
        if (( linux_entries > 0 )) \
            && grep -Eq '^[[:space:]]+path:[[:space:]]+boot\(\):/' "$config" \
            && grep -Eq '^[[:space:]]+module_path:[[:space:]]+boot\(\):/' "$config" \
            && grep -Eq '^[[:space:]]+cmdline:[[:space:]]+[^[:space:]]' "$config"; then
            pass 'Limine Linux entries' "$linux_entries direct boot entries are configured"
        else
            fail 'Limine Linux entries' 'config lacks a complete direct Linux entry'
        fi
    else
        fail 'Limine Linux entries' 'limine.conf is missing'
    fi

    if [[ -r $config && -d $entries ]]; then
        while IFS= read -r -d '' entry; do
            mapfile -t initrds < <(sed -n -E \
                's/^[[:space:]]*initrd[[:space:]]+//p' "$entry")
            kernel=$(sed -n -E 's/^[[:space:]]*linux[[:space:]]+//p' "$entry" | head -n 1)
            cmdline=$(sed -n -E 's/^[[:space:]]*options[[:space:]]+//p' "$entry" | head -n 1)
            [[ -n $kernel && -n $cmdline && ${#initrds[@]} -gt 0 ]] || continue
            available=true
            [[ -f "$(root_path "/boot$kernel")" ]] || available=false
            for initrd in "${initrds[@]}"; do
                [[ -f "$(root_path "/boot$initrd")" ]] || available=false
            done
            [[ $available == true ]] || continue

            source_entries=$((source_entries + 1))
            grep -Fqx -- "    path: boot():$kernel" "$config" \
                || handoff_drift=$((handoff_drift + 1))
            grep -Fqx -- "    cmdline: $cmdline" "$config" \
                || handoff_drift=$((handoff_drift + 1))
            for initrd in "${initrds[@]}"; do
                grep -Fqx -- "    module_path: boot():$initrd" "$config" \
                    || handoff_drift=$((handoff_drift + 1))
            done
        done < <(find "$entries" -maxdepth 1 -type f -name '*.conf' -print0 2>/dev/null)

        if (( source_entries == 0 )); then
            fail 'Limine BLS handoff' 'no complete source Linux entries are available'
        elif (( handoff_drift == 0 )); then
            pass 'Limine BLS handoff' "$source_entries source entries match exactly"
        else
            fail 'Limine BLS handoff' "$handoff_drift generated fields differ from the BLS source"
        fi
    else
        fail 'Limine BLS handoff' 'source or generated boot entries are unreadable'
    fi

    if ! command -v efibootmgr > /dev/null 2>&1; then
        fail 'UEFI boot order' 'efibootmgr is unavailable'
        return
    fi
    if ! output=$(efibootmgr -v 2>/dev/null); then
        fail 'UEFI boot order' 'firmware entries are unreadable'
        return
    fi
    order=$(sed -n 's/^BootOrder:[[:space:]]*//p' <<< "$output" | head -n 1)
    first=${order%%,*}

    while IFS= read -r line; do
        [[ $line =~ ^Boot([0-9A-Fa-f]{4})(\*)?[[:space:]] ]] || continue
        id=${BASH_REMATCH[1]^^}
        prefix=${line%%$'\t'*}
        label=${prefix#Boot????}
        label=${label#\*}
        label=$(trim_space "$label")
        case "$label" in
            'Blankweave Boot Manager')
                limine_ids+=("$id")
                lower=${line,,}
                [[ $lower == *'\efi\blankweave\limine-x64.efi'* ]] \
                    || limine_path_valid=false
                ;;
            'Linux Boot Manager')
                if [[ ",${order^^}," == *",$id,"* ]]; then
                    recovery_entries=$((recovery_entries + 1))
                fi
                ;;
        esac
    done <<< "$output"

    if (( ${#limine_ids[@]} == 1 )) && [[ ${limine_ids[0]} == "${first^^}" ]] \
        && [[ $limine_path_valid == true ]]; then
        pass 'UEFI boot order' "Blankweave Limine is first (Boot${limine_ids[0]})"
    elif (( ${#limine_ids[@]} == 1 )); then
        fail 'UEFI boot order' 'Blankweave Limine is not first or points to the wrong loader'
    else
        fail 'UEFI boot order' "expected one Blankweave Limine entry, found ${#limine_ids[@]}"
    fi

    if (( recovery_entries == 1 )) && [[ -r $config ]] \
        && grep -Fq '    entry: Linux Boot Manager' "$config"; then
        pass 'bootloader recovery' 'systemd-boot remains available from Limine and firmware'
    elif (( recovery_entries == 1 )); then
        warn 'bootloader recovery' 'systemd-boot remains in firmware but is absent from the Limine menu'
    else
        warn 'bootloader recovery' 'a unique Linux Boot Manager recovery entry was not found'
    fi
}

check_cpu_microcode() {
    local repository=$1 package

    # shellcheck source=scripts/hardware-capabilities.sh
    source "$repository/scripts/hardware-capabilities.sh"
    hardware_capabilities_detect
    if hardware_capability_has cpu-intel; then
        package=intel-ucode
    elif hardware_capability_has cpu-amd; then
        package=amd-ucode
    else
        skip 'CPU microcode package' 'CPU vendor is not Intel or AMD'
        return
    fi

    if ! command -v pacman > /dev/null 2>&1; then
        skip 'CPU microcode package' 'pacman is unavailable'
    elif pacman -Q "$package" > /dev/null 2>&1; then
        pass 'CPU microcode package' "$package is installed"
    else
        fail 'CPU microcode package' "$package is not installed"
    fi
}

check_services() {
    local repository=$1 unit
    local -a system_units=(NetworkManager.service)

    # shellcheck source=scripts/hardware-capabilities.sh
    source "$repository/scripts/hardware-capabilities.sh"
    hardware_capabilities_detect
    if hardware_capability_has bluetooth; then
        system_units+=(bluetooth.service)
    fi

    if ! command -v systemctl > /dev/null 2>&1; then
        skip services 'systemctl is unavailable'
        return
    fi

    for unit in "${system_units[@]}"; do
        if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
            pass "$unit" 'enabled'
        else
            warn "$unit" 'not enabled'
        fi
    done

    if systemctl --user is-active --quiet wayland-session@hyprland.desktop.target 2>/dev/null; then
        pass 'UWSM session' 'active'
    elif [[ "${XDG_SESSION_TYPE:-}" == wayland ]]; then
        warn 'UWSM session' 'Wayland is active but the UWSM target is not'
    else
        skip 'UWSM session' 'not currently in the graphical session'
    fi
}

print_report() {
    local repository="$1"
    local os_release kernel session desktop package version os_file capabilities
    local -a packages=(hyprland hyprlock uwsm quickshell plymouth limine efibootmgr)

    os_file=$(root_path /etc/os-release)
    os_release=unknown
    if [[ -r "$os_file" ]]; then
        os_release=$(sed -n 's/^PRETTY_NAME=//p' "$os_file" | head -n 1)
        os_release=${os_release#\"}
        os_release=${os_release%\"}
    fi
    kernel=$(uname -r 2>/dev/null || printf 'unknown')
    session=${XDG_SESSION_TYPE:-unknown}
    desktop=${XDG_CURRENT_DESKTOP:-unknown}
    # shellcheck source=scripts/hardware-capabilities.sh
    source "$repository/scripts/hardware-capabilities.sh"
    hardware_capabilities_detect
    capabilities=$(hardware_capabilities_list)
    if hardware_capability_has cpu-intel; then
        packages+=(intel-ucode)
    elif hardware_capability_has cpu-amd; then
        packages+=(amd-ucode)
    fi

    printf '\nSanitized report\n'
    printf '  blankweave: %s (%s)\n' "$(head -n 1 "$repository/VERSION" 2>/dev/null || printf unknown)" "$(short_revision "$repository")"
    printf '  operating system: %s\n' "$os_release"
    printf '  kernel: %s\n' "$kernel"
    printf '  session: %s / %s\n' "$session" "$desktop"
    printf '  capabilities: %s\n' "${capabilities:-none}"
    printf '  packages:\n'
    for package in "${packages[@]}"; do
        version=not-installed
        if command -v pacman > /dev/null 2>&1; then
            version=$(pacman -Q "$package" 2>/dev/null | awk '{print $2}' || printf 'not-installed')
        fi
        printf '    %s: %s\n' "$package" "$version"
    done
    printf '  privacy: usernames, hostnames, network addresses, disk identifiers, and serial numbers omitted\n'
}

main() {
    local repository

    repository=${1:-}
    [[ -n "$repository" ]] || {
        printf '%s doctor: repository path is required\n' "$PROGRAM_NAME" >&2
        return 2
    }
    shift

    case "${1:-}" in
        '') ;;
        --report) REPORT=true ;;
        --help|-h)
            usage
            return 0
            ;;
        *)
            usage >&2
            return 2
            ;;
    esac
    (( $# <= 1 )) || {
        usage >&2
        return 2
    }

    printf 'Blankweave doctor\n\n'
    check_repository "$repository"
    check_commands
    check_user_configuration
    check_console_session
    check_keyring
    check_plymouth
    check_bootloader
    check_cpu_microcode "$repository"
    check_services "$repository"

    printf '\nSummary: %d passed, %d warnings, %d failures, %d skipped\n' \
        "$PASSED" "$WARNED" "$FAILED" "$SKIPPED"

    if [[ "$REPORT" == true ]]; then
        print_report "$repository"
    fi

    (( FAILED == 0 ))
}

main "$@"
