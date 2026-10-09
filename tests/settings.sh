#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

mkdir -p "$test_root/bin" "$test_root/home" "$test_root/runtime"
chmod 700 "$test_root/runtime"
cat > "$test_root/bin/qs" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$SETTINGS_TEST_LOG"
exit "${SETTINGS_TEST_EXIT:-0}"
EOF
chmod +x "$test_root/bin/qs"
export SETTINGS_TEST_LOG="$test_root/command"
export SETTINGS_SYNC_STATE="$test_root/synced"
HOME="$test_root/home" PATH="$test_root/bin:$PATH" "$repository/bin/blankweave" settings
printf 'ipc\n-n\n-p\n%s\ncall\nblankweave\nsettings\n' \
    "$test_root/home/.local/share/blankweave/quickshell" > "$test_root/expected"
diff -u "$test_root/expected" "$SETTINGS_TEST_LOG"
if HOME="$test_root/home" PATH="$test_root/bin:$PATH" SETTINGS_TEST_EXIT=1 \
    "$repository/bin/blankweave" settings > "$test_root/output" 2>&1; then
    printf 'Settings should report a failed shell connection\n' >&2
    exit 1
fi
grep -q 'could not open settings' "$test_root/output"
if "$repository/bin/blankweave" settings unexpected > "$test_root/output" 2>&1; then
    printf 'Settings should reject unexpected arguments\n' >&2
    exit 1
fi

HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/home/.config" \
    XDG_RUNTIME_DIR="$test_root/runtime" QT_QPA_PLATFORM=offscreen \
    QT_QUICK_BACKEND=software /usr/lib/qt6/bin/qmltestrunner \
    -input "$repository/tests/qml" -o -,txt
mkdir -p "$test_root/backend/Services"
cp "$repository/defaults/quickshell/Services/SettingsAppearance.qml" "$test_root/backend/Services/"
cp "$repository/tests/quickshell/settings-backend.qml" "$test_root/backend/shell.qml"
cp "$repository/tests/fixtures/settings-theme.sh" "$test_root/backend/theme.sh"
if ! HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/home/.config" \
    XDG_RUNTIME_DIR="$test_root/runtime" QT_QPA_PLATFORM=offscreen \
    QT_QUICK_BACKEND=software timeout 15 qs \
    -p "$test_root/backend" > "$test_root/backend.log" 2>&1; then
    cat "$test_root/backend.log"
    exit 1
fi
if ! grep -q SETTINGS_BACKEND_PASSED "$test_root/backend.log"; then
    cat "$test_root/backend.log"
    exit 1
fi

# Load the real native window in a separate shell with an isolated home. This
# catches shell-only types and lifecycle errors that qmltestrunner cannot load.
mkdir -p "$test_root/window" "$test_root/home/.local/share/blankweave/shell" \
    "$test_root/home/.local/share/blankweave/themes/obsidian" "$test_root/home/.config/blankweave"
cp -R "$repository/defaults/quickshell/"{Settings,Services,Components,Assets} "$test_root/window/"
cp "$repository/defaults/quickshell/Theme.qml" "$test_root/window/"
cp "$repository/tests/quickshell/settings-window.qml" "$test_root/window/shell.qml"
cp "$repository/tests/fixtures/settings-theme.sh" "$test_root/home/.local/share/blankweave/shell/theme-apply.sh"
cp "$repository/defaults/themes/obsidian/theme.json" "$test_root/home/.local/share/blankweave/themes/obsidian/"
if ! HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/home/.config" \
    XDG_RUNTIME_DIR="$test_root/runtime" QT_QPA_PLATFORM=offscreen \
    QT_QUICK_BACKEND=software timeout 15 qs -p "$test_root/window" > "$test_root/window.log" 2>&1; then
    cat "$test_root/window.log"
    exit 1
fi
if ! grep -q SETTINGS_WINDOW_PASSED "$test_root/window.log" \
    || grep -Eq '(TypeError|ReferenceError|Binding loop|Unable to assign|Failed to load)' "$test_root/window.log"; then
    cat "$test_root/window.log"
    exit 1
fi
printf 'Settings command and interface tests passed.\n'
