#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

state = Path(os.environ['SETTINGS_SYSTEM_SOUNDS_STATE'])
default = {'preferences': {'event-sounds': True, 'input-feedback-sounds': False, 'theme-name': 'freedesktop'},
           'themes': [{'id': 'freedesktop', 'name': 'Default'}, {'id': 'custom', 'name': 'Custom'}],
           'gtkSynced': False, 'previewAvailable': True,
           'writable': {'event-sounds': True, 'input-feedback-sounds': True, 'theme-name': True}}
data = json.loads(state.read_text()) if state.exists() else default
command = sys.argv[1]
if command == 'status':
    print(json.dumps(data))
elif command == 'set':
    key, value = sys.argv[2:]
    if key == 'theme-name' and value == 'custom':
        print('Fixture theme apply failed', file=sys.stderr)
        sys.exit(1)
    data['preferences'][key] = value if key == 'theme-name' else value == 'true'
    data['gtkSynced'] = True
    state.write_text(json.dumps(data))
elif command == 'sync':
    data['gtkSynced'] = True
    state.write_text(json.dumps(data))
elif command == 'preview':
    print('Fixture playback failed', file=sys.stderr)
    sys.exit(1)
