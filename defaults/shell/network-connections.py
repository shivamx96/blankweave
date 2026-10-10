#!/usr/bin/env python3
"""Read NetworkManager links and change an explicitly captured connection.

No secrets are requested. DNS persistence uses nmcli's partial update; live
reapply patches only DNS on GetAppliedConnection with its version guard.
"""
import ipaddress
import json
import re
import subprocess
import sys
import time

import gi
from gi.repository import Gio, GLib

NM = 'org.freedesktop.NetworkManager'
ROOT = '/org/freedesktop/NetworkManager'
DEVICE = NM + '.Device'
CONNECTION = NM + '.Settings.Connection'
ACTIVE = NM + '.Connection.Active'
PRESETS = {
    'Automatic': ('', ''),
    'Cloudflare': ('1.1.1.1,1.0.0.1', '2606:4700:4700::1111,2606:4700:4700::1001'),
    'Google': ('8.8.8.8,8.8.4.4', '2001:4860:4860::8888,2001:4860:4860::8844'),
    'Quad9': ('9.9.9.9,149.112.112.112', '2620:fe::fe,2620:fe::9'),
    'OpenDNS': ('208.67.222.222,208.67.220.220', '2620:119:35::35,2620:119:53::53'),
}


def addresses(text, version):
    if not isinstance(text, str) or len(text) > 2048:
        raise ValueError('Enter IP addresses separated by commas or spaces.')
    result = []
    for token in re.split(r'[,\s]+', text.strip()):
        if not token:
            continue
        address = ipaddress.ip_address(token)
        if address.version != version or '%' in token or address.is_unspecified or address.is_multicast:
            raise ValueError(f'Enter valid IPv{version} DNS server addresses.')
        if str(address) not in result:
            result.append(str(address))
    if len(result) > 8:
        raise ValueError('Use at most eight DNS servers per address family.')
    return result


def dns_values(section, version):
    if 'dns-data' in section:
        return section['dns-data']
    if version == 4:
        return [str(ipaddress.ip_address(int(value).to_bytes(4, sys.byteorder))) for value in section.get('dns', [])]
    return [str(ipaddress.ip_address(bytes(value))) for value in section.get('dns', [])]


def dns_patch(version, servers, automatic):
    # The wire format uses network-order bytes stored in host-order uint32s.
    values = [int.from_bytes(ipaddress.ip_address(value).packed, sys.byteorder) for value in servers] if version == 4 else [list(ipaddress.ip_address(value).packed) for value in servers]
    return {'dns': GLib.Variant('au' if version == 4 else 'aay', values),
            'ignore-auto-dns': GLib.Variant('b', not automatic)}


def variant_settings(value):
    """Keep each setting's original signature for a lossless live DNS patch."""
    result = {}
    for i in range(value.n_children()):
        entry = value.get_child_value(i)
        section = entry.get_child_value(1)
        result[entry.get_child_value(0).get_string()] = {
            section.get_child_value(j).get_child_value(0).get_string():
            section.get_child_value(j).get_child_value(1).get_variant()
            for j in range(section.n_children())}
    return result


