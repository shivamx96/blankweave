#!/usr/bin/env python3
import copy
import importlib.util
import ipaddress
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch
from gi.repository import GLib

SPEC = importlib.util.spec_from_file_location('network_connections', Path(__file__).resolve().parents[1] / 'defaults/shell/network-connections.py')
n = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(n)
UUID = '11111111-1111-1111-1111-111111111111'
PATH = n.ROOT + '/Devices/1'


class FakeNetwork(n.Network):
    def __init__(self):
        self.owner = ':1.42'
        self.calls = []
        self.device = {'DeviceType': 1, 'Interface': 'eth-test', 'Managed': True, 'State': 100,
                       'ActiveConnection': '/active/1', 'Ip4Config': '/ip4', 'Ip6Config': '/ip6', 'AvailableConnections': ['/profile']}
        self.active = {'Connection': '/profile', 'Uuid': UUID, 'Id': 'Desk: <b>LAN</b>', 'State': 2, 'Default': True}
        self.saved = {'connection': {'uuid': GLib.Variant('s', UUID), 'id': GLib.Variant('s', 'Desk: <b>LAN</b>'), 'type': GLib.Variant('s', '802-3-ethernet')},
                      'ipv4': {'method': GLib.Variant('s', 'auto'), 'dns-search': GLib.Variant('as', ['corp.test']), 'route-metric': GLib.Variant('x', 77)},
                      'ipv6': {'method': GLib.Variant('s', 'auto')},
                      '802-1x': {'password-flags': GLib.Variant('u', 1)}}
        self.live = copy.copy(self.saved)
        self.live = {k: dict(v) for k, v in self.saved.items()}
        self.live['ipv4']['route-metric'] = GLib.Variant('x', 88)
        self.version = 5
        self.fail_reapply = False
        self.mismatch = False
        self.carrier = True
        self.switched = False

    def settings(self, path):
        return GLib.Variant('a{sa{sv}}', self.saved).unpack()

    def props(self, path, interface):
        if interface == n.DEVICE:
            return dict(self.device)
        if interface == n.DEVICE + '.Wired':
            return {'Carrier': self.carrier, 'Speed': 1000}
        if interface == n.ACTIVE:
            return dict(self.active)
        if interface.endswith('.IP4Config'):
            return {'AddressData': [{'address': '192.0.2.2', 'prefix': 24}], 'Gateway': '192.0.2.1', 'NameserverData': [{'address': '192.0.2.53'}]}
        if interface.endswith('.IP6Config'):
            return {'AddressData': [{'address': '2001:db8::1', 'prefix': 64}], 'Nameservers': [list(ipaddress.ip_address('2001:db8::53').packed)]}
        raise AssertionError(interface)

    def call(self, path, interface, method, parameters=None):
        self.calls.append((path, interface, method, parameters))
        if method == 'GetDevices':
            return GLib.Variant('(ao)', ([PATH],))
        if method == 'GetAppliedConnection':
            return GLib.Variant('(a{sa{sv}}t)', (self.live, self.version))
        if method == 'Reapply':
            self.asserted_version = parameters.get_child_value(1).unpack()
            self.asserted_flags = parameters.get_child_value(2).unpack()
            if self.fail_reapply:
                raise GLib.Error('Version changed')
            if not self.mismatch:
                self.live = n.variant_settings(parameters.get_child_value(0))
            return GLib.Variant('()', ())
        if method == 'GetConnectionByUuid':
            return GLib.Variant('(o)', ('/profile',))
        if method == 'ActivateConnection':
            self.device['State'] = 100
            self.device['ActiveConnection'] = '/active/1'
            return GLib.Variant('(o)', ('/active/1',))
        if method == 'DeactivateConnection':
            self.device['State'] = 30
            self.device['ActiveConnection'] = '/'
            return GLib.Variant('()', ())
        if method == 'AddAndActivateConnection':
            self.device['State'] = 100
            self.device['ActiveConnection'] = '/active/2'
            return GLib.Variant('(oo)', ('/profile', '/active/2'))
        raise AssertionError(method)

    def modify(self, args, **kwargs):
        self.command = args
        assert kwargs['timeout'] == 15
        assert args[:7] == ['nmcli', '--wait', '10', 'connection', 'modify', 'uuid', UUID]
        for key, val in zip(args[7::2], args[8::2]):
            section, key = key.split('.', 1)
            if key == 'dns':
                self.saved[section].update(n.dns_patch(int(section[-1]), n.addresses(val, int(section[-1])), False))
            elif key == 'ignore-auto-dns':
                self.saved[section][key] = GLib.Variant('b', val == 'yes')
        # Match the supplied automatic flag, regardless of argument order.
        for key, val in zip(args[7::2], args[8::2]):
            if key.endswith('.ignore-auto-dns'):
                self.saved[key.split('.')[0]]['ignore-auto-dns'] = GLib.Variant('b', val == 'yes')
        if self.switched:
            self.active['Uuid'] = 'another-profile'
        return subprocess.CompletedProcess(args, 0)


