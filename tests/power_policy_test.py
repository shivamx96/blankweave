#!/usr/bin/env python3
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from gi.repository import Gio, GLib
from power_profiles_test import Bus, power, SERVICE

SPEC = importlib.util.spec_from_file_location('policy', Path(__file__).resolve().parents[1] / 'defaults/shell/power_policy.py')
policy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(policy)


class BatteryBus(Bus):
    def __init__(self):
        super().__init__()
        self.holds = []
        self.source_owner = ':1.30'
        self.on_battery = False
        self.percentage = 70.0
        self.present = True
        self.kind = 2
        self.state = None
        self.source_reads = 0
        self.change_on_guard = False
        self.hold_on_guard = False
        self.profile_reads = 0

    def call_sync(self, destination, path, interface, method, args, reply, flags, timeout, cancellable):
        if method == 'GetNameOwner' and args.unpack()[0] == policy.UPOWER:
            if not self.source_owner:
                raise Gio.DBusError.new_for_dbus_error('org.freedesktop.DBus.Error.NameHasNoOwner', 'Not running')
            return GLib.Variant('(s)', (self.source_owner,))
        if destination == self.source_owner:
            assert flags == Gio.DBusCallFlags.NO_AUTO_START
            if path == policy.ROOT:
                self.source_reads += 1
                if self.change_on_guard and self.source_reads == 2:
                    self.on_battery = True
                return GLib.Variant('(a{sv})', ({'OnBattery': GLib.Variant('b', self.on_battery)},))
            if path == policy.ROOT + '/devices/DisplayDevice':
                return GLib.Variant('(a{sv})', ({'Type': GLib.Variant('u', self.kind),
                    'IsPresent': GLib.Variant('b', self.present), 'Percentage': GLib.Variant('d', self.percentage),
                    'State': GLib.Variant('u', self.state if self.state is not None else 2 if self.on_battery else 1)},))
            raise AssertionError(path)
        if method == 'GetAll':
            self.profile_reads += 1
            if self.hold_on_guard and self.profile_reads == 2:
                self.holds = [{'ApplicationId': 'app', 'Profile': 'performance', 'Reason': 'Rendering'}]
        return super().call_sync(destination, path, interface, method, args, reply, flags, timeout, cancellable)


