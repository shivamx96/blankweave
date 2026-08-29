#!/usr/bin/env bash
#
# Web apps in the Omarchy manner: a site opened as its own window through
# Helium's --app mode, with a desktop entry so the launcher lists it and
# Hyprland sees a class of its own. App windows join the running Helium
# instance, so a web app shares its logins with the browser.
#
#   webapp.sh launch <url>
#   webapp.sh install <name> <url> <icon>   icon: a URL or a file, PNG or SVG
#   webapp.sh remove <name>
#   webapp.sh list
#   webapp.sh sync                          converge the bundled entries
#
# Entries are ~/.local/share/applications/blankweave-webapp-<slug>.desktop and
# icons are installed under the hicolor theme as blankweave-webapp-<slug>.
# Chromium names an --app window chrome-<host>__<path>-Default, with the
# path's slashes turned into underscores; StartupWMClass carries that so a
# window is matched back to its entry.

set -euo pipefail

BROWSER=${BLANKWEAVE_WEBAPP_BROWSER:-helium-browser}
DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
APPLICATIONS_DIR=$DATA_HOME/applications
PNG_ICONS_DIR=$DATA_HOME/icons/hicolor/256x256/apps
SVG_ICONS_DIR=$DATA_HOME/icons/hicolor/scalable/apps
MANIFEST=${BLANKWEAVE_WEBAPP_MANIFEST:-$DATA_HOME/blankweave/webapps/webapps.tsv}
FALLBACK_ICON=web-browser
PREFIX=blankweave-webapp-
SCRIPT=$(readlink -f "${BASH_SOURCE[0]}")

die() {
    printf 'webapp: %s\n' "$*" >&2
    exit 1
}

warn() {
    printf 'webapp: %s\n' "$*" >&2
}

usage() {
    cat >&2 <<'USAGE'
Usage: webapp.sh launch <url>
       webapp.sh install <name> <url> <icon>
       webapp.sh remove <name>
       webapp.sh list
       webapp.sh sync
USAGE
    exit 2
}

slugify() {
    local slug
    slug=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
    [[ -n "$slug" ]] || die "name has no usable characters: $1"
    printf '%s\n' "$slug"
}

