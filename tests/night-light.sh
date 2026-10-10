#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/home" "$test_root/runtime" "$test_root/shell/Services"
chmod 700 "$test_root/runtime"
export HOME=$test_root/home XDG_CONFIG_HOME=$test_root/home/.config XDG_RUNTIME_DIR=$test_root/runtime
export NIGHT_LIGHT_TEST_STATE=$test_root/daemon
export PATH=$test_root/bin:$PATH
ln -s "$repository/tests/fixtures/night-light-daemon.py" "$test_root/bin/hyprctl"
ln -s "$repository/tests/fixtures/night-light-daemon.py" "$test_root/bin/hyprsunset"
helper=$repository/defaults/shell/night-light.py
python3 "$helper" status | jq -e '.available and .preferences.mode == "off" and .temperature == -1' >/dev/null
for args in 'bad 4500 21:00 07:00' 'always 1000 21:00 07:00' 'schedule 4500 29:00 07:00' 'schedule 4500 21:00 21:00'; do
    read -ra values <<< "$args"
    if python3 "$helper" set "${values[@]}" >/dev/null 2>&1; then exit 1; fi
done
[[ ! -e $XDG_CONFIG_HOME/blankweave/night-light.json ]]
# A foreign daemon is read but never replaced or mutated.
printf '{"temperature":5000,"identity":true}' > "$NIGHT_LIGHT_TEST_STATE"
python3 "$helper" status | jq -e '.identity and .temperature == 5000' >/dev/null
python3 "$helper" set always 4500 21:00 07:00
if python3 "$helper" run > "$test_root/conflict" 2>&1; then exit 1; fi
grep -q 'Another night-light service' "$test_root/conflict"
jq -e '.identity and .temperature == 5000' "$NIGHT_LIGHT_TEST_STATE" >/dev/null
rm "$NIGHT_LIGHT_TEST_STATE"
python3 "$helper" set off 4500 21:00 07:00
cp "$helper" "$test_root/shell/night-light.py"
cp "$repository/defaults/quickshell/Services/SettingsNightLight.qml" "$test_root/shell/Services/"
cp "$repository/tests/quickshell/settings-night-light.qml" "$test_root/shell/shell.qml"
if ! QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software timeout 20 qs -p "$test_root/shell" > "$test_root/log" 2>&1; then
    cat "$test_root/log"
    exit 1
fi
if ! grep -q SETTINGS_NIGHT_LIGHT_PASSED "$test_root/log" || grep -Eq '(TypeError|ReferenceError|Binding loop|Unable to assign|Failed to load)' "$test_root/log"; then
    cat "$test_root/log"
    exit 1
fi
[[ $(wc -l < "$NIGHT_LIGHT_TEST_STATE.starts") == 4 && ! -e $NIGHT_LIGHT_TEST_STATE ]]
grep -q 'time = 22:15| temperature = 3000' "$NIGHT_LIGHT_TEST_STATE.starts"
grep -q 'time = 06:45| identity = true' "$NIGHT_LIGHT_TEST_STATE.starts"
printf 'Night-light validation, daemon ownership, restart and schedule tests passed.\n'
