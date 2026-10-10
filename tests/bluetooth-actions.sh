#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# Every BlueZ request is redirected to a fresh private bus with a fake service.
dbus-run-session -- python3 "$repository/tests/bluetooth_action_test.py"
