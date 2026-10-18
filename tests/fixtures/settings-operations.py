#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

if sys.argv[1:] == ['jobs']:
    print('[]')
    sys.exit(0)
domain, command = sys.argv[1:]
state = Path(os.environ['SETTINGS_OPERATIONS_LOG'] + '.' + domain)
with Path(os.environ['SETTINGS_OPERATIONS_LOG']).open('a') as stream:
    stream.write(domain + ' ' + command + '\n')
if command == 'status':
    print(json.dumps(dict(revision='fixture', writable=True, message='', details=[], actions=[], job=json.loads(state.read_text()) if state.exists() else None)))
else:
    request = json.load(sys.stdin)
    assert request['action'] == 'fixture' and request['revision'] == 'fixture'
    if request.get('folder') == 'reject':
        print('The folder is unavailable.', file=sys.stderr)
        sys.exit(1)
    state.write_text(json.dumps(dict(id='fixture-job', phase='completed', label='Fixture', message='Done', cancellable=False)))
    print(json.dumps(dict(jobId='fixture-job')))
