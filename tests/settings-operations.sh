#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PYTHONDONTWRITEBYTECODE=1 python3 "$repository/tests/settings_operations_test.py"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/Services" "$test_root/home" "$test_root/runtime"
chmod 700 "$test_root/runtime"
cp "$repository/defaults/quickshell/Services/"{SettingsTask,SettingsOperationsService}.qml "$test_root/Services/"
cp "$repository/tests/quickshell/settings-operations.qml" "$test_root/shell.qml"
cp "$repository/tests/fixtures/settings-operations.py" "$test_root/fixture.py"
if ! HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/home/.config" \
    XDG_RUNTIME_DIR="$test_root/runtime" SETTINGS_OPERATIONS_LOG="$test_root/commands" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software timeout 15 qs \
    -p "$test_root" > "$test_root/output" 2>&1; then
    cat "$test_root/output"
    exit 1
fi
if ! grep -q SETTINGS_OPERATIONS_PASSED "$test_root/output" \
    || grep -Eq '(TypeError|ReferenceError|Binding loop|Unable to assign|Failed to load|Error:)' "$test_root/output"; then
    cat "$test_root/output"
    exit 1
fi
grep -Fxq 'vpn apply' "$test_root/commands"