class Network:
    def __init__(self):
        self.bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        self.owner = self.bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus',
                                       'org.freedesktop.DBus', 'GetNameOwner', GLib.Variant('(s)', (NM,)),
                                       None, Gio.DBusCallFlags.NONE, 5000, None).unpack()[0]

    def call(self, path, interface, method, parameters=None):
        return self.bus.call_sync(self.owner, path, interface, method, parameters, None,
                                  Gio.DBusCallFlags.NONE, 10000, None)

    def props(self, path, interface):
        return self.call(path, 'org.freedesktop.DBus.Properties', 'GetAll', GLib.Variant('(s)', (interface,))).unpack()[0]

    def settings(self, path):
        return self.call(path, CONNECTION, 'GetSettings').unpack()[0]

    def ip(self, device, version):
        path = device.get(f'Ip{version}Config', '/')
        if path == '/':
            return {'addresses': [], 'gateway': '', 'dns': []}
        data = self.props(path, NM + f'.IP{version}Config')
        dns = [item['address'] for item in data.get('NameserverData', []) if 'address' in item]
        if not dns:
            dns = dns_values({'dns': data.get('Nameservers', [])}, version)
        return {'addresses': [str(item['address']) + '/' + str(item['prefix']) for item in data.get('AddressData', [])],
                'gateway': data.get('Gateway', ''), 'dns': dns}

    def row(self, path):
        device = self.props(path, DEVICE)
        if device.get('DeviceType') not in (1, 2):
            return None
        active_path = device.get('ActiveConnection', '/')
        active = self.props(active_path, ACTIVE) if active_path != '/' else {}
        profile = active.get('Connection', '/')
        settings = self.settings(profile) if profile != '/' else {}
        wired = self.props(path, DEVICE + '.Wired') if device['DeviceType'] == 1 else {}
        choices = []
        if device['DeviceType'] == 1:
            for candidate in device.get('AvailableConnections', []):
                connection = self.settings(candidate).get('connection', {})
                if connection.get('type') == '802-3-ethernet':
                    choices.append({'uuid': connection['uuid'], 'name': connection['id']})
        dns = {}
        for version in (4, 6):
            section = settings.get(f'ipv{version}', {})
            dns[str(version)] = {'enabled': section.get('method', 'disabled') not in ('disabled', 'ignore', 'link-local', 'shared'),
                                 'automatic': not section.get('ignore-auto-dns', False),
                                 'servers': dns_values(section, version)}
        provider = 'Custom'
        enabled = [v for v in (4, 6) if dns[str(v)]['enabled']]
        for name, servers in PRESETS.items():
            if enabled and all(dns[str(v)]['automatic'] == (name == 'Automatic') and
                               dns[str(v)]['servers'] == addresses(servers[v == 6], v) for v in enabled):
                provider = name
                break
        return {'path': path, 'owner': self.owner, 'interface': device['Interface'],
                'kind': 'ethernet' if device['DeviceType'] == 1 else 'wifi',
                'managed': device.get('Managed', False), 'state': device.get('State', 0),
                'connected': device.get('State') == 100 and active.get('State') == 2,
                'carrier': wired.get('Carrier', False), 'speed': wired.get('Speed', 0),
                'activePath': active_path, 'uuid': active.get('Uuid', ''), 'name': active.get('Id', ''),
                'default': active.get('Default', False) or active.get('Default6', False),
                'profiles': sorted(choices, key=lambda item: (item['name'], item['uuid'])),
                'ipv4': self.ip(device, 4), 'ipv6': self.ip(device, 6), 'dns': dns, 'provider': provider}

    def status(self):
        paths = self.call(ROOT, NM, 'GetDevices').unpack()[0]
        rows = []
        for path in paths:
            try:
                row = self.row(path)
                if row:
                    rows.append(row)
            except GLib.Error:
                # A device can disappear during a status snapshot; never reuse it.
                continue
        return {'devices': rows}

    def target(self, request, connected=False):
        if request.get('owner') != self.owner or not re.fullmatch(ROOT + r'/Devices/[0-9]+', request.get('path', '')):
            raise ValueError('The network device changed. Refresh and try again.')
        row = self.row(request['path'])
        if not row or any(row[key] != request.get(key) for key in ('interface', 'uuid', 'activePath')):
            raise ValueError('The connection changed. Refresh and try again.')
        if not row['managed'] or (connected and not row['connected']):
            raise ValueError('This connection is no longer active or managed by NetworkManager.')
        return row

    def wait(self, path, predicate):
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            row = self.row(path)
            if row and predicate(row):
                return
            if row and row['state'] == 120:
                raise ValueError('Ethernet connection failed. Check the cable and profile settings.')
            time.sleep(.2)
        raise ValueError('The request timed out. Refresh to check the connection.')

    def ethernet(self, request):
        row = self.target(request)
        if row['kind'] != 'ethernet':
            raise ValueError('Select an Ethernet adapter.')
        if request['action'] == 'disconnect':
            if not row['connected']:
                raise ValueError('This Ethernet connection is no longer active.')
            # Address the captured activation, never a newly activated connection.
            self.call(ROOT, NM, 'DeactivateConnection', GLib.Variant('(o)', (row['activePath'],)))
            self.wait(row['path'], lambda current: current['activePath'] != row['activePath'])
            return
        if row['activePath'] != '/' or not row['carrier'] or row['state'] not in (30, 120):
            raise ValueError('Connect a cable and wait for the adapter to become ready.')
        uuid = request.get('profile', '')
        if uuid:
            if uuid not in [item['uuid'] for item in row['profiles']]:
                raise ValueError('That Ethernet profile is no longer available for this adapter.')
            profile = self.call(ROOT + '/Settings', NM + '.Settings', 'GetConnectionByUuid', GLib.Variant('(s)', (uuid,))).unpack()[0]
            self.call(ROOT, NM, 'ActivateConnection', GLib.Variant('(ooo)', (profile, row['path'], '/')))
        else:
            if row['profiles']:
                raise ValueError('Choose an existing Ethernet profile.')
            settings = {'connection': {'type': GLib.Variant('s', '802-3-ethernet'),
                                       'id': GLib.Variant('s', 'Ethernet ' + row['interface'])},
                        'ipv4': {'method': GLib.Variant('s', 'auto')},
                        'ipv6': {'method': GLib.Variant('s', 'auto')}}
            _, activation = self.call(ROOT, NM, 'AddAndActivateConnection', GLib.Variant('(a{sa{sv}}oo)', (settings, row['path'], '/'))).unpack()
            self.wait(row['path'], lambda current: current['connected'] and current['activePath'] == activation)
            return
        self.wait(row['path'], lambda current: current['connected'] and current['uuid'] == uuid)

    def set_dns(self, request):
        provider = request.get('provider')
        if provider not in (*PRESETS, 'Custom'):
            raise ValueError('Choose a DNS provider.')
        inputs = PRESETS[provider] if provider in PRESETS else (request.get('ipv4', ''), request.get('ipv6', ''))
        servers = {v: addresses(inputs[v == 6], v) for v in (4, 6)}
        row = self.target(request, connected=True)
        enabled = [v for v in (4, 6) if row['dns'][str(v)]['enabled']]
        if not enabled:
            raise ValueError('DNS cannot be configured for this connection’s IP methods.')
        if provider == 'Custom' and any(not servers[v] for v in enabled):
            raise ValueError('Enter at least one DNS server for each enabled IP version.')
        # Fetch variants and version together to retain exact setting types.
        snapshot = self.call(row['path'], DEVICE, 'GetAppliedConnection', GLib.Variant('(u)', (0,)))
        live = variant_settings(snapshot.get_child_value(0))
        version = snapshot.get_child_value(1).unpack()
        if live['connection']['uuid'].unpack() != row['uuid']:
            raise ValueError('The active connection changed. Refresh and try again.')
        arguments = []
        for v in enabled:
            section = live.get(f'ipv{v}', {})
            if section.get('method', GLib.Variant('s', 'disabled')).unpack() in ('disabled', 'ignore', 'link-local', 'shared'):
                raise ValueError('Saved IP settings differ from the active connection. Reconnect before changing DNS.')
            section.pop('dns-data', None)
            section.update(dns_patch(v, servers[v], provider == 'Automatic'))
            live[f'ipv{v}'] = section
            arguments.extend([f'ipv{v}.ignore-auto-dns', 'no' if provider == 'Automatic' else 'yes',
                              f'ipv{v}.dns', ','.join(servers[v])])
        self.target(request, connected=True)
        result = subprocess.run(['nmcli', '--wait', '10', 'connection', 'modify', 'uuid', row['uuid'], *arguments],
                                capture_output=True, text=True, timeout=15, check=False)
        if result.returncode:
            raise ValueError('Could not save DNS settings. Check NetworkManager permissions and try again.')
        try:
            self.target(request, connected=True)
            self.call(row['path'], DEVICE, 'Reapply', GLib.Variant('(a{sa{sv}}tu)', (live, version, 1)))
            current = self.target(request, connected=True)
            actual = self.call(row['path'], DEVICE, 'GetAppliedConnection', GLib.Variant('(u)', (0,))).unpack()[0]
            if actual.get('connection', {}).get('uuid') != row['uuid']:
                raise ValueError('Connection changed')
            for v in enabled:
                saved = current['dns'][str(v)]
                if saved['servers'] != servers[v] or saved['automatic'] != (provider == 'Automatic') or dns_values(actual.get(f'ipv{v}', {}), v) != servers[v] or bool(actual.get(f'ipv{v}', {}).get('ignore-auto-dns', False)) != (provider != 'Automatic'):
                    raise ValueError('DNS readback did not match')
        except (GLib.Error, ValueError, KeyError) as error:
            raise ValueError('DNS settings were saved, but could not be confirmed on the active connection. Reconnect this profile to apply them.') from error


def main():
    try:
        network = Network()
        if sys.argv[1:] == ['status']:
            print(json.dumps(network.status()))
        elif sys.argv[1:] == ['apply']:
            request = json.loads(sys.stdin.read(8192))
            if not isinstance(request, dict):
                raise ValueError('Invalid network request.')
            if request.get('action') == 'dns':
                network.set_dns(request)
            elif request.get('action') in ('connect', 'disconnect'):
                network.ethernet(request)
            else:
                raise ValueError('Unknown network action.')
        else:
            raise ValueError('Usage: network-connections.py status | apply (JSON on stdin)')
    except (GLib.Error, OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        message = str(error) if isinstance(error, ValueError) else 'NetworkManager could not complete the request. Refresh and check permissions.'
        print(message, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
