#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
import time

path = Path(os.environ['SETTINGS_POWER_STATE'])
value = json.loads(path.read_text()) if path.exists() else {
    'available': True, 'service': 'org.freedesktop.UPower.PowerProfiles', 'owner': ':1.23',
    'profile': 'balanced', 'profiles': [{'id': 'power-saver', 'name': 'Power saver'}, {'id': 'balanced', 'name': 'Balanced'},
                                        {'id': 'performance', 'name': 'Performance'}],
    'degraded': 'high-operating-temperature',
    'holds': [{'application': '<b>Renderer</b>', 'profile': 'performance', 'reason': 'Rendering'}],
}
value.setdefault('automatic', {
    'ready': True, 'settings': {'version': 1, 'enabled': False, 'ac': 'balanced', 'battery': 'balanced', 'low': 'power-saver', 'threshold': 15},
    'source': {'available': True, 'owner': ':1.30', 'onBattery': False, 'percentage': 70}, 'message': 'Automatic switching is off.'})
if sys.argv[1:] == ['status']:
    print(json.dumps(value))
elif sys.argv[1] == 'set':
    time.sleep(0.15)
    if sys.argv[-1] == 'performance':
        sys.exit('Fixture permission denied; profile unchanged.')
    value['profile'] = sys.argv[-1]
    value['automatic']['settings']['enabled'] = False
    path.write_text(json.dumps(value))
elif sys.argv[1:] == ['auto-configure']:
    request = json.load(sys.stdin)
    if request['settings']['threshold'] == 40:
        sys.exit('Fixture preference save denied.')
    if request['expected'] != value['automatic']['settings']:
        sys.exit('Fixture stale preferences.')
    value['automatic']['settings'] = request['settings']
    path.write_text(json.dumps(value))
elif sys.argv[1:] == ['auto-tick']:
    auto = value['automatic']
    if auto['settings']['enabled']:
        mode = 'ac' if not auto['source']['onBattery'] else 'low' if auto['source']['percentage'] <= auto['settings']['threshold'] else 'battery'
        value['profile'] = auto['settings'][mode]
        auto['message'] = 'Automatic profile applied.'
        path.write_text(json.dumps(value))
elif sys.argv[1:] == ['fixture-source']:
    value['automatic']['source'].update(onBattery=True, percentage=10)
    path.write_text(json.dumps(value))
elif sys.argv[1:] == ['fixture-ac']:
    value['automatic']['source'].update(onBattery=False, percentage=70)
    path.write_text(json.dumps(value))
else:
    sys.exit('Invalid fixture request')
