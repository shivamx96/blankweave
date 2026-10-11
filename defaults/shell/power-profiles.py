#!/usr/bin/env python3
"""Read and explicitly select system power profiles without starting a daemon."""
import json
import sys

from gi.repository import Gio, GLib

ENDPOINTS = {
    'org.freedesktop.UPower.PowerProfiles': '/org/freedesktop/UPower/PowerProfiles',
    'net.hadess.PowerProfiles': '/net/hadess/PowerProfiles',
}
LABELS = {'power-saver': 'Power saver', 'balanced': 'Balanced', 'performance': 'Performance'}


class Power:
    def __init__(self, bus=None):
        self.bus = bus if bus is not None else Gio.bus_get_sync(Gio.BusType.SYSTEM, None)

    def owner(self, service):
        try:
            return self.bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus',
                                      'org.freedesktop.DBus', 'GetNameOwner', GLib.Variant('(s)', (service,)),
                                      None, Gio.DBusCallFlags.NO_AUTO_START, 5000, None).unpack()[0]
        except GLib.Error as error:
            if Gio.DBusError.get_remote_error(error) == 'org.freedesktop.DBus.Error.NameHasNoOwner':
                return ''
            raise

    def props(self, service, owner):
        return self.bus.call_sync(owner, ENDPOINTS[service], 'org.freedesktop.DBus.Properties',
                                  'GetAll', GLib.Variant('(s)', (service,)), None,
                                  Gio.DBusCallFlags.NO_AUTO_START, 5000, None).unpack()[0]

    def snapshot(self, service, owner):
        data = self.props(service, owner)
        profiles = data.get('Profiles')
        active = data.get('ActiveProfile')
        degraded = data.get('PerformanceDegraded', '')
        holds = data.get('ActiveProfileHolds', [])
        if (not isinstance(profiles, list) or not isinstance(active, str) or not active
                or not isinstance(degraded, str) or not isinstance(holds, list)
                or any(not isinstance(row, dict) or not isinstance(row.get('Profile'), str) for row in profiles)
                or any(not isinstance(row, dict) or any(not isinstance(row.get(key), str)
                       for key in ('ApplicationId', 'Profile', 'Reason')) for row in holds)):
            raise ValueError('The power service returned invalid profile information.')
        ids = {row['Profile'] for row in profiles}
        return {'available': True, 'service': service, 'owner': owner, 'profile': active,
                'profiles': [{'id': key, 'name': name} for key, name in LABELS.items() if key in ids],
                'degraded': degraded, 'holds': [{'application': row['ApplicationId'], 'profile': row['Profile'],
                                               'reason': row['Reason']} for row in holds]}

    def status(self):
        for service in ENDPOINTS:
            owner = self.owner(service)
            if owner:
                result = self.snapshot(service, owner)
                if self.owner(service) != owner:
                    raise ValueError('The power service restarted. Refresh and try again.')
                return result
        return {'available': False, 'service': '', 'owner': '', 'profile': '',
                'profiles': [], 'degraded': '', 'holds': []}

    def apply(self, service, owner, profile, guard=None):
        if service not in ENDPOINTS or profile not in LABELS or not owner.startswith(':'):
            raise ValueError('Invalid power profile request.')
        if self.owner(service) != owner:
            raise ValueError('The power service changed. Refresh and choose a profile again.')
        current = self.snapshot(service, owner)
        if profile not in [row['id'] for row in current['profiles']]:
            raise ValueError('That power profile is no longer available. Refresh and choose another.')
        if guard is not None:
            guard(current)
        # A no-op must not cancel an application's profile hold.
        if current['profile'] == profile:
            return
        if self.owner(service) != owner:
            raise ValueError('The power service changed. Refresh and choose a profile again.')
        self.bus.call_sync(owner, ENDPOINTS[service], 'org.freedesktop.DBus.Properties', 'Set',
                           GLib.Variant('(ssv)', (service, 'ActiveProfile', GLib.Variant('s', profile))),
                           None, Gio.DBusCallFlags.NO_AUTO_START, 10000, None)
        if self.owner(service) != owner:
            raise ValueError('The power service restarted before the change could be verified. Refresh and try again.')
        if self.snapshot(service, owner)['profile'] != profile:
            raise ValueError('The requested power profile did not stay active. Another application or the system may have changed it.')


def main():
    from power_policy import Policy
    arguments = sys.argv[1:]
    policy = Policy()
    if arguments == ['status']:
        power = Power()
        current = power.status()
        current['automatic'] = policy.status(power, current)
        print(json.dumps(current))
    elif len(arguments) == 4 and arguments[0] == 'set':
        policy.manual(Power(), *arguments[1:])
    elif arguments == ['auto-tick']:
        policy.tick(Power())
    elif arguments == ['auto-configure']:
        policy.configure(Power(), json.load(sys.stdin))
    else:
        raise ValueError('Usage: power-profiles.py status | set <service> <owner> <profile> | auto-tick | auto-configure (JSON on stdin)')


if __name__ == '__main__':
    try:
        main()
    except GLib.Error as error:
        remote = Gio.DBusError.get_remote_error(error) or ''
        if 'AccessDenied' in remote or 'NotAuthorized' in remote or 'Auth' in remote:
            print('Permission to change the power profile was denied. Check your session permissions and try again.', file=sys.stderr)
        else:
            print('Could not contact the power profile service. Refresh and try again.', file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
