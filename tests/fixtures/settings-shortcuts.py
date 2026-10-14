#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
path=Path(os.environ['SETTINGS_SHORTCUTS_STATE'])
state=json.loads(path.read_text()) if path.exists() else dict(
    revision='initial',session='fixture',fingerprint='live',installed=True,synced=True,message='',
    rows=[dict(id='settings',label='Open Settings',group='Applications',default='SUPER + comma',value='SUPER + comma',available=True,overridden=False),
          dict(id='terminal',label='Open terminal',group='Applications',default='SUPER + Return',value='SUPER + Return',available=True,overridden=False)],
    keys=['comma','Return','F8','F9'],other=[dict(key='F12',modmask=0,keycode=0,description='Hold to dictate',submap='',release=False)],writes=0)
if sys.argv[1:]==['status']:
    print(json.dumps(state))
elif sys.argv[1:]==['apply']:
    request=json.load(sys.stdin)
    assert request['id']=='settings' and request['session']=='fixture'
    assert request['revision']==state['revision'] and request['fingerprint']==state['fingerprint']
    if request['value']=='SUPER + F9':sys.exit('Shortcut conflicts with a personal binding.')
    state['rows'][0]['value']=request['value'] or 'SUPER + comma'
    state['rows'][0]['overridden']=request['value'] is not None
    state['writes']+=1;state['revision']=str(state['writes']);state['fingerprint']='live'+str(state['writes'])
    path.write_text(json.dumps(state))
else:sys.exit(2)
