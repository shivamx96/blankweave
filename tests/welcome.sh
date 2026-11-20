#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software /usr/lib/qt6/bin/qmltestrunner -input "$repository/tests/qml/tst_welcome.qml" -o -,txt < /dev/null
python3 - "$repository" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
shell = (root/'defaults/quickshell/shell.qml').read_text()
assert 'welcome-eligible' in shell
assert 'function welcome()' in shell
assert 'root.welcome.activity()' in shell
assert 'blocked: root.welcome.visible || root.power.lowBattery.warningLevel > 0' in shell
toast = (root/'defaults/quickshell/Modules/WelcomeToast.qml').read_text()
assert 'WlrKeyboardFocus.OnDemand' in toast and 'WlrLayer.Top' in toast
assert 'Hyprland.focusedMonitor.name' in toast
assert 'property bool welcomeShown: false' in (root/'defaults/quickshell/Services/ShellPreferences.qml').read_text()
install = (root/'install.sh').read_text()
assert 'if [[ $FIRST_INSTALL == true ]]; then' in install
assert 'welcome-eligible' in install
print('Welcome shell integration checks passed.')
PY
