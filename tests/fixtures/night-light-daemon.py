#!/usr/bin/env python3
"""Fake protocol peer for the real night-light helper and QML lifecycle tests."""
import json
import os
from pathlib import Path
import re
import signal
import sys
import time
state = Path(os.environ['NIGHT_LIGHT_TEST_STATE'])
if Path(sys.argv[0]).name == 'hyprctl':
    if not state.exists():
        sys.exit(1)
    value = json.loads(state.read_text())
    if sys.argv[2:] == ['temperature']:
        print(value['temperature'])
    elif sys.argv[2:] == ['identity', 'get']:
        print('true' if value['identity'] else 'false')
    else:
        sys.exit(2)  # Read-only status must never change identity.
    sys.exit(0)
assert len(sys.argv) == 1
config = (Path(os.environ['XDG_CONFIG_HOME']) / 'hypr/hyprsunset.conf').read_text()
state.write_text(json.dumps({'temperature': int(re.search(r'temperature = (\d+)', config)[1]), 'identity': False}))
with state.with_suffix('.starts').open('a') as stream:
    stream.write(config.replace('\n', '|') + '\n')
def stop(*args):
    state.unlink(missing_ok=True)
    sys.exit(0)
signal.signal(signal.SIGTERM, stop)
while True:
    time.sleep(.05)
