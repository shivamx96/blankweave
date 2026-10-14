import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
SHELL=Path(__file__).resolve().parents[1]/'defaults/shell'
sys.path.insert(0,str(SHELL))
class Webapps(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        env=patch.dict(os.environ,XDG_CONFIG_HOME=str(self.root/'config'),XDG_DATA_HOME=str(self.root/'data'),BLANKWEAVE_WEBAPP_BROWSER='/bin/true')
        env.start();self.addCleanup(env.stop)
        spec=importlib.util.spec_from_file_location('webapps',SHELL/'webapps-settings.py');self.m=importlib.util.module_from_spec(spec);spec.loader.exec_module(self.m)
    def apply(self,**request):self.m.apply(dict(revision=self.m.status()['revision'],**request))
    def test_create_remove_and_url_field_code_escape(self):
        self.apply(action='create',name='My App',url='https://example.com/a%20b')
        row=self.m.status()['rows'][0];self.assertTrue(row['removable']);self.assertEqual(row['id'],'my-app')
        text=(self.m.APPS/'blankweave-webapp-my-app.desktop').read_text()
        self.assertIn('a%%20b',text);self.assertIn('Icon=web-browser',text)
        with self.assertRaises(ValueError):self.apply(action='create',name='My App',url='https://example.com')
        self.apply(action='remove',id=row['id']);self.assertEqual(self.m.status()['rows'],[])
    def test_injection_credentials_and_collision_rejected(self):
        for name,url in [('Bad\nExec=oops','https://example.com'),('Good','file:///etc/passwd'),('Good','https://user:pass@example.com'),('Good','https://example.com/$(oops)')]:
            with self.assertRaises(ValueError):self.apply(action='create',name=name,url=url)
        self.assertEqual(self.m.status()['rows'],[])
    def test_bundled_symlink_and_stale(self):
        self.apply(action='create',name='One',url='https://example.com')
        stale=self.m.status()['revision'];path=self.m.APPS/'blankweave-webapp-one.desktop'
        path.write_text(path.read_text().replace('=user','=bundled'))
        with self.assertRaises(ValueError):self.m.apply(dict(revision=stale,action='remove',id='one'))
        with self.assertRaises(ValueError):self.apply(action='remove',id='one')
        target=self.root/'target';target.write_text(path.read_text().replace('=bundled','=user'));path.unlink();path.symlink_to(target)
        with self.assertRaises(ValueError):self.apply(action='remove',id='one')
        self.assertTrue(target.exists())
if __name__=='__main__':unittest.main()
