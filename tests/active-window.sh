#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

mkdir -p "$test_root/home" "$test_root/runtime"
chmod 700 "$test_root/runtime"
cp -R "$repository/defaults/quickshell" "$test_root/shell"
cp "$repository/tests/quickshell/active-window.qml" "$test_root/shell/shell.qml"
cp "$repository/tests/fixtures/active-window.sh" "$test_root/shell/query.sh"
export ACTIVE_WINDOW_QUERY_LOG="$test_root/queries"

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
printf 'empty\nempty\nfocused\nfocused\ndelayed-focused\ndelayed-empty\ndelayed-focused\nfailed\nmalformed\ninvalid-address\n' > "$test_root/expected-queries"
diff -u "$test_root/expected-queries" "$test_root/queries"
