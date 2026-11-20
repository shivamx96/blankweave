#!/usr/bin/env python3
"""Read shell preferences without writing them; resolve auto with Qt itself."""
import json
import os
from pathlib import Path
import subprocess

path = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'blankweave/shell.json'
try:
    mode = json.loads(path.read_text()).get('timeFormat', 'auto')
except (OSError, ValueError, AttributeError):
    mode = 'auto'
if mode in ('12h', '24h'):
    print('$TIME12' if mode == '12h' else '$TIME')
else:
    result = subprocess.run(['/usr/lib/qt6/bin/qml', '-a', 'core', str(Path(__file__).with_name('lock-time-format.qml'))],
                            capture_output=True, text=True, timeout=10,
                            env=dict(os.environ, QML_DISABLE_DISK_CACHE='1'))
    if result.returncode not in (12, 24):
        raise RuntimeError('Could not resolve the lock clock session locale with Qt')
    print('$TIME12' if result.returncode == 12 else '$TIME')
