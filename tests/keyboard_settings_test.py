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
SPEC = importlib.util.spec_from_file_location('keyboard', REPO / 'defaults/shell/keyboard-settings.py')
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)
DEFAULTS = dict(kb_layout='us', kb_variant='', kb_options='caps:escape', kb_file='', kb_rules='', kb_model='')

class KeyboardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        env = patch.dict(os.environ, XDG_CONFIG_HOME=self.temp.name, HYPRLAND_INSTANCE_SIGNATURE='session')
        env.start(); self.addCleanup(env.stop)
        self.keyboard = m.Keyboard()
        self.live = copy.deepcopy(DEFAULTS)
        self.marker = 'defaults'; self.errors = []; self.reject = False; self.override = False
        self.rows = [dict(name='keyboard', address='0x1', layout='us,de', variant=',', active_keymap='English (US)', active_layout_index=0)]
        mocked = patch.object(m, 'ipc', side_effect=self.ipc); mocked.start(); self.addCleanup(mocked.stop)

    def ipc(self, *args):
        if args[0] == 'repl': return self.marker
        if args[0] == 'configerrors': return json.dumps(self.errors)
        if args[0] == 'devices': return json.dumps({'keyboards': self.rows})
        if args[0] == '-j': return '\n\n'.join(json.dumps({'option':'input.'+k, 'str':v}) for k,v in self.live.items())
        if args[0] == 'reload':
            if self.reject:
                self.reject = False
                raise ValueError('Rejected reload')
            self.live = copy.deepcopy(DEFAULTS)
            self.live.update(self.keyboard.settings()['values'])
            if self.override: self.live['kb_layout'] = 'fr'
            self.marker = m.revision(self.keyboard.settings()) if self.keyboard.config.exists() else 'defaults'
            return 'ok'
        if args[0] == 'switchxkblayout':
            self.rows[0]['active_layout_index'] = int(args[2]); return 'ok'
        raise AssertionError(args)

    def request(self):
        return dict(revision=m.revision(self.keyboard.settings()), session='session', expected=copy.deepcopy(self.live),
                    values=dict(kb_layout='us,de', kb_variant=',', kb_options='caps:escape,grp:alt_shift_toggle'))

    def test_apply_reset_and_lua(self):
        self.keyboard.apply(self.request())
        self.assertEqual(self.live['kb_layout'], 'us,de')
        self.assertEqual(self.live['kb_options'], 'caps:escape,grp:alt_shift_toggle')
        subprocess.run(['lua', '-e', 'hl={config=function(v) assert(v.input.kb_layout=="us,de") end}; dofile(arg[1])', str(self.keyboard.rules)], check=True)
        r=self.request();r['values']={};self.keyboard.apply(r)
        self.assertEqual(self.live, DEFAULTS)

    def test_rollback(self):
        self.reject=True
        with self.assertRaisesRegex(ValueError,'restored'): self.keyboard.apply(self.request())
        self.assertFalse(self.keyboard.config.exists());self.assertFalse(self.keyboard.rules.exists())

    def test_override_rollback(self):
        self.override=True
        with self.assertRaisesRegex(ValueError,'overrides'): self.keyboard.apply(self.request())
        self.assertFalse(self.keyboard.config.exists())

    def test_stale_revision_session_and_values(self):
        for key,value in [('revision','old'),('session','old'),('expected',{})]:
            r=self.request();r[key]=value
            with self.assertRaisesRegex(ValueError,'changed'): self.keyboard.apply(r)
        self.assertFalse(self.keyboard.config.exists())

    def test_bad_layout_lists(self):
        for layouts, variants in [('',''),('us,de', ''),('us,us',','),('invalid',''),('us','invalid'),('us,de,fr,gb,es',',,,,')]:
            r=self.request();r['values'].update(kb_layout=layouts,kb_variant=variants)
            with self.assertRaises(ValueError): self.keyboard.apply(r)

    def test_preserve_options(self):
        r=self.request();r['values']['kb_options']='grp:alt_shift_toggle'
        with self.assertRaisesRegex(ValueError,'unrelated'):self.keyboard.apply(r)

    def test_custom_shortcut_preserved(self):
        self.live['kb_options']='caps:escape,grp:rctrl_toggle'
        r=self.request();r['values']['kb_options']=self.live['kb_options'];self.keyboard.apply(r)
        self.assertEqual(self.live['kb_options'],'caps:escape,grp:rctrl_toggle')

    def test_custom_keymap(self):
        self.live['kb_file']='/custom.xkb'
        with self.assertRaisesRegex(ValueError,'custom keymap'):self.keyboard.apply(self.request())

    def test_external_lua(self):
        self.keyboard.directory.mkdir();self.keyboard.rules.write_text('-- personal')
        with self.assertRaisesRegex(ValueError,'preserved'):self.keyboard.apply(self.request())
        self.assertEqual(self.keyboard.rules.read_text(),'-- personal')

    def test_symlink(self):
        request = self.request()
        self.keyboard.directory.mkdir(); target=Path(self.temp.name)/'personal';target.write_text('private')
        self.keyboard.config.symlink_to(target)
        with self.assertRaisesRegex(ValueError,'symlinks'):self.keyboard.apply(request)
        self.assertEqual(target.read_text(),'private')

    def test_config_errors(self):
        self.errors=['bad config']
        with self.assertRaisesRegex(ValueError,'existing'):self.keyboard.apply(self.request())

    def test_switch_identity_and_index(self):
        r=dict(session='session',device='keyboard',address='0x1',layout='us,de',variant=',',index=1)
        self.keyboard.switch(r);self.assertEqual(self.rows[0]['active_layout_index'],1)
        for key,value in [('address','0x2'),('layout','us'),('index',2),('index',True),('session','old')]:
            bad=dict(r);bad[key]=value
            with self.assertRaises(ValueError):self.keyboard.switch(bad)
        self.rows.append(dict(self.rows[0]))
        with self.assertRaisesRegex(ValueError,'changed'):self.keyboard.switch(r)

    def test_status_catalog(self):
        status=self.keyboard.status()
        self.assertTrue(status['synced'])
        self.assertTrue(any(r['layout']=='us' and r['variant']=='dvorak' for r in status['catalog']))

if __name__ == '__main__': unittest.main()
