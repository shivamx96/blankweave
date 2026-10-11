#!/usr/bin/env python3
"""Per-system-battery health and UPower's configured charging-limit switch."""
import hashlib
import json
import math
import sys

from gi.repository import Gio, GLib

SERVICE = 'org.freedesktop.UPower'
ROOT = '/org/freedesktop/UPower'
DEVICE = SERVICE + '.Device'
STATES = {0: 'Unknown', 1: 'Charging', 2: 'Discharging', 3: 'Empty', 4: 'Fully charged',
          5: 'Waiting to charge', 6: 'Waiting to discharge'}


def number(value, minimum=0, maximum=None):
    if (type(value) not in (int, float) or not math.isfinite(value) or value < minimum
            or (maximum is not None and value > maximum)):
        return None
    return value


def positive(value):
    result = number(value)
    return result if result is not None and result > 0 else None


def identity(data):
    # Recheck hardware identity without putting battery serial numbers in the UI,
    # process arguments, or diagnostic output.
    fields = [str(data.get(key, '')) for key in ('NativePath', 'Vendor', 'Model', 'Serial')]
    return hashlib.sha256(json.dumps(fields).encode()).hexdigest()


class Batteries:
    def __init__(self, bus=None):
        self.bus = bus if bus is not None else Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        self.owner = self.get_owner()

    def get_owner(self):
        try:
            return self.bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus',
                                      'GetNameOwner', GLib.Variant('(s)', (SERVICE,)), None,
                                      Gio.DBusCallFlags.NO_AUTO_START, 5000, None).unpack()[0]
        except GLib.Error as error:
            if Gio.DBusError.get_remote_error(error) == 'org.freedesktop.DBus.Error.NameHasNoOwner':
                return ''
            raise

    def call(self, path, interface, method, parameters=None):
        return self.bus.call_sync(self.owner, path, interface, method, parameters, None,
                                  Gio.DBusCallFlags.NO_AUTO_START, 10000, None)

    def paths(self):
        return self.call(ROOT, SERVICE, 'EnumerateDevices').unpack()[0]

    def row(self, path):
        if path == ROOT + '/devices/DisplayDevice':
            return None
        data = self.call(path, 'org.freedesktop.DBus.Properties', 'GetAll', GLib.Variant('(s)', (DEVICE,))).unpack()[0]
        if data.get('Type') != 2 or data.get('PowerSupply') is not True or data.get('IsPresent') is not True:
            return None
        supported = data.get('ChargeThresholdSupported') is True and type(data.get('ChargeThresholdEnabled')) is bool
        enabled = data.get('ChargeThresholdEnabled') if supported else None
        flags = data.get('ChargeThresholdSettingsSupported')
        start = number(data.get('ChargeStartThreshold'), 0, 100)
        end = number(data.get('ChargeEndThreshold'), 0, 100)
        if type(flags) is int:
            start = start if flags & 1 else None
            end = end if flags & 2 else None
        else:
            # Older UPower versions lack the capability bitmask. Zero and the
            # unsigned sentinel must not be advertised as usable preset limits.
            start = start if start else None
            end = end if end else None
        cycles = data.get('ChargeCycles')
        health = number(data.get('Capacity'), 0, 100)
        return {'path': path, 'owner': self.owner, 'identity': identity(data),
                'name': str(data.get('Model') or 'System battery'), 'vendor': str(data.get('Vendor') or ''),
                'charge': number(data.get('Percentage'), 0, 100), 'health': health if health else None,
                'energyFull': positive(data.get('EnergyFull')), 'energyDesign': positive(data.get('EnergyFullDesign')),
                'cycles': cycles if type(cycles) is int and cycles >= 0 else None,
                'state': STATES.get(data.get('State'), 'Unknown'),
                'supported': supported, 'enabled': enabled, 'start': start, 'end': end,
                'firmware': type(flags) is int and bool(flags & 4)}

    def status(self):
        if not self.owner:
            return {'available': False, 'batteries': []}
        rows = []
        for path in self.paths():
            try:
                row = self.row(path)
            except GLib.Error as error:
                if Gio.DBusError.get_remote_error(error) in ('org.freedesktop.DBus.Error.UnknownObject', 'org.freedesktop.DBus.Error.UnknownInterface'):
                    continue  # A battery disappeared while enumerating.
                raise
            if row is not None:
                rows.append(row)
        if self.get_owner() != self.owner:
            raise ValueError('The battery service restarted. Refresh and try again.')
        return {'available': True, 'batteries': rows}

    def apply(self, request):
        if (not isinstance(request, dict) or set(request) != {'owner', 'path', 'identity', 'enabled'}
                or any(not isinstance(request[key], str) for key in ('owner', 'path', 'identity'))
                or type(request['enabled']) is not bool):
            raise ValueError('Invalid battery charge-limit request.')
        if not self.owner or self.owner != request['owner'] or self.get_owner() != self.owner:
            raise ValueError('The battery service changed. Refresh and choose the battery again.')
        if request['path'] not in self.paths():
            raise ValueError('That battery is no longer connected.')
        current = self.row(request['path'])
        if current is None or current['identity'] != request['identity']:
            raise ValueError('That battery changed. Refresh and choose it again.')
        if not current['supported']:
            raise ValueError('This battery does not expose a supported charge-limit control.')
        if current['enabled'] == request['enabled']:
            return
        if self.get_owner() != self.owner:
            raise ValueError('The battery service changed. Refresh and try again.')
        self.call(request['path'], DEVICE, 'EnableChargeThreshold', GLib.Variant('(b)', (request['enabled'],)))
        if self.get_owner() != self.owner or request['path'] not in self.paths():
            raise ValueError('The battery disappeared or the service restarted before the change could be verified.')
        result = self.row(request['path'])
        if result is None or result['identity'] != request['identity'] or result['enabled'] != request['enabled']:
            raise ValueError('The charge-limit change could not be verified. Refresh to check the current state.')


def main():
    if sys.argv[1:] == ['status']:
        print(json.dumps(Batteries().status(), allow_nan=False))
    elif sys.argv[1:] == ['set']:
        Batteries().apply(json.load(sys.stdin))
    else:
        raise ValueError('Usage: battery-health.py status | set (JSON on stdin)')


if __name__ == '__main__':
    try:
        main()
    except GLib.Error as error:
        remote = Gio.DBusError.get_remote_error(error) or ''
        if any(word in remote for word in ('AccessDenied', 'NotAuthorized', 'Auth')):
            print('Permission to change the charge limit was denied. Check your session permissions and try again.', file=sys.stderr)
        else:
            print('Could not read or change battery settings. Refresh and try again.', file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
