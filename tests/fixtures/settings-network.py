#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

state = Path(os.environ['SETTINGS_NETWORK_STATE'])
if state.exists():
    devices = json.loads(state.read_text())
else:
    devices = [{'path': '/org/freedesktop/NetworkManager/Devices/1', 'owner': ':1.42', 'interface': 'eth-test',
                'kind': 'ethernet', 'managed': True, 'state': 100, 'connected': True, 'carrier': True,
                'speed': 1000, 'activePath': '/active/1', 'uuid': 'test-uuid', 'name': 'Test LAN', 'default': True,
                'profiles': [{'uuid': 'test-uuid', 'name': 'Test LAN'}],
                'ipv4': {'addresses': ['192.0.2.2/24'], 'gateway': '192.0.2.1', 'dns': ['192.0.2.53']},
                'ipv6': {'addresses': [], 'gateway': '', 'dns': []},
                'dns': {'4': {'enabled': True, 'automatic': True, 'servers': []},
                        '6': {'enabled': False, 'automatic': True, 'servers': []}}, 'provider': 'Automatic'}]
if sys.argv[1] == 'status':
    print(json.dumps({'devices': devices}))
else:
    request = json.load(sys.stdin)
    if request.get('provider') == 'Custom':
        print('Enter valid IPv4 DNS server addresses.', file=sys.stderr)
        sys.exit(1)
    if request['action'] == 'dns':
        devices[0]['provider'] = request['provider']
    elif request['action'] == 'disconnect':
        devices[0].update(connected=False, state=30, activePath='/', uuid='', name='')
    else:
        devices[0].update(connected=True, state=100, activePath='/active/2', uuid='test-uuid', name='Test LAN')
    state.write_text(json.dumps(devices))
