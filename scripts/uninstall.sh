#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
apply=false
yes=false
purge=()
for option in "$@"; do
    case "$option" in
        --apply) apply=true ;;
        --yes) yes=true ;;
        --purge-config) purge=(--purge-config) ;;
        --help|-h) printf 'Usage: blankweave uninstall [--apply] [--purge-config] [--yes]\nPreview removal; packages are never removed.\n'; exit 0 ;;
        *) printf 'blankweave uninstall: unknown option: %s\n' "$option" >&2; exit 2 ;;
    esac
done
root=${BLANKWEAVE_SYSTEM_ROOT:-}
home=${BLANKWEAVE_USER_HOME:-$HOME}
action=preview
if [[ $apply == true ]]; then
    if [[ $yes != true ]]; then
        [[ -t 0 ]] || { printf 'Removal requires terminal confirmation or --yes.\n' >&2; exit 2; }
        printf 'Remove proven Blankweave files? Set up another session before rebooting. [y/N]: '
        read -r answer
        [[ $answer == y || $answer == yes ]] || exit 0
    fi
    action=apply
    if [[ -z $root && $EUID != 0 ]]; then
        exec sudo python3 "$repository/scripts/uninstall-footprint.py" "$action" '' "$home" "${purge[@]}"
    fi
fi
exec python3 "$repository/scripts/uninstall-footprint.py" "$action" "$root" "$home" "${purge[@]}"
