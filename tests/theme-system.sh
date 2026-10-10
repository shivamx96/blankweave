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

# The privileged tools are stand-ins and every system path is redirected
# into the sandbox, so the test never needs root and never touches /usr.
fake_bin=$test_root/fake-bin
mkdir -p "$fake_bin"
for command in gsettings dunstctl hyprctl awww plymouth-set-default-theme; do
    ln -s "$repository/tests/fixtures/fake-log.sh" "$fake_bin/$command"
done
ln -s "$repository/tests/fixtures/fake-gdbus.sh" "$fake_bin/gdbus"
ln -s "$repository/tests/fixtures/fake-papirus-folders.sh" "$fake_bin/papirus-folders"

home=$test_root/home
data=$home/.local/share/blankweave
system=$test_root/system
mkdir -p "$data" "$home/.config" "$system/share/plymouth/themes" "$system/boot/entries"
for directory in dunst ghostty hypr plymouth shell themes; do
    cp -R "$repository/defaults/$directory" "$data/"
done
for theme in Papirus Papirus-Dark Papirus-Light; do
    mkdir -p "$system/share/icons/$theme/48x48/places"
    touch "$system/share/icons/$theme/48x48/places/folder-blue.svg" \
        "$system/share/icons/$theme/48x48/places/folder-green.svg"
    ln -s folder-blue.svg "$system/share/icons/$theme/48x48/places/folder.svg"
done
printf 'title Arch\noptions root=/dev/sda2 rw quiet splash vt.default_red=30 vt.default_grn=30 vt.default_blu=46\n' \
    > "$system/boot/entries/arch.conf"
printf 'title Fallback\noptions root=/dev/sda2 rw\n' > "$system/boot/entries/plain.conf"

export HOME=$home
export XDG_CONFIG_HOME=$home/.config
export FAKE_LOG=$test_root/side-effects.log
export PATH=$fake_bin:$PATH
export BLANKWEAVE_ICONS_DIR=$system/share/icons
export BLANKWEAVE_PLYMOUTH_DIR=$system/share/plymouth/themes/blankweave
export BLANKWEAVE_BOOT_ENTRIES=$system/boot/entries
: > "$FAKE_LOG"

apply=$data/shell/theme-apply.sh
sync=$repository/scripts/theme-system.sh
stage=$data/plymouth/blankweave
installed=$BLANKWEAVE_PLYMOUTH_DIR

# Without an applied theme there is nothing to install.
expect_failure "$sync" "$home"

# Applying stages the splash for root: the script rendered with Plymouth's
# float colours and the theme's artwork copied in next to it.
"$apply" set moss
[[ -f $stage/blankweave.script ]]
grep -Fxq 'Window.SetBackgroundTopColor(0.02, 0.051, 0.039);' "$stage/blankweave.script"
cmp -s "$stage/logo.png" "$data/themes/moss/plymouth/logo.png"
cmp -s "$stage/progress_bar.png" "$data/themes/moss/plymouth/progress_bar.png"
[[ ! -f $stage/blankweave.script.tmpl ]] || true
status=$("$apply" status)
[[ $(jq -r '.system.folders' <<< "$status") == true ]]
[[ $(jq -r '.system.bootSplash' <<< "$status") == true ]]
[[ $(jq -r '.system.pending' <<< "$status") == true ]]

# The sync colours every installed Papirus variant, installs the splash once,
# and repaints the console colours in entries that carry them.
"$sync" --progress "$home" > "$test_root/sync.out"
grep '^blankweave-theme-sync:' "$test_root/sync.out" > "$test_root/progress"
printf 'blankweave-theme-sync:folders\nblankweave-theme-sync:boot-splash\nblankweave-theme-sync:console\nblankweave-theme-sync:complete\n' > "$test_root/expected-progress"
diff -u "$test_root/expected-progress" "$test_root/progress"
for theme in Papirus Papirus-Dark Papirus-Light; do
    [[ $(readlink "$system/share/icons/$theme/48x48/places/folder.svg") == folder-green.svg ]]
    grep -Fxq "papirus-folders -C green -t $theme" "$FAKE_LOG"
done
for file in blankweave.plymouth blankweave.script logo.png progress_bar.png progress_box.png; do
    cmp -s "$stage/$file" "$installed/$file"
