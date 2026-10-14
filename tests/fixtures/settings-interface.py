#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
path=Path(os.environ['SETTINGS_INTERFACE_STATE'])
state=json.loads(path.read_text()) if path.exists() else dict(
    revision='initial',session='fixture',installed=True,synced=True,theme='Bibata-Modern-Ice',
    saved=dict(version=1,text_scale=1,cursor_size=24),desktop=dict(text_scale=1,cursor_size=24),writes=0)
if sys.argv[1:]==['status']:
    print(json.dumps(state))
elif sys.argv[1:]==['apply']:
    request=json.load(sys.stdin)
    assert request['revision']==state['revision'] and request['session']=='fixture'
    assert request['desktop']==state['desktop'] and request['theme']==state['theme']
    if request['key']=='cursor_size' and request['value']==48:sys.exit('Pointer size rejected; previous settings restored.')
    state['saved'][request['key']]=request['value'];state['desktop'][request['key']]=request['value']
    state['writes']+=1;state['revision']=str(state['writes'])
    path.write_text(json.dumps(state))
    config=Path(os.environ['XDG_CONFIG_HOME'])/'blankweave/interface.json';config.parent.mkdir(parents=True,exist_ok=True)
    temporary=config.with_suffix('.tmp');temporary.write_text(json.dumps(state['saved']));temporary.replace(config)
else:sys.exit(2)
