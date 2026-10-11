#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

mkdir -p "$test_root/home" "$test_root/runtime" "$test_root/shell/Modules" "$test_root/shell/Components"
chmod 700 "$test_root/runtime"
cp "$repository/defaults/quickshell/Modules/ActiveWindowWidget.qml" "$test_root/shell/Modules/"
cp "$repository/defaults/quickshell/Components/"{WidgetFrame,VectorMark}.qml "$test_root/shell/Components/"
cp -R "$repository/defaults/quickshell/Assets" "$test_root/shell/"
cp "$repository/tests/quickshell/active-window.qml" "$test_root/shell/shell.qml"

if ! HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/home/.config" \
    XDG_RUNTIME_DIR="$test_root/runtime" HYPRLAND_INSTANCE_SIGNATURE='' \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    timeout 15 qs -p "$test_root/shell" > "$test_root/output" 2>&1; then
    cat "$test_root/output"
    exit 1
fi
cat "$test_root/output"
grep -q ACTIVE_WINDOW_PASSED "$test_root/output"
if grep -Eq '(TypeError|ReferenceError|Binding loop|Unable to assign|Failed to load)' "$test_root/output"; then
    exit 1
fi
