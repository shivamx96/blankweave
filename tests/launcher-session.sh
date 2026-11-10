#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/home" "$test_root/runtime" "$test_root/bin" "$test_root/data"
chmod 700 "$test_root/runtime"
cp -R "$repository/defaults/quickshell" "$test_root/shell"
cp "$repository/tests/quickshell/launcher-session.qml" "$test_root/shell/shell.qml"
if ! HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/home/.config" \
    XDG_DATA_HOME="$test_root/data" XDG_DATA_DIRS="$test_root/data" \
    XDG_RUNTIME_DIR="$test_root/runtime" HYPRLAND_INSTANCE_SIGNATURE='' \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    timeout 15 qs -p "$test_root/shell" > "$test_root/output" 2>&1; then
    cat "$test_root/output"
    exit 1
fi
grep -q LAUNCHER_SESSION_PASSED "$test_root/output" || { cat "$test_root/output"; exit 1; }
if grep -Eq '(TypeError|ReferenceError|Binding loop|Unable to assign|Failed to load|Error:)' "$test_root/output"; then
    cat "$test_root/output"
    exit 1
fi
printf 'Launcher output/session tests passed.\n'
