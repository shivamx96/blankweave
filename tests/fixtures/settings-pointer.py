#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

path = Path(os.environ['SETTINGS_POINTER_STATE'])
state = json.loads(path.read_text()) if path.exists() else {
    'saved': {'version': 1, 'global': {}, 'touchpad': {}, 'devices': {}},
    'revision': 'initial', 'session': 'fixture', 'installed': True, 'synced': True, 'message': '',
    'values': {'global': {'sensitivity': 0, 'accel_profile': '', 'natural_scroll': False, 'left_handed': False},
               'touchpad': {'natural_scroll': True, 'tap_to_click': True, 'disable_while_typing': True}},
    'devices': [{'name': 'fixture-touchpad', 'address': '0x1', 'kind': 'touchpad', 'unique': True}], 'writes': 0}
if sys.argv[1:] == ['status']:
    print(json.dumps(state))
elif sys.argv[1:] == ['apply']:
    request = json.load(sys.stdin)
    assert request['revision'] == state['revision'] and request['session'] == 'fixture'
    if state['writes'] == 2:
        sys.exit('Personal configuration overrides this setting; change reverted.')
    scope, key, value = request['scope'], request['key'], request['value']
    if scope == 'device':
        assert request['device'] == 'fixture-touchpad' and request['address'] == '0x1'
        state['saved']['devices'].setdefault(request['device'], {})[key] = value
    else:
        state['saved'][scope][key] = value
        state['values'][scope][key] = value
    state['writes'] += 1
    state['revision'] = str(state['writes'])
    path.write_text(json.dumps(state))
else:
    sys.exit(2)
