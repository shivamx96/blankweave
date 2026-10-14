#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
path = Path(os.environ['SETTINGS_DEFAULT_APPS_STATE'])
state = json.loads(path.read_text()) if path.exists() else dict(revision='initial', context='fixture', writable=True, message='', rows=[
    dict(id='browser', label='Web browser', types=['text/html'], local=False,
         current=[dict(type='text/html', id='one.desktop', name='One')],
         choices=[dict(id='one.desktop', name='One'), dict(id='two.desktop', name='Two')]),
    dict(id='music', label='MP3 audio', types=['audio/mpeg'], local=False,
         current=[dict(type='audio/mpeg', id='', name='')], choices=[])])
if sys.argv[1:] == ['status']:
    print(json.dumps(state))
elif sys.argv[1:] == ['apply']:
    request = json.load(sys.stdin)
    if request['revision'] != state['revision'] or request['context'] != state['context']:
        sys.exit('Applications changed. Refresh and try again.')
    row = next(r for r in state['rows'] if r['id'] == request['group'])
    app = request['application'] or 'one.desktop'
    row['current'][0].update(id=app, name=app)
    row['local'] = request['application'] is not None
    row['choices'].reverse()
    state['revision'] += '!'
    path.write_text(json.dumps(state))
else:
    sys.exit(2)
