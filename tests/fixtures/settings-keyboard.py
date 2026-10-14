#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
path = Path(os.environ['SETTINGS_KEYBOARD_STATE'])
state = json.loads(path.read_text()) if path.exists() else {
    'saved': {'version': 1, 'values': {}}, 'revision': 'initial', 'session': 'fixture',
    'installed': True, 'synced': True, 'message': '',
    'values': dict(kb_layout='us', kb_variant='', kb_options='caps:escape', kb_file='', kb_rules='', kb_model=''),
    'devices': [dict(name='keyboard', address='0x1', layout='us', variant='', active_keymap='English (US)', active_layout_index=0)],
    'catalog': [dict(layout='us', variant='', label='English (US)'), dict(layout='de', variant='', label='German')], 'writes': 0}
if sys.argv[1:] == ['status']:
    print(json.dumps(state))
elif sys.argv[1:] == ['apply']:
    request = json.load(sys.stdin)
    assert request['revision'] == state['revision'] and request['session'] == 'fixture'
    assert request['expected'] == state['values']
    if state['writes'] == 1:
        sys.exit('Personal configuration overrides this setting; change reverted.')
    state['saved']['values'] = request['values']
    state['values'].update(request['values'])
    state['devices'][0].update(layout=state['values']['kb_layout'], variant=state['values']['kb_variant'])
    state['writes'] += 1; state['revision'] = str(state['writes'])
    path.write_text(json.dumps(state))
elif sys.argv[1:] == ['switch']:
    request = json.load(sys.stdin)
    assert request['device'] == 'keyboard' and request['address'] == '0x1' and request['index'] == 1
    state['devices'][0].update(active_layout_index=1, active_keymap='German')
    path.write_text(json.dumps(state))
else:
    sys.exit(2)
