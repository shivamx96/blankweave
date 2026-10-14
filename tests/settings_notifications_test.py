import datetime
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

SHELL = Path(__file__).resolve().parents[1] / 'defaults/shell'
sys.path.insert(0, str(SHELL))


class Notifications(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.env = patch.dict(os.environ, XDG_CONFIG_HOME=self.tmp.name, XDG_CONFIG_DIRS=self.tmp.name, XDG_RUNTIME_DIR=self.tmp.name)
        self.env.start(); self.addCleanup(self.env.stop)
        spec = importlib.util.spec_from_file_location('notifications', SHELL / 'notification-settings.py')
        self.module = importlib.util.module_from_spec(spec); spec.loader.exec_module(self.module)
        self.paused = False
        self.fail = False
        self.calls = []
        def command(args, **kwargs):
            self.calls.append(args)
            if args[1] == 'is-paused': return str(self.paused).lower()
            if args[1] == 'set-paused': self.paused = args[2] == 'true'; return ''
            if args[1] == 'history': return json.dumps({'data': [[{'appname': {'data': 'Mail [Work]'}}]]})
            if args[1] == 'reload' and self.fail: self.fail = False; raise ValueError('Reload failed')
            return ''
        self.mock = patch.object(self.module, 'run', command); self.mock.start(); self.addCleanup(self.mock.stop)

    def apply(self, **request):
        self.module.apply(dict(revision=self.module.status()['revision'], **request))

    def test_overnight_boundaries(self):
        value = dict(self.module.DEFAULT, schedule=True)
        for hour, minute, expected in [(21,59,False),(22,0,True),(7,59,True),(8,0,False)]:
            self.assertEqual(self.module.quiet(value, datetime.datetime(2026,1,1,hour,minute)), expected)
        value.update(start='09:00',end='17:00')
        self.assertTrue(self.module.quiet(value,datetime.datetime(2026,1,1,12)))

    def test_manual_rules_and_stale_revision(self):
        stale = self.module.status()['revision']
        self.apply(action='manual', value=True)
        self.assertTrue(self.paused)
        with self.assertRaises(ValueError): self.module.apply(dict(revision=stale, action='manual', value=False))
        self.apply(action='app', app='Mail [Work]', blocked=True)
        self.assertIn('appname = "Mail [[]Work]"', self.module.RULES.read_text())
        self.apply(action='app', app='Mail [Work]', blocked=False)
        self.assertNotIn('skip_display', self.module.RULES.read_text())

    def test_failed_reload_restores_and_invalid_schedule_no_write(self):
        self.apply(action='manual', value=True)
        before = self.module.PATH.read_bytes(), self.module.RULES.read_bytes()
        self.fail = True
        with self.assertRaises(ValueError): self.apply(action='manual', value=False)
        self.assertEqual(before, (self.module.PATH.read_bytes(), self.module.RULES.read_bytes()))
        self.assertTrue(self.paused)
        with self.assertRaises(ValueError): self.apply(action='schedule', enabled=True, start='25:00', end='08:00')
        self.assertEqual(before, (self.module.PATH.read_bytes(), self.module.RULES.read_bytes()))

    def test_symlink_protected_and_personal_rules_preserved(self):
        personal = Path(self.tmp.name) / 'dunst/dunstrc.d/95-personal.conf'
        personal.parent.mkdir(parents=True); personal.write_text('# personal\n')
        self.apply(action='manual', value=True)
        self.assertEqual(personal.read_text(), '# personal\n')
        self.module.PATH.unlink(); self.module.PATH.symlink_to(personal)
        with self.assertRaises(ValueError): self.module.status()

    def tick(self, active):
        with patch.object(self.module, 'quiet', return_value=active):
            self.module.reconcile(self.module.policy())

    def test_app_edit_preserves_preexisting_pause(self):
        self.paused = True
        self.apply(action='app', app='Mail [Work]', blocked=True)
        self.assertTrue(self.paused)
        self.tick(False)
        self.assertTrue(self.paused)
        self.assertFalse(any(c[1:] == ['set-paused', 'false'] for c in self.calls))

    def test_external_pause_and_resume_are_adopted(self):
        self.apply(action='manual', value=False)
        self.paused = True
        self.tick(False)
        self.assertTrue(self.paused)
        self.assertTrue(self.module.policy()['manual'])
        self.paused = False
        self.tick(False)
        self.assertFalse(self.paused)
        self.assertFalse(self.module.policy()['manual'])
        self.tick(False)
        self.assertFalse(self.paused)

    def test_toggle_uses_actual_state_in_both_directions(self):
        self.apply(action='manual', value=False)
        self.paused = True
        state = self.module.status()
        self.module.apply(dict(revision=state['revision'], action='manual', value=not state['paused']))
        self.assertFalse(self.paused)
        self.apply(action='manual', value=True)
        self.paused = False
        state = self.module.status()
        self.module.apply(dict(revision=state['revision'], action='manual', value=not state['paused']))
        self.assertTrue(self.paused)

    def test_schedule_releases_only_its_own_pause(self):
        self.apply(action='manual', value=False)
        self.tick(True)
        self.assertTrue(self.paused)
        self.tick(False)
        self.assertFalse(self.paused)
        self.paused = True
        self.tick(False)
        self.tick(True)
        self.tick(False)
        self.assertTrue(self.paused)

    def test_external_resume_overrides_current_window_not_next_window(self):
        self.apply(action='manual', value=False)
        self.tick(True)
        self.paused = False
        self.tick(True)
        self.tick(True)
        self.assertFalse(self.paused)
        self.tick(False)
        self.tick(True)
        self.assertTrue(self.paused)

    def test_manual_resume_and_schedule_disable(self):
        self.apply(action='manual', value=False)
        self.tick(True)
        with patch.object(self.module, 'quiet', return_value=True):
            self.apply(action='manual', value=False)
        self.tick(True)
        self.assertFalse(self.paused)
        self.tick(False)
        self.tick(True)
        with patch.object(self.module, 'quiet', side_effect=[True, True, False]):
            self.apply(action='schedule', enabled=False, start='22:00', end='08:00')
        self.assertFalse(self.paused)

    def test_session_restore_and_failed_state_write_rollback(self):
        self.apply(action='manual', value=True)
        self.module.STATE.unlink()
        self.paused = False
        self.tick(False)
        self.assertTrue(self.paused)
        before = self.module.PATH.read_bytes(), self.module.STATE.read_bytes()
        original = self.module.atomic
        def write(path, text):
            if path == self.module.STATE: raise OSError('Session state unavailable')
            original(path, text)
        with patch.object(self.module, 'atomic', side_effect=write):
            with self.assertRaises(OSError): self.apply(action='manual', value=False)
        self.assertTrue(self.paused)
        self.assertEqual(before, (self.module.PATH.read_bytes(), self.module.STATE.read_bytes()))


if __name__ == '__main__': unittest.main()
