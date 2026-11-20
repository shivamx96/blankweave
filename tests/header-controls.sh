#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/home/.local/share/blankweave/themes" "$test_root/runtime" "$test_root/shell"
chmod 700 "$test_root/runtime"
cp "$repository/defaults/themes/design-defaults.json" "$test_root/home/.local/share/blankweave/themes/"
cp -R "$repository/defaults/quickshell/"{Components,Assets,Modules,Services,Settings} "$test_root/shell/"
cp "$repository/defaults/quickshell/Theme.qml" "$test_root/shell/"
cp "$repository/tests/quickshell/bar-widgets.qml" "$test_root/shell/shell.qml"
if ! HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/home/.config" \
    XDG_DATA_HOME="$test_root/home/.local/share" XDG_DATA_DIRS="$test_root/home/.local/share" \
    XDG_RUNTIME_DIR="$test_root/runtime" HYPRLAND_INSTANCE_SIGNATURE='' \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    timeout 15 qs -p "$test_root/shell" > "$test_root/output" 2>&1; then
    cat "$test_root/output"
    exit 1
fi
if ! grep -q BAR_WIDGETS_PASSED "$test_root/output" \
    || grep -Eq '(TypeError|ReferenceError|Binding loop|Unable to assign|Failed to load|Error:)' "$test_root/output"; then
    cat "$test_root/output"
    exit 1
fi
python3 "$repository/tests/header_actions_test.py" </dev/null
printf 'Header control and bar widget fixtures passed.\n'
