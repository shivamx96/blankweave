#!/usr/bin/env python3
"""Airplane mode and temporary WPA2 hotspots; secrets travel only over stdin/D-Bus."""
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import uuid

from gi.repository import Gio, GLib

SPEC = importlib.util.spec_from_file_location('network_connections', Path(__file__).with_name('network-connections.py'))
network = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(network)
NM, ROOT, DEVICE = network.NM, network.ROOT, network.DEVICE
MARKER = 'org.blankweave.hotspot'


def run_rfkill(*args):
    result = subprocess.run(['rfkill', *args], capture_output=True, text=True, timeout=5, check=False)
    if result.returncode:
        raise ValueError('Could not change wireless radios. Check rfkill permissions and try again.')
    return result.stdout


def radios():
    rows = json.loads(run_rfkill('--json', '--output', 'ID,TYPE,DEVICE,SOFT,HARD'))['rfkilldevices']
    return [{'id': int(row['id']), 'type': row['type'], 'name': row['device'],
             'soft': row['soft'] == 'blocked', 'hard': row['hard'] == 'blocked'} for row in rows]


def bluez():
    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    # No activation: airplane mode should also work when BlueZ is not running.
    names = bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus',
                         'ListNames', None, None, Gio.DBusCallFlags.NONE, 5000, None).unpack()[0]
    if 'org.bluez' not in names:
        return bus, []
    objects = bus.call_sync('org.bluez', '/', 'org.freedesktop.DBus.ObjectManager', 'GetManagedObjects',
                            None, None, Gio.DBusCallFlags.NO_AUTO_START, 5000, None).unpack()[0]
    return bus, [{'path': path, 'address': interfaces['org.bluez.Adapter1']['Address'],
                  'powered': interfaces['org.bluez.Adapter1']['Powered']}
                 for path, interfaces in objects.items() if 'org.bluez.Adapter1' in interfaces]


