#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin"
export XDG_CONFIG_HOME=$test_root/config
export LAYOUT_TEST_STATE=$test_root/monitors.json
export LAYOUT_TEST_LOG=$test_root/commands
export PATH=$test_root/bin:$PATH
ln -s "$repository/tests/fixtures/hyprctl-layout.py" "$test_root/bin/hyprctl"
cat > "$LAYOUT_TEST_STATE" <<'JSON'
[
 {"id":0,"name":"eDP-1","description":"Laptop","width":2880,"height":1800,"refreshRate":90,"scale":1.5,"x":0,"y":0,"mirrorOf":"none","transform":0,"availableModes":["2880x1800@90.00Hz","2880x1800@60.00Hz"]},
 {"id":1,"name":"DP-3","description":"Desk monitor","width":1920,"height":1080,"refreshRate":60,"scale":1,"x":1920,"y":0,"mirrorOf":"none","transform":1,"availableModes":["1920x1080@60.00Hz"]}
]
JSON
cp "$LAYOUT_TEST_STATE" "$test_root/original"
script=$repository/defaults/shell/monitor-layout.sh
pending=$XDG_CONFIG_HOME/blankweave/.monitor-mode-preview.json
store=$XDG_CONFIG_HOME/blankweave/monitor-setups.json
config=$XDG_CONFIG_HOME/blankweave/monitors.json
token() { jq -r .token "$pending"; }

"$script" preset-save Desk
desk=$(jq -r '.setups[0].id' "$store")
"$script" status | jq -e '.presets[0].available and (.presets[0].name == "Desk")' >/dev/null
[[ ! -e $config && ! -e $LAYOUT_TEST_LOG ]]
if "$script" preset-save 'desk' 2>/dev/null; then exit 1; fi
if "$script" preset-save '' 2>/dev/null; then exit 1; fi
if "$script" preset-save $'bad\nname' 2>/dev/null; then exit 1; fi

# Capture by description; switching ports retains compatibility.
jq '.[1].name = "DP-7"' "$LAYOUT_TEST_STATE" > "$test_root/reconnected"
mv "$test_root/reconnected" "$LAYOUT_TEST_STATE"
"$script" status | jq -e '.presets[0].available' >/dev/null
if "$script" mirror-preview DP-7 DP-7 2>/dev/null; then exit 1; fi
if "$script" mirror-preview DP-7 missing 2>/dev/null; then exit 1; fi
[[ ! -e $pending && ! -e $LAYOUT_TEST_LOG ]]

# A real-shaped mirror ID is mapped to its connector; the mirror remains listed.
"$script" mirror-preview DP-7 eDP-1
"$script" status | jq -e '(.monitors | length) == 2 and .monitors[1].mirrorConnector == "eDP-1" and .preview.kind == "layout"' >/dev/null
[[ ! -e $config ]]
if "$script" preset-save Temporary 2>/dev/null; then exit 1; fi
if "$script" set-scale DP-7 1 2>/dev/null; then exit 1; fi
"$script" mode-confirm "$(token)"
jq -e '.monitors[0].mirror == "Laptop" and .monitors[0].transform == 1 and (.monitors | length) == 1' "$config" >/dev/null
if "$script" set DP-7 left 2>/dev/null; then exit 1; fi
if "$script" mode-preview DP-7 1920x1080@60.00 2>/dev/null; then exit 1; fi
if "$script" mirror-preview eDP-1 DP-7 2>/dev/null; then exit 1; fi
"$script" preset-save Presentation
presentation=$(jq -r '.setups[1].id' "$store")

# Extending a mirror is previewed; revert restores the mirroring relationship.
"$script" mirror-preview DP-7 none
jq -e '.[1].mirrorOf == "none" and .[1].x == 1920' "$LAYOUT_TEST_STATE" >/dev/null
"$script" mode-revert "$(token)"
jq -e '.[1].mirrorOf == "0"' "$LAYOUT_TEST_STATE" >/dev/null

# Restore saved coordinates and rotation, keep them, then preserve mirror rules
# through later scale changes on the source.
"$script" preset-preview "$desk"
jq -e '.[1].mirrorOf == "none" and .[1].x == 1920 and .[1].transform == 1' "$LAYOUT_TEST_STATE" >/dev/null
"$script" mode-confirm "$(token)"
"$script" preset-preview "$presentation"
"$script" mode-confirm "$(token)"
"$script" set-scale eDP-1 1.5
jq -e '.[1].mirrorOf == "0"' "$LAYOUT_TEST_STATE" >/dev/null
"$script" preset-preview "$desk"
"$script" mode-confirm "$(token)"
saved=$(cat "$config")

# Silently ignored mirroring must fail, restore live state, and leave saves alone.
if LAYOUT_IGNORE_MIRROR=1 "$script" mirror-preview DP-7 eDP-1 2>/dev/null; then exit 1; fi
[[ ! -e $pending && $(cat "$config") == "$saved" ]]
jq -e '.[1].mirrorOf == "none"' "$LAYOUT_TEST_STATE" >/dev/null

# The independent watchdog restores the whole layout without UI participation.
"$script" mirror-preview DP-7 eDP-1
for ((attempt=0; attempt<130; attempt++)); do
    [[ -e $pending ]] || break
    sleep .2
done
[[ ! -e $pending && $(cat "$config") == "$saved" ]]
jq -e '.[1].mirrorOf == "none" and .[1].x == 1920' "$LAYOUT_TEST_STATE" >/dev/null

# Missing outputs and unsupported modes are explained; invalid restores do not
# touch the compositor. Unplugging during preview still permits rollback.
"$script" mirror-preview DP-7 eDP-1
jq '[.[0]]' "$LAYOUT_TEST_STATE" > "$test_root/unplugged"
mv "$test_root/unplugged" "$LAYOUT_TEST_STATE"
if "$script" mode-confirm "$(token)" 2>/dev/null; then exit 1; fi
"$script" mode-revert "$(token)"
"$script" status | jq -e '(.presets[0].available | not) and (.presets[0].reason | contains("same displays"))' >/dev/null
before=$(cat "$LAYOUT_TEST_LOG")
if "$script" preset-preview "$desk" 2>/dev/null; then exit 1; fi
[[ $(cat "$LAYOUT_TEST_LOG") == "$before" ]]
cp "$test_root/original" "$LAYOUT_TEST_STATE"
jq '.[1].availableModes = []' "$LAYOUT_TEST_STATE" > "$test_root/unsupported"
mv "$test_root/unsupported" "$LAYOUT_TEST_STATE"
"$script" status | jq -e '(.presets[0].available | not) and (.presets[0].reason | contains("no longer supported"))' >/dev/null

"$script" preset-delete "$desk"
[[ $(jq '.setups | length' "$store") == 1 ]]
if "$script" preset-delete "$desk" 2>/dev/null; then exit 1; fi
"$script" preset-delete "$presentation"
[[ $(jq '.setups | length' "$store") == 0 ]]
printf 'bad json' > "$store"
if "$script" preset-save Recover 2>/dev/null; then exit 1; fi
[[ $(cat "$store") == 'bad json' ]]
printf 'Display mirroring and saved setup tests passed.\n'
