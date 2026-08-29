#!/bin/sh

set -eu

repository_url=https://github.com/shivamx96/hyprarch.git
hyprarch_dir=$HOME/.local/share/hyprarch
repository=$hyprarch_dir/repository
temporary_repository=

die() {
    printf 'hyprarch bootstrap: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [ -n "$temporary_repository" ] && [ -d "$temporary_repository" ]; then
        rm -rf -- "$temporary_repository"
    fi
}
trap cleanup EXIT HUP INT TERM

[ "$(id -u)" -ne 0 ] || die "run this command as your normal user, not root"
[ -r /etc/arch-release ] || die "Hyprarch currently supports Arch Linux only"
if ! (: </dev/tty) 2>/dev/null; then
    die "an interactive terminal is required"
fi

if ! command -v git >/dev/null 2>&1; then
    command -v sudo >/dev/null 2>&1 || die "git is missing and sudo is unavailable"
    printf 'Installing Git...\n'
    sudo pacman -S --needed --noconfirm git
fi

mkdir -p "$hyprarch_dir"

if [ -e "$repository" ]; then
    [ -d "$repository/.git" ] || die "refusing unexpected path at $repository"
    [ -x "$repository/bin/hyprarch" ] \
        || die "the managed repository is missing bin/hyprarch"
    origin=$(git -C "$repository" remote get-url origin 2>/dev/null) \
        || die "existing repository has no origin remote"
    [ "$origin" = "$repository_url" ] \
        || die "existing repository has an unexpected origin: $origin"
    exec "$repository/bin/hyprarch" update </dev/tty
fi

temporary_repository=$(mktemp -d "$hyprarch_dir/.repository.XXXXXX")
printf 'Downloading Hyprarch...\n'
git clone --depth 1 --branch main "$repository_url" "$temporary_repository"
mv "$temporary_repository" "$repository"
temporary_repository=

exec "$repository/bin/hyprarch" _apply "$repository" </dev/tty
