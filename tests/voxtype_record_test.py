"""Exercise press/release ordering without a microphone or running compositor."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RecordingOrder(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="blankweave-voxtype-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.runtime = self.root / "runtime"
        (self.runtime / "voxtype").mkdir(parents=True)
        self.children = []
        self.addCleanup(self.stop_children)
        shutil.copy(ROOT / "defaults/shell/voxtype-record.sh", self.root / "record.sh")
        (self.root / "voxtype-focus.py").write_text("""import os, pathlib, time
root = pathlib.Path(os.environ['AUDIT_ROOT'])
name = os.environ['PROBE_NAME']
(root / (name + '.ready')).touch()
while not (root / (name + '.go')).exists(): time.sleep(.005)
raise SystemExit(int(os.environ.get('FOCUS_RESULT', '0')))
""")
        (self.root / "voxtype").write_text(r"""#!/usr/bin/env python3
import os, pathlib, sys, time
root = pathlib.Path(os.environ['AUDIT_ROOT'])
with (root / 'commands').open('a') as stream: stream.write(' '.join(sys.argv[1:]) + '\n')
if os.environ.get('HOLD_PROVIDER'):
    (root / 'provider.ready').touch()
    while not (root / 'provider.go').exists(): time.sleep(.005)
raise SystemExit(int(os.environ.get('PROVIDER_EXIT', '0')))
""")
        (self.root / "voxtype").chmod(0o700)
        self.env = {**os.environ, "PATH": str(self.root) + ":" + os.environ["PATH"],
                    "XDG_RUNTIME_DIR": str(self.runtime), "AUDIT_ROOT": str(self.root),
                    "BLANKWEAVE_VOXTYPE_FOCUS": "fixture"}

    def stop_children(self):
        for child in self.children:
            if child.poll() is None:
                # Release fake providers before waiting for shell EXIT cleanup.
                for marker in self.root.glob('*.ready'):
                    marker.with_suffix('.go').touch()
                child.terminate()
                try: child.wait(timeout=2)
                except subprocess.TimeoutExpired: child.kill(); child.wait()

    def launch(self, action, name="probe", **extra):
        child = subprocess.Popen(["bash", str(self.root / "record.sh"), action],
                                 env={**self.env, "PROBE_NAME": name, **extra})
        self.children.append(child)
        return child

    def wait_ready(self, name):
        deadline = time.monotonic() + 3
        while not (self.root / (name + '.ready')).exists():
            if time.monotonic() > deadline: self.fail('Timed out waiting for ' + name)
            time.sleep(.005)

    def release(self, name):
        (self.root / (name + '.go')).touch()

    def commands(self):
        file = self.root / 'commands'
        return file.read_text().splitlines() if file.exists() else []

    def test_release_or_cancel_during_probe_cancels_start(self):
        for action in ('stop', 'cancel'):
            with self.subTest(action=action):
                start = self.launch('start', action)
                self.wait_ready(action)
                self.assertEqual(self.launch(action).wait(timeout=2), 0)
                self.release(action)
                self.assertEqual(start.wait(timeout=2), 0)
                self.assertNotIn('record start', self.commands())
                self.assertEqual(self.commands()[-1], 'record ' + action)
                self.assertFalse((self.runtime / 'blankweave/voxtype-output-mode').exists())

    def test_second_toggle_cancels_preparing_toggle(self):
        start = self.launch('toggle')
        self.wait_ready('probe')
        self.assertEqual(self.launch('toggle').wait(timeout=2), 0)
        self.release('probe')
        self.assertEqual(start.wait(timeout=2), 0)
        self.assertEqual(self.commands(), [])

    def test_new_request_survives_old_probe_completion(self):
        old = self.launch('start', 'old', FOCUS_RESULT='1')
        self.wait_ready('old')
        self.assertEqual(self.launch('stop').wait(timeout=2), 0)
        new = self.launch('start', 'new')
        self.wait_ready('new')
        self.release('old')
        self.assertEqual(old.wait(timeout=2), 0)
        self.release('new')
        self.assertEqual(new.wait(timeout=2), 0)
        self.assertEqual(self.commands(), ['record stop', 'record start'])
        self.assertFalse((self.runtime / 'blankweave/voxtype-output-mode').exists())

    def test_release_waits_for_committing_start(self):
        start = self.launch('start', HOLD_PROVIDER='1')
        self.wait_ready('probe')
        self.release('probe')
        self.wait_ready('provider')
        stop = self.launch('stop')
        # Provider is gated, not merely slow: stop cannot overtake it.
        with self.assertRaises(subprocess.TimeoutExpired): stop.wait(timeout=.1)
        self.release('provider')
        self.assertEqual(start.wait(timeout=2), 0)
        self.assertEqual(stop.wait(timeout=2), 0)
        self.assertEqual(self.commands(), ['record start', 'record stop'])

    def test_active_toggle_preserves_delivery_route(self):
        (self.runtime / 'voxtype/state').write_text('recording')
        directory = self.runtime / 'blankweave'
        directory.mkdir()
        (directory / 'voxtype-output-mode').write_text('clipboard')
        self.assertEqual(self.launch('toggle').wait(timeout=2), 0)
        self.assertEqual(self.commands(), ['record toggle'])
        self.assertEqual((directory / 'voxtype-output-mode').read_text(), 'clipboard')
        self.assertFalse((self.root / 'probe.ready').exists())

    def test_settings_clipboard_start_does_not_probe_focus(self):
        self.assertEqual(self.launch('start-clipboard').wait(timeout=2), 0)
        self.assertEqual(self.commands(), ['record start --clipboard --no-auto-submit'])
        self.assertEqual((self.runtime / 'blankweave/voxtype-output-mode').read_text().strip(), 'clipboard')
        self.assertFalse((self.root / 'probe.ready').exists())

    def test_provider_failure_clears_pending_and_returns_failure(self):
        start = self.launch('start', PROVIDER_EXIT='7')
        self.wait_ready('probe')
        self.release('probe')
        self.assertEqual(start.wait(timeout=2), 7)
        self.assertFalse((self.runtime / 'blankweave/voxtype-pending-start').exists())

    def test_stuck_start_times_out_and_queued_stop_can_proceed(self):
        start = self.launch('start', HOLD_PROVIDER='1')
        self.wait_ready('probe')
        self.release('probe')
        self.wait_ready('provider')
        stop = self.launch('stop')
        # Never open provider.go: exercise the real timeout, not a mock timer.
        self.assertEqual(start.wait(timeout=8), 124)
        self.assertEqual(stop.wait(timeout=2), 0)
        self.assertEqual(self.commands(), ['record start', 'record stop'])


if __name__ == '__main__':
    unittest.main()
