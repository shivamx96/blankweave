#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

path = Path(os.environ['SETTINGS_WIRELESS_STATE'])
if path.exists():
    state = json.loads(path.read_text())
else:
    state = {'radioError': '', 'networkError': '',
             'airplane': {'requested': False, 'blocked': False, 'radios': [{'name': 'radio', 'type': 'wlan', 'soft': False, 'hard': False}]},
             'network': {'wifiEnabled': True, 'hardwareEnabled': True, 'sharingAvailable': True, 'devices': [
                 {'path': '/org/freedesktop/NetworkManager/Devices/1', 'owner': ':1.42', 'interface': 'wifi-test',
                  'uuid': 'test-uuid', 'activePath': '/active/1', 'name': 'Test Wi-Fi', 'ssid': 'Test Wi-Fi',
                  'apCapable': True, 'hotspot': False, 'owned': False, 'connected': True, 'managed': True, 'state': 100}]}}
if sys.argv[1] == 'status':
    print(json.dumps(state))
else:
    request = json.load(sys.stdin)
    if request['action'] == 'airplane':
        state['airplane'].update(requested=request['enabled'], blocked=request['enabled'])
        state['airplane']['radios'][0]['soft'] = request['enabled']
    elif request['action'] == 'start':
        if request['ssid'] == 'Fail':
            print('Hotspot request failed.', file=sys.stderr)
            sys.exit(1)
        assert request['password'] == 'test-secret'
        assert request['replace'] is True
        state['network']['devices'][0].update(uuid='hotspot-uuid', activePath='/hotspot/1', ssid=request['ssid'], hotspot=True, owned=True)
    else:
        assert request['activePath'] == '/hotspot/1'
        state['network']['devices'][0].update(uuid='', activePath='/', ssid='', name='', hotspot=False, owned=False, connected=False, state=30)
    path.write_text(json.dumps(state))
