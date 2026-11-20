#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PYTHONDONTWRITEBYTECODE=1 python3 - "$repository" <<'PY'
import sys, subprocess
sys.path.insert(0, sys.argv[1] + '/defaults/shell')
import settings_devices as devices
devices.installed = lambda *args: True
calls=[]
def run(args, **kwargs):
    calls.append((args, kwargs))
    return 'network ipp://printer.local/ipp/print\nnetwork ipps://printer.local/secure\nnetwork ipp://secret:password@private.local/\nnetwork socket://printer.local/\nnetwork ipp://printer.local/ipp/print'
devices.run = run
assert devices.discovered_printers() == ['ipp://printer.local/ipp/print', 'ipps://printer.local/secure']
assert calls == [(['lpinfo', '-v'], {'timeout': 3})]
def timeout(*a, **k): raise subprocess.TimeoutExpired('lpinfo', 3)
devices.run = timeout
assert devices.discovered_printers() == []
devices.installed = lambda *a: False
assert devices.discovered_printers() == []
print('Bounded read-only printer discovery tests passed.')
PY
