"""Persisted, opt-in profile changes on power-source transitions."""
from contextlib import contextmanager
import fcntl
import json
import math
import os
from pathlib import Path
import tempfile

from gi.repository import Gio, GLib

DEFAULTS = {'version': 1, 'enabled': False, 'ac': 'balanced', 'battery': 'balanced',
            'low': 'power-saver', 'threshold': 15}
MODES = ('power-saver', 'balanced', 'performance')
UPOWER = 'org.freedesktop.UPower'
ROOT = '/org/freedesktop/UPower'


def validate(value):
    if (not isinstance(value, dict) or set(value) != set(DEFAULTS)
            or type(value['version']) is not int or value['version'] != 1
            or type(value['enabled']) is not bool
            or any(value[key] not in MODES for key in ('ac', 'battery', 'low'))
            or type(value['threshold']) is not int or not 5 <= value['threshold'] <= 50):
        raise ValueError('Invalid automatic power preferences. Check power-profiles.json.')
    return value


def read(path, default):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return default


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, prefix='.power-', delete=False) as stream:
        temporary = Path(stream.name)
        try:
            json.dump(value, stream)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)


def source(power):
    owner = power.owner(UPOWER)
    if not owner:
        return {'available': False, 'owner': '', 'onBattery': False, 'percentage': 0}

    def props(path, interface):
        return power.bus.call_sync(owner, path, 'org.freedesktop.DBus.Properties', 'GetAll',
                                   GLib.Variant('(s)', (interface,)), None,
                                   Gio.DBusCallFlags.NO_AUTO_START, 5000, None).unpack()[0]

    root = props(ROOT, UPOWER)
    device = props(ROOT + '/devices/DisplayDevice', UPOWER + '.Device')
    if power.owner(UPOWER) != owner:
        raise ValueError('The battery service restarted. Automatic switching will retry.')
    on_battery, percentage = root.get('OnBattery'), device.get('Percentage')
    if (type(on_battery) is not bool or type(percentage) not in (int, float)
            or not math.isfinite(percentage) or not 0 <= percentage <= 100):
        raise ValueError('Battery status is unknown. Automatic switching is paused.')
    # OnBattery is a convenience flag, not positive evidence of AC: UPower
    # also clears it when a battery becomes empty. Keep battery states on the
    # battery policy, and require a charging/full state before inferring AC.
    state = device.get('State')
    if state in (2, 3, 6):  # Discharging, empty, pending discharge.
        on_battery = True
    elif not on_battery and state not in (1, 4, 5):
        raise ValueError('Battery power source is unknown. Automatic switching is paused.')
    return {'available': device.get('Type') == 2 and device.get('IsPresent') is True,
            'owner': owner, 'onBattery': on_battery, 'percentage': percentage}


def condition(settings, supply, previous):
    if not supply['available']:
        raise ValueError('Automatic profiles need a supported battery and a running UPower service.')
    if not supply['onBattery']:
        return 'ac'
    # Leave the low-battery state only after a five percentage-point recovery.
    low = (previous.get('settings') == settings and previous.get('sourceOwner') == supply['owner']
           and previous.get('condition') == 'low')
    if supply['percentage'] <= settings['threshold'] or (low and supply['percentage'] < settings['threshold'] + 5):
        return 'low'
    return 'battery'


