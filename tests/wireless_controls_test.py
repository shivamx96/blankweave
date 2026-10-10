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
from gi.repository import GLib
from network_connections_test import FakeNetwork, PATH, UUID

SPEC = importlib.util.spec_from_file_location('wireless', Path(__file__).resolve().parents[1] / 'defaults/shell/wireless-controls.py')
w = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(w)


class AirplaneTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.airplane = w.Airplane()
        self.airplane.directory = Path(directory.name)
        self.airplane.path = self.airplane.directory / 'airplane.json'
        self.rows = [{'id': 1, 'type': 'wlan', 'name': 'wifi', 'soft': False, 'hard': False},
                     {'id': 2, 'type': 'bluetooth', 'name': 'bt', 'soft': True, 'hard': False}]
        self.calls = []
        self.fail = False
        for target, replacement in [('radios', lambda: copy.deepcopy(self.rows)), ('run_rfkill', self.rfkill), ('bluez', lambda: (None, []))]:
            patcher = patch.object(w, target, replacement)
            patcher.start(); self.addCleanup(patcher.stop)

    def rfkill(self, command, target):
        self.calls.append((command, target))
        if self.fail:
            raise ValueError('Permission denied')
        for row in self.rows:
            if target == 'all' or str(row['id']) == target:
                row['soft'] = command == 'block'

    def test_status_is_readonly(self):
        result = self.airplane.status()
        self.assertFalse(result['requested'])
        self.assertFalse(result['blocked'])
        self.assertFalse(self.airplane.path.exists())
        self.assertEqual(self.calls, [])

    def test_enable_restore_previous_radio_state(self):
        self.airplane.apply(True)
        self.assertTrue(self.airplane.status()['blocked'])
        self.assertTrue(self.airplane.status()['requested'])
        self.assertEqual(self.airplane.path.stat().st_mode & 0o777, 0o600)
        self.airplane.apply(False)
        self.assertFalse(self.rows[0]['soft'])
        self.assertTrue(self.rows[1]['soft'])
        self.assertFalse(self.airplane.path.exists())

    def test_retry_preserves_snapshot_and_external_override_reported(self):
        self.airplane.apply(True)
        self.rows[0]['soft'] = False
        self.assertFalse(self.airplane.status()['blocked'])
        self.assertTrue(self.airplane.status()['requested'])
        self.airplane.apply(True)
        self.airplane.apply(False)
        self.assertFalse(self.rows[0]['soft'])

    def test_failure_keeps_restore_data(self):
        self.fail = True
        with self.assertRaisesRegex(ValueError, 'Permission'):
            self.airplane.apply(True)
        self.assertTrue(self.airplane.path.exists())
        self.fail = False
        self.airplane.apply(False)
        self.assertFalse(self.rows[0]['soft'])

    def test_restore_matches_radio_name_not_reused_id(self):
        self.airplane.apply(True)
        self.rows[0]['id'] = 9
        self.rows.append({'id': 1, 'type': 'wwan', 'name': 'new-radio', 'soft': True, 'hard': False})
        self.airplane.apply(False)
        self.assertFalse(self.rows[0]['soft'])
        self.assertTrue(self.rows[2]['soft'])

    def test_hardware_block_is_reported_and_never_changed(self):
        self.rows[0]['hard'] = True
        self.rows[1]['hard'] = True
        self.assertTrue(self.airplane.status()['blocked'])
        self.airplane.apply(False)
        self.assertTrue(self.airplane.status()['blocked'])
        self.assertTrue(all(row['hard'] for row in self.rows))

    def test_missing_radios_bad_input_and_corrupt_state_do_not_write(self):
        with self.assertRaises(ValueError):
            self.airplane.apply('on')
        self.airplane.path.write_text('bad')
        with self.assertRaises(ValueError):
            self.airplane.apply(True)
        self.rows.clear()
        with self.assertRaisesRegex(ValueError, 'No wireless'):
            self.airplane.apply(True)
        self.assertEqual(self.calls, [])

    def test_bluetooth_power_restored_even_if_originally_unblocked_but_off(self):
        class Bus:
            def call_sync(inner, *args):
                self.assertEqual(args[2:4], ('org.freedesktop.DBus.Properties', 'Set'))
                self.assertFalse(args[4].unpack()[2])
                self.power_restored = True
        self.power_restored = False
        adapter = {'path': '/org/bluez/hci0', 'address': 'AA:BB', 'powered': False}
        with patch.object(w, 'bluez', return_value=(Bus(), [adapter])):
            self.airplane.apply(True)
            self.airplane.apply(False)
        self.assertTrue(self.power_restored)

    def test_rfkill_command_and_json_format(self):
        result = subprocess.CompletedProcess([], 0, json.dumps({'rfkilldevices': [{'id': 2, 'type': 'wlan', 'device': 'phy0', 'soft': 'blocked', 'hard': 'unblocked'}]}))
        with patch.object(w.subprocess, 'run', return_value=result) as process:
            output = ORIGINAL_RFKILL('--json', '--output', 'ID,TYPE,DEVICE,SOFT,HARD')
            self.assertEqual(json.loads(output)['rfkilldevices'][0]['soft'], 'blocked')
            self.assertEqual(process.call_args.args[0][0], 'rfkill')
            self.assertNotIn('shell', process.call_args.kwargs)