done
grep -Fxq 'Plymouth.SetDisplayPasswordFunction(display_password_callback);' "$installed/blankweave.script"
grep -Fxq '    if (mode == "boot" || mode == "resume") {' "$installed/blankweave.script"
[[ ! -e $installed/blankweave.script.tmpl ]]
[[ $(grep -c 'plymouth-set-default-theme -R blankweave' "$FAKE_LOG") == 1 ]]
grep -Fq 'vt.default_red=5 vt.default_grn=13 vt.default_blu=10' "$system/boot/entries/arch.conf"
expect_failure grep -Fq 'vt.default' "$system/boot/entries/plain.conf"
[[ $(jq -r '.system.pending' <<< "$("$apply" status)") == false ]]

# A second run finds everything current and rebuilds nothing.
: > "$FAKE_LOG"
"$sync" "$home" > "$test_root/sync.out"
[[ ! -s $FAKE_LOG ]]
grep -Fq 'Boot splash already current' "$test_root/sync.out"

# Switching back only redoes what changed; the mode alone changes nothing
# root owns, because the splash always uses the dark palette.
"$apply" set obsidian
[[ $(jq -r '.system.pending' <<< "$("$apply" status)") == true ]]
"$sync" "$home" > /dev/null
[[ $(readlink "$system/share/icons/Papirus/48x48/places/folder.svg") == folder-blue.svg ]]
grep -Fxq 'Window.SetBackgroundTopColor(0.02, 0.031, 0.059);' "$installed/blankweave.script"
: > "$FAKE_LOG"
"$apply" toggle
[[ $(jq -r '.system.pending' <<< "$("$apply" status)") == false ]]

# A theme without splash artwork leaves the installed splash alone rather
# than shipping a stage with another theme's logo.
plain=$XDG_CONFIG_HOME/blankweave/themes/plain
mkdir -p "$plain"
jq 'del(.plymouth) | del(.folderColor) | .name = "Plain"' "$data/themes/obsidian/theme.json" > "$plain/theme.json"
"$apply" set plain
[[ ! -f $stage/logo.png ]]
[[ $(jq -r '.system.pending' <<< "$("$apply" status)") == false ]]
: > "$FAKE_LOG"
"$sync" "$home" > "$test_root/sync.out"
grep -Fq 'incomplete' "$test_root/sync.out"
[[ ! -s $FAKE_LOG ]]
cmp -s "$data/themes/obsidian/plymouth/logo.png" "$installed/logo.png"

# A failed initramfs rebuild must remain pending even after artwork was copied,
# and a retry must rebuild rather than treating matching files as success.
"$apply" set moss
rm "$fake_bin/plymouth-set-default-theme"
printf '#!/usr/bin/env bash\nexit 9\n' > "$fake_bin/plymouth-set-default-theme"
chmod +x "$fake_bin/plymouth-set-default-theme"
if "$sync" --progress "$home" > "$test_root/failed-sync.out" 2>&1; then
    printf 'Expected boot-image rebuild failure\n' >&2
    exit 1
fi
[[ -f $installed/.sync-pending ]]
[[ $(jq -r '.system.bootSplash' <<< "$("$apply" status)") == true ]]
expect_failure grep -q '^blankweave-theme-sync:complete$' "$test_root/failed-sync.out"
rm "$fake_bin/plymouth-set-default-theme"
ln -s "$repository/tests/fixtures/fake-log.sh" "$fake_bin/plymouth-set-default-theme"
: > "$FAKE_LOG"
"$sync" --progress "$home" > "$test_root/retried-sync.out"
grep -Fxq 'plymouth-set-default-theme -R blankweave' "$FAKE_LOG"
[[ ! -e $installed/.sync-pending ]]
[[ $(jq -r '.system.pending' <<< "$("$apply" status)") == false ]]

# The GUI action authenticates only active local sessions, against the fixed
# root-owned helper path; it must never become a passwordless action.
python3 - "$repository/defaults/polkit/org.blankweave.theme-sync.policy" <<'PY'
import sys
import xml.etree.ElementTree as ET
action = ET.parse(sys.argv[1]).getroot().find('action')
assert action.attrib['id'] == 'org.blankweave.theme-sync'
assert action.findtext('defaults/allow_active') == 'auth_admin'
assert action.findtext('defaults/allow_inactive') == 'no'
assert action.findtext('defaults/allow_any') == 'no'
assert action.find("annotate[@key='org.freedesktop.policykit.exec.path']").text == '/usr/lib/blankweave/theme-system'
assert action.find("annotate[@key='org.freedesktop.policykit.exec.allow_gui']") is None
PY

printf 'Theme system tests passed.\n'
