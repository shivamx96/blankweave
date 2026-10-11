#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest
from gi.repository import Gio, GLib

SPEC = importlib.util.spec_from_file_location('battery', Path(__file__).resolve().parents[1] / 'defaults/shell/battery-health.py')
battery = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(battery)
PATH = battery.ROOT + '/devices/battery_BAT0'
OTHER = battery.ROOT + '/devices/battery_BAT1'


def device(**changes):
    return {'Type': 2, 'PowerSupply': True, 'IsPresent': True, 'NativePath': 'BAT0', 'Vendor': 'Vendor',
            'Model': '<b>Battery</b>', 'Serial': 'private-serial', 'Percentage': 0.0, 'Capacity': 88.0,
            'EnergyFull': 44.0, 'EnergyFullDesign': 50.0, 'ChargeCycles': 0, 'State': 2,
            'ChargeThresholdSupported': True, 'ChargeThresholdEnabled': False,
            'ChargeThresholdSettingsSupported': 3, 'ChargeStartThreshold': 75, 'ChargeEndThreshold': 80, **changes}


class Bus:
    def __init__(self):
        self.owner = ':1.34'
        self.devices = {PATH: device(), OTHER: device(NativePath='BAT1', Serial='another-serial', ChargeCycles=50)}
        self.writes = []
        self.calls = []
        self.denied = False
        self.ignore = False
        self.restart = False
        self.replace = False
        self.gone = ''

    def call_sync(self, destination, path, interface, method, args, reply, flags, timeout, cancellable):
        self.calls.append((destination, path, interface, method))
        assert flags == Gio.DBusCallFlags.NO_AUTO_START
        assert 0 < timeout <= 10000
        if method == 'GetNameOwner':
            assert args.unpack()[0] == battery.SERVICE
            if not self.owner:
                raise Gio.DBusError.new_for_dbus_error('org.freedesktop.DBus.Error.NameHasNoOwner', 'Not running')
            return GLib.Variant('(s)', (self.owner,))
        assert destination == self.owner
        if method == 'EnumerateDevices':
            assert path == battery.ROOT and interface == battery.SERVICE
            return GLib.Variant('(ao)', (list(self.devices),))
        if path == self.gone:
            raise Gio.DBusError.new_for_dbus_error('org.freedesktop.DBus.Error.UnknownObject', 'Removed')
        if method == 'GetAll':
            assert interface == 'org.freedesktop.DBus.Properties' and args.unpack()[0] == battery.DEVICE
            properties = {}
            for key, value in self.devices[path].items():
                signature = 'b' if type(value) is bool else 's' if type(value) is str else 'd' if type(value) is float else 'i' if key == 'ChargeCycles' else 'u'
                properties[key] = GLib.Variant(signature, value)
            return GLib.Variant('(a{sv})', (properties,))
        if method == 'EnableChargeThreshold':
            assert interface == battery.DEVICE
            self.writes.append((path, args.unpack()[0]))
            if self.denied:
                raise Gio.DBusError.new_for_dbus_error('org.freedesktop.DBus.Error.AccessDenied', 'Denied')
            if not self.ignore:
                self.devices[path]['ChargeThresholdEnabled'] = args.unpack()[0]
            if self.restart:
                self.owner = ':1.35'
            if self.replace:
                self.devices[path]['Serial'] = 'replacement'
            return GLib.Variant('()', ())
        raise AssertionError(method)


