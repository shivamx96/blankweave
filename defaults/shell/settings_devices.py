"""Date/time, printing/scanning and firmware providers."""
import datetime
import json
from pathlib import Path
import re
import subprocess
from settings_operations import action, choice, field, installed, path_value, privileged, require, run, select, state


def properties(command):
    return dict(line.split('=', 1) for line in run(command).splitlines() if '=' in line)


def printers():
    return [line.split()[1] for line in run(['lpstat', '-p'], codes=(0, 1)).splitlines() if line.startswith('printer ')]


def devices():
    return json.loads(run(['fwupdmgr', 'get-devices', '--json'], codes=(0, 2))).get('Devices', [])


def status(domain):
    if domain == 'datetime':
        if not installed('timedatectl', 'localectl'): return state('Install systemd tools to configure date and region.')
        props = properties(['timedatectl', 'show'])
        zones = run(['timedatectl', 'list-timezones']).splitlines()
        zone = props.get('Timezone', '')
        locale = run(['localectl', 'status'])
        return state('Time and region changes apply system-wide. Applications may need to restart after a region change.',
                     [f'Timezone: {zone}', f'Network time: {props.get("NTP", "unknown")}', f'Synchronized: {props.get("NTPSynchronized", "unknown")}', locale],
                     [action('timezone', 'Set timezone', [field('zone', 'Timezone', zone, [choice(z) for z in zones])]),
                      action('ntp', 'Set clock synchronization', [field('enabled', 'Network time', props.get('NTP', 'yes'), [choice('yes', 'Automatic'), choice('no', 'Manual')])]),
                      action('time', 'Set date and time', [field('time', 'Local date and time (YYYY-MM-DD HH:MM:SS)')], 'Automatic time must be off. Changing time affects running applications.'),
                      action('locale', 'Set system region', [field('locale', 'Generated locale (for example en_US.UTF-8)')], 'Change system-wide date, number, and currency formats. Sign in again to apply.')],
                     [zone, props.get('NTP'), locale])
    if domain == 'printers':
        details, actions, names = [], [], []
        if installed('lpstat', 'lpadmin'):
            names = printers()
            details.append(run(['lpstat', '-t'], codes=(0, 1)) or 'No printers configured.')
            actions.append(action('add', 'Add IPP printer', [field('name', 'Printer name'), field('uri', 'IPP device URI (ipp:// or ipps://)')], 'Add and enable this printer for this computer.'))
            if names:
                target = field('printer', 'Printer', names[0], [choice(n) for n in names])
                actions += [action('default', 'Set default printer', [target]),
                            action('remove', 'Remove printer', [target], 'Remove this printer and its queue?'),
                            action('test', 'Print a test page', [target], 'Send one test page to this printer.')]
            jobs = run(['lpstat', '-o'], codes=(0, 1)).splitlines()
            if jobs:
                ids = [line.split()[0] for line in jobs]
                actions.append(action('cancel', 'Cancel print job', [field('job', 'Job', ids[0], [choice(i) for i in ids])], 'Cancel this print job?'))
        if installed('scanimage'):
            actions += [action('scanners', 'Discover scanners', cancellable=True),
                        action('scan', 'Scan a page', [field('device', 'Scanner device identifier (from discovery)'), field('folder', 'Save folder', str(Path.home() / 'Pictures'))], cancellable=True)]
        return state('Printers use CUPS; scanners use SANE. Install cups and sane for missing functionality. Discovery runs only when requested.', details, actions, names)
    if domain == 'firmware':
        if not installed('fwupdmgr'): return state('Install fwupd to check supported device firmware.')
        rows = devices()
        options = [choice(d['DeviceId'], d.get('Name', d['DeviceId'])) for d in rows if 'DeviceId' in d]
        actions = [action('check', 'Check firmware updates', confirm='Refresh firmware metadata from the configured remotes.')]
        if options: actions.append(action('update', 'Update device firmware', [field('device', 'Device', options[0]['value'], options)], 'Install available firmware for this device. Keep power connected. Flashing cannot be cancelled; a reboot may be required.'))
        return state('Only devices supported by fwupd can be updated. The provider checks device and power requirements before flashing.',
                     [str(d.get('Name', 'Device')) + ': ' + str(d.get('Version', 'Unknown version')) for d in rows], actions,
                     [(d.get('DeviceId'), d.get('Version')) for d in rows])
    raise ValueError('Unknown device provider.')


