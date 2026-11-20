#!/usr/bin/env bash
# Focused outcome checks, independent of other Settings control work.
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$repository" <<'PY'
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

repo = Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='blankweave-settings-outcomes-') as tmp:
    root = Path(tmp)
    (root / 'home').mkdir()
    (root / 'runtime').mkdir(mode=0o700)
    env = dict(os.environ, HOME=str(root / 'home'), XDG_CONFIG_HOME=str(root / 'home/.config'),
               XDG_RUNTIME_DIR=str(root / 'runtime'), QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
               SETTINGS_TASK_STATE=str(root / 'state'))
    env.pop('WAYLAND_DISPLAY', None)
    subprocess.run(['/usr/lib/qt6/bin/qmltestrunner', '-input', str(repo / 'tests/qml/tst_next_settings.qml'),
                    '-o', '-,txt'], env=env, stdin=subprocess.DEVNULL, check=True)
    # Copy only the adapter under test so no native service can be instantiated.
    (root / 'Services').mkdir()
    for name in ['SettingsTask.qml', 'SettingsOutcome.js']:
        shutil.copy(repo / 'defaults/quickshell/Services' / name, root / 'Services' / name)
    shutil.copy(repo / 'tests/quickshell/settings-task.qml', root / 'shell.qml')
    shutil.copy(repo / 'tests/fixtures/settings-task.py', root / 'task.py')
    result = subprocess.run(['timeout', '15', 'qs', '-p', tmp], env=env, stdin=subprocess.DEVNULL,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True)
    print(result.stdout)
    assert 'SETTINGS_TASK_PASSED' in result.stdout
    assert not any(word in result.stdout for word in ['TypeError', 'ReferenceError', 'Error:', 'Binding loop', 'Unable to assign'])
PY
