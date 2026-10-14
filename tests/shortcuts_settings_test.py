#!/usr/bin/env python3
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('shortcuts', REPO / 'defaults/shell/shortcuts-settings.py')
m = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(m)

class ShortcutTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        env = patch.dict(os.environ, HOME=self.temp.name, XDG_CONFIG_HOME=self.temp.name, HYPRLAND_INSTANCE_SIGNATURE='session')
        env.start(); self.addCleanup(env.stop)
        self.helper=m.Shortcuts(); self.marker='defaults'; self.errors=[]; self.reject=False; self.override=False; self.options=''
        self.rows=self.bindings({})
        mocked=patch.object(m, 'ipc', side_effect=self.ipc);mocked.start();self.addCleanup(mocked.stop)

    def bindings(self, saved):
        rows=[]
        for r in m.catalog():
            _,mask,key=m.chord(saved.get(r['id'],r['default']))
            rows.append(dict(description='blankweave:'+r['id'],key=key,modmask=mask,keycode=0,submap='',repeat=r['repeat']))
        return rows

    def ipc(self,*args):
        if args[0]=='repl':return self.marker
        if args[0]=='configerrors':return json.dumps(self.errors)
        if args[0]=='binds':return json.dumps(self.rows)
        if args[0]=='getoption':return json.dumps({'str':self.options})
        if args[0]=='reload':
            if self.reject:self.reject=False;raise ValueError('Rejected reload')
            saved=self.helper.settings()
            self.rows=self.bindings(saved['bindings'])
            if self.override:self.rows=[r for r in self.rows if r['description']!='blankweave:terminal']
            self.marker=m.revision(saved) if self.helper.config.exists() else 'defaults'
            return 'ok'
        raise AssertionError(args)

    def request(self, action='terminal',value='SUPER + CTRL + F8'):
        return dict(revision=m.revision(self.helper.settings()),session='session',fingerprint=m.revision([self.rows,self.options]),id=action,value=value)

    def test_apply_reset(self):
        self.helper.apply(self.request())
        self.assertEqual(self.helper.settings()['bindings']['terminal'],'SUPER + CTRL + F8')
        self.assertTrue(self.helper.verified(self.rows,'terminal','SUPER + CTRL + F8'))
        self.helper.apply(self.request(value=None));self.assertEqual(self.helper.settings()['bindings'],{})
        self.assertTrue(self.helper.verified(self.rows,'terminal','SUPER + Return'))

    def test_managed_conflict(self):
        with self.assertRaisesRegex(ValueError,'conflicts'):self.helper.apply(self.request(value='SUPER + b'))
        self.assertFalse(self.helper.config.exists())

    def test_personal_release_and_keycode_conflicts(self):
        for key,code in [('F8',0),('',74)]:
            self.rows=self.bindings({})+[dict(description='Personal action',key=key,modmask=68,keycode=code,submap='',release=True)]
            with self.assertRaisesRegex(ValueError,'Personal action'):self.helper.apply(self.request())

    def test_submaps(self):
        self.rows.append(dict(description='submap action',key='F8',modmask=68,keycode=0,submap='resize'))
        self.helper.apply(self.request())
        self.rows.append(dict(description='universal action',key='F9',modmask=68,keycode=0,submap='resize',submap_universal='true'))
        with self.assertRaisesRegex(ValueError,'universal action'):self.helper.apply(self.request(value='SUPER + CTRL + F9'))

    def test_layout_switch_conflict(self):
        self.options='grp:win_space_toggle'
        # Remove launcher to isolate the XKB conflict.
        self.rows=[r for r in self.rows if r['description']!='blankweave:launcher']
        with self.assertRaisesRegex(ValueError,'layout switcher'):self.helper.apply(self.request(value='SUPER + space'))

    def test_stale(self):
        for key,val in [('revision','old'),('session','old'),('fingerprint','old')]:
            r=self.request();r[key]=val
            with self.assertRaisesRegex(ValueError,'changed'):self.helper.apply(r)

    def test_removed_action(self):
        self.rows=[r for r in self.rows if r['description']!='blankweave:terminal']
        with self.assertRaisesRegex(ValueError,'removed'):self.helper.apply(self.request())
        self.assertFalse(next(r for r in self.helper.status()['rows'] if r['id']=='terminal')['available'])

    def test_unsafe_chords(self):
        for value in ['A','SHIFT + A','SUPER + SUPER + A','SUPER + code:24','SUPER + mouse:272','SUPER + A; os.execute("x")','CTRL + Unknown',[],None]:
            with self.assertRaises(ValueError):m.chord(value)
        self.assertEqual(m.chord('SHIFT + SUPER + b')[0],'SUPER + SHIFT + B')

    def test_rollback(self):
        self.reject=True
        with self.assertRaisesRegex(ValueError,'restored'):self.helper.apply(self.request())
        self.assertFalse(self.helper.config.exists());self.assertFalse(self.helper.rules.exists())

    def test_readback_rollback(self):
        self.override=True
        with self.assertRaisesRegex(ValueError,'overrides'):self.helper.apply(self.request())
        self.assertFalse(self.helper.config.exists())

    def test_existing_errors(self):
        self.errors=['bad config']
        with self.assertRaisesRegex(ValueError,'existing'):self.helper.apply(self.request())

    def test_user_files(self):
        request=self.request();self.helper.directory.mkdir();target=Path(self.temp.name)/'personal';target.write_text('personal')
        self.helper.rules.symlink_to(target)
        with self.assertRaisesRegex(ValueError,'symlinks'):self.helper.apply(request)
        self.helper.rules.unlink();self.helper.rules.write_text('-- personal')
        with self.assertRaisesRegex(ValueError,'preserved'):self.helper.apply(request)
        self.assertEqual(target.read_text(),'personal')

    def test_lua_catalog_and_callbacks(self):
        # Execute the real file with harmless dispatcher stubs; its declarations
        # must match the catalog, including workspace callbacks and repeat flags.
        script='''
local dispatcher = setmetatable({}, {__index=function(self, key) return self end, __call=function() return function() end end})
local workspace_action
hl = {dsp=dispatcher, bind=function(keys, action, options)
 print(options.description .. "\\t" .. keys .. "\\t" .. tostring(options.repeating == true))
 if options.description == "blankweave:workspace-3" then workspace_action=action end
end, get_active_monitor=function() return {active_workspace={id=3}} end,
get_monitors=function() return {{},{}} end, dispatch=function() end}
dofile(arg[0]); assert(type(workspace_action)=="function"); workspace_action(); os.exit(0)
'''
        result=subprocess.run(['lua','-e',script,str(REPO/'defaults/hypr/keybindings.lua')],check=True,text=True,capture_output=True)
        captured=[line.split('\t') for line in result.stdout.splitlines()]
        expected=[['blankweave:'+r['id'],r['default'],str(r['repeat']).lower()] for r in m.catalog()]
        self.assertEqual(captured,expected)
        self.helper.apply(self.request())
        # Saved bindings are applied by Lua without changing the catalog action.
        result=subprocess.run(['lua','-e',script,str(REPO/'defaults/hypr/keybindings.lua')],check=True,text=True,capture_output=True)
        self.assertIn('blankweave:terminal\tSUPER + CTRL + F8\tfalse',result.stdout)

if __name__=='__main__':unittest.main()
