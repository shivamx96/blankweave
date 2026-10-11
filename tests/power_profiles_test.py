#!/usr/bin/env python3
"""Exercise the helper's D-Bus contract without touching host power settings."""
import importlib.util
from pathlib import Path
import unittest
from gi.repository import Gio, GLib

SPEC = importlib.util.spec_from_file_location('power', Path(__file__).resolve().parents[1] / 'defaults/shell/power-profiles.py')
power = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(power)
SERVICE = next(iter(power.ENDPOINTS))


class Bus:
    def __init__(self):
        self.owner = ':1.23'
        self.service = SERVICE
        self.profile = 'balanced'
        self.profiles = ['power-saver', 'balanced', 'performance']
        self.holds = [{'ApplicationId': '<b>Renderer</b>', 'Profile': 'performance', 'Reason': 'Rendering'}]
        self.degraded = 'high-operating-temperature'
        self.writes = []
        self.calls = []
        self.ignore = False
        self.denied = False
        self.restart_on_set = False
        self.restart_on_read = False
        self.invalid = False

    def call_sync(self, destination, path, interface, method, args, reply, flags, timeout, cancellable):
        self.calls.append((destination, path, interface, method))
        assert flags == Gio.DBusCallFlags.NO_AUTO_START
        assert 0 < timeout <= 10000
        if method == 'GetNameOwner':
            if args.unpack()[0] != self.service or not self.owner:
                raise Gio.DBusError.new_for_dbus_error('org.freedesktop.DBus.Error.NameHasNoOwner', 'Not running')
            return GLib.Variant('(s)', (self.owner,))
        assert destination == self.owner  # Never write using a replaceable well-known name.
        assert path == power.ENDPOINTS[self.service]
        assert interface == 'org.freedesktop.DBus.Properties'
        if method == 'GetAll':
            assert args.unpack()[0] == self.service
            result = {
                'Profiles': GLib.Variant('aa{sv}', [{'Profile': GLib.Variant('s', p)} for p in self.profiles]),
                'ActiveProfile': GLib.Variant('s', self.profile),
                'PerformanceDegraded': GLib.Variant('s', self.degraded),
                'ActiveProfileHolds': GLib.Variant('aa{sv}', [{k: GLib.Variant('s', v) for k, v in h.items()} for h in self.holds]),
            }
            if self.invalid:
                del result['Profiles']
            if self.restart_on_read:
                self.owner = ':1.24'
            return GLib.Variant('(a{sv})', (result,))
        if method == 'Set':
            service, key, profile = args.unpack()
            assert (service, key) == (self.service, 'ActiveProfile')
            self.writes.append(profile)
            if self.denied:
                raise Gio.DBusError.new_for_dbus_error('org.freedesktop.DBus.Error.AccessDenied', 'Denied')
            if not self.ignore:
                self.profile = profile
            if self.restart_on_set:
                self.owner = ':1.24'
            return GLib.Variant('()', ())
        raise AssertionError(method)


class PowerTests(unittest.TestCase):
    def setUp(self):
        self.bus = Bus()
        self.power = power.Power(self.bus)

    def apply(self, profile='power-saver'):
        self.power.apply(self.bus.service, ':1.23', profile)

    def test_status_reads_supported_profiles_holds_and_degradation(self):
        result = self.power.status()
        self.assertEqual(result['profile'], 'balanced')
        self.assertEqual(result['profiles'][0], {'id': 'power-saver', 'name': 'Power saver'})
        self.assertEqual(result['holds'][0]['application'], '<b>Renderer</b>')
        self.assertEqual(result['degraded'], 'high-operating-temperature')
        self.assertEqual(self.bus.writes, [])

    def test_absent_daemon_is_unavailable_without_activation(self):
        self.bus.owner = ''
        self.assertFalse(self.power.status()['available'])
        self.assertTrue(all(call[3] == 'GetNameOwner' for call in self.bus.calls))

    def test_legacy_endpoint(self):
        self.bus.service = 'net.hadess.PowerProfiles'
        self.assertEqual(self.power.status()['service'], self.bus.service)
        self.apply()
        self.assertEqual(self.bus.profile, 'power-saver')

    def test_unreported_performance_profile_is_not_offered_or_set(self):
        self.bus.profiles.remove('performance')
        self.assertEqual(len(self.power.status()['profiles']), 2)
        with self.assertRaisesRegex(ValueError, 'no longer available'):
            self.apply('performance')
        self.assertEqual(self.bus.writes, [])

    def test_write_is_verified_and_only_changes_active_profile(self):
        self.apply()
        self.assertEqual(self.bus.writes, ['power-saver'])
        self.assertEqual(self.bus.calls[-1][3], 'GetAll')
        self.assertEqual(self.power.status()['profile'], 'power-saver')

    def test_no_op_preserves_holds(self):
        self.apply('balanced')
        self.assertEqual(self.bus.writes, [])

    def test_stale_daemon_rejected_before_write(self):
        self.bus.owner = ':1.24'
        with self.assertRaisesRegex(ValueError, 'service changed'):
            self.apply()
        self.assertEqual(self.bus.writes, [])

    def test_restart_during_discovery_rejected(self):
        self.bus.restart_on_read = True
        with self.assertRaisesRegex(ValueError, 'restarted'):
            self.power.status()

    def test_restart_between_validation_and_write_rejected(self):
        self.bus.restart_on_read = True
        with self.assertRaisesRegex(ValueError, 'service changed'):
            self.apply()
        self.assertEqual(self.bus.writes, [])

    def test_restart_after_write_is_unverified(self):
        self.bus.restart_on_set = True
        with self.assertRaisesRegex(ValueError, 'verified'):
            self.apply()

    def test_readback_mismatch_not_success(self):
        self.bus.ignore = True
        with self.assertRaisesRegex(ValueError, 'did not stay active'):
            self.apply()

    def test_permission_denial_propagates(self):
        self.bus.denied = True
        with self.assertRaises(GLib.Error):
            self.apply()
        self.assertEqual(self.bus.profile, 'balanced')

    def test_invalid_status_rejected(self):
        self.bus.invalid = True
        with self.assertRaisesRegex(ValueError, 'invalid profile'):
            self.power.status()

    def test_unknown_profile_not_exposed_as_supported(self):
        self.bus.profiles += ['future-mode']
        self.assertEqual(len(self.power.status()['profiles']), 3)
        with self.assertRaisesRegex(ValueError, 'Invalid'):
            self.apply('future-mode')
        self.assertEqual(self.bus.writes, [])

    def test_invalid_target_never_calls_bus(self):
        for service, owner, profile in [('evil', ':1.23', 'balanced'), (SERVICE, '', 'balanced'), (SERVICE, ':1.23', 'bad')]:
            with self.assertRaises(ValueError):
                self.power.apply(service, owner, profile)
        self.assertEqual(self.bus.calls, [])


if __name__ == '__main__':
    unittest.main()
