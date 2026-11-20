#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/shell" "$test_root/runtime" "$test_root/home"
chmod 700 "$test_root/runtime"
cp -R "$repository/defaults/quickshell/Services" "$test_root/shell/"
cp "$repository/tests/quickshell/launcher-usage.qml" "$test_root/shell/shell.qml"
run_fixture() {
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime"         QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software         timeout 10 qs -p "$test_root/shell" > "$test_root/log" 2>&1
    if ! grep -q USAGE_PASSED "$test_root/log" || grep -Eq '(Error:|TypeError|ReferenceError|Unable to assign)' "$test_root/log"; then
        cat "$test_root/log"
        exit 1
    fi
    python3 - "$test_root/state/blankweave/launcher-usage.json" <<'PY'
import json,sys
data=json.load(open(sys.argv[1]))
assert data["version"] == 1 and list(data["applications"]) == ["terminal"]
assert data["applications"]["terminal"]["count"] == int(__import__("os").environ.get("USAGE_EXISTING", "0")) + 1
assert data["applications"]["terminal"]["last"] > 0
PY
}
run_fixture
export USAGE_EXISTING=1
run_fixture
unset USAGE_EXISTING
printf '{broken' > "$test_root/state/blankweave/launcher-usage.json"
run_fixture
printf '{"version":1,"applications":{"removed":{"count":50,"last":1800000000000}}}' > "$test_root/state/blankweave/launcher-usage.json"
run_fixture
printf 'Launcher usage missing/corrupt state and atomic persistence fixtures passed.\n'
