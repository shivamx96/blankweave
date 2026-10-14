#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

path = Path(os.environ['SETTINGS_IDLE_STATE'])
state = json.loads(path.read_text()) if path.exists() else {
    'settings': {'version': 1, 'ac': {'dim': 150, 'lock': 300, 'screen': 600, 'suspend': 0}, 'battery': {'dim': 150, 'lock': 300, 'screen': 360, 'suspend': 1800}},
    'revision': 'initial', 'managed': True, 'running': True, 'applied': True,
    'battery': True, 'source': 'ac', 'message': 'Idle settings are active.'}
if sys.argv[1:] == ['status']:
    print(json.dumps(state))
elif sys.argv[1:] == ['configure']:
    request = json.load(sys.stdin)
    if state['revision'] != 'initial':
        sys.exit('Settings changed elsewhere. Refresh and try again.')
    assert request['revision'] == state['revision']
    state['settings'] = request['settings']
    state['revision'] = 'updated'
    state['applied'] = False
    state['message'] = 'Waiting for the idle service to apply saved settings…'
    path.write_text(json.dumps(state))
else:
    sys.exit(2)