class Policy:
    def __init__(self):
        self.boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
        self.config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'blankweave/power-profiles.json'
        directory = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'blankweave'
        self.state = directory / 'power-profiles-auto.json'
        self.lock = directory / 'power-profiles.lock'

    def settings(self):
        return validate(read(self.config, dict(DEFAULTS)))

    def previous(self):
        value = read(self.state, {})
        if not isinstance(value, dict) or (value and (value.get('version') != 1
                      or any(not isinstance(value.get(k), str) for k in ('boot', 'owner', 'sourceOwner', 'condition', 'profile'))
                      or value['condition'] not in ('ac', 'battery', 'low'))):
            raise ValueError('Saved automatic power state is invalid. Check power-profiles-auto.json.')
        if value:
            validate(value.get('settings'))
        return value

    @contextmanager
    def locked(self):
        self.lock.parent.mkdir(parents=True, exist_ok=True)
        with self.lock.open('a') as stream:
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise ValueError('Another power change is in progress. Try again.') from error
            yield

    def status(self, power, current):
        result = {'ready': False, 'settings': dict(DEFAULTS), 'source': {'available': False}, 'message': ''}
        try:
            settings = self.settings()
            result.update(ready=True, settings=settings)
            supply = source(power)
            result['source'] = supply
            if not settings['enabled']:
                result['message'] = 'Automatic switching is off.'
            elif not current['available']:
                result['message'] = 'Waiting for the power profile service.'
            else:
                previous = self.previous()
                mode = condition(settings, supply, previous)
                if current['holds']:
                    result['message'] = 'Waiting for application profile holds to finish.'
                elif settings[mode] not in [row['id'] for row in current['profiles']]:
                    result['message'] = 'The profile saved for this power state is unavailable. Choose another profile.'
                elif self.matches(previous, settings, supply, current, mode):
                    result['message'] = ('Automatic profile applied.' if current['profile'] == previous['profile']
                                         else 'Profile changed elsewhere; keeping it until the next power-state change.')
                else:
                    result['message'] = 'Waiting to apply the profile for this power state.'
        except (OSError, ValueError, GLib.Error) as error:
            result['message'] = str(error) if not isinstance(error, GLib.Error) else 'Battery status is unavailable. Automatic switching is paused.'
        return result

    def matches(self, previous, settings, supply, current, mode):
        return (previous.get('boot') == self.boot and previous.get('settings') == settings and previous.get('owner') == current['owner']
                and previous.get('sourceOwner') == supply['owner'] and previous.get('condition') == mode)

    def configure(self, power, request):
        if not isinstance(request, dict) or set(request) != {'expected', 'settings'}:
            raise ValueError('Invalid automatic power request.')
        new = validate(request['settings'])
        with self.locked():
            if self.settings() != request['expected']:
                raise ValueError('Automatic preferences changed elsewhere. Refresh and try again.')
            if new['enabled']:
                current = power.status()
                if not current['available'] or any(new[key] not in [row['id'] for row in current['profiles']] for key in ('ac', 'battery', 'low')):
                    raise ValueError('One of the selected power profiles is unavailable. Choose supported profiles before enabling.')
                condition(new, source(power), {})
            save(self.config, new)
            # Reset only on a successful explicit settings change. A failure here
            # is reported; the already saved settings remain the source of truth.
            self.state.unlink(missing_ok=True)

    def manual(self, power, service, owner, profile):
        with self.locked():
            settings = self.settings()
            if settings['enabled']:
                # Disable durably before writing, so an in-flight or later tick
                # cannot undo an explicit manual choice (even if its write fails).
                save(self.config, {**settings, 'enabled': False})
            power.apply(service, owner, profile)

    def tick(self, power):
        with self.locked():
            settings = self.settings()
            if not settings['enabled']:
                return
            current = power.status()
            if not current['available']:
                raise ValueError('Waiting for the power profile service.')
            supply = source(power)
            previous = self.previous()
            mode = condition(settings, supply, previous)
            if self.matches(previous, settings, supply, current, mode) or current['holds']:
                return
            target = settings[mode]

            def guard(latest):
                if latest['holds']:
                    raise ValueError('Waiting for application profile holds to finish.')
                check = source(power)
                if check['owner'] != supply['owner'] or condition(settings, check, previous) != mode:
                    raise ValueError('The power source changed during the request. Automatic switching will retry.')

            power.apply(current['service'], current['owner'], target, guard=guard)
            save(self.state, {'version': 1, 'boot': self.boot, 'settings': settings, 'owner': current['owner'],
                              'sourceOwner': supply['owner'], 'condition': mode, 'profile': target})
