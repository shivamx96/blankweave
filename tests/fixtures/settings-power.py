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
if sys.argv[1:] == ['status']:
    print(json.dumps(value))
elif sys.argv[1] == 'set':
    time.sleep(0.15)
    if sys.argv[-1] == 'performance':
        sys.exit('Fixture permission denied; profile unchanged.')
    value['profile'] = sys.argv[-1]
    path.write_text(json.dumps(value))
else:
    sys.exit('Invalid fixture request')
