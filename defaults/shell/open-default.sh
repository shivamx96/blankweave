#!/usr/bin/env bash
# Resolution and desktop-entry launching share the Settings GIO implementation.
set -euo pipefail
exec python3 "$(dirname -- "${BASH_SOURCE[0]}")/default-apps.py" open "$@"
