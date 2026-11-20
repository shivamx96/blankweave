#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/home" "$test_root/runtime" "$test_root/config"
chmod 700 "$test_root/runtime"
cp -R "$repository/defaults/quickshell/"{Services,Components,Assets,Settings} "$test_root/config/"
cp "$repository/tests/quickshell/script-poller.qml" "$test_root/config/shell.qml"
cp "$repository/tests/fixtures/script-poller.sh" "$test_root/fake.sh"
chmod +x "$test_root/fake.sh"
printf 'echo LOGIN_PROFILE_NOISE\n' > "$test_root/home/.bash_profile"
# Also guards against a future change to invoke a login shell before the fixture.
if rg -n '"-lc"|"--login"' "$repository/defaults/quickshell/Services/ScriptPoller.qml"; then
    printf 'ScriptPoller must not invoke a login shell\n' >&2
    exit 1
fi
if ! HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/home/.config" \
    XDG_RUNTIME_DIR="$test_root/runtime" QT_QPA_PLATFORM=offscreen \
    QT_QUICK_BACKEND=software POLLER_TEST_DIR="$test_root" \
    timeout 12 qs -p "$test_root/config" > "$test_root/log" 2>&1 </dev/null; then
    cat "$test_root/log"
    exit 1
fi
cat "$test_root/log"
grep -q SCRIPT_POLLER_PASSED "$test_root/log"
if grep -Eq 'TypeError|ReferenceError|Binding loop|Unable to assign|Failed to load|Error:|LOGIN_PROFILE_NOISE' "$test_root/log"; then
    exit 1
fi
[[ ! -e $test_root/survived ]]
[[ $(cat "$test_root/count") == 1 ]]
printf 'Script poller tests passed.\n'
