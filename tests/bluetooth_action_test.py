#!/usr/bin/env python3
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'defaults/shell/bluetooth-action.py'
DEVICE = '/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF'

class BluetoothTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.state = Path(cls.temp.name) / 'state.json'
        cls.state.write_text('{}')
        cls.env = dict(os.environ, BLUETOOTH_TEST_STATE=str(cls.state), DBUS_SYSTEM_BUS_ADDRESS=os.environ['DBUS_SESSION_BUS_ADDRESS'])
        cls.server = subprocess.Popen([sys.executable, str(ROOT / 'tests/fixtures/bluez-service.py')], env=cls.env,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if cls.server.stdout.readline().strip() != 'READY':
            raise RuntimeError(cls.server.stderr.read())

    @classmethod
    def tearDownClass(cls):
        cls.server.terminate()
        cls.server.communicate(timeout=5)
        cls.temp.cleanup()

    def run_action(self, action='pair', scenario=None, answer=True, cancel=False, stale=False):
        self.state.write_text(json.dumps(scenario or {}))
        process = subprocess.Popen([sys.executable, str(HELPER), action, DEVICE], env=self.env, text=True,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        events = queue.Queue()
        def reader():
            for line in process.stdout:
                events.put(json.loads(line))
        thread = threading.Thread(target=reader, daemon=True)
        thread.start()
        received = []
        try:
            while True:
                event = events.get(timeout=10)
                received.append(event)
                if event['kind'] == 'result':
                    break
                prompt = event.get('prompt')
                if prompt and prompt['type'] != 'display':
                    if stale:
                        process.stdin.write(json.dumps({'id': prompt['id'] - 1, 'value': answer}) + '\n')
                    process.stdin.write(json.dumps({'cancel': True} if cancel else {'id': prompt['id'], 'value': answer}) + '\n')
                    process.stdin.flush()
            process.wait(timeout=5)
            thread.join(timeout=2)
            error = process.stderr.read()
            self.assertEqual(error, '')
            return process.returncode, received, json.loads(self.state.read_text())
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
            process.stdin.close()
            process.stdout.close()
            process.stderr.close()

    def test_confirmation_is_interactive_and_agent_is_unregistered(self):
        code, events, state = self.run_action(stale=True)
        self.assertEqual(code, 0)
        self.assertEqual(events[0]['prompt']['code'], '012345')
        self.assertTrue(state['Paired'] and state['Connected'] and state['Trusted'])
        self.assertIn('UnregisterAgent', state['calls'])
        self.assertNotIn('RequestDefaultAgent', state['calls'])

    def test_pin_and_passkey(self):
        for kind, answer, expected in [('pin', 'aB123', 'aB123'), ('passkey', '000123', 123)]:
            with self.subTest(kind=kind):
                code, _, state = self.run_action(scenario={'prompt': kind}, answer=answer)
                self.assertEqual(code, 0)
                self.assertEqual(state['answer'], [expected])

    def test_display_and_authorization(self):
        for kind in ['display', 'authorization', 'service']:
            with self.subTest(kind=kind):
                code, _, state = self.run_action(scenario={'prompt': kind})
                self.assertEqual(code, 0)
                self.assertTrue(state['Connected'])

    def test_cancel_and_reject_do_not_connect(self):
        for cancel in [False, True]:
            code, _, state = self.run_action(answer=False, cancel=cancel)
            self.assertEqual(code, 1)
            self.assertNotIn('Connect', state['calls'])
            self.assertIn('CancelPairing', state['calls'])
            self.assertIn('UnregisterAgent', state['calls'])

    def test_foreign_device_is_rejected(self):
        code, _, state = self.run_action(scenario={'prompt': 'foreign'})
        self.assertEqual(code, 1)
        self.assertNotIn('Connect', state['calls'])

    def test_connection_failure_and_readback_mismatch(self):
        for scenario in [{'failConnect': True}, {'readbackMismatch': True}]:
            code, events, _ = self.run_action('connect', scenario)
            self.assertEqual(code, 1)
            self.assertFalse(events[-1]['success'])

    def test_disconnect_and_forget(self):
        code, _, state = self.run_action('disconnect', {'Connected': True})
        self.assertEqual(code, 0)
        self.assertFalse(state['Connected'])
        code, _, state = self.run_action('forget')
        self.assertEqual(code, 0)
        self.assertTrue(state['removed'])

    def test_invalid_device_path_is_rejected(self):
        result = subprocess.run([sys.executable, str(HELPER), 'forget', '/org/bluez/hci0'], env=self.env,
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 1)
        self.assertIn('Invalid', json.loads(result.stdout)['message'])

    def test_blocked_device_can_be_forgotten_but_not_connected(self):
        code, _, state = self.run_action('connect', {'Blocked': True})
        self.assertEqual(code, 1)
        self.assertNotIn('Connect', state['calls'])
        code, _, state = self.run_action('forget', {'Blocked': True})
        self.assertEqual(code, 0)
        self.assertTrue(state['removed'])

if __name__ == '__main__':
    unittest.main()
