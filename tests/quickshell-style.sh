#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$repository" <<'PY'
import pathlib,re,sys
root=pathlib.Path(sys.argv[1])
# Theme owns palette fallbacks/high-contrast substitutions. No other hex literals.
hex_allowlist={"Theme.qml"}
# ListView's zero-duration highlight intentionally never animates selection.
duration_allowlist={("Settings/SettingsComboBox.qml", "highlightMoveDuration: 0"),("Launcher/ApplicationLauncher.qml", "highlightMoveDuration: 0")}
for p in (root/"defaults/quickshell").rglob("*.qml"):
    name=str(p.relative_to(root/"defaults/quickshell"))
    for line in p.read_text().splitlines():
        assert not re.search(r'#[0-9a-fA-F]{3,8}\b',line) or name in hex_allowlist,(name,line)
        if re.search(r'\b(?:duration|\w+Duration):',line,re.I):
            assert "motionDuration" in line or (name,line.strip()) in duration_allowlist,(name,line)
brightness=(root/"defaults/quickshell/Services/DisplayBrightness.qml").read_text()
assert not re.search(r'(reportedModel|serial)\s*===?\s*["\']',brightness)
assert "LG HDR 4K" not in brightness and "27UL850" not in brightness
widget=(root/"defaults/quickshell/Modules/BrightnessWidget.qml").read_text()
assert "visible: display.available" not in widget
assert "Brightness is not available for this display" in widget
for name in ["Audio","Brightness","Bluetooth","Network","Notification","Battery"]:
    assert "iconMark:" in (root/f"defaults/quickshell/Modules/{name}Widget.qml").read_text()
assert "VectorMark {" in (root/"defaults/quickshell/Components/WidgetFrame.qml").read_text()
print("QML style/capability scans passed.")
PY
