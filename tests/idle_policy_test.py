#!/usr/bin/env python3
"""Isolated idle policy and supervisor tests: never invoke host session actions."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('idle_policy', REPO / 'defaults/shell/idle-policy.py')
idle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(idle)


class IdleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.env = patch.dict(os.environ, {'XDG_CONFIG_HOME': str(self.root / 'config'),
            'XDG_DATA_HOME': str(self.root / 'data'), 'XDG_RUNTIME_DIR': str(self.root / 'run')})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.policy = idle.Policy()
        self.policy.base.parent.mkdir(parents=True)
        self.base = (REPO / 'defaults/hardware/hypridle-battery.conf').read_text()
        self.policy.base.write_text(self.base)
        self.policy.entry.parent.mkdir(parents=True)
        self.policy.entry.symlink_to(self.policy.base)

    def test_defaults_preserve_installed_policy(self):
        self.assertEqual(self.policy.desired()[0], idle.normalize(self.base))
        self.assertFalse(self.policy.config.exists())
        self.assertEqual(self.policy.settings()['ac'], {'dim': 150, 'lock': 300, 'screen': 360, 'suspend': 1800})
        self.policy.base.write_text((REPO / 'defaults/hardware/hypridle-ac.conf').read_text())
        self.assertEqual(self.policy.settings()['battery'], {'dim': 300, 'lock': 600, 'screen': 0, 'suspend': 0})

    def test_custom_configs_are_readonly(self):
        self.policy.entry.unlink()
        self.policy.entry.write_text('custom settings\n')
        with self.assertRaisesRegex(ValueError, 'custom'):
            self.configure()
        self.assertEqual(self.policy.entry.read_text(), 'custom settings\n')
        self.assertFalse(self.policy.config.exists())
        foreign = self.root / 'foreign'
        foreign.write_text(self.base)
        self.policy.entry.unlink()
        self.policy.entry.symlink_to(foreign)
        self.assertFalse(self.policy.managed())

    def configure(self, revision=None):
        settings = self.policy.settings()
        settings['ac']['screen'] = 600
        self.policy.configure({'settings': settings, 'revision': revision or self.policy.revision()})

    def test_configuration_requires_live_runner_and_compare_swap(self):
        with self.assertRaisesRegex(ValueError, 'not running'):
            self.configure()
        with self.policy.locked('runner.lock'):
            self.assertTrue(self.policy.running())
            old = self.policy.revision()
            self.configure()
            self.assertEqual(self.policy.settings()['ac']['screen'], 600)
            with self.assertRaisesRegex(ValueError, 'changed elsewhere'):
                self.configure(old)
        self.assertFalse(self.policy.running())
        self.assertEqual(self.policy.config.stat().st_mode & 0o777, 0o600)

    def test_corrupt_preferences_are_preserved(self):
        self.policy.config.parent.mkdir(parents=True)
        self.policy.config.write_text('{broken')
        with self.assertRaises(ValueError):
            self.policy.settings()
        self.assertEqual(self.policy.config.read_text(), '{broken')

    def test_validation_rejects_executable_or_unbounded_values(self):
        good = self.policy.settings()
        for value in [-1, True, 5, 999999, '60; reboot', None]:
            bad = copy.deepcopy(good)
            bad['ac']['screen'] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                idle.validate(bad)
        for value in [[], {}, dict(good, version=True), dict(good, extra=3)]:
            with self.assertRaises(ValueError):
                idle.validate(value)

    def test_render_never_keeps_lock_and_resume_protection(self):
        text = idle.render(self.base, {'dim': 150, 'lock': 300, 'screen': 0, 'suspend': 0})
        self.assertIn('before_sleep_cmd = loginctl lock-session', text)
        self.assertIn('timeout = 300', text)
        self.assertNotIn(idle.DPMS_OFF, text)
        self.assertNotIn('on-timeout = systemctl suspend', text)

    def test_never_allows_no_idle_actions_without_removing_manual_lock(self):
        text = idle.render(self.base, dict(dim=0, lock=0, screen=0, suspend=0))
        self.assertIn('on-timeout = /usr/bin/true', text)
        self.assertNotIn('brightness.sh', text)
        self.assertNotIn('on-timeout = loginctl', text)
        self.assertNotIn(idle.DPMS_OFF, text)
        self.assertNotIn('systemctl suspend', text)
        self.assertIn('lock_cmd = pidof hyprlock || hyprlock', text)
        self.assertIn('before_sleep_cmd = loginctl lock-session', text)

    def test_short_timeouts_lock_before_screen_or_sleep(self):
        text = idle.render(self.base, {'dim': 150, 'lock': 300, 'screen': 60, 'suspend': 120})
        self.assertIn('timeout = 59\n    on-timeout = loginctl lock-session', text)
        self.assertIn('timeout = 29\n    on-timeout = ', text)
        self.assertIn('on-resume = ' + idle.DPMS_ON, text)
        self.assertIn('after_sleep_cmd = ' + idle.DPMS_ON, text)

    def test_source_selection_and_empty_battery(self):
        directory = self.root / 'supply'
        directory.mkdir()
        self.assertEqual(idle.supply(directory), (False, 'ac'))
        battery = directory / 'BAT0'
        battery.mkdir()
        (battery / 'type').write_text('Battery')
        for state in ['Unknown', 'Discharging', 'Full', 'Not charging']:
            (battery / 'status').write_text(state)
            self.assertEqual(idle.supply(directory), (True, 'battery'))
        ac = directory / 'AC'
        ac.mkdir()
        (ac / 'type').write_text('Mains')
        (ac / 'online').write_text('1')
        self.assertEqual(idle.supply(directory), (True, 'ac'))
        (battery / 'status').write_text('Discharging')
        self.assertEqual(idle.supply(directory), (True, 'battery'))
        (battery / 'scope').write_text('Device')
        self.assertEqual(idle.supply(directory), (False, 'ac'))

    def test_applied_policy_uses_current_source(self):
        settings = self.policy.settings()
        settings['ac'].update(dim=0, lock=0, screen=0, suspend=0)
        idle.save(self.policy.config, json.dumps(settings))
        with patch.object(idle, 'supply', return_value=(True, 'ac')):
            self.assertNotIn('on-timeout = systemctl suspend', self.policy.desired()[0])
        with patch.object(idle, 'supply', return_value=(True, 'battery')):
            self.assertIn('on-timeout = systemctl suspend', self.policy.desired()[0])

    def test_runtime_acknowledgement_requires_fresh_live_runner(self):
        with self.policy.locked('runner.lock'):
            state = {'time': time.monotonic(), 'revision': self.policy.revision(), 'error': ''}
            idle.save(self.policy.runtime / 'status.json', json.dumps(state))
            self.assertTrue(self.policy.status()['applied'])
            state['time'] -= 30
            idle.save(self.policy.runtime / 'status.json', json.dumps(state))
            self.assertFalse(self.policy.status()['applied'])
        self.assertFalse(self.policy.status()['applied'])

    def test_supervisor_switches_policy_and_reaps_only_its_child(self):
        binary = self.root / 'bin'
        binary.mkdir()
        helper = self.root / 'idle-policy.py'
        helper.write_text((REPO / 'defaults/shell/idle-policy.py').read_text())
        brightness = self.root / 'brightness.sh'
        brightness.write_text('#!/bin/sh\nexit 0\n')
        brightness.chmod(0o755)
        (binary / 'hyprctl').write_text('#!/bin/sh\nexit 0\n')
        (binary / 'hyprctl').chmod(0o755)
        fake = binary / 'hypridle'
        fake.write_text('#!/usr/bin/env python3\nimport os,sys,time\nfrom pathlib import Path\n'
                        'with open(os.environ["IDLE_TEST_LOG"],"a") as f:\n'
                        ' f.write(Path(sys.argv[2]).read_text()+"\\n===START===\\n"); f.flush()\n'
                        'if Path(os.environ["IDLE_TEST_REJECT"]).exists() and "blankweave-idle/hypridle.conf" in sys.argv[2]: sys.exit(1)\n'
                        'while True: time.sleep(1)\n')
        fake.chmod(0o755)
        mode = self.root / 'mode'
        mode.write_text('ac')
        runner = self.root / 'runner.py'
        runner.write_text('import importlib.util\nfrom pathlib import Path\n'
                          f's=importlib.util.spec_from_file_location("idle", {str(helper)!r})\n'
                          'm=importlib.util.module_from_spec(s); s.loader.exec_module(m)\n'
                          f'm.supply=lambda: (True, Path({str(mode)!r}).read_text())\n'
                          'm.Policy().run()\n')
        log = self.root / 'child.log'
        reject = self.root / 'reject'
        environment = dict(os.environ, PATH=str(binary)+os.pathsep+os.environ['PATH'], IDLE_TEST_LOG=str(log), IDLE_TEST_REJECT=str(reject))
        process = subprocess.Popen(['python3', str(runner)], env=environment, stderr=subprocess.PIPE)
        self.addCleanup(lambda: process.poll() is None and process.kill())
        def wait_for(predicate):
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                if predicate():
                    return
                time.sleep(0.1)
            self.fail('Supervisor did not converge')
        try:
            wait_for(lambda: self.policy.running() and self.policy.status()['applied'])
            self.configure()
            wait_for(lambda: self.policy.status()['applied'])
            self.assertIn('timeout = 600\n    on-timeout = ' + idle.DPMS_OFF, log.read_text())
            count = log.read_text().count('===START===')
            mode.write_text('battery')
            wait_for(lambda: log.read_text().count('===START===') > count)
            self.assertIn('timeout = 360\n    on-timeout = ' + idle.DPMS_OFF, log.read_text().split('===START===')[-2])
            # Broken preferences leave the last good process running and surface failure.
            self.policy.config.write_text('{broken')
            time.sleep(2.5)
            state = json.loads((self.policy.runtime / 'status.json').read_text())
            self.assertTrue(state['error'])
            self.assertEqual(log.read_text().count('===START==='), count + 1)
            # A rejected generated config falls back once, without continually
            # restarting the fallback and preventing its lock timer from firing.
            self.policy.config.unlink()
            reject.touch()
            self.configure()
            settings = self.policy.settings()
            settings['battery']['screen'] = 900
            idle.save(self.policy.config, json.dumps(settings))
            wait_for(lambda: 'could not start' in json.loads((self.policy.runtime / 'status.json').read_text())['error'])
            count = log.read_text().count('===START===')
            time.sleep(2.5)
            self.assertEqual(log.read_text().count('===START==='), count)
            self.assertFalse(self.policy.status()['applied'])

        finally:
            process.terminate()
            _, errors = process.communicate(timeout=8)
        self.assertEqual(process.returncode, 0, errors.decode())
        self.assertFalse(self.policy.running())
        self.assertFalse((self.policy.runtime / 'status.json').exists())


if __name__ == '__main__':
    unittest.main()