class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.environment = patch.dict(os.environ, {'XDG_CONFIG_HOME': self.directory.name + '/config', 'XDG_STATE_HOME': self.directory.name + '/state'})
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.bus = BatteryBus()
        self.power = power.Power(self.bus)
        self.policy = policy.Policy()
        self.settings = {**policy.DEFAULTS, 'enabled': True, 'ac': 'performance', 'battery': 'balanced'}

    def enable(self, **changes):
        self.settings.update(changes)
        self.policy.configure(self.power, {'expected': self.policy.settings(), 'settings': self.settings})
        self.bus.source_reads = self.bus.profile_reads = 0

    def test_defaults_are_off_and_status_does_not_write(self):
        result = self.policy.status(self.power, self.power.status())
        self.assertFalse(result['settings']['enabled'])
        self.assertTrue(result['source']['available'])
        self.assertFalse(self.policy.config.exists())
        self.assertFalse(self.policy.state.exists())
        self.assertEqual(self.bus.writes, [])

    def test_disabled_tick_does_not_contact_bus(self):
        self.policy.tick(self.power)
        self.assertEqual(self.bus.calls, [])
        self.assertEqual(self.bus.source_reads, 0)

    def test_ac_battery_low_and_replug_transitions(self):
        self.enable()
        self.policy.tick(self.power)
        self.bus.on_battery = True
        self.policy.tick(self.power)
        self.bus.percentage = 15
        self.policy.tick(self.power)
        self.bus.on_battery = False
        self.policy.tick(self.power)
        self.assertEqual(self.bus.writes, ['performance', 'balanced', 'power-saver', 'performance'])

    def test_hysteresis_and_steady_state_do_not_repeat_writes(self):
        self.enable()
        self.bus.on_battery = True
        for level in (15, 16, 14, 18, 19.99, 20):
            self.bus.percentage = level
            self.policy.tick(self.power)
        self.assertEqual(self.bus.writes, ['power-saver', 'balanced'])

    def test_empty_battery_does_not_become_ac(self):
        self.enable()
        self.bus.on_battery, self.bus.percentage = True, 2
        self.policy.tick(self.power)
        self.bus.on_battery, self.bus.percentage, self.bus.state = False, 0, 3
        self.policy.tick(self.power)
        self.assertEqual(self.bus.writes, ['power-saver'])
        self.assertEqual(self.policy.previous()['condition'], 'low')
        self.assertTrue(self.policy.status(self.power, self.power.status())['source']['onBattery'])
        # An actual transition to charging still selects the AC profile.
        self.bus.state = 1
        self.policy.tick(self.power)
        self.assertEqual(self.bus.writes, ['power-saver', 'performance'])

    def test_battery_states_override_false_on_battery(self):
        self.enable()
        self.bus.percentage = 0
        for state in (2, 3, 6):  # Discharging, empty, pending discharge.
            self.bus.state = state
            self.policy.tick(self.power)
            self.assertEqual(self.policy.previous()['condition'], 'low')
        self.assertEqual(self.bus.writes, ['power-saver'])

    def test_unknown_battery_state_is_not_confirmed_ac(self):
        self.enable()
        for state in (0, 99):
            self.bus.state = state
            with self.assertRaisesRegex(ValueError, 'unknown'):
                self.policy.tick(self.power)
        self.assertEqual(self.bus.writes, [])
        self.assertFalse(self.policy.state.exists())

    def test_ac_states_remain_supported(self):
        self.enable()
        for state in (1, 4, 5):  # Charging, fully charged, pending charge.
            self.bus.state = state
            self.policy.tick(self.power)
            self.assertEqual(self.policy.previous()['condition'], 'ac')
        self.assertEqual(self.bus.writes, ['performance'])

    def test_preferences_and_transition_survive_restart(self):
        self.enable()
        self.policy.tick(self.power)
        restarted = policy.Policy()
        self.assertEqual(restarted.settings(), self.settings)
        restarted.tick(self.power)
        self.assertEqual(self.bus.writes, ['performance'])
        self.assertEqual(self.policy.config.stat().st_mode & 0o777, 0o600)

    def test_external_manual_profile_survives_until_transition(self):
        self.enable()
        self.policy.tick(self.power)
        self.bus.profile = 'power-saver'
        self.policy.tick(self.power)
        self.assertEqual(self.bus.profile, 'power-saver')
        self.assertIn('changed elsewhere', self.policy.status(self.power, self.power.status())['message'])
        self.bus.on_battery = True
        self.policy.tick(self.power)
        self.assertEqual(self.bus.profile, 'balanced')

    def test_manual_selection_disables_automation_even_for_same_profile(self):
        self.enable()
        self.policy.manual(self.power, SERVICE, ':1.23', 'balanced')
        self.assertFalse(self.policy.settings()['enabled'])
        self.policy.tick(self.power)
        self.assertEqual(self.bus.writes, [])

    def test_failed_manual_write_still_disables_automation(self):
        self.enable()
        self.bus.denied = True
        with self.assertRaises(GLib.Error):
            self.policy.manual(self.power, SERVICE, ':1.23', 'power-saver')
        self.assertFalse(self.policy.settings()['enabled'])

    def test_disable_does_not_change_profile_and_works_without_services(self):
        self.enable()
        self.policy.tick(self.power)
        self.bus.owner = self.bus.source_owner = ''
        self.policy.configure(self.power, {'expected': self.settings, 'settings': {**self.settings, 'enabled': False}})
        self.policy.tick(self.power)
        self.assertEqual(self.bus.writes, ['performance'])

    def test_holds_delay_automatic_change(self):
        self.enable()
        self.bus.holds = [{'ApplicationId': 'app', 'Profile': 'balanced', 'Reason': 'Busy'}]
        self.policy.tick(self.power)
        self.assertEqual(self.bus.writes, [])
        self.assertFalse(self.policy.state.exists())
        self.bus.holds = []
        self.policy.tick(self.power)
        self.assertEqual(self.bus.writes, ['performance'])

    def test_hold_arriving_before_write_blocks_change(self):
        self.enable()
        self.bus.hold_on_guard = True
        with self.assertRaisesRegex(ValueError, 'holds'):
            self.policy.tick(self.power)
        self.assertEqual(self.bus.writes, [])

    def test_power_source_change_before_write_retries_without_mutation(self):
        self.enable()
        self.bus.change_on_guard = True
        with self.assertRaisesRegex(ValueError, 'source changed'):
            self.policy.tick(self.power)
        self.assertEqual(self.bus.writes, [])
        self.policy.tick(self.power)
        self.assertEqual(self.bus.profile, 'balanced')

    def test_missing_battery_or_upower_never_guesses_ac(self):
        self.enable()
        for owner, present, kind in [('', True, 2), (':1.30', False, 2), (':1.30', True, 3)]:
            self.bus.source_owner, self.bus.present, self.bus.kind = owner, present, kind
            with self.assertRaises(ValueError):
                self.policy.tick(self.power)
        self.assertEqual(self.bus.writes, [])

    def test_invalid_percentage_pauses(self):
        self.enable()
        for percentage in (-1, 101, float('nan')):
            self.bus.percentage = percentage
            with self.assertRaisesRegex(ValueError, 'unknown'):
                self.policy.tick(self.power)
        self.assertEqual(self.bus.writes, [])

    def test_invalid_preferences_are_preserved_and_block_automation(self):
        self.policy.config.parent.mkdir(parents=True)
        self.policy.config.write_text('{invalid')
        result = self.policy.status(self.power, self.power.status())
        self.assertFalse(result['ready'])
        with self.assertRaises(ValueError):
            self.policy.tick(self.power)
        self.assertEqual(self.policy.config.read_text(), '{invalid')
        self.assertEqual(self.bus.writes, [])

    def test_unavailable_saved_profile_does_not_fallback(self):
        self.enable()
        self.bus.profiles.remove('performance')
        with self.assertRaisesRegex(ValueError, 'no longer available'):
            self.policy.tick(self.power)
        self.assertFalse(self.policy.state.exists())
        self.assertEqual(self.bus.writes, [])

    def test_failed_write_not_recorded_as_applied_and_retry_recovers(self):
        self.enable()
        self.bus.ignore = True
        with self.assertRaisesRegex(ValueError, 'did not stay active'):
            self.policy.tick(self.power)
        self.assertFalse(self.policy.state.exists())
        self.bus.ignore = False
        self.policy.tick(self.power)
        self.assertEqual(self.policy.previous()['profile'], 'performance')

    def test_daemon_restart_reapplies_enabled_policy(self):
        self.enable()
        self.policy.tick(self.power)
        self.bus.profile = 'balanced'
        self.bus.owner = ':1.24'
        self.policy.tick(self.power)
        self.assertEqual(self.bus.writes, ['performance', 'performance'])

    def test_new_boot_reapplies_even_when_dbus_names_are_reused(self):
        self.enable()
        self.policy.tick(self.power)
        self.bus.profile = 'balanced'
        self.policy.boot = 'a-new-boot'
        self.policy.tick(self.power)
        self.assertEqual(self.bus.writes, ['performance', 'performance'])

    def test_stale_config_request_is_rejected(self):
        self.enable()
        with self.assertRaisesRegex(ValueError, 'changed elsewhere'):
            self.policy.configure(self.power, {'expected': policy.DEFAULTS, 'settings': self.settings})
        self.assertEqual(self.policy.settings(), self.settings)

    def test_save_failure_does_not_enable_policy_or_touch_hardware(self):
        with patch.object(policy, 'save', side_effect=PermissionError('Denied')):
            with self.assertRaises(PermissionError):
                self.enable()
        self.assertFalse(self.policy.settings()['enabled'])
        self.assertEqual(self.bus.writes, [])

    def test_lock_serializes_tick_and_manual_changes(self):
        self.enable()
        with self.policy.locked():
            with self.assertRaisesRegex(ValueError, 'in progress'):
                self.policy.tick(self.power)
            with self.assertRaisesRegex(ValueError, 'in progress'):
                self.policy.manual(self.power, SERVICE, ':1.23', 'power-saver')
        self.assertEqual(self.bus.writes, [])

    def test_threshold_and_schema_validation(self):
        for changes in ({'threshold': True}, {'threshold': 51}, {'threshold': 0}, {'ac': 'unknown'}, {'enabled': 1}, {'version': True}, {'future': 1}):
            with self.assertRaises(ValueError):
                policy.validate({**policy.DEFAULTS, **changes})

    def test_corrupt_runtime_state_blocks_writes(self):
        self.enable()
        self.policy.state.write_text('[]')
        with self.assertRaisesRegex(ValueError, 'invalid'):
            self.policy.tick(self.power)
        self.assertEqual(self.bus.writes, [])


if __name__ == '__main__':
    unittest.main()
