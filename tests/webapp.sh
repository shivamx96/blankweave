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

expect_failure() {
    if "$@" 2> /dev/null; then
        printf 'Expected failure: %s\n' "$*" >&2
        exit 1
    fi
}

# The browser and the icon download are stand-ins: the browser logs its
# arguments, and curl writes a PNG header to -o for a known URL and fails for
# anything else, so the sync's fallback path is exercised without a network.
fake_bin=$test_root/fake-bin
mkdir -p "$fake_bin"
ln -s "$repository/tests/fixtures/fake-log.sh" "$fake_bin/helium-browser"
cat > "$fake_bin/curl" <<'CURL'
#!/usr/bin/env bash
output=
url=
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) output=$2; shift 2 ;;
        http*) url=$1; shift ;;
        *) shift ;;
    esac
done
[[ "$url" == https://icons.test/* ]] || exit 22
printf '\x89PNG\r\n\x1a\n' > "$output"
CURL
chmod +x "$fake_bin/curl"

home=$test_root/home
data=$home/.local/share/blankweave
mkdir -p "$data"
cp -R "$repository/defaults/shell" "$data/"
cp -R "$repository/defaults/webapps" "$data/"

export HOME=$home
export XDG_DATA_HOME=$home/.local/share
export FAKE_LOG=$test_root/side-effects.log
export PATH=$fake_bin:$PATH
: > "$FAKE_LOG"

script=$data/shell/webapp.sh
applications=$XDG_DATA_HOME/applications
png_icons=$XDG_DATA_HOME/icons/hicolor/256x256/apps
svg_icons=$XDG_DATA_HOME/icons/hicolor/scalable/apps
png_icon=$test_root/icon.png
svg_icon=$test_root/icon.svg
printf '\x89PNG\r\n\x1a\n' > "$png_icon"
printf '<?xml version="1.0"?>\n<svg xmlns="http://www.w3.org/2000/svg"/>\n' > "$svg_icon"

field() {
    sed -n "s/^$2=//p" "$1"
}

# launch hands the URL to Helium's app mode and nothing else.
"$script" launch https://example.com/
grep -Fxq 'helium-browser --app=https://example.com/' "$FAKE_LOG"

# A URL that would need quoting in an Exec line is refused rather than escaped.
expect_failure "$script" launch 'https://example.com/"a'
expect_failure "$script" launch ftp://example.com/
expect_failure "$script" install Bad "https://x.test/\$HOME" "$png_icon"

# install writes a desktop entry whose StartupWMClass is the class Chromium
# gives an --app window: chrome-<host>__<path with / as _>-Default.
"$script" install 'Google Messages' https://messages.google.com/web/ "$png_icon" > /dev/null
entry=$applications/blankweave-webapp-google-messages.desktop
[[ -f "$entry" ]]
[[ "$(field "$entry" Name)" == 'Google Messages' ]]
[[ "$(field "$entry" Exec)" == "$script launch https://messages.google.com/web/" ]]
[[ "$(field "$entry" Icon)" == blankweave-webapp-google-messages ]]
[[ "$(field "$entry" StartupWMClass)" == chrome-messages.google.com__web-Default ]]
[[ "$(field "$entry" X-Blankweave-Webapp)" == user ]]
[[ -f "$png_icons/blankweave-webapp-google-messages.png" ]]

# A bare origin yields an empty path segment, a percent sign is doubled for
# the Exec line, and an SVG lands in the scalable directory.
"$script" install 'Notes 100%' 'https://notes.test/?q=1#top' "$svg_icon" > /dev/null
entry=$applications/blankweave-webapp-notes-100.desktop
[[ "$(field "$entry" StartupWMClass)" == chrome-notes.test__-Default ]]
[[ "$(field "$entry" Exec)" == "$script launch https://notes.test/?q=1#top" ]]
[[ -f "$svg_icons/blankweave-webapp-notes-100.svg" ]]
"$script" install 'Notes 100%' 'https://notes.test/' "$png_icon" > /dev/null
[[ ! -f "$svg_icons/blankweave-webapp-notes-100.svg" ]]
[[ -f "$png_icons/blankweave-webapp-notes-100.png" ]]

# Anything but PNG or SVG is refused, and a URL icon that cannot be fetched
# fails a user install outright.
printf 'GIF89a' > "$test_root/icon.gif"
expect_failure "$script" install Gif https://gif.test/ "$test_root/icon.gif"
expect_failure "$script" install Missing https://missing.test/ https://nowhere.test/icon.png
[[ ! -f "$applications/blankweave-webapp-gif.desktop" ]]
[[ ! -f "$applications/blankweave-webapp-missing.desktop" ]]

listing=$("$script" list)
grep -Fq $'google-messages\tGoogle Messages\thttps://messages.google.com/web/\tuser' <<< "$listing"
grep -Fq $'notes-100\tNotes 100%\thttps://notes.test/\tuser' <<< "$listing"

# sync converges the bundled entries: icons are fetched once, an unreachable
# icon degrades to the theme's browser icon instead of failing the apply, and
# a user entry is never touched.
manifest=$test_root/webapps.tsv
export BLANKWEAVE_WEBAPP_MANIFEST=$manifest
cat > "$manifest" <<MANIFEST
# comment
Chat	https://chat.test/rooms/1	https://icons.test/chat.png
Mail	https://mail.test/	https://nowhere.test/mail.png
MANIFEST
"$script" sync 2> /dev/null
entry=$applications/blankweave-webapp-chat.desktop
[[ "$(field "$entry" X-Blankweave-Webapp)" == bundled ]]
[[ "$(field "$entry" StartupWMClass)" == chrome-chat.test__rooms_1-Default ]]
[[ "$(field "$entry" Icon)" == blankweave-webapp-chat ]]
[[ -f "$png_icons/blankweave-webapp-chat.png" ]]
[[ "$(field "$applications/blankweave-webapp-mail.desktop" Icon)" == web-browser ]]
[[ -f "$applications/blankweave-webapp-google-messages.desktop" ]]

# Once the icon is present the sync does not download it again.
rm "$fake_bin/curl"
"$script" sync 2> /dev/null
[[ -f "$png_icons/blankweave-webapp-chat.png" ]]

# Dropping a site from the manifest removes its bundled entry only.
printf 'Chat\thttps://chat.test/rooms/1\thttps://icons.test/chat.png\n' > "$manifest"
"$script" sync 2> /dev/null
[[ ! -f "$applications/blankweave-webapp-mail.desktop" ]]
[[ -f "$applications/blankweave-webapp-chat.desktop" ]]
[[ -f "$applications/blankweave-webapp-google-messages.desktop" ]]

# A malformed manifest line stops the sync before anything is written.
printf 'Broken\thttps://broken.test/\n' > "$manifest"
expect_failure "$script" sync
[[ ! -f "$applications/blankweave-webapp-broken.desktop" ]]

# remove clears the entry and its icon, and refuses an unknown name.
"$script" remove 'Google Messages' > /dev/null
[[ ! -f "$applications/blankweave-webapp-google-messages.desktop" ]]
[[ ! -f "$png_icons/blankweave-webapp-google-messages.png" ]]
expect_failure "$script" remove 'Google Messages'

# Without Helium a sync is a no-op that still succeeds, so an apply on a
# machine without the desktop profile is not held up, and launch says why.
# The browser is named explicitly so a Helium on the developer's PATH cannot
# stand in for the missing one.
export BLANKWEAVE_WEBAPP_BROWSER=$test_root/no-such-browser
rm -f "$applications"/blankweave-webapp-*.desktop
"$script" sync > /dev/null
[[ -z "$(find "$applications" -name 'blankweave-webapp-*.desktop')" ]]
expect_failure "$script" launch https://example.com/

# The bundled manifest itself is well formed: three tab-separated fields
# with an https site and an https PNG or SVG icon on every entry.
while IFS=$'\t' read -r name url icon extra; do
    [[ -n "$name" && "$name" != \#* ]] || continue
    [[ -z "${extra:-}" ]] || { printf 'Extra manifest field: %s\n' "$name" >&2; exit 1; }
    [[ "$url" =~ ^https:// ]] || { printf 'Bad URL for %s\n' "$name" >&2; exit 1; }
    [[ "$icon" =~ ^https://.*\.(png|svg)$ ]] || { printf 'Bad icon for %s\n' "$name" >&2; exit 1; }
done < "$repository/defaults/webapps/webapps.tsv"

printf 'webapp tests passed\n'
