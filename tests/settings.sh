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
export SETTINGS_WIFI_PROFILES_STATE="$test_root/wifi-profiles-state"
export SETTINGS_SYSTEM_SOUNDS_STATE="$test_root/system-sounds-state"
export SETTINGS_VOICE_LOG="$test_root/voice-commands"
export SETTINGS_SYNC_STATE="$test_root/synced"
export SETTINGS_DISPLAYS_STATE="$test_root/displays-state"
export SETTINGS_BRIGHTNESS_DIR="$test_root/brightness-state"
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
    -input "$repository/tests/qml" -o -,txt > "$test_root/qml.log" 2>&1 || { cat "$test_root/qml.log"; exit 1; }
cat "$test_root/qml.log"
if grep -Eq '(TypeError|ReferenceError|Binding loop|Unable to assign|Failed to load)' "$test_root/qml.log"; then
    exit 1
fi
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

# Dictation actions use a fake service and never record or restart host audio.
mkdir -p "$test_root/voice/Services"
cp "$repository/defaults/quickshell/Services/"{Voxtype,ScriptPoller}.qml "$test_root/voice/Services/"
cp "$repository/tests/quickshell/settings-voice.qml" "$test_root/voice/shell.qml"
cp "$repository/tests/fixtures/settings-voice.sh" "$test_root/voice/voice.sh"
printf 'profiles=voice-dictation\n' > "$test_root/voice/install.conf"
printf '{}\n' > "$test_root/voice/transcript.json"
if ! HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/home/.config" \
    XDG_RUNTIME_DIR="$test_root/runtime" QT_QPA_PLATFORM=offscreen \
    QT_QUICK_BACKEND=software timeout 15 qs -p "$test_root/voice" > "$test_root/voice.log" 2>&1; then
    cat "$test_root/voice.log"
    exit 1
fi
if ! grep -q SETTINGS_VOICE_PASSED "$test_root/voice.log" \
    || grep -Eq '(TypeError|ReferenceError|Binding loop|Unable to assign|Failed to load)' "$test_root/voice.log"; then
    cat "$test_root/voice.log"
    exit 1
fi
printf 'start-clipboard\nstop\ncancel\nrestart\nstart-clipboard\n' > "$test_root/expected-voice"
diff -u "$test_root/expected-voice" "$SETTINGS_VOICE_LOG"

# Sound preferences and playback are isolated from the session's settings bus.
mkdir -p "$test_root/sounds/Services"
cp "$repository/defaults/quickshell/Services/SettingsSystemSounds.qml" "$test_root/sounds/Services/"
cp "$repository/tests/quickshell/settings-system-sounds.qml" "$test_root/sounds/shell.qml"
cp "$repository/tests/fixtures/settings-system-sounds.py" "$test_root/sounds/sounds.py"
if ! HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/home/.config" \
    XDG_RUNTIME_DIR="$test_root/runtime" QT_QPA_PLATFORM=offscreen \
    QT_QUICK_BACKEND=software timeout 15 qs -p "$test_root/sounds" > "$test_root/sounds.log" 2>&1; then
    cat "$test_root/sounds.log"
    exit 1
fi
if ! grep -q SETTINGS_SYSTEM_SOUNDS_PASSED "$test_root/sounds.log" \
    || grep -Eq '(TypeError|ReferenceError|Binding loop|Unable to assign|Failed to load)' "$test_root/sounds.log"; then
    cat "$test_root/sounds.log"
    exit 1
fi

# Native networking is supplied with fake devices: never scan or change host Wi-Fi.
mkdir -p "$test_root/wifi"
cp -R "$repository/defaults/quickshell/"{Services,Settings,Components,Assets,Modules} "$test_root/wifi/"
cp "$repository/defaults/quickshell/Theme.qml" "$test_root/wifi/"
mkdir -p "$test_root/home/.local/share/blankweave/shell"
cat > "$test_root/home/.local/share/blankweave/shell/network-status.sh" <<'EOF'
#!/usr/bin/env bash
printf '{}\n'
EOF
chmod +x "$test_root/home/.local/share/blankweave/shell/network-status.sh"
cp "$repository/tests/quickshell/settings-wifi.qml" "$test_root/wifi/shell.qml"
cp "$repository/tests/fixtures/settings-wifi-profiles.py" "$test_root/wifi/profiles.py"
if ! HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/home/.config" \
    XDG_RUNTIME_DIR="$test_root/runtime" QT_QPA_PLATFORM=offscreen \
    QT_QUICK_BACKEND=software timeout 15 qs -p "$test_root/wifi" > "$test_root/wifi.log" 2>&1; then
    cat "$test_root/wifi.log"
    exit 1
