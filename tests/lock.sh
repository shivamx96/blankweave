#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PYTHONDONTWRITEBYTECODE=1 python3 - "$repository" <<'PY'
from pathlib import Path
import os
import subprocess
import sys
import tempfile
import time

helper = Path(sys.argv[1]) / 'defaults/shell/lock.sh'
with tempfile.TemporaryDirectory(prefix='blankweave-lock-test-') as temporary:
    root = Path(temporary)
    commands = root / 'bin'
    commands.mkdir()
    (commands / 'pidof').write_text('''#!/usr/bin/python3
from pathlib import Path
import os, sys
assert sys.argv[1:] == ['hyprlock']
sys.exit(0 if Path(os.environ['LOCK_TEST_ROOT'], 'active').exists() else 1)
''')
    (commands / 'hyprlock').write_text('''#!/usr/bin/python3
from pathlib import Path
import os, time
root = Path(os.environ['LOCK_TEST_ROOT'])
with (root / 'starts').open('a') as stream:
    stream.write('start\\n')
# Simulate slow client startup before pidof can see the process.
time.sleep(0.15)
(root / 'active').touch()
while not (root / 'release').exists():
    time.sleep(0.01)
(root / 'active').unlink()
(root / 'done').touch()
''')
    for command in commands.iterdir():
        command.chmod(0o755)
    env = dict(os.environ, PATH=str(commands) + ':/usr/bin:/bin',
               XDG_RUNTIME_DIR=str(root), LOCK_TEST_ROOT=str(root))
    def request():
        # Capture pipes too: a background child must not hold the caller open.
        subprocess.run(['bash', str(helper)], env=env, check=True,
                       capture_output=True, timeout=2)
    def wait_for(path):
        deadline = time.monotonic() + 3
        while not path.exists():
            if time.monotonic() > deadline:
                raise AssertionError('Stub did not reach ' + path.name)
            time.sleep(0.01)
    # An existing client is a no-op, even if it was started outside the helper.
    (root / 'active').touch()
    request()
    # Wait for the short-lived background check to release its file lock.
    subprocess.run(['flock', str(root / 'blankweave-lock/launch.lock'), 'true'], check=True, timeout=2)
    assert not (root / 'starts').exists()
    (root / 'active').unlink()
    try:
        request()
        wait_for(root / 'starts')
        # Race requests while the first process is not yet visible to pidof.
        requests = [subprocess.Popen(['bash', str(helper)], env=env) for _ in range(12)]
        for process in requests:
            assert process.wait(timeout=2) == 0
        wait_for(root / 'active')
        request()
        assert (root / 'starts').read_text() == 'start\n'
    finally:
        (root / 'release').touch()
        wait_for(root / 'done')
        subprocess.run(['flock', str(root / 'blankweave-lock/launch.lock'), 'true'], check=True, timeout=2)
    # A dead client can be replaced; no stale guard strands recovery.
    (root / 'done').unlink()
    request()
    wait_for(root / 'done')
    assert (root / 'starts').read_text() == 'start\nstart\n'
    # Text indication queries LEDs read-only and handles unavailable IPC quietly.
    caps = helper.with_name('lock-caps.sh')
    (commands / 'hyprctl').write_text('''#!/usr/bin/python3
import json, os, sys
assert sys.argv[1:] == ['-j', 'devices']
print(json.dumps({'keyboards': [{'capsLock': os.environ.get('CAPS') == '1'}]}))
''')
    (commands / 'hyprctl').chmod(0o755)
    for state, expected in [('1', 'Caps Lock is on'), ('0', '')]:
        result = subprocess.run(['sh', str(caps)], env=dict(env, CAPS=state),
                                capture_output=True, text=True, check=True)
        assert result.stdout.strip() == expected
print('lock helper: PASS (existing, concurrent, nonblocking, recovery; stub clients only)')
PY