ORIGINAL_RFKILL = w.run_rfkill


class FakeHotspots(w.Hotspots):
    settings = FakeNetwork.settings

    def __init__(self):
        FakeNetwork.__init__(self)
        self.device['DeviceType'] = 2
        self.saved['connection']['type'] = GLib.Variant('s', '802-11-wireless')
        self.saved['802-11-wireless'] = {'mode': GLib.Variant('s', 'infrastructure'), 'ssid': GLib.Variant('ay', b'Home')}
        self.manager = {'WirelessEnabled': True, 'WirelessHardwareEnabled': True}
        self.capabilities = 0x68
        self.fail_wait = False

    def props(self, path, interface):
        if interface == w.NM:
            return self.manager
        if interface == w.DEVICE + '.Wireless':
            return {'WirelessCapabilities': self.capabilities}
        return FakeNetwork.props(self, path, interface)

    def call(self, path, interface, method, parameters=None):
        if method == 'AddAndActivateConnection2':
            self.calls.append((path, interface, method, parameters))
            self.saved = w.network.variant_settings(parameters.get_child_value(0))
            self.active.update(Uuid=self.saved['connection']['uuid'].unpack(), Connection='/hotspot', Id='Blankweave Hotspot')
            self.device.update(State=100, ActiveConnection='/hotspot_active')
            return GLib.Variant('(ooa{sv})', ('/hotspot', '/hotspot_active', {}))
        if method == 'Delete':
            self.calls.append((path, interface, method, parameters))
            return GLib.Variant('()', ())
        return FakeNetwork.call(self, path, interface, method, parameters)

    def wait(self, path, predicate):
        if self.fail_wait or not predicate(self.row(path)):
            raise ValueError('timeout')


