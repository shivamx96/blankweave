#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
REPO=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(REPO/'defaults/shell'))
SPEC=importlib.util.spec_from_file_location('interface',REPO/'defaults/shell/interface-settings.py')
m=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(m)

class InterfaceTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        env=patch.dict(os.environ,HOME=self.temp.name,XDG_CONFIG_HOME=self.temp.name,HYPRLAND_INSTANCE_SIGNATURE='session')
        env.start();self.addCleanup(env.stop)
        self.helper=m.Interface();self.helper.directory.mkdir()
        (self.helper.directory/'theme.json').write_text(json.dumps({'cursorTheme':'Bibata-Modern-Ice'}))
        self.desktop=dict(text_scale=1.0,cursor_size=24);self.marker='defaults';self.errors=[];self.reject=False;self.reject_cursor=False;self.reject_setting=False
        self.writable=True;self.cursor=24;self.calls=[]
        mocked=patch.object(m,'run',side_effect=self.fake_run);mocked.start();self.addCleanup(mocked.stop)
        for version in ('gtk-3.0','gtk-4.0'):
            path=Path(self.temp.name)/version/'settings.ini';path.parent.mkdir()
            path.write_text('[Settings]\ngtk-font-name=Personal 12\ngtk-enable-event-sounds=false\ngtk-cursor-theme-size=24\n')

    def fake_run(self,*args):
        self.calls.append(args)
        if args[0]=='gsettings':
            key='text_scale' if args[3]=='text-scaling-factor' else 'cursor_size'
            if args[1]=='get':return str(self.desktop[key])
            if args[1]=='writable':return str(self.writable).lower()
            if args[1]=='set':
                if self.reject_setting:self.reject_setting=False;raise ValueError('Desktop rejected value')
                self.desktop[key]=float(args[4]) if key=='text_scale' else int(args[4]);return ''
        if args[:2]==('hyprctl','repl'):return self.marker
        if args[:2]==('hyprctl','configerrors'):return json.dumps(self.errors)
        if args[:2]==('hyprctl','reload'):
            if self.reject:self.reject=False;raise ValueError('Reload rejected')
            self.marker=m.revision(self.helper.settings()) if self.helper.config.exists() else 'defaults';return 'ok'
        if args[:2]==('hyprctl','setcursor'):
            if self.reject_cursor:self.reject_cursor=False;return 'error'
            self.cursor=int(args[3]);return 'ok'
        raise AssertionError(args)

    def request(self,key='cursor_size',value=32):
        return dict(revision=m.revision(self.helper.settings()),session='session',desktop=dict(self.desktop),theme='Bibata-Modern-Ice',key=key,value=value)

    def test_cursor_save_and_reset(self):
        self.helper.apply(self.request());self.assertEqual(self.cursor,32);self.assertEqual(self.desktop['cursor_size'],32)
        for version in ('gtk-3.0','gtk-4.0'):
            text=(Path(self.temp.name)/version/'settings.ini').read_text()
            self.assertIn('gtk-cursor-theme-size=32',text);self.assertIn('gtk-font-name=Personal 12',text);self.assertIn('gtk-enable-event-sounds=false',text)
        self.helper.apply(self.request(value=24));self.assertEqual(self.cursor,24)

    def test_text_does_not_change_cursor(self):
        self.desktop['cursor_size']=40
        self.helper.apply(self.request('text_scale',1.3))
        self.assertEqual(self.desktop,dict(text_scale=1.3,cursor_size=40))
        self.assertFalse(any(c[:2]==('hyprctl','setcursor') for c in self.calls))
        self.assertEqual(self.helper.settings()['text_scale'],1.3)

    def test_stale(self):
        for key,value in [('revision','old'),('session','old'),('desktop',{}),('theme','other')]:
            request=self.request();request[key]=value
            with self.assertRaisesRegex(ValueError,'changed'):self.helper.apply(request)

    def test_bad_values(self):
        for key,value in [('cursor_size',True),('cursor_size',1000),('text_scale',0),('text_scale',1.4),('text_scale','1.3')]:
            with self.assertRaises(ValueError):self.helper.apply(self.request(key,value))

    def test_rollback_reload_cursor_and_desktop(self):
        for failure in ('reject','reject_cursor','reject_setting'):
            setattr(self,failure,True)
            with self.assertRaisesRegex(ValueError,'restored'):self.helper.apply(self.request())
            self.assertFalse(self.helper.config.exists());self.assertFalse(self.helper.rules.exists())
            self.assertEqual(self.cursor,24);self.assertEqual(self.desktop['cursor_size'],24)
            for version in ('gtk-3.0','gtk-4.0'):
                path=Path(self.temp.name)/version/'settings.ini'
                self.assertIn('gtk-cursor-theme-size=24',path.read_text());self.assertEqual(path.stat().st_mode & 0o777,0o644)

    def test_readonly(self):
        self.writable=False
        with self.assertRaisesRegex(ValueError,'read-only'):self.helper.apply(self.request())
        self.assertFalse(self.helper.config.exists())

    def test_existing_errors(self):
        self.errors=['bad config']
        with self.assertRaisesRegex(ValueError,'existing'):self.helper.apply(self.request())

    def test_personal_lua_and_symlink(self):
        request=self.request();self.helper.rules.write_text('-- personal')
        with self.assertRaisesRegex(ValueError,'preserved'):self.helper.apply(request)
        self.helper.rules.unlink();self.helper.rules.symlink_to(self.helper.directory/'theme.json')
        with self.assertRaisesRegex(ValueError,'symlinks'):self.helper.apply(request)

    def test_lua_startup_size(self):
        self.helper.apply(self.request(value=48))
        script='hl={env=function(k,v) assert(v=="48") end}; dofile(arg[0]); assert(blankweave_interface_revision); os.exit(0)'
        subprocess.run(['lua','-e',script,str(self.helper.rules)],check=True)

    def test_concurrent_change(self):
        with self.helper.locked():
            with self.assertRaisesRegex(ValueError,"in progress"):self.helper.apply(self.request())

    def test_status(self):
        state=self.helper.status();self.assertTrue(state['synced']);self.assertEqual(state['saved'],m.DEFAULTS)

if __name__=='__main__':unittest.main()