class BatteryTests(unittest.TestCase):
    def setUp(self):
        self.bus = Bus()
        self.batteries = battery.Batteries(self.bus)
        self.row = self.batteries.row(PATH)
        self.request = {key: self.row[key] for key in ('owner', 'path', 'identity')}
        self.request['enabled'] = True

    def test_status_reports_individual_battery_health_without_serials(self):
        rows = self.batteries.status()['batteries']
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]['health'], 88)
        self.assertEqual(rows[0]['cycles'], 0)
        self.assertEqual(rows[0]['charge'], 0)
        self.assertEqual(rows[0]['energyFull'], 44)
        self.assertNotIn('private-serial', str(rows))
        self.assertNotEqual(rows[0]['identity'], rows[1]['identity'])
        self.assertEqual(self.bus.writes, [])

    def test_non_system_absent_and_aggregate_devices_are_excluded(self):
        for index, data in enumerate([device(Type=3), device(PowerSupply=False), device(IsPresent=False), device(Type=1)]):
            self.bus.devices[battery.ROOT + '/devices/extra_' + str(index)] = data
        self.bus.devices[battery.ROOT + '/devices/DisplayDevice'] = device()
        self.assertEqual(len(self.batteries.status()['batteries']), 2)

    def test_absent_service_is_not_started(self):
        self.bus.owner = ''
        backend = battery.Batteries(self.bus)
        self.assertEqual(backend.status(), {'available': False, 'batteries': []})

    def test_removed_battery_during_enumeration_is_skipped(self):
        self.bus.gone = OTHER
        self.assertEqual(len(self.batteries.status()['batteries']), 1)

    def test_firmware_mode_never_invents_percentages(self):
        self.bus.devices[PATH].update(ChargeThresholdSettingsSupported=4, ChargeStartThreshold=0, ChargeEndThreshold=0)
        row = self.batteries.row(PATH)
        self.assertTrue(row['supported'] and row['firmware'])
        self.assertIsNone(row['start'])
        self.assertIsNone(row['end'])

    def test_unknown_values_and_unsigned_sentinel_are_not_zero_health(self):
        self.bus.devices[PATH].update(Capacity=0.0, ChargeCycles=-1, EnergyFull=0.0,
                                      EnergyFullDesign=float('nan'), Percentage=float('nan'),
                                      ChargeStartThreshold=4294967295, ChargeEndThreshold=4294967295)
        row = self.batteries.row(PATH)
        for key in ('health', 'cycles', 'energyFull', 'energyDesign', 'charge', 'start', 'end'):
            self.assertIsNone(row[key], key)

    def test_legacy_thresholds_and_missing_api(self):
        del self.bus.devices[PATH]['ChargeThresholdSettingsSupported']
        self.assertEqual(self.batteries.row(PATH)['end'], 80)
        del self.bus.devices[PATH]['ChargeThresholdSupported']
        row = self.batteries.row(PATH)
        self.assertFalse(row['supported'])
        self.assertIsNone(row['enabled'])

    def test_end_only_threshold(self):
        self.bus.devices[PATH]['ChargeThresholdSettingsSupported'] = 2
        row = self.batteries.row(PATH)
        self.assertIsNone(row['start'])
        self.assertEqual(row['end'], 80)

    def test_mutation_targets_only_captured_battery_and_reads_back(self):
        self.batteries.apply(self.request)
        self.assertEqual(self.bus.writes, [(PATH, True)])
        self.assertTrue(self.batteries.row(PATH)['enabled'])
        self.assertFalse(self.batteries.row(OTHER)['enabled'])
        self.assertFalse(any(call[3] == 'Set' for call in self.bus.calls))

    def test_disable_and_noop(self):
        self.batteries.apply(self.request)
        self.batteries.apply(self.request)
        self.batteries.apply({**self.request, 'enabled': False})
        self.assertEqual(self.bus.writes, [(PATH, True), (PATH, False)])

    def test_stale_daemon_owner_cannot_retarget_action(self):
        self.bus.owner = ':1.35'
        with self.assertRaisesRegex(ValueError, 'service changed'):
            battery.Batteries(self.bus).apply(self.request)
        self.assertEqual(self.bus.writes, [])

    def test_replacement_at_same_path_cannot_retarget_action(self):
        self.bus.devices[PATH]['Serial'] = 'replacement'
        with self.assertRaisesRegex(ValueError, 'battery changed'):
            self.batteries.apply(self.request)
        self.assertEqual(self.bus.writes, [])

    def test_removed_device_rejected(self):
        del self.bus.devices[PATH]
        with self.assertRaisesRegex(ValueError, 'no longer connected'):
            self.batteries.apply(self.request)
        self.assertEqual(self.bus.writes, [])

    def test_lost_capability_and_non_system_device_rejected(self):
        self.bus.devices[PATH]['ChargeThresholdSupported'] = False
        with self.assertRaisesRegex(ValueError, 'supported charge-limit'):
            self.batteries.apply(self.request)
        self.bus.devices[PATH]['PowerSupply'] = False
        with self.assertRaisesRegex(ValueError, 'battery changed'):
            self.batteries.apply(self.request)
        self.assertEqual(self.bus.writes, [])

    def test_permission_denial_is_not_success(self):
        self.bus.denied = True
        with self.assertRaises(GLib.Error):
            self.batteries.apply(self.request)
        self.assertFalse(self.batteries.row(PATH)['enabled'])

    def test_readback_mismatch_is_not_success(self):
        self.bus.ignore = True
        with self.assertRaisesRegex(ValueError, 'could not be verified'):
            self.batteries.apply(self.request)

    def test_restart_after_write_is_unverified(self):
        self.bus.restart = True
        with self.assertRaisesRegex(ValueError, 'before the change could be verified'):
            self.batteries.apply(self.request)

    def test_replacement_after_write_is_unverified(self):
        self.bus.replace = True
        with self.assertRaisesRegex(ValueError, 'could not be verified'):
            self.batteries.apply(self.request)

    def test_invalid_requests_never_write(self):
        for changes in ({'enabled': 1}, {'path': None}, {'identity': []}, {'extra': 'value'}):
            with self.assertRaises(ValueError):
                self.batteries.apply({**self.request, **changes})
        self.assertEqual(self.bus.writes, [])


if __name__ == '__main__':
    unittest.main()