class HotspotTest(unittest.TestCase):
    def setUp(self):
        self.net = FakeHotspots()
        self.request = {**self.net.row(PATH), 'action': 'start', 'ssid': 'Test hotspot', 'password': 'not-a-real-secret', 'replace': True}
        patcher = patch.object(w.shutil, 'which', return_value='/fake/program')
        patcher.start(); self.addCleanup(patcher.stop)

    def test_status_reports_capability_and_never_returns_password(self):
        status = self.net.status()
        self.assertTrue(status['devices'][0]['apCapable'])
        self.assertTrue(status['sharingAvailable'])
        self.assertNotIn('password', json.dumps(status))
        self.assertNotIn('psk', json.dumps(status))

    def test_secure_volatile_hotspot_then_stop_exact_activation(self):
        self.net.start(self.request)
        call = next(c for c in self.net.calls if c[2] == 'AddAndActivateConnection2')
        settings, device, specific, options = call[3].unpack()
        self.assertEqual(options, {'persist': 'volatile'})
        self.assertEqual(device, PATH)
        self.assertFalse(settings['connection']['autoconnect'])
        self.assertEqual(settings['ipv4']['method'], 'shared')
        self.assertEqual(settings['ipv6']['method'], 'disabled')
        self.assertEqual(settings['802-11-wireless-security']['proto'], ['rsn'])
        self.assertEqual(settings['802-11-wireless-security']['pairwise'], ['ccmp'])
        self.assertEqual(settings['802-11-wireless-security']['psk'], 'not-a-real-secret')
        self.net.stop({**self.net.row(PATH), 'action': 'stop'})
        stop = next(c for c in self.net.calls if c[2] == 'DeactivateConnection')
        self.assertEqual(stop[3].unpack(), ('/hotspot_active',))

    def test_invalid_credentials_rejected_before_activation(self):
        for name, password in [('', 'password'), ('☃' * 11, 'password'), ('line\nbreak', 'password'), ('ok', 'short'), ('ok', 'é' * 8), ('ok', 'a' * 64)]:
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.net.start({**self.request, 'ssid': name, 'password': password})
        self.assertFalse(any(c[2] == 'AddAndActivateConnection2' for c in self.net.calls))

    def test_confirmation_required_for_current_connection(self):
        with self.assertRaisesRegex(ValueError, 'Confirm'):
            self.net.start({**self.request, 'replace': False})
        self.net.device.update(State=30, ActiveConnection='/')
        self.net.start({**self.net.row(PATH), 'ssid': 'Test', 'password': 'password', 'replace': False})

    def test_stale_target_blocked_radio_missing_dependencies_and_capabilities(self):
        with self.assertRaises(ValueError):
            self.net.start({**self.request, 'owner': ':1.99'})
        self.net.manager['WirelessEnabled'] = False
        with self.assertRaisesRegex(ValueError, 'Turn on'):
            self.net.start(self.request)
        self.net.manager['WirelessEnabled'] = True
        self.net.capabilities = 0x40
        with self.assertRaisesRegex(ValueError, 'WPA2'):
            self.net.start(self.request)
        self.net.capabilities = 0x68
        with patch.object(w.shutil, 'which', return_value=None), self.assertRaisesRegex(ValueError, 'dnsmasq'):
            self.net.start(self.request)
        self.assertFalse(any(c[2] == 'AddAndActivateConnection2' for c in self.net.calls))

    def test_foreign_ap_and_changed_activation_cannot_be_stopped(self):
        self.net.saved['802-11-wireless']['mode'] = GLib.Variant('s', 'ap')
        with self.assertRaisesRegex(ValueError, 'no longer active'):
            self.net.stop(self.net.row(PATH))
        self.net.saved['802-11-wireless']['mode'] = GLib.Variant('s', 'infrastructure')
        self.net.start(self.request)
        captured = self.net.row(PATH)
        self.net.device['ActiveConnection'] = '/another_active'
        with self.assertRaisesRegex(ValueError, 'changed'):
            self.net.stop(captured)

    def test_failed_start_cleans_only_its_own_temporary_profile(self):
        self.net.fail_wait = True
        with self.assertRaisesRegex(ValueError, 'hotspot'):
            self.net.start(self.request)
        stop = next(c for c in self.net.calls if c[2] == 'DeactivateConnection')
        self.assertEqual(stop[3].unpack(), ('/hotspot_active',))
        deleted = [c[0] for c in self.net.calls if c[2] == 'Delete']
        self.assertEqual(deleted, ['/hotspot'])
        self.assertNotIn('/profile', deleted)


if __name__ == '__main__':
    unittest.main()
