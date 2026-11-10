#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 "$repository/tests/system_sounds_test.py"

PYTHONDONTWRITEBYTECODE=1 python3 "$repository/tests/system_bell_test.py"
