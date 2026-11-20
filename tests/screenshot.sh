#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
testroot=$(mktemp -d)
trap 'rm -rf -- "$testroot"' EXIT
export HOME=$testroot/home XDG_RUNTIME_DIR=$testroot/run TESTROOT=$testroot
mkdir -p "$testroot/bin" "$HOME" "$XDG_RUNTIME_DIR"
export PATH="$testroot/bin:$PATH"
# Every graphical command is a stub, including helpers triggered by actions.
cat > "$testroot/bin/stub" <<'STUB'
#!/usr/bin/env bash
set -eu
name=${0##*/}
printf '%s' "$name" >> "$TESTROOT/log"
printf ' <%s>' "$@" >> "$TESTROOT/log"
printf '\n' >> "$TESTROOT/log"
[[ ${FAIL:-} != "$name" ]] || exit 1
case "$name" in
hyprctl)
 case "$1" in
 monitors) echo '[{"name":"DP-1","focused":false,"activeWorkspace":{"id":1}},{"name":"DP-2","focused":true,"activeWorkspace":{"id":2},"specialWorkspace":{"id":-99}}]' ;;
 activewindow) echo '{"at":[-100,20],"size":[600,400]}' ;;
 clients) echo '[{"mapped":true,"at":[10,20],"size":[300,200],"workspace":{"id":1}},{"mapped":true,"at":[-50,40],"size":[500,250],"workspace":{"id":2}},{"mapped":true,"at":[0,0],"size":[50,50],"workspace":{"id":3}},{"mapped":true,"at":[1,2],"size":[30,40],"workspace":{"id":-99}},{"mapped":true,"pinned":true,"at":[3,4],"size":[20,30],"workspace":{"id":4}},{"mapped":true,"hidden":true,"at":[9,9],"size":[9,9],"workspace":{"id":1}}]' ;;
 *) exit 90 ;;
 esac ;;
slurp) cat > "$TESTROOT/rectangles"; [[ ${CANCEL:-0} != 1 ]] || exit 1; echo '-50,40 500x250' ;;
grim) printf PNG > "${@: -1}"; [[ ${EMPTY:-0} != 1 ]] || : > "${@: -1}" ;;
wl-copy)
 files=("$HOME"/Pictures/Screenshots/*.png)
 [[ -s ${files[0]} ]] || exit 91
 cat > "$TESTROOT/clipboard"; cmp "${files[0]}" "$TESTROOT/clipboard" ;;
xdg-user-dir) echo "$HOME/Pictures" ;;
notify-send) echo 123 >&3; printf '%s' "${ACTION:-}" ;;
esac
STUB
chmod +x "$testroot/bin/stub"
for name in grim slurp wl-copy hyprctl notify-send xdg-user-dir satty xdg-open dunstctl; do
 ln -s stub "$testroot/bin/$name"
done
reset_case() {
 rm -rf "$HOME/Pictures" "$testroot/clipboard" "$testroot/rectangles" "${XDG_RUNTIME_DIR:?}"/*
 : > "$testroot/log"
 unset FAIL CANCEL EMPTY ACTION
}
run() { bash "$repo/defaults/shell/screenshot.sh" "$1" </dev/null; }
reset_case
run screen
grep -q 'grim <-o> <DP-2>' "$testroot/log"
grep -q 'wl-copy <--type> <image/png>' "$testroot/log"
grep -q 'notify-send <--app-name=Blankweave> <--transient> <--expire-time=12000>' "$testroot/log"
grep -q '<--action=default=Open> <--action=annotate=Annotate> <--id-fd=3>' "$testroot/log"
grep -q '<--hint=string:image-path:' "$testroot/log"
[[ $(cat "$testroot/clipboard") == PNG ]]
run screen
grep -q 'dunstctl <close> <123>' "$testroot/log"
reset_case
run region
printf '10,20 300x200\n-50,40 500x250\n1,2 30x40\n3,4 20x30\n' > "$testroot/expected"
cmp "$testroot/expected" "$testroot/rectangles"
grep -q 'grim <-g> <-50,40 500x250>' "$testroot/log"
reset_case
run window
grep -q 'grim <-g> <-100,20 600x400>' "$testroot/log"
for failure in cancel grim slurp hyprctl empty; do
 reset_case
 echo previous > "$testroot/clipboard"
 case "$failure" in cancel) export CANCEL=1 ;; empty) export EMPTY=1 ;; *) export FAIL=$failure ;; esac
 run region
 [[ ! -e $HOME/Pictures ]]
 [[ $(cat "$testroot/clipboard") == previous ]]
 if grep -q '^wl-copy\|^notify-send' "$testroot/log"; then exit 1; fi
done
# Cancellation preserves an existing screenshots directory byte for byte too.
reset_case
mkdir -p "$HOME/Pictures/Screenshots"
echo keep > "$HOME/Pictures/Screenshots/existing.png"
echo previous > "$testroot/clipboard"
export CANCEL=1
run region
[[ $(cat "$HOME/Pictures/Screenshots/existing.png") == keep ]]
[[ $(find "$HOME/Pictures/Screenshots" -type f | wc -l) == 1 ]]
[[ $(cat "$testroot/clipboard") == previous ]]
reset_case
export FAIL=xdg-user-dir
run screen
[[ -d $HOME/Pictures/Screenshots ]]
reset_case
export FAIL=wl-copy
run screen
grep -q 'Saved; clipboard unavailable' "$testroot/log"
reset_case
export FAIL=notify-send
run screen
[[ -s $testroot/clipboard ]]
printf 'Screenshot tests passed\n'
