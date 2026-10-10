#!/usr/bin/env python3
import json
import sys

def emit(**data):
    print(json.dumps(data), flush=True)

action, key = sys.argv[1:]
if key.endswith('_00'):
    emit(kind='result', success=False, message='Device refused the connection')
    sys.exit(1)
if action == 'pair':
    emit(kind='prompt', prompt={'id':1, 'type':'confirm', 'code':'012345'})
    response = json.loads(sys.stdin.readline())
    if response.get('cancel'):
        emit(kind='result', success=False, message='Pairing canceled.')
        sys.exit(1)
    if response != {'id':1, 'value':True}:
        sys.exit(2)
emit(kind='result', success=True, message='')