# The URL lands in a desktop Exec line, which is split on whitespace and
# unquotes backslashes and double quotes; refuse anything that would need
# escaping instead of getting the escaping subtly wrong.
validate_url() {
    [[ "$1" =~ ^https?://[^[:space:]\"\'\\\`\$]+$ ]] || die "not an http(s) URL: $1"
}

app_class() {
    local rest host path
    rest=${1#*://}
    rest=${rest%%[?#]*}
    host=${rest%%/*}
    path=${rest#"$host"}
    path=${path#/}
    path=${path%/}
    printf 'chrome-%s__%s-Default\n' "$host" "${path//\//_}"
}

desktop_file() {
    printf '%s\n' "$APPLICATIONS_DIR/$PREFIX$1.desktop"
}

desktop_field() {
    sed -n "s/^$2=//p" "$1" | head -n 1
}

# Only PNG and SVG go into the icon theme; anything else is refused rather
# than installed under a name that lies about its format.
icon_format() {
    local head
    head=$(head -c 512 "$1" | tr -d '\0')
    if [[ "$head" == $'\x89PNG'* ]]; then
        printf 'png\n'
    elif [[ "$head" == *'<svg'* ]]; then
        printf 'svg\n'
    else
        return 1
    fi
}

remove_icon() {
    rm -f "$PNG_ICONS_DIR/$PREFIX$1.png" "$SVG_ICONS_DIR/$PREFIX$1.svg"
}

# Installs the icon and prints the icon name to use, or the fallback when the
# source cannot be fetched and $3 says that is tolerable.
install_icon() {
    local slug=$1 source=$2 tolerate=$3
    local staged format target
    staged=$(mktemp)
    trap 'rm -f "$staged"' RETURN

    if [[ "$source" =~ ^https?:// ]]; then
        if ! curl -fsSL --max-time 30 -o "$staged" "$source"; then
            [[ "$tolerate" == tolerate ]] || die "could not download the icon: $source"
            warn "could not download the icon for $slug, using $FALLBACK_ICON"
            printf '%s\n' "$FALLBACK_ICON"
            return 0
        fi
    else
        [[ -r "$source" ]] || die "icon is not readable: $source"
        cp -f "$source" "$staged"
    fi

    format=$(icon_format "$staged") || die "icon is neither PNG nor SVG: $source"
    remove_icon "$slug"
    if [[ "$format" == png ]]; then
        target=$PNG_ICONS_DIR/$PREFIX$slug.png
    else
        target=$SVG_ICONS_DIR/$PREFIX$slug.svg
    fi
    mkdir -p "$(dirname "$target")"
    install -m 0644 "$staged" "$target"
    printf '%s\n' "$PREFIX$slug"
}

write_entry() {
    local name=$1 url=$2 icon=$3 origin=$4
    local slug file staged exec_url
    slug=$(slugify "$name")
    file=$(desktop_file "$slug")
    exec_url=${url//%/%%}
    mkdir -p "$APPLICATIONS_DIR"
    staged=$(mktemp "$APPLICATIONS_DIR/.$PREFIX.XXXXXX")
    cat > "$staged" <<ENTRY
[Desktop Entry]
Type=Application
Version=1.5
Name=$name
Comment=$url
Exec=$SCRIPT launch $exec_url
Icon=$icon
Terminal=false
Categories=Network;WebBrowser;
StartupNotify=true
StartupWMClass=$(app_class "$url")
X-Blankweave-Webapp=$origin
ENTRY
    chmod 0644 "$staged"
    mv -f "$staged" "$file"
}

refresh_database() {
    if command -v update-desktop-database > /dev/null 2>&1; then
        update-desktop-database "$APPLICATIONS_DIR" 2> /dev/null || true
    fi
}

bundled_slugs() {
    local name url icon
    [[ -r "$MANIFEST" ]] || return 0
    while IFS=$'\t' read -r name url icon; do
        [[ -n "$name" && "$name" != \#* ]] || continue
        slugify "$name"
    done < "$MANIFEST"
}

command_launch() {
    [[ $# -eq 1 ]] || usage
    validate_url "$1"
    command -v "$BROWSER" > /dev/null 2>&1 \
        || die "$BROWSER is not installed; web apps need the desktop profile"
    exec "$BROWSER" --app="$1"
}

command_install() {
    [[ $# -eq 3 ]] || usage
    local name=$1 url=$2 icon_source=$3 slug icon
    validate_url "$url"
    slug=$(slugify "$name")
    icon=$(install_icon "$slug" "$icon_source" strict)
    write_entry "$name" "$url" "$icon" user
    refresh_database
    printf 'Installed %s -> %s\n' "$name" "$(desktop_file "$slug")"
}

command_remove() {
    [[ $# -eq 1 ]] || usage
    local slug file
    slug=$(slugify "$1")
    file=$(desktop_file "$slug")
    [[ -f "$file" ]] || die "no web app named $1"
    rm -f "$file"
    remove_icon "$slug"
    refresh_database
    printf 'Removed %s\n' "$slug"
}

command_list() {
    [[ $# -eq 0 ]] || usage
    local file slug
    shopt -s nullglob
    for file in "$APPLICATIONS_DIR/$PREFIX"*.desktop; do
        slug=$(basename "$file" .desktop)
        slug=${slug#"$PREFIX"}
        printf '%s\t%s\t%s\t%s\n' "$slug" "$(desktop_field "$file" Name)" \
            "$(desktop_field "$file" Comment)" "$(desktop_field "$file" X-Blankweave-Webapp)"
    done
}

# Converges the bundled entries on the manifest: every listed site gets an
# entry (icons are fetched once and kept), and a bundled entry that has left
# the manifest is removed. Entries the user installed are never touched.
command_sync() {
    [[ $# -eq 0 ]] || usage
    local name url icon_source slug icon file
    local -a keep=()

    if ! command -v "$BROWSER" > /dev/null 2>&1; then
        printf 'webapp: %s is not installed, skipping web apps\n' "$BROWSER"
        return 0
    fi
    [[ -r "$MANIFEST" ]] || die "manifest is missing: $MANIFEST"

    while IFS=$'\t' read -r name url icon_source; do
        [[ -n "$name" && "$name" != \#* ]] || continue
        [[ -n "$url" && -n "$icon_source" ]] || die "manifest line needs name, url, icon: $name"
        validate_url "$url"
        slug=$(slugify "$name")
        keep+=("$slug")
        if [[ -f "$PNG_ICONS_DIR/$PREFIX$slug.png" ]]; then
            icon=$PREFIX$slug
        elif [[ -f "$SVG_ICONS_DIR/$PREFIX$slug.svg" ]]; then
            icon=$PREFIX$slug
        else
            icon=$(install_icon "$slug" "$icon_source" tolerate)
        fi
        write_entry "$name" "$url" "$icon" bundled
    done < "$MANIFEST"

    shopt -s nullglob
    for file in "$APPLICATIONS_DIR/$PREFIX"*.desktop; do
        [[ "$(desktop_field "$file" X-Blankweave-Webapp)" == bundled ]] || continue
        slug=$(basename "$file" .desktop)
        slug=${slug#"$PREFIX"}
        if [[ ! " ${keep[*]} " == *" $slug "* ]]; then
            rm -f "$file"
            remove_icon "$slug"
        fi
    done
    refresh_database
}

main() {
    local command=${1:-}
    shift || true
    case "$command" in
        launch) command_launch "$@" ;;
        install) command_install "$@" ;;
        remove) command_remove "$@" ;;
        list) command_list "$@" ;;
        sync) command_sync "$@" ;;
        *) usage ;;
    esac
}

main "$@"
