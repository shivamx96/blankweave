#!/usr/bin/env python3
"""Runtime lid integration with the stateful fake compositor, never the session."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / 'defaults/shell'))
spec = importlib.util.spec_from_file_location('monitor_setups', ROOT / 'defaults/shell/monitor-setups.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class LidTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = self.root / 'config/blankweave'; self.config.mkdir(parents=True)
        self.runtime = self.root / 'runtime'; self.runtime.mkdir()
        binary = self.root / 'bin'; binary.mkdir()
        (binary / 'hyprctl').symlink_to(ROOT / 'tests/fixtures/hyprctl-layout.py')
        self.state = self.root / 'live.json'
        self.original = [dict(id=0, name='eDP-1', description='Panel', width=2880, height=1800,
            refreshRate=90, scale=1.5, x=-1920, y=100, transform=2, mirrorOf='none',
            availableModes=['2880x1800@90.00Hz']),
            dict(id=1, name='DP-1', description='Desk', width=1920, height=1080,
            refreshRate=60, scale=1, x=0, y=0, transform=0, mirrorOf='none',
            availableModes=['1920x1080@60.00Hz'])]
        self.write(self.original)
        env = patch.dict(os.environ, XDG_CONFIG_HOME=str(self.config.parent),
            XDG_RUNTIME_DIR=str(self.runtime), HYPRLAND_INSTANCE_SIGNATURE='isolated-lid',
            LAYOUT_TEST_STATE=str(self.state), LAYOUT_TEST_LOG=str(self.root / 'commands'),
            PATH=str(binary) + ':' + os.environ['PATH'])
        env.start(); self.addCleanup(env.stop)
        self.helper = m.Setups(str(self.config), str(ROOT / 'defaults/shell/monitor-layout.sh'))
        self.script = ROOT / 'defaults/shell/monitor-layout.sh'
        saved = self.helper.snapshot(m.live_monitors())
        saved[0].update(icc='/tmp/fixture.icc', cm='srgb')
        (self.config / 'monitors.json').write_text(json.dumps({'monitors': saved}))
        (self.config / 'monitors.lua').write_text('\n'.join(m.render(row) for row in saved))
        self.helper.save('Desk')
        self.before = {p.name: p.read_bytes() for p in self.config.glob('*') if p.is_file()}

    def write(self, rows): self.state.write_text(json.dumps(rows))
    def rows(self): return json.loads(self.state.read_text())
    def run_shell(self, *args, success=True):
        result = subprocess.run([str(self.script), *args], stdin=subprocess.DEVNULL, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stderr)
    def unchanged(self):
        for name, data in self.before.items(): self.assertEqual((self.config / name).read_bytes(), data, name)

    def test_docked_and_undocked(self):
        self.run_shell('lid', 'closed')
        self.assertTrue(self.rows()[0]['disabled'])
        self.assertFalse(self.rows()[1].get('disabled', False))
        self.run_shell('lid', 'open')
        panel = self.rows()[0]
        for key, value in self.original[0].items(): self.assertEqual(panel[key], value, key)
        self.assertEqual(panel['icc'], '/tmp/fixture.icc'); self.assertEqual(panel['cm'], 'srgb')
        self.unchanged()
        self.write([self.original[0]])
        self.run_shell('lid', 'closed')
        self.assertFalse(self.rows()[0].get('disabled', False))
        self.unchanged()

    def test_hotplug_and_session(self):
        self.run_shell('lid', 'closed')
        self.write([self.rows()[0]])
        self.run_shell('lid', 'reconcile')
        self.assertFalse(self.rows()[0]['disabled'])
        self.write(self.rows() + [self.original[1]])
        self.run_shell('lid', 'reconcile')
        self.assertTrue(self.rows()[0]['disabled'])
        with patch.dict(os.environ, HYPRLAND_INSTANCE_SIGNATURE='new-session'):
            self.assertFalse(self.helper.lid_path().exists())
        self.unchanged()

    def test_preview_defers_and_reconciles(self):
        self.helper.pending.write_text('{"token":"fixture"}')
        self.run_shell('lid', 'closed')
        self.assertFalse(self.rows()[0].get('disabled', False))
        self.helper.pending.unlink()
        # A stale watchdog's no-op revert also processes deferred events.
        self.run_shell('mode-revert', 'fixture')
        self.assertTrue(self.rows()[0]['disabled'])
        self.helper.pending.write_text('{"token":"fixture"}')
        self.write([self.rows()[0]])
        self.run_shell('lid', 'reconcile')
        self.assertFalse(self.rows()[0]['disabled'])
        self.helper.pending.unlink()
        self.unchanged()

    def test_reload_reasserts_runtime_overlay(self):
        self.run_shell('lid', 'closed')
        snapshot = json.loads(self.helper.lid_path().read_text())['layout']
        # A theme/preferences reload can load the saved enabled monitor rule.
        self.write(self.original)
        self.run_shell('lid', 'reconcile')
        self.assertTrue(self.rows()[0]['disabled'])
        self.assertEqual(json.loads(self.helper.lid_path().read_text())['layout'], snapshot)
        self.run_shell('lid', 'open')
        self.unchanged()

    def test_expired_preview_reconciles(self):
        self.run_shell('mode-preview', 'DP-1', '1920x1080@60.00')
        self.run_shell('lid', 'closed')
        self.assertFalse(self.rows()[0].get('disabled', False))
        pending = json.loads(self.helper.pending.read_text()); pending['deadline'] = 0
        self.helper.pending.write_text(json.dumps(pending))
        self.run_shell('mode-confirm', pending['token'], success=False)
        self.assertTrue(self.rows()[0]['disabled'])
        self.unchanged()

    def test_ignored_disable_recovers(self):
        with patch.dict(os.environ, LAYOUT_IGNORE_DISABLE='1'):
            self.run_shell('lid', 'closed', success=False)
        self.assertTrue(m.live_monitors())
        self.assertFalse(self.rows()[0].get('disabled', False))
        self.assertFalse(json.loads(self.helper.lid_path().read_text())['layout'])
        self.unchanged()

    def test_mirror_and_setup_guard(self):
        rows = self.rows(); rows[1]['mirrorOf'] = '0'; rows[1]['x'] = rows[0]['x']; rows[1]['y'] = rows[0]['y']; self.write(rows)
        self.run_shell('lid', 'closed')
        self.assertEqual(self.rows()[1]['mirrorOf'], 'none')
        identifier = self.helper.presets()[0]['id']
        self.run_shell('preset-preview', identifier, success=False)
        self.run_shell('preset-save', 'Hidden', success=False)
        self.run_shell('apply', success=False)
        self.assertTrue(self.rows()[0]['disabled'])
        self.run_shell('lid', 'open')
        self.assertEqual(self.rows()[1]['mirrorOf'], '0')
        self.unchanged()

    def test_startup_closed_and_no_lid(self):
        with patch.object(m, 'current_lid_closed', return_value=True): self.helper.lid('startup')
        self.assertTrue(self.rows()[0]['disabled'])
        self.helper.lid('open')
        with patch.object(m, 'current_lid_closed', return_value=None): self.helper.lid('startup')
        self.assertFalse(self.rows()[0]['disabled'])
        self.unchanged()

if __name__ == '__main__': unittest.main(argv=[sys.argv[0]] + sys.argv[1:])
