#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
sandbox=$(mktemp -d)
trap 'rm -rf -- "$sandbox"' EXIT
mkdir -p "$sandbox/config/blankweave" "$sandbox/test/Services" "$sandbox/test/Components"
chmod 700 "$sandbox"
cp "$repository/defaults/quickshell/Services/ShellPreferences.qml" "$sandbox/test/Services/"
cp "$repository/defaults/quickshell/Components/LocaleFormats.js" "$sandbox/test/Components/"
sed 's@../../defaults/quickshell/Services@./Services@' "$repository/tests/quickshell/locale-preferences.qml" > "$sandbox/test/shell.qml"
export HOME="$sandbox" XDG_CONFIG_HOME="$sandbox/config" XDG_RUNTIME_DIR="$sandbox"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
/usr/lib/qt6/bin/qmltestrunner -input "$repository/tests/qml" -o -,txt </dev/null
timeout 8 qs -p "$sandbox/test" </dev/null > "$sandbox/log" 2>&1
cat "$sandbox/log"
if grep -Eq 'ERROR|Error|TypeError|ReferenceError' "$sandbox/log"; then exit 1; fi
python3 - "$sandbox/config/blankweave/shell.json" <<'PY'
import json, sys
value = json.load(open(sys.argv[1]))
assert value["welcomeShown"] is True
assert value["timeFormat"] == "auto"
assert value["temperatureUnit"] == "auto"
PY
