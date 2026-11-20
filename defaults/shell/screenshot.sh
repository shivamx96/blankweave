#!/usr/bin/env bash
# Capture in layout coordinates; publish a complete file before touching clipboard.
set -euo pipefail
umask 077
exec 2>/dev/null
mode=${1:-screen}
case "$mode" in screen|region|window) ;; *) exit 2 ;; esac
work=$(mktemp -d) || exit 0
trap 'rm -rf -- "$work"' EXIT
# Close only our previous preview, so a quick second capture excludes it.
state=$work/notification.id
if [[ -n ${XDG_RUNTIME_DIR:-} && -d $XDG_RUNTIME_DIR ]]; then
    state=$XDG_RUNTIME_DIR/blankweave-screenshot.id
fi
if [[ -f $state && ! -L $state ]]; then
    read -r previous < "$state" || true
    [[ ${previous:-} =~ ^[0-9]+$ ]] && dunstctl close "$previous" || true
fi
monitors=$(hyprctl monitors -j) || exit 0
args=()
geometry_filter='select(.size[0] > 0 and .size[1] > 0) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"'
case "$mode" in
    screen)
        output=$(jq -er '.[] | select(.focused == true) | .name' <<< "$monitors") || exit 0
        args=(-o "$output") ;;
    window)
        window=$(hyprctl activewindow -j) || exit 0
        geometry=$(jq -er "$geometry_filter" <<< "$window") || exit 0
        args=(-g "$geometry") ;;
    region)
        clients=$(hyprctl clients -j) || exit 0
        # All visible workspaces, including special workspaces and pinned clients.
        jq -r --argjson monitors "$monitors" '
            [$monitors[] | .activeWorkspace.id, .specialWorkspace.id | select(. != null and . != 0)] as $visible
            | .[] | select(.mapped == true and .hidden != true)
            | select(.pinned == true or (.workspace.id as $id | $visible | index($id)))
            | select(.size[0] > 0 and .size[1] > 0)
            | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"
        ' <<< "$clients" > "$work/rectangles" || exit 0
        geometry=$(slurp < "$work/rectangles") || exit 0
        [[ -n $geometry ]] || exit 0
        args=(-g "$geometry") ;;
esac
grim "${args[@]}" "$work/capture.png" || exit 0
[[ -s $work/capture.png ]] || exit 0
pictures=$(xdg-user-dir PICTURES) || pictures=
[[ $pictures = /* && $pictures != "$HOME" ]] || pictures=$HOME/Pictures
directory=$pictures/Screenshots
# No directory or file changes before a successful capture.
mkdir -p -- "$directory" || exit 0
file=$directory/Screenshot-$(date +%Y%m%d-%H%M%S-%N).png
mv -- "$work/capture.png" "$file" || exit 0
body='Saved and copied to clipboard'
wl-copy --type image/png < "$file" || body='Saved; clipboard unavailable'
# ID and chosen action use separate descriptors. Bound even with DND or a
# notification server that ignores expiry. Actions never keep a waiter alive.
action=$(timeout 16s notify-send --app-name=Blankweave --transient \
    --expire-time=12000 --icon="$file" --hint="string:image-path:$file" \
    --action=default=Open --action=annotate=Annotate --id-fd=3 \
    'Screenshot saved' "$body" 3> "$state") || action=
case "$action" in
    default) xdg-open "$file" >/dev/null 2>&1 & ;;
    annotate) satty --filename "$file" >/dev/null 2>&1 & ;;
esac
