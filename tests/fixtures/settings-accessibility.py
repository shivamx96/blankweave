#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
path=Path(os.environ['SETTINGS_ACCESSIBILITY_STATE'])
state=json.loads(path.read_text()) if path.exists() else dict(
    revision='initial',session='fixture',installed=True,synced=True,
    saved=dict(version=1,reduced_motion=False,high_contrast=False),desktop=dict(reduced_motion=False,high_contrast=False,compositor_motion=False),writes=0)
if sys.argv[1:]==['status']:
    print(json.dumps(state))
elif sys.argv[1:]==['apply']:
    request=json.load(sys.stdin)
    assert request['revision']==state['revision'] and request['session']=='fixture' and request['desktop']==state['desktop']
    if request['key']=='reduced_motion' and request['value'] is False:sys.exit('Personal configuration overrides animations; previous settings restored.')
    state['saved'][request['key']]=request['value'];state['desktop'][request['key']]=request['value']
    if request['key']=='reduced_motion':state['desktop']['compositor_motion']=request['value']
    state['writes']+=1;state['revision']=str(state['writes'])
    path.write_text(json.dumps(state))
    config=Path(os.environ['XDG_CONFIG_HOME'])/'blankweave/accessibility.json';config.parent.mkdir(parents=True,exist_ok=True)
    temporary=config.with_suffix('.tmp');temporary.write_text(json.dumps(state['saved']));temporary.replace(config)
else:sys.exit(2)