class Airplane:
    def __init__(self):
        self.directory = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'blankweave'
        self.path = self.directory / 'airplane.json'

    def saved(self):
        if not self.path.exists():
            return None
        value = json.loads(self.path.read_text())
        if not isinstance(value, dict) or value.get('version') != 1 or not isinstance(value.get('radios'), list) or not isinstance(value.get('bluetooth'), list):
            raise ValueError('The saved airplane-mode state is invalid.')
        if any(not isinstance(row, dict) or not isinstance(row.get('name'), str) or not isinstance(row.get('type'), str)
               or type(row.get('soft')) is not bool for row in value['radios']) or any(
                   not isinstance(row, dict) or not isinstance(row.get('address'), str) or type(row.get('powered')) is not bool
                   for row in value['bluetooth']):
            raise ValueError('The saved airplane-mode state is invalid.')
        return value

    def status(self):
        current = radios()
        return {'radios': current, 'requested': self.saved() is not None,
                'blocked': bool(current) and all(row['soft'] or row['hard'] for row in current)}

    def store(self, value):
        with tempfile.NamedTemporaryFile(mode='w', dir=self.directory, prefix='.airplane-', delete=False) as stream:
            temporary = Path(stream.name)
            try:
                json.dump(value, stream)
                stream.flush()
                temporary.replace(self.path)
            finally:
                temporary.unlink(missing_ok=True)

    def apply(self, enable):
        if type(enable) is not bool:
            raise ValueError('Invalid airplane-mode request.')
        self.directory.mkdir(parents=True, exist_ok=True)
        with open(self.directory / 'airplane.lock', 'w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            current = radios()
            if not current:
                raise ValueError('No wireless radios detected.')
            saved = self.saved()
            if enable:
                if saved is None:
                    _, adapters = bluez()
                    saved = {'version': 1, 'radios': current, 'bluetooth': adapters}
                else:
                    known = {(row['type'], row['name']) for row in saved['radios']}
                    saved['radios'] += [row for row in current if (row['type'], row['name']) not in known]
                self.store(saved)  # Keep restoration data even if only some radios turn off.
                run_rfkill('block', 'all')
                if not all(row['soft'] or row['hard'] for row in radios()):
                    raise ValueError('Some radios are still enabled. Retry turning them off.')
            else:
                # With no saved state, an explicit request to leave airplane mode unblocks radios.
                desired = {(row['type'], row['name']): row['soft'] for row in (saved or {}).get('radios', [])}
                for row in current:
                    soft = desired.get((row['type'], row['name']), row['soft'] if saved else False)
                    run_rfkill('block' if soft else 'unblock', str(row['id']))
                if saved and saved['bluetooth']:
                    bus, adapters = bluez()
                    previous = {row['address']: row['powered'] for row in saved['bluetooth']}
                    for adapter in adapters:
                        if adapter['address'] in previous:
                            bus.call_sync('org.bluez', adapter['path'], 'org.freedesktop.DBus.Properties', 'Set',
                                          GLib.Variant('(ssv)', ('org.bluez.Adapter1', 'Powered', GLib.Variant('b', previous[adapter['address']]))),
                                          None, Gio.DBusCallFlags.NO_AUTO_START, 5000, None)
                    _, restored = bluez()
                    if any(adapter['address'] in previous and adapter['powered'] != previous[adapter['address']] for adapter in restored):
                        raise ValueError('Bluetooth power could not be restored. Check the hardware switch and retry.')
                for row in radios():
                    expected = desired.get((row['type'], row['name']), row['soft'] if saved else False)
                    if row['soft'] != expected:
                        raise ValueError('Some radios could not be restored. Check the hardware switch and retry.')
                self.path.unlink(missing_ok=True)


class Hotspots(network.Network):
    def row(self, path):
        base = super().row(path)
        if not base or base['kind'] != 'wifi':
            return None
        device = self.props(path, DEVICE)
        wireless = self.props(path, DEVICE + '.Wireless')
        settings = {}
        if base['activePath'] != '/':
            active = self.props(base['activePath'], network.ACTIVE)
            settings = self.settings(active['Connection'])
        wifi = settings.get('802-11-wireless', {})
        base.update(apCapable=(wireless.get('WirelessCapabilities', 0) & 0x68) == 0x68,
                    hotspot=wifi.get('mode') == 'ap',
                    owned=settings.get('user', {}).get('data', {}).get(MARKER) == '1',
                    ssid=bytes(wifi.get('ssid', [])).decode('utf-8', 'replace'))
        return base

    def status(self):
        status = super().status()
        manager = self.props(ROOT, NM)
        status.update(wifiEnabled=manager.get('WirelessEnabled', False),
                      hardwareEnabled=manager.get('WirelessHardwareEnabled', False),
                      sharingAvailable=bool(shutil.which('dnsmasq') and shutil.which('nft')))
        return status

    def stop(self, request):
        row = self.target(request)
        if not row['hotspot'] or not row['owned']:
            raise ValueError('That Blankweave hotspot is no longer active.')
        self.call(ROOT, NM, 'DeactivateConnection', GLib.Variant('(o)', (row['activePath'],)))
        self.wait(row['path'], lambda item: item['activePath'] != row['activePath'])

    def start(self, request):
        ssid, password = request.get('ssid'), request.get('password')
        if not isinstance(ssid, str) or not ssid.strip() or not 1 <= len(ssid.encode('utf-8')) <= 32 or any(ord(c) < 32 or ord(c) == 127 for c in ssid):
            raise ValueError('Use a hotspot name of 1–32 UTF-8 bytes, without control characters.')
        if not isinstance(password, str) or not 8 <= len(password) <= 63 or any(ord(c) < 32 or ord(c) > 126 for c in password):
            raise ValueError('Use a password of 8–63 printable ASCII characters.')
        row = self.target(request)
        manager = self.props(ROOT, NM)
        if not manager.get('WirelessEnabled') or not manager.get('WirelessHardwareEnabled'):
            raise ValueError('Turn on Wi-Fi and release any hardware radio switch first.')
        if not row['apCapable'] or row['hotspot'] or row['state'] not in (30, 100, 120):
            raise ValueError('This adapter is unavailable or does not support a WPA2 hotspot.')
        if not shutil.which('dnsmasq') or not shutil.which('nft'):
            raise ValueError('Hotspot sharing requires dnsmasq and nftables. Install the required packages first.')
        if row['activePath'] != '/' and request.get('replace') is not True:
            raise ValueError('Confirm disconnecting this adapter’s current Wi-Fi connection first.')
        identity = str(uuid.uuid4())
        settings = {
            'connection': {'type': GLib.Variant('s', '802-11-wireless'), 'uuid': GLib.Variant('s', identity),
                           'id': GLib.Variant('s', 'Blankweave Hotspot'), 'autoconnect': GLib.Variant('b', False)},
            '802-11-wireless': {'mode': GLib.Variant('s', 'ap'), 'ssid': GLib.Variant('ay', ssid.encode('utf-8'))},
            '802-11-wireless-security': {'key-mgmt': GLib.Variant('s', 'wpa-psk'), 'proto': GLib.Variant('as', ['rsn']),
                                        'pairwise': GLib.Variant('as', ['ccmp']), 'group': GLib.Variant('as', ['ccmp']),
                                        'psk': GLib.Variant('s', password)},
            'ipv4': {'method': GLib.Variant('s', 'shared')},
            'ipv6': {'method': GLib.Variant('s', 'disabled')},
            'user': {'data': GLib.Variant('a{ss}', {MARKER: '1'})}}
        self.target(request)
        profile, activation, _ = self.call(ROOT, NM, 'AddAndActivateConnection2',
            GLib.Variant('(a{sa{sv}}ooa{sv})', (settings, row['path'], '/', {'persist': GLib.Variant('s', 'volatile')}))).unpack()
        try:
            self.wait(row['path'], lambda current: current['connected'] and current['uuid'] == identity and current['hotspot'])
        except (GLib.Error, ValueError):
            # Only touch the activation/profile created by this request, never the former Wi-Fi profile.
            try:
                self.call(ROOT, NM, 'DeactivateConnection', GLib.Variant('(o)', (activation,)))
            except GLib.Error:
                pass
            try:
                self.call(profile, network.CONNECTION, 'Delete')
            except GLib.Error:
                pass
            raise ValueError('The hotspot could not be confirmed. Refresh to check its state, then reconnect Wi-Fi if needed.') from None


def status():
    result = {'airplane': None, 'radioError': '', 'network': None, 'networkError': ''}
    try:
        result['airplane'] = Airplane().status()
    except (OSError, ValueError, KeyError, subprocess.SubprocessError):
        result['radioError'] = 'Wireless radio state is unavailable.'
    try:
        result['network'] = Hotspots().status()
    except (GLib.Error, OSError, ValueError, KeyError, subprocess.SubprocessError):
        result['networkError'] = 'NetworkManager hotspot controls are unavailable.'
    return result


def main():
    try:
        if sys.argv[1:] == ['status']:
            print(json.dumps(status()))
        elif sys.argv[1:] == ['apply']:
            request = json.loads(sys.stdin.read(8192))
            if not isinstance(request, dict):
                raise ValueError('Invalid wireless request.')
            if request.get('action') == 'airplane':
                Airplane().apply(request.get('enabled'))
            elif request.get('action') == 'start':
                if Airplane().status()['requested']:
                    raise ValueError('Turn off airplane mode before starting a hotspot.')
                Hotspots().start(request)
            elif request.get('action') == 'stop':
                Hotspots().stop(request)
            else:
                raise ValueError('Unknown wireless action.')
        else:
            raise ValueError('Usage: wireless-controls.py status | apply (JSON on stdin)')
    except (GLib.Error, OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(str(error) if isinstance(error, ValueError) else 'Wireless request failed. Refresh to check the current state and retry.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