class NetworkTest(unittest.TestCase):
    def setUp(self):
        self.net = FakeNetwork()
        self.request = {**self.net.row(PATH), 'action': 'dns', 'provider': 'Cloudflare'}
        self.patcher = patch.object(n.subprocess, 'run', self.net.modify)
        self.mock = self.patcher.start()
        self.addCleanup(self.patcher.stop)

    def test_status_has_profiles_addresses_and_both_families_without_secrets(self):
        row = self.net.status()['devices'][0]
        self.assertEqual(row['provider'], 'Automatic')
        self.assertEqual(row['profiles'], [{'uuid': UUID, 'name': 'Desk: <b>LAN</b>'}])
        self.assertEqual(row['ipv4']['addresses'], ['192.0.2.2/24'])
        self.assertEqual(row['ipv6']['dns'], ['2001:db8::53'])
        self.assertFalse(any(call[2] == 'GetSecrets' for call in self.net.calls))

    def test_dns_preserves_saved_and_applied_settings_and_version(self):
        self.net.set_dns(self.request)
        self.assertEqual(self.net.row(PATH)['provider'], 'Cloudflare')
        self.assertEqual(self.net.saved['ipv4']['route-metric'].unpack(), 77)
        self.assertEqual(self.net.live['ipv4']['route-metric'].unpack(), 88)
        self.assertEqual(self.net.live['ipv4']['dns-search'].unpack(), ['corp.test'])
        self.assertEqual(self.net.live['802-1x']['password-flags'].unpack(), 1)
        self.assertEqual(self.net.asserted_version, 5)
        self.assertEqual(self.net.asserted_flags, 1)

    def test_automatic_clears_overrides_and_enables_dhcp_dns(self):
        self.net.set_dns(self.request)
        self.net.set_dns({**self.request, 'provider': 'Automatic'})
        self.assertEqual(self.net.row(PATH)['provider'], 'Automatic')
        self.assertEqual(n.dns_values(self.net.settings('/profile')['ipv4'], 4), [])

    def test_custom_validation_and_deduplication(self):
        self.net.set_dns({**self.request, 'provider': 'Custom', 'ipv4': '192.0.2.53 192.0.2.53', 'ipv6': '2001:db8::53'})
        self.assertEqual(self.net.row(PATH)['dns']['4']['servers'], ['192.0.2.53'])
        for bad in ('', 'bad', '1.1.1.1; reboot', '::1', '0.0.0.0', '224.0.0.1'):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                self.net.set_dns({**self.request, 'provider': 'Custom', 'ipv4': bad, 'ipv6': '::1'})

    def test_disabled_ipv6_is_preserved(self):
        self.net.saved['ipv6']['method'] = GLib.Variant('s', 'disabled')
        self.net.live['ipv6']['method'] = GLib.Variant('s', 'disabled')
        before = dict(self.net.live['ipv6'])
        self.net.set_dns(self.request)
        self.assertEqual(self.net.live['ipv6'], before)
        self.assertFalse(any('ipv6.' in arg for arg in self.net.command))
        self.assertEqual(self.net.row(PATH)['provider'], 'Cloudflare')

    def test_saved_live_ip_method_difference_blocks_edit(self):
        self.net.live['ipv6']['method'] = GLib.Variant('s', 'disabled')
        with self.assertRaisesRegex(ValueError, 'Reconnect'):
            self.net.set_dns(self.request)
        self.assertFalse(hasattr(self.net, 'command'))

    def test_stale_device_activation_and_daemon_guard(self):
        for key, bad in [('owner', ':1.99'), ('path', '/bad'), ('interface', 'eth-new'), ('uuid', 'changed'), ('activePath', '/active/9')]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.net.set_dns({**self.request, key: bad})
        self.assertFalse(hasattr(self.net, 'command'))

    def test_saved_but_live_failure_is_explicit_without_reconnect(self):
        for key in ('fail_reapply', 'mismatch', 'switched'):
            with self.subTest(key=key):
                self.setUp()
                setattr(self.net, key, True)
                with self.assertRaisesRegex(ValueError, 'saved.*could not be confirmed'):
                    self.net.set_dns(self.request)
                self.assertFalse(any(c[2] == 'ActivateConnection' for c in self.net.calls))

    def test_permission_failure_does_not_reapply(self):
        with patch.object(n.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1)):
            with self.assertRaisesRegex(ValueError, 'permissions'):
                self.net.set_dns(self.request)
        self.assertFalse(any(c[2] == 'Reapply' for c in self.net.calls))

    def test_disconnect_targets_captured_activation(self):
        self.net.ethernet({**self.request, 'action': 'disconnect'})
        call = next(c for c in self.net.calls if c[2] == 'DeactivateConnection')
        self.assertEqual(call[3].unpack(), ('/active/1',))
        self.assertEqual(self.net.device['ActiveConnection'], '/')

    def test_connect_profile_and_no_profile_dhcp(self):
        self.net.device.update(State=30, ActiveConnection='/')
        request = {**self.net.row(PATH), 'action': 'connect', 'profile': UUID}
        self.net.ethernet(request)
        self.assertTrue(self.net.row(PATH)['connected'])
        self.net.device.update(State=30, ActiveConnection='/', AvailableConnections=[])
        self.net.ethernet({**self.net.row(PATH), 'action': 'connect', 'profile': ''})
        call = next(c for c in self.net.calls if c[2] == 'AddAndActivateConnection')
        settings = call[3].unpack()[0]
        self.assertEqual(settings['ipv4']['method'], 'auto')
        self.assertEqual(settings['ipv6']['method'], 'auto')

    def test_missing_cable_unmanaged_unknown_profile_and_wifi_rejected(self):
        self.net.device.update(State=30, ActiveConnection='/')
        request = {**self.net.row(PATH), 'action': 'connect', 'profile': UUID}
        self.net.carrier = False
        with self.assertRaisesRegex(ValueError, 'cable'):
            self.net.ethernet(request)
        self.net.carrier = True
        with self.assertRaisesRegex(ValueError, 'profile'):
            self.net.ethernet({**request, 'profile': 'unknown'})
        self.net.device['Managed'] = False
        with self.assertRaisesRegex(ValueError, 'managed'):
            self.net.ethernet(request)
        self.net.device.update(Managed=True, DeviceType=2)
        with self.assertRaisesRegex(ValueError, 'Ethernet'):
            self.net.ethernet(request)
        self.assertFalse(any(c[2] in ('ActivateConnection', 'AddAndActivateConnection') for c in self.net.calls))

    def test_provider_matching_requires_exact_addresses(self):
        self.net.set_dns(self.request)
        self.net.saved['ipv4'].update(n.dns_patch(4, ['1.1.1.1', '1.0.0.1', '192.0.2.53'], False))
        self.assertEqual(self.net.row(PATH)['provider'], 'Custom')


if __name__ == '__main__':
    unittest.main()
