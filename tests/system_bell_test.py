#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'defaults/shell'))
import system_bell as bell


class BellTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        env = patch.dict(os.environ, XDG_CONFIG_HOME=self.temp.name, HYPRLAND_INSTANCE_SIGNATURE='test')
        env.start(); self.addCleanup(env.stop)
        self.backend = bell.Bell()
        self.current = 'default'; self.marker = 'defaults'; self.errors = []
        self.override = False; self.calls = []; self.reject = False
        p = patch.object(bell.shutil, 'which', return_value='/fixture/hyprctl'); p.start(); self.addCleanup(p.stop)
        p = patch.object(bell, 'run', side_effect=self.fake_run); p.start(); self.addCleanup(p.stop)

    def fake_run(self, args):
        self.calls.append(args)
        self.assertEqual(args[0], 'hyprctl')
        if args[1] == 'getoption': return json.dumps({'str': self.current})
        if args[1] == 'repl': return self.marker
        if args[1] == 'configerrors': return json.dumps(self.errors)
        if args[1] == 'reload':
            if self.reject:
                self.reject = False
                raise ValueError('Reload rejected')
            data = self.backend.saved()
            self.marker = bell.digest(data) if self.backend.config.exists() else 'defaults'
            self.current = 'default' if self.override or data['enabled'] else 'none'
            return 'ok'
        self.fail(str(args))

    def request(self, enabled):
        state = self.backend.status()
        return {**{key: state[key] for key in ('revision', 'session', 'current')}, 'enabled': enabled}

    def test_status_does_not_write_and_toggle_persists_verified_state(self):
        self.assertTrue(self.backend.status()['writable'])
        self.assertTrue(self.backend.status()['enabled'])
        self.assertFalse(self.backend.directory.exists())
        self.backend.apply(self.request(False))
        self.assertEqual(self.current, 'none')
        self.assertFalse(self.backend.status()['enabled'])
        self.assertIn('bell_sound = "none"', self.backend.rules.read_text())
        self.backend.apply(self.request(True))
        self.assertEqual(self.current, 'default')
        self.assertFalse(any('play' in ' '.join(call) for call in self.calls))

    def test_stale_session_revision_or_current_state_never_writes(self):
        for key in ('session', 'revision', 'current'):
            request = self.request(False); request[key] = 'stale'
            with self.assertRaisesRegex(ValueError, 'state changed'): self.backend.apply(request)
        self.assertFalse(self.backend.config.exists())

    def test_personal_configuration_and_links_preserved(self):
        self.current = '/personal/bell.ogg'
        self.assertFalse(self.backend.status()['writable'])
        self.current = 'default'
        self.backend.directory.mkdir(parents=True)
        self.backend.rules.write_text('-- Personal config\n')
        self.assertFalse(self.backend.status()['writable'])
        self.backend.rules.unlink(); self.backend.rules.symlink_to(Path(self.temp.name) / 'missing')
        self.assertFalse(self.backend.status()['writable'])

    def test_rejected_reload_or_personal_override_rolls_back(self):
        for kind in ('reject', 'override'):
            setattr(self, kind, True)
            with self.assertRaisesRegex(ValueError, 'Previous settings restored'):
                self.backend.apply(self.request(False))
            self.assertFalse(self.backend.config.exists())
            self.assertFalse(self.backend.rules.exists())
            self.assertEqual(self.current, 'default')
            setattr(self, kind, False)

    def test_config_errors_or_unloaded_preferences_are_readonly(self):
        self.errors = ['existing error']
        with self.assertRaisesRegex(ValueError, 'existing compositor errors'): self.backend.apply(self.request(False))
        self.assertFalse(self.backend.config.exists())
        self.marker = 'missing'
        self.assertFalse(self.backend.status()['writable'])
        self.backend.session = ''
        self.assertFalse(self.backend.status()['available'])

    def test_external_edit_during_failed_reload_is_preserved(self):
        def reload_with_edit():
            self.backend.rules.write_text('-- External edit during apply\n')
            raise ValueError('Reload failed')
        with patch.object(self.backend, 'reload', side_effect=reload_with_edit):
            with self.assertRaisesRegex(ValueError, 'Files changed externally'):
                self.backend.apply(self.request(False))
        self.assertEqual(self.backend.rules.read_text(), '-- External edit during apply\n')
        self.assertFalse(self.backend.config.exists())

    def test_failed_second_write_restores_first(self):
        actual = bell.atomic
        def fail(path, text):
            if path == self.backend.rules: raise OSError('disk error')
            return actual(path, text)
        with patch.object(bell, 'atomic', side_effect=fail):
            with self.assertRaisesRegex(ValueError, 'Previous settings restored'): self.backend.apply(self.request(False))
        self.assertFalse(self.backend.config.exists())
        self.assertFalse(self.backend.rules.exists())


if __name__ == '__main__': unittest.main()
