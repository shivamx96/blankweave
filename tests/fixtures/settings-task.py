import json
import os
from pathlib import Path
import sys
path = Path(os.environ['SETTINGS_TASK_STATE'])
state = json.loads(path.read_text()) if path.exists() else dict(revision='1', value=False)
if sys.argv[1:] == ['status']: print(json.dumps(state))
else:
    request = json.load(sys.stdin)
    if request.get('cancel'):
        print(json.dumps({'error': {'message': 'Cancelled', 'detail': '', 'cancelled': True}}))
        sys.exit(1)
    if request['revision'] != state['revision']:
        print(json.dumps({'error': {'message': 'Settings changed. Refresh and try again.', 'detail': 'Revision mismatch.'}}))
        sys.exit('Settings changed. Refresh and try again.')
    state['value'] = request['value']; state['revision'] += '!'
    path.write_text(json.dumps(state))
