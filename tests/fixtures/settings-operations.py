#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

domain, command = sys.argv[1:]
with Path(os.environ['SETTINGS_OPERATIONS_LOG']).open('a') as stream:
    stream.write(domain + ' ' + command + '\n')
if command == 'status':
    print(json.dumps(dict(revision='fixture', writable=True, message='', details=[], actions=[], job=None)))
else:
    request = json.load(sys.stdin)
    assert request['action'] == 'fixture' and request['revision'] == 'fixture'
