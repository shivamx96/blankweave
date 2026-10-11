#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
import time

path = Path(os.environ['SETTINGS_BATTERY_STATE'])
value = json.loads(path.read_text()) if path.exists() else {'available': True, 'batteries': [
    {'path': '/battery/0', 'owner': ':1.34', 'identity': 'first', 'name': '<b>Battery A</b>', 'vendor': 'Vendor',
     'charge': 67, 'health': 94, 'energyFull': 47, 'energyDesign': 50, 'cycles': 99, 'state': 'Discharging',
     'supported': True, 'enabled': False, 'firmware': True, 'start': None, 'end': None},
    {'path': '/battery/1', 'owner': ':1.34', 'identity': 'second', 'name': 'Battery B', 'vendor': 'Vendor',
     'charge': None, 'health': None, 'energyFull': None, 'energyDesign': None, 'cycles': None, 'state': 'Unknown',
     'supported': False, 'enabled': None, 'firmware': False, 'start': None, 'end': None}]}
if sys.argv[1:] == ['status']:
    print(json.dumps(value))
elif sys.argv[1:] == ['set']:
    request = json.load(sys.stdin)
    time.sleep(0.15)
    row = next((row for row in value['batteries'] if all(row[key] == request[key] for key in ('owner', 'path', 'identity'))), None)
    if not row:
        sys.exit('Fixture battery changed.')
    if not request['enabled']:
        sys.exit('Fixture permission denied.')
    row['enabled'] = request['enabled']
    path.write_text(json.dumps(value))
else:
    sys.exit('Invalid fixture command')