def apply(domain, request):
    command = request['action']
    if domain == 'datetime':
        if command == 'timezone':
            zone = select(request, 'zone', run(['timedatectl', 'list-timezones']).splitlines())
            run(['timedatectl', 'set-timezone', zone])
        elif command == 'ntp': run(['timedatectl', 'set-ntp', select(request, 'enabled', ['yes', 'no'])])
        elif command == 'time':
            text = require(request, 'time', r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}')
            datetime.datetime.strptime(text, '%Y-%m-%d %H:%M:%S')
            if properties(['timedatectl', 'show']).get('NTP') == 'yes': raise ValueError('Turn automatic time off first.')
            run(['timedatectl', 'set-time', text])
        elif command == 'locale':
            locale = select(request, 'locale', run(['localectl', 'list-locales']).splitlines())
            run(['localectl', 'set-locale', 'LC_TIME=' + locale, 'LC_NUMERIC=' + locale, 'LC_MONETARY=' + locale])
        else: raise ValueError('Unknown date/time operation.')
        return 'Saved. ' + run(['timedatectl', 'status'])
    if domain == 'printers':
        if command == 'scanners': return run(['scanimage', '-L'], timeout=60, codes=(0, 1)) or 'No scanners found.'
        if command == 'scan':
            device = require(request, 'device', maximum=512)
            available = run(['scanimage', '--formatted-device-list=%d%n'], timeout=60).splitlines()
            if device not in available: raise ValueError('Scanner is unavailable. Discover scanners again.')
            folder = path_value(request, 'folder', directory=True)
            target = folder / ('Scan-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f') + '.png')
            try:
                with target.open('xb') as stream:
                    result = subprocess.run(['scanimage', '--device-name', device, '--format=png'], stdout=stream, stderr=subprocess.PIPE, timeout=300)
                if result.returncode: raise ValueError(result.stderr.decode(errors='replace')[:2000])
            except Exception:
                target.unlink(missing_ok=True); raise
            return 'Scan saved to ' + str(target)
        if command == 'add':
            name = require(request, 'name', r'[A-Za-z0-9][A-Za-z0-9_-]{0,63}')
            uri = require(request, 'uri', r'ipps?://[^\s]+')
            from urllib.parse import urlsplit
            if urlsplit(uri).username or urlsplit(uri).password: raise ValueError('Do not include credentials in printer URLs.')
            return privileged('printer-add', name=name, uri=uri)
        if command == 'cancel':
            jobs = [line.split()[0] for line in run(['lpstat', '-o'], codes=(0, 1)).splitlines()]
            return run(['cancel', select(request, 'job', jobs)])
        name = select(request, 'printer', printers())
        if command == 'default': return run(['lpoptions', '-d', name])
        if command == 'remove': return privileged('printer-remove', name=name)
        if command == 'test': return run(['lp', '-d', name], input='Blankweave printer test\n')
    if domain == 'firmware':
        if command == 'check':
            run(['fwupdmgr', 'refresh', '--force'], timeout=180)
            data = json.loads(run(['fwupdmgr', 'get-updates', '--json'], codes=(0, 2)))
            return '\n'.join(d.get('Name', 'Device') + ': ' + ', '.join(r.get('Version', '?') for r in d.get('Releases', [])) for d in data.get('Devices', [])) or 'No firmware updates available.'
        if command == 'update':
            device = select(request, 'device', [d.get('DeviceId') for d in devices()])
            return run(['fwupdmgr', 'update', device, '--assume-yes', '--no-reboot-check'], timeout=7200)
    raise ValueError('Unknown device operation.')
