#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PYTHONDONTWRITEBYTECODE=1 python3 "$repository/tests/settings_webapps_test.py"
