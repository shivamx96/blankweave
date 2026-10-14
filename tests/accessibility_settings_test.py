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
SPEC=importlib.util.spec_from_file_location('accessibility',REPO/'defaults/shell/accessibility-settings.py')
m=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(m)

class AccessibilityTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        env=patch.dict(os.environ,HOME=self.temp.name,XDG_CONFIG_HOME=self.temp.name,HYPRLAND_INSTANCE_SIGNATURE='session')
        env.start();self.addCleanup(env.stop)
        self.helper=m.Accessibility();self.helper.directory.mkdir()
        self.desktop=dict(reduced_motion=False,high_contrast=False,compositor_motion=False)
        self.marker='defaults';self.errors=[];self.reject=False;self.reject_setting=False;self.override=False;self.writable=True
        mocked=patch.object(m,'run',side_effect=self.fake_run);mocked.start();self.addCleanup(mocked.stop)
        for version in ('gtk-3.0','gtk-4.0'):
            path=Path(self.temp.name)/version/'settings.ini';path.parent.mkdir()
            path.write_text('[Settings]\ngtk-font-name=Personal 12\ngtk-cursor-theme-size=32\ngtk-enable-animations=true\n')

    def fake_run(self,*args):
        if args[0]=='gsettings':
            key='reduced_motion' if args[3]=='enable-animations' else 'high_contrast'
            if args[1]=='get':return str(not self.desktop[key] if key=='reduced_motion' else self.desktop[key]).lower()
            if args[1]=='writable':return str(self.writable).lower()
            if args[1]=='set':
                if self.reject_setting:self.reject_setting=False;raise ValueError('Desktop rejected value')
                self.desktop[key]=(args[4]=='false') if key=='reduced_motion' else (args[4]=='true');return ''
        if args[:2]==('hyprctl','getoption'):return json.dumps({'bool':not self.desktop['compositor_motion']})
        if args[:2]==('hyprctl','repl'):return self.marker
        if args[:2]==('hyprctl','configerrors'):return json.dumps(self.errors)
        if args[:2]==('hyprctl','reload'):
            if self.reject:self.reject=False;raise ValueError('Reload rejected')
            data=self.helper.settings()
            self.desktop['compositor_motion']=False if self.override else data['reduced_motion']
            self.marker=m.revision(data) if self.helper.config.exists() else 'defaults';return 'ok'
        raise AssertionError(args)

    def request(self,key='reduced_motion',value=True):
        return dict(revision=m.revision(self.helper.settings()),session='session',desktop=dict(self.desktop),key=key,value=value)

    def test_motion_and_restore(self):
        self.helper.apply(self.request());self.assertTrue(self.desktop['reduced_motion']);self.assertTrue(self.desktop['compositor_motion'])
        for version in ('gtk-3.0','gtk-4.0'):
            text=(Path(self.temp.name)/version/'settings.ini').read_text()
            self.assertIn('gtk-enable-animations=false',text);self.assertIn('gtk-font-name=Personal 12',text);self.assertIn('gtk-cursor-theme-size=32',text)
        self.helper.apply(self.request(value=False));self.assertFalse(self.desktop['compositor_motion']);self.assertFalse(self.desktop['reduced_motion'])

    def test_independent_preferences(self):
        self.helper.apply(self.request());self.helper.apply(self.request('high_contrast',True))
        self.assertTrue(all(self.desktop.values()))
        self.helper.apply(self.request('high_contrast',False));self.assertTrue(self.desktop['reduced_motion'])

    def test_stale(self):
        for key,value in [('revision','old'),('session','old'),('desktop',{})]:
            request=self.request();request[key]=value
            with self.assertRaisesRegex(ValueError,'changed'):self.helper.apply(request)

    def test_strict_booleans(self):
        for value in [1,0,None,'true',[],{}]:
            with self.assertRaises(ValueError):self.helper.apply(self.request(value=value))

    def test_rollback(self):
        for failure in ('reject','reject_setting','override'):
            setattr(self,failure,True)
            with self.assertRaisesRegex(ValueError,'restored'):self.helper.apply(self.request())
            self.assertFalse(self.helper.config.exists());self.assertFalse(self.helper.rules.exists())
            self.assertFalse(self.desktop['reduced_motion']);self.assertFalse(self.desktop['compositor_motion'])
            for version in ('gtk-3.0','gtk-4.0'):
                self.assertIn('gtk-enable-animations=true',(Path(self.temp.name)/version/'settings.ini').read_text())
            setattr(self,failure,False)

    def test_readonly_and_errors(self):
        self.writable=False
        with self.assertRaisesRegex(ValueError,'read-only'):self.helper.apply(self.request())
        self.writable=True;self.errors=['bad config']
        with self.assertRaisesRegex(ValueError,'existing'):self.helper.apply(self.request())

    def test_personal_files(self):
        request=self.request();self.helper.rules.write_text('-- personal')
        with self.assertRaisesRegex(ValueError,'preserved'):self.helper.apply(request)
        self.helper.rules.unlink();self.helper.rules.symlink_to(self.helper.directory/'missing')
        with self.assertRaisesRegex(ValueError,'symlinks'):self.helper.apply(request)

    def test_concurrent_change(self):
        with self.helper.locked():
            with self.assertRaisesRegex(ValueError,'in progress'):self.helper.apply(self.request())

    def test_compositor_integration_order(self):
        self.helper.apply(self.request())
        script='''local enabled; hl={config=function(v) enabled=v.animations.enabled end,curve=function() end,animation=function() end}; dofile(arg[0]); assert(enabled==false); assert(blankweave_accessibility_revision); os.exit(0)'''
        subprocess.run(['lua','-e',script,str(REPO/'defaults/hypr/animations.lua')],check=True)

if __name__=='__main__':unittest.main()
