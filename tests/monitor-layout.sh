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

fake_bin=$test_root/fake-bin
mkdir -p "$fake_bin"
ln -s "$repository/tests/fixtures/fake-hyprctl.sh" "$fake_bin/hyprctl"

monitors=$test_root/monitors.json
cat > "$monitors" <<'JSON'
[
  {"name": "eDP-1", "description": "Samsung Display Corp. 0x4170", "x": 0, "y": 0, "width": 2880, "height": 1800, "scale": 1.6},
  {"name": "DP-3", "description": "LG Electronics LG HDR 4K 0x000596ED", "x": 1800, "y": 0, "width": 3840, "height": 2160, "scale": 1.5}
]
JSON

export XDG_CONFIG_HOME=$test_root/config
export FAKE_HYPRCTL_MONITORS=$monitors
export FAKE_HYPRCTL_LOG=$test_root/eval.log
export PATH=$fake_bin:$PATH

script=$repository/defaults/shell/monitor-layout.sh
config=$XDG_CONFIG_HOME/blankweave/monitors.json
rules=$XDG_CONFIG_HOME/blankweave/monitors.lua

# Status without any persisted choice reports every monitor as automatic and
# recognises the internal panel.
status=$("$script" status)
[[ $(jq -r '.monitors | length' <<< "$status") == 2 ]]
[[ $(jq -r '.monitors[0].internal' <<< "$status") == true ]]
[[ $(jq -r '.monitors[1].internal' <<< "$status") == false ]]
[[ $(jq -r '.monitors[1].position' <<< "$status") == auto ]]
[[ $(jq -r '.monitors[0].scale' <<< "$status") == 1.6 ]]
[[ $(jq -r '.monitors[0].effectiveScale' <<< "$status") == 1.6 ]]
jq -e '.monitors[0].scaleOptions == [1, 1.2, 1.25, 1.5, 1.6, 1.8, 2, 2.25, 2.5, 3]' \
    <<< "$status" >/dev/null
jq -e '.monitors[0].scaleOptions | index(1.4) == null' <<< "$status" >/dev/null
[[ ! -e $config ]]

# Choosing a position persists it by description with the live scale frozen
# in, generates a desc: rule, and applies it through hyprctl eval.
"$script" set DP-3 left
[[ $(jq -r '.monitors | length' "$config") == 1 ]]
[[ $(jq -r '.monitors[0].description' "$config") == 'LG Electronics LG HDR 4K 0x000596ED' ]]
[[ $(jq -r '.monitors[0].position' "$config") == auto-left ]]
[[ $(jq -r '.monitors[0].scale' "$config") == 1.5 ]]
[[ $(jq -r '.monitors[0].scaleExplicit' "$config") == false ]]
grep -Fxq 'hl.monitor({ output = "desc:LG Electronics LG HDR 4K 0x000596ED", mode = "preferred", position = "auto-left", scale = 1.5 })' "$rules"
grep -Fq "dofile(\"$rules\")" "$FAKE_HYPRCTL_LOG"
[[ $(jq -r '.monitors[1].position' <<< "$("$script" status)") == left ]]

# Re-choosing replaces the entry rather than adding a second one.
"$script" set DP-3 above
[[ $(jq -r '.monitors | length' "$config") == 1 ]]
[[ $(jq -r '.monitors[0].position' "$config") == auto-up ]]
[[ $(grep -c '^hl.monitor' "$rules") == 1 ]]

# A second monitor keeps its own entry.
"$script" set eDP-1 below
[[ $(jq -r '.monitors | length' "$config") == 2 ]]
[[ $(grep -c '^hl.monitor' "$rules") == 2 ]]