fi
if ! grep -q SETTINGS_WIFI_PASSED "$test_root/wifi.log" \
    || grep -Eq '(TypeError|ReferenceError|Binding loop|Unable to assign|Failed to load|Error:)' "$test_root/wifi.log"; then
    cat "$test_root/wifi.log"
    exit 1
fi

# Exercise monitor discovery and mutations with a fixture, never the real compositor.
mkdir -p "$test_root/displays/Services"
cp "$repository/defaults/quickshell/Services/SettingsDisplays.qml" "$test_root/displays/Services/"
cp "$repository/tests/quickshell/settings-displays.qml" "$test_root/displays/shell.qml"
cp "$repository/tests/fixtures/settings-displays.sh" "$test_root/displays/displays.sh"
if ! HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/home/.config" \
    XDG_RUNTIME_DIR="$test_root/runtime" QT_QPA_PLATFORM=offscreen \
    QT_QUICK_BACKEND=software timeout 15 qs \
    -p "$test_root/displays" > "$test_root/displays.log" 2>&1; then
    cat "$test_root/displays.log"
    exit 1
fi
if ! grep -q SETTINGS_DISPLAYS_PASSED "$test_root/displays.log" \
    || grep -Eq '(TypeError|ReferenceError|Binding loop|Unable to assign|Failed to load)' "$test_root/displays.log"; then
    cat "$test_root/displays.log"
    exit 1
fi
printf 'DP-3 auto\nDP-3 1.25\nset DP-3 left\nset DP-3 below\nset DP-3 auto\nmode-preview eDP-1 2880x1800@60.00\nmode-confirm test-token\nmode-preview eDP-1 2880x1800@90.00\nmode-revert test-token\nmirror-preview DP-3 eDP-1\nmode-confirm test-token\npreset-save Presentation\npreset-preview desk\nmode-revert test-token\npreset-delete desk\n' > "$test_root/expected-displays"
diff -u "$test_root/expected-displays" "$SETTINGS_DISPLAYS_STATE.commands"

# Backlight/DDC state and slow hardware races use a separate fake device store.
mkdir -p "$test_root/brightness/Services"
cp "$repository/defaults/quickshell/Services/DisplayBrightness.qml" "$test_root/brightness/Services/"
cp "$repository/tests/quickshell/settings-brightness.qml" "$test_root/brightness/shell.qml"
cp "$repository/tests/fixtures/settings-brightness.sh" "$test_root/brightness/brightness.sh"
if ! HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/home/.config" \
    XDG_RUNTIME_DIR="$test_root/runtime" QT_QPA_PLATFORM=offscreen \
    QT_QUICK_BACKEND=software timeout 25 qs -p "$test_root/brightness" > "$test_root/brightness.log" 2>&1; then
    cat "$test_root/brightness.log"
    exit 1
fi
if ! grep -q SETTINGS_BRIGHTNESS_PASSED "$test_root/brightness.log" \
    || grep -Eq '(TypeError|ReferenceError|Binding loop|Unable to assign|Failed to load)' "$test_root/brightness.log"; then
    cat "$test_root/brightness.log"
    exit 1
fi
printf 'eDP-1 63\neDP-1 64\neDP-1 5\neDP-1 100\neDP-1 55\neDP-1 65\nDP-3 45\neDP-1 70\n' > "$test_root/expected-brightness"
diff -u "$test_root/expected-brightness" "$SETTINGS_BRIGHTNESS_DIR/commands"

# Load the real native window in a separate shell with an isolated home. This
# catches shell-only types and lifecycle errors that qmltestrunner cannot load.
mkdir -p "$test_root/window" "$test_root/home/.local/share/blankweave/shell" \
    "$test_root/home/.local/share/blankweave/themes/obsidian" "$test_root/home/.config/blankweave"
cp -R "$repository/defaults/quickshell/"{Settings,Services,Components,Assets} "$test_root/window/"
cp "$repository/defaults/quickshell/Theme.qml" "$test_root/window/"
cp "$repository/tests/quickshell/settings-window.qml" "$test_root/window/shell.qml"
cp "$repository/tests/fixtures/settings-theme.sh" "$test_root/home/.local/share/blankweave/shell/theme-apply.sh"
cp "$repository/tests/fixtures/settings-system-sounds.py" "$test_root/home/.local/share/blankweave/shell/system-sounds.py"
cp "$repository/tests/fixtures/settings-wifi-profiles.py" "$test_root/home/.local/share/blankweave/shell/wifi-profiles.py"
cp "$repository/tests/fixtures/settings-displays.sh" "$test_root/home/.local/share/blankweave/shell/monitor-layout.sh"
cp "$repository/tests/fixtures/settings-brightness.sh" "$test_root/home/.local/share/blankweave/shell/brightness.sh"
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
