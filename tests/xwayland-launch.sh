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

script=$repository/defaults/shell/xwayland-launch.sh
fake_bin=$test_root/bin
mkdir -p "$fake_bin"
export PATH=$fake_bin:$PATH
export MONITORS_JSON=$test_root/monitors.json

# The compositor stand-in answers `hyprctl monitors -j` from a file.
cat > "$fake_bin/hyprctl" <<'HYPRCTL'
#!/usr/bin/env bash
[[ "$*" == "monitors -j" ]] || exit 1
cat "$MONITORS_JSON"
HYPRCTL
chmod +x "$fake_bin/hyprctl"

# The launched command reports the environment it received.
cat > "$fake_bin/report-env" <<'REPORT'
#!/usr/bin/env bash
printf 'scaling=%s cursor=%s args=%s\n' \
    "${STEAM_FORCE_DESKTOPUI_SCALING:-unset}" "${XCURSOR_SIZE:-unset}" "$*"
REPORT
chmod +x "$fake_bin/report-env"

# The focused monitor's scale wins, and the cursor grows with it.
cat > "$MONITORS_JSON" <<'JSON'
[
 {"name":"eDP-1","scale":2.0,"focused":false},
 {"name":"DP-1","scale":1.5,"focused":true}
]
JSON
output=$(XCURSOR_SIZE=24 "$script" report-env --one two)
[[ $output == 'scaling=1.5 cursor=36 args=--one two' ]] || {
    printf 'Unexpected focused-monitor result: %s\n' "$output" >&2
    exit 1
}

# Without a focused monitor the first one listed is used.
cat > "$MONITORS_JSON" <<'JSON'
[{"name":"DP-1","scale":2,"focused":false}]
JSON
output=$(XCURSOR_SIZE=24 "$script" report-env)
[[ $output == 'scaling=2 cursor=48 args=' ]] || {
    printf 'Unexpected first-monitor result: %s\n' "$output" >&2
    exit 1
}

# A missing or unusable compositor answer falls back to 1x untouched.
printf 'not json\n' > "$MONITORS_JSON"
output=$(XCURSOR_SIZE=24 "$script" report-env)
[[ $output == 'scaling=1 cursor=24 args=' ]] || {
    printf 'Unexpected fallback result: %s\n' "$output" >&2
    exit 1
}
# A compositor that cannot answer at all (no session) is the same fallback.
printf '#!/usr/bin/env bash\nexit 1\n' > "$fake_bin/hyprctl"
output=$(XCURSOR_SIZE=32 "$script" report-env)
[[ $output == 'scaling=1 cursor=32 args=' ]] || {
    printf 'Unexpected no-compositor result: %s\n' "$output" >&2
    exit 1
}

# The wrapper replaces itself with the command, so its exit status is passed on.
if "$script" false; then
    printf 'Expected the launched command status to propagate.\n' >&2
    exit 1
fi
if "$script" 2> /dev/null; then
    printf 'Expected usage failure without a command.\n' >&2
    exit 1
fi

# The Steam entry is a complete shadow of the packaged one: it keeps the URL
# handler and every launch path goes through the wrapper.
entry=$repository/defaults/applications/steam.desktop
grep -qx 'MimeType=x-scheme-handler/steam;x-scheme-handler/steamlink;' "$entry"
grep -qx 'X-Blankweave-Entry=steam' "$entry"
if grep -E '^Exec=' "$entry" | grep -qv '^Exec=@BLANKWEAVE_SHELL_DIR@/xwayland-launch.sh /usr/bin/steam'; then
    printf 'Every Exec line must go through the wrapper.\n' >&2
    exit 1
fi
rendered=$(sed "s|@BLANKWEAVE_SHELL_DIR@|/home/example/.local/share/blankweave/shell|g" "$entry")
if grep -q '@BLANKWEAVE_SHELL_DIR@' <<< "$rendered"; then
    printf 'Rendering must replace every placeholder.\n' >&2
    exit 1
fi
grep -qx 'Exec=/home/example/.local/share/blankweave/shell/xwayland-launch.sh /usr/bin/steam %U' <<< "$rendered"

# The Hyprland defaults leave XWayland unscaled.
grep -q 'force_zero_scaling = true' "$repository/defaults/hypr/hyprland.lua"
