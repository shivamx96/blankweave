import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
SHELL = Path(__file__).resolve().parents[1] / 'defaults/shell'
sys.path.insert(0, str(SHELL))

class Startup(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        env = patch.dict(os.environ, XDG_CONFIG_HOME=str(self.root/'user'), XDG_CONFIG_DIRS=str(self.root/'system'), XDG_CURRENT_DESKTOP='Hyprland')
        env.start(); self.addCleanup(env.stop)
        spec = importlib.util.spec_from_file_location('startup', SHELL/'startup-settings.py')
        self.m = importlib.util.module_from_spec(spec); spec.loader.exec_module(self.m)
        self.system = self.root/'system/autostart/test.desktop'; self.system.parent.mkdir(parents=True)
        self.original = '# Keep\n[Desktop Entry]\nType=Application\nName=Test\nName[fr]=Essai\nExec=/bin/false\nOnlyShowIn=Hyprland;\n[Other]\nHidden=preserve\n'
        self.system.write_text(self.original)
        self.user = self.root/'user/autostart/test.desktop'

    def apply(self, **request): self.m.apply(dict(revision=self.m.status()['revision'], id='test.desktop', **request))

    def test_disable_enable_reset_preserves_system_and_keys(self):
        self.apply(action='enable', enabled=False)
        self.assertFalse(self.m.status()['rows'][0]['enabled'])
        self.assertEqual(self.system.read_text(),self.original)
        self.assertIn('Name[fr]=Essai',self.user.read_text())
        self.assertIn('[Other]\nHidden=preserve', self.user.read_text())
        self.apply(action='enable', enabled=True)
        self.assertTrue(self.m.status()['rows'][0]['enabled'])
        self.apply(action='reset')
        self.assertFalse(self.user.exists())

    def test_stale_symlink_and_malformed(self):
        revision = self.m.status()['revision']; self.system.write_text(self.original+'# Changed\n')
        with self.assertRaises(ValueError): self.m.apply(dict(revision=revision,id='test.desktop',action='enable',enabled=False))
        self.user.parent.mkdir(parents=True); self.user.symlink_to(self.system)
        self.assertFalse(self.m.status()['rows'][0]['writable'])
        self.user.unlink(); self.user.write_text('broken')
        self.assertFalse(self.m.status()['rows'][0]['writable'])

    def test_restrictions_and_personal_entries(self):
        self.system.write_text(self.original.replace('Hyprland;', 'GNOME;'))
        self.assertIn('another desktop', self.m.status()['rows'][0]['reason'])
        self.user.parent.mkdir(parents=True); self.user.write_text(self.original)
        self.apply(action='enable',enabled=False)
        self.assertFalse(self.m.status()['rows'][0]['reset'])
        with self.assertRaises(ValueError): self.apply(action='reset')

if __name__ == '__main__': unittest.main()
