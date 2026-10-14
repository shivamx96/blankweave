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
SPEC = importlib.util.spec_from_file_location('pointer', REPO / 'defaults/shell/pointer-settings.py')
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)
DEFAULTS = {'global': {'sensitivity': 0.0, 'natural_scroll': False, 'left_handed': False, 'accel_profile': ''},
            'touchpad': {'natural_scroll': True, 'tap_to_click': True, 'disable_while_typing': True}}


class PointerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        env = patch.dict(os.environ, XDG_CONFIG_HOME=str(self.root), HYPRLAND_INSTANCE_SIGNATURE='session-one')
        env.start(); self.addCleanup(env.stop)
        self.pointer = m.Pointer()
        self.live = copy.deepcopy(DEFAULTS)
        self.marker = 'defaults'
        self.errors = []
        self.reject = False
        self.override = False
        self.disconnect = False
        self.rows = [{'name': 'mouse', 'address': '0x1'}, {'name': 'touchpad', 'address': '0x2'}]
        self.calls = []
        mocked = patch.object(m, 'ipc', side_effect=self.ipc)
        mocked.start(); self.addCleanup(mocked.stop)
        kinds = patch.object(m, 'device_kinds', return_value={'mouse': 'mouse', 'touchpad': 'touchpad'})
        kinds.start(); self.addCleanup(kinds.stop)

    def ipc(self, *args):
        self.calls.append(args)
        if args[0] == 'repl':
            return self.marker
        if args[0] == 'devices':
            return json.dumps({'mice': self.rows})
        if args[0] == 'configerrors':
            return json.dumps(self.errors)
        if args[0] == '-j':
            return '\n\n'.join(json.dumps({'option': 'input.' + ('touchpad.' if scope == 'touchpad' else '') + key,
                m.FIELDS[scope][key]: self.live[scope][key]}) for scope in m.FIELDS for key in m.FIELDS[scope])
        if args[0] == 'reload':
            if self.reject:
                self.reject = False
                raise ValueError('Compositor rejected configuration')
            saved = self.pointer.settings()
            self.live = copy.deepcopy(DEFAULTS)
            for scope in ('global', 'touchpad'):
                self.live[scope].update(saved[scope])
            if self.override:
                self.live['global']['sensitivity'] = 0.0
            self.marker = m.revision(saved) if self.pointer.config.exists() else 'defaults'
            if self.disconnect:
                self.rows = []
            return 'ok'
        self.fail('Unexpected IPC ' + repr(args))

    def request(self, **changes):
        return dict({'revision': m.revision(self.pointer.settings()), 'session': 'session-one',
                     'scope': 'global', 'device': '', 'address': '', 'key': 'sensitivity', 'value': 0.5}, **changes)

    def test_status_reads_live_values_and_device_kinds(self):
        status = self.pointer.status()
        self.assertTrue(status['installed'] and status['synced'])
        self.assertEqual(status['values'], DEFAULTS)
        self.assertEqual(status['devices'][1]['kind'], 'touchpad')
        self.assertFalse(self.pointer.config.exists())

    def test_global_save_and_reset_persist_and_readback(self):
        self.pointer.apply(self.request())
        self.assertEqual(self.pointer.status()['values']['global']['sensitivity'], .5)
        self.assertEqual(self.pointer.config.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.pointer.rules.read_text(), m.render(self.pointer.settings()))
        self.pointer.apply(self.request(value=None))
        self.assertEqual(self.pointer.settings()['global'], {})
        self.assertEqual(self.pointer.status()['values']['global']['sensitivity'], 0)

    def test_touchpad_defaults_do_not_replace_mouse_defaults(self):
        self.pointer.apply(self.request(scope='touchpad', key='natural_scroll', value=False))
        self.assertFalse(self.pointer.status()['values']['touchpad']['natural_scroll'])
        self.assertEqual(self.pointer.settings()['global'], {})

    def test_device_override_and_reset_preserve_other_devices(self):
        self.pointer.apply(self.request(scope='device', device='touchpad', address='0x2', key='tap_to_click', value=False))
        self.pointer.apply(self.request(scope='device', device='mouse', address='0x1'))
        self.assertEqual(self.pointer.settings()['devices']['touchpad'], {'tap_to_click': False})
        self.assertEqual(self.live, DEFAULTS)
        self.pointer.apply(self.request(scope='device', device='touchpad', address='0x2', key='tap_to_click', value=None))
        self.assertNotIn('touchpad', self.pointer.settings()['devices'])
        self.assertIn('mouse', self.pointer.settings()['devices'])

    def test_stale_revision_or_session_rejected(self):
        request = self.request()
        self.pointer.apply(request)
        for change in ({}, {'revision': m.revision(self.pointer.settings()), 'session': 'old-session'}):
            with self.assertRaisesRegex(ValueError, 'changed'):
                self.pointer.apply(dict(request, **change))
        self.assertEqual(self.pointer.settings()['global']['sensitivity'], .5)

    def test_replacement_and_duplicate_device_not_retargeted(self):
        request = self.request(scope='device', device='mouse', address='old-address')
        with self.assertRaisesRegex(ValueError, 'changed'):
            self.pointer.apply(request)
        self.rows.append({'name': 'mouse', 'address': '0x3'})
        with self.assertRaisesRegex(ValueError, 'ambiguous'):
            self.pointer.apply(self.request(scope='device', device='mouse', address='0x1'))
        self.assertFalse(self.pointer.config.exists())

    def test_touchpad_only_options_rejected_for_mouse(self):
        with self.assertRaisesRegex(ValueError, 'Unsupported'):
            self.pointer.apply(self.request(scope='device', device='mouse', address='0x1', key='tap_to_click', value=True))

    def test_failed_reload_restores_files_and_live_state(self):
        self.reject = True
        with self.assertRaisesRegex(ValueError, 'Previous settings restored'):
            self.pointer.apply(self.request())
        self.assertFalse(self.pointer.config.exists())
        self.assertFalse(self.pointer.rules.exists())
        self.assertEqual(self.live, DEFAULTS)

    def test_personal_override_mismatch_rolls_back(self):
        self.override = True
        with self.assertRaisesRegex(ValueError, 'personal configuration overrides'):
            self.pointer.apply(self.request())
        self.assertFalse(self.pointer.config.exists())

    def test_disconnect_during_apply_rolls_back(self):
        self.disconnect = True
        with self.assertRaisesRegex(ValueError, 'disconnected'):
            self.pointer.apply(self.request(scope='device', device='mouse', address='0x1'))
        self.assertFalse(self.pointer.config.exists())

    def test_existing_errors_or_missing_integration_blocks_writes(self):
        self.errors = ['existing error']
        with self.assertRaisesRegex(ValueError, 'existing Hyprland'):
            self.pointer.apply(self.request())
        self.errors = []
        self.marker = 'missing'
        with self.assertRaisesRegex(ValueError, 'not loaded'):
            self.pointer.apply(self.request())
        self.assertFalse(self.pointer.config.exists())

    def test_external_generated_file_is_preserved(self):
        self.pointer.directory.mkdir()
        self.pointer.rules.write_text('-- user-owned\n')
        with self.assertRaisesRegex(ValueError, 'edited outside'):
            self.pointer.apply(self.request())
        self.assertEqual(self.pointer.rules.read_text(), '-- user-owned\n')

    def test_symlinks_and_corrupt_preferences_preserved(self):
        self.pointer.directory.mkdir()
        original = self.root / 'original'
        original.write_text(json.dumps(m.EMPTY))
        self.pointer.config.symlink_to(original)
        with self.assertRaisesRegex(ValueError, 'symlinks'):
            self.pointer.apply(self.request())
        self.assertTrue(self.pointer.config.is_symlink())
        self.pointer.config.unlink()
        self.pointer.config.write_text('{bad')
        with self.assertRaises(ValueError):
            self.pointer.status()
        self.assertEqual(self.pointer.config.read_text(), '{bad')

    def test_invalid_values_and_code_cannot_be_written(self):
        for value in (True, 2, float('nan'), float('inf'), '0; os.execute("reboot")'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.pointer.apply(self.request(value=value))
        with self.assertRaises(ValueError):
            self.pointer.apply(self.request(key='enabled', value=False))
        self.assertFalse(self.pointer.config.exists())

    def test_generated_lua_quotes_device_names_and_executes_only_config(self):
        data = copy.deepcopy(m.EMPTY)
        name = 'mouse"}); error("injected") -- λ\\test'
        data['devices'][name] = {'sensitivity': .25, 'natural_scroll': True}
        rules = self.root / 'rules.lua'
        rules.write_text(m.render(data))
        harness = self.root / 'test.lua'
        harness.write_text('local seen = nil\nhl = {config=function(_) end, device=function(d) seen=d end}\n'
                           + 'dofile(' + m.lua(str(rules)) + ')\nassert(seen.name == ' + m.lua(name) + ')\n'
                           + 'assert(seen.natural_scroll and seen.sensitivity == 0.25)\n')
        subprocess.run(['lua', str(harness)], check=True)

    def test_save_failure_restores_the_other_file(self):
        original_save = m.save
        def fail_config(path, text):
            if path == self.pointer.config:
                raise OSError('disk full')
            original_save(path, text)
        with patch.object(m, 'save', side_effect=fail_config), self.assertRaisesRegex(ValueError, 'disk full'):
            self.pointer.apply(self.request())
        self.assertFalse(self.pointer.rules.exists())

    def test_existing_custom_acceleration_does_not_disable_other_controls(self):
        self.live['global']['accel_profile'] = 'custom 200 0.0 0.5 1.0'
        self.assertEqual(self.pointer.status()['values']['global']['accel_profile'], 'custom 200 0.0 0.5 1.0')
        with self.assertRaisesRegex(ValueError, 'Unsupported'):
            self.pointer.apply(self.request(key='accel_profile', value='custom arbitrary'))

    def test_read_failure_does_not_mutate_preferences(self):
        with patch.object(m, 'ipc', side_effect=subprocess.TimeoutExpired('hyprctl', 10)), self.assertRaises(subprocess.TimeoutExpired):
            self.pointer.status()
        self.assertFalse(self.pointer.config.exists())


class DeviceKindTests(unittest.TestCase):
    def test_udev_capabilities_not_name_guessing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            event = root / 'sys/event1'
            (event / 'device').mkdir(parents=True)
            (event / 'device/name').write_text('Example Input')
            (event / 'dev').write_text('13:65')
            (root / 'udev').mkdir()
            (root / 'udev/c13:65').write_text('E:ID_INPUT_TOUCHPAD=1\n')
            self.assertEqual(m.device_kinds(root / 'sys', root / 'udev'), {'example-input': 'touchpad'})


if __name__ == '__main__':
    unittest.main()