# Auto removes the entry and places the monitor automatically for this session.
: > "$FAKE_HYPRCTL_LOG"
"$script" set DP-3 auto
[[ $(jq -r '.monitors | length' "$config") == 1 ]]
[[ $(jq -r '.monitors[0].description' "$config") == 'Samsung Display Corp. 0x4170' ]]
if grep -q 'LG HDR' "$rules"; then
    printf 'Auto must drop the generated rule.\n' >&2
    exit 1
fi
grep -Fq 'position = "auto"' "$FAKE_HYPRCTL_LOG"
[[ $(jq -r '.monitors[1].position' <<< "$("$script" status)") == auto ]]

# Scaling is available on every connected display. An explicit choice is
# persisted alongside the current position, applied live, and reflected in
# status independently of the compositor's effective scale snapshot.
"$script" set-scale DP-3 1.6
[[ $(jq -r '.monitors | length' "$config") == 2 ]]
[[ $(jq -r '.monitors[] | select(.description | startswith("LG ")) | .position' "$config") == auto ]]
[[ $(jq -r '.monitors[] | select(.description | startswith("LG ")) | .scale' "$config") == 1.6 ]]
[[ $(jq -r '.monitors[] | select(.description | startswith("LG ")) | .scaleExplicit' "$config") == true ]]
grep -Fxq 'hl.monitor({ output = "desc:LG Electronics LG HDR 4K 0x000596ED", mode = "preferred", position = "auto", scale = 1.6 })' "$rules"
status=$("$script" status)
[[ $(jq -r '.monitors[1].scale' <<< "$status") == 1.6 ]]
[[ $(jq -r '.monitors[1].effectiveScale' <<< "$status") == 1.5 ]]

# Position changes retain an explicitly selected scale, and choosing automatic
# placement keeps that scale rule instead of deleting it.
"$script" set DP-3 right
[[ $(jq -r '.monitors[] | select(.description | startswith("LG ")) | .position' "$config") == auto-right ]]
[[ $(jq -r '.monitors[] | select(.description | startswith("LG ")) | .scale' "$config") == 1.6 ]]
"$script" set DP-3 auto
[[ $(jq -r '.monitors | length' "$config") == 2 ]]
[[ $(jq -r '.monitors[] | select(.description | startswith("LG ")) | .position' "$config") == auto ]]

# Hyprland's automatic PPI-derived scale is emitted as a Lua string and also
# survives later position changes.
"$script" set-scale DP-3 auto
[[ $(jq -r '.monitors[] | select(.description | startswith("LG ")) | .scale' "$config") == auto ]]
grep -Fxq 'hl.monitor({ output = "desc:LG Electronics LG HDR 4K 0x000596ED", mode = "preferred", position = "auto", scale = "auto" })' "$rules"
"$script" set DP-3 above
grep -Fxq 'hl.monitor({ output = "desc:LG Electronics LG HDR 4K 0x000596ED", mode = "preferred", position = "auto-up", scale = "auto" })' "$rules"

# Invalid input is rejected before anything is written or applied.
: > "$FAKE_HYPRCTL_LOG"
before=$(cat "$config")
for arguments in 'DP-3 sideways' 'DP-9 left' 'DP-3'; do
    # shellcheck disable=SC2086
    if "$script" set $arguments 2>/dev/null; then
        printf 'Invalid input "%s" must be rejected.\n' "$arguments" >&2
        exit 1
    fi
done
for arguments in 'DP-3 1.4' 'DP-9 1.5' 'DP-3 banana' 'DP-3'; do
    # shellcheck disable=SC2086
    if "$script" set-scale $arguments 2>/dev/null; then
        printf 'Invalid scale input "%s" must be rejected.\n' "$arguments" >&2
        exit 1
    fi
done
[[ $(cat "$config") == "$before" ]]
[[ ! -s $FAKE_HYPRCTL_LOG ]]

# A corrupt config counts as empty instead of breaking status.
printf 'not json' > "$config"
[[ $(jq -r '.monitors[1].position' <<< "$("$script" status)") == auto ]]

printf 'Monitor layout script tests passed.\n'
