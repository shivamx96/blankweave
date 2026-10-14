import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
SHELL=Path(__file__).resolve().parents[1]/'defaults/shell'
sys.path.insert(0,str(SHELL))
class Wallpaper(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        env=patch.dict(os.environ,XDG_CONFIG_HOME=str(self.root));env.start();self.addCleanup(env.stop)
        spec=importlib.util.spec_from_file_location('wallpaper',SHELL/'wallpaper-settings.py')
        self.m=importlib.util.module_from_spec(spec);spec.loader.exec_module(self.m)
        self.theme=self.root/'theme.png';self.theme.touch()
        self.image=self.root/'custom image.png';self.image.touch()
        (self.root/'blankweave').mkdir();(self.root/'blankweave/theme.json').write_text(json.dumps({'wallpaper':str(self.theme)}))
        self.screens=[dict(name='DP-1',description='Unique screen')]
        self.current={'DP-1':str(self.theme)};self.calls=[];self.reject=False
        def command(args,**kwargs):
            self.calls.append(args)
            if args[0]=='hyprctl':return json.dumps(self.screens)
            if args[1]=='query':return '\n'.join(f': {k}: 1920x1080, scale: 1, currently displaying: image: {v}' for k,v in self.current.items())
            if self.reject:self.reject=False;raise ValueError('Image rejected')
            self.current[args[args.index('--outputs')+1]]=args[2];return ''
        mock=patch.object(self.m,'run',command);mock.start();self.addCleanup(mock.stop)
    def apply(self,**request):self.m.apply(dict(revision=self.m.status()['revision'],id='Unique screen',**request))
    def test_set_restore_new_connector_reset(self):
        self.apply(action='set',path=str(self.image),fit='fit')
        self.assertEqual(self.current['DP-1'],str(self.image))
        self.screens=[dict(name='DP-2',description='Unique screen')];self.current={'DP-2':str(self.theme)}
        self.m.restore_saved('DP-2');self.assertEqual(self.current['DP-2'],str(self.image))
        self.apply(action='reset');self.assertEqual(self.current['DP-2'],str(self.theme));self.assertEqual(self.m.preferences(),{})
    def test_failure_invalid_and_stale_do_not_persist(self):
        self.reject=True
        with self.assertRaises(ValueError):self.apply(action='set',path=str(self.image),fit='crop')
        self.assertFalse(self.m.PATH.exists());self.assertEqual(self.current['DP-1'],str(self.theme))
        with self.assertRaises(ValueError):self.apply(action='set',path='/missing.png',fit='fit')
        revision=self.m.status()['revision'];self.screens=[]
        with self.assertRaises(ValueError):self.m.apply(dict(revision=revision,id='Unique screen',action='reset'))
        self.assertFalse(self.m.PATH.exists())
    def test_duplicate_description_and_symlink(self):
        self.screens.append(dict(name='DP-2',description='Unique screen'))
        self.assertEqual(len(set(s['id'] for s in self.m.monitors())),2)
        target=self.root/'owned';target.write_text('{}');self.m.PATH.symlink_to(target)
        self.assertFalse(self.m.status()['writable'])
if __name__=='__main__':unittest.main()
