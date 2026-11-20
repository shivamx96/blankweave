#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/home" "$test_root/runtime" "$test_root/bin" "$test_root/data"
chmod 700 "$test_root/runtime"
mkdir -p "$test_root/data/applications"
cat > "$test_root/data/applications/blankweave-test-terminal.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Blankweave fake terminal
Exec=never-launch-this "two words" %f %U
Terminal=true
Path=/tmp
EOF
cat > "$test_root/data/applications/blankweave-test-theme.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Desktop theme
Exec=never-launch-this
EOF
cat > "$test_root/bin/cliphist" <<'STUB'
#!/usr/bin/env bash
# Isolated launcher must never reach the session history.
sleep 0.3
exit 0
STUB
chmod +x "$test_root/bin/cliphist"
export PATH="$test_root/bin:$PATH"
cp -R "$repository/defaults/quickshell" "$test_root/shell"
# Offscreen Qt has no layer-shell backend. Keep production search/activation and
# delegates, replacing only the native window wrapper in this temporary copy.
python3 - "$test_root/shell/Launcher/ApplicationLauncher.qml" <<'PYWRAP'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text()
s = s.replace('PanelWindow {', 'Rectangle {', 1)
s = s.replace('    screen: targetScreen', '    property var screen: targetScreen')
s = s.replace('    exclusiveZone: 0', '    width: 620; height: 680')
s = s.replace('    surfaceFormat.opaque: false', '')
a = s.index('    anchors {'); b = s.index('    function normalized', a)
s = s[:a] + s[b:]
p.write_text(s)
PYWRAP
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

bash "$repository/tests/launcher-usage.sh" </dev/null
