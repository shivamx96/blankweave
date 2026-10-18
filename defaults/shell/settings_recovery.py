"""Expose real recovery capabilities without assuming a boot/storage layout."""
from pathlib import Path
import re
import os
from settings_support import atomic, config_home, read
from settings_operations import missing, notice, action, choice, field, installed, privileged, run, select, state


def can_hibernate():
    import gi
    from gi.repository import Gio
    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    return bus.call_sync('org.freedesktop.login1', '/org/freedesktop/login1', 'org.freedesktop.login1.Manager',
                         'CanHibernate', None, None, Gio.DBusCallFlags.NONE, 5000, None).unpack()[0]


def status(domain):
    if domain == 'snapshots':
        if not installed('snapper'): return state('File backups are independent of system snapshots.', notices=[missing('snapper')])
        filesystem = run(['findmnt', '-n', '-o', 'FSTYPE', '/'])
        configured = Path('/etc/snapper/configs/root').exists()
        actions = []
        if configured:
            actions = [action('list', 'List system snapshots'), action('create', 'Create system snapshot'),
                       action('delete', 'Delete system snapshot', [field('number', 'Snapshot number')], 'Permanently delete the selected snapshot? Keep snapshots needed by your recovery plan.'),
                       action('schedule', 'Set snapshot schedule', [field('enabled', 'Hourly snapshots', 'no', [choice('yes'), choice('no')], input_type='toggle')], 'Enable or disable root timeline snapshots. Snapper’s configured retention limits apply.')]
        elif filesystem == 'btrfs' and not Path('/.snapshots').exists():
            actions = [action('setup', 'Set up root snapshots', confirm='Create a Snapper root configuration on this Btrfs filesystem. Existing nested subvolumes are excluded from root snapshots. This does not add a boot-menu recovery entry.')]
        notices = []
        if not configured:
            if filesystem != 'btrfs': notices.append(notice('unsupported', 'System snapshots are unavailable on ' + filesystem, 'Automatic snapshot setup requires a Btrfs root filesystem. Use file backups on this computer; Settings will not reformat your disk.', 'backup'))
            elif Path('/.snapshots').exists(): notices.append(notice('not-configured', 'An existing snapshots folder needs review', 'Review the existing /.snapshots folder and configure Snapper manually before using these controls. Settings will not replace it.'))
            else: notices.append(notice('not-configured', 'System snapshots are not set up', 'Choose Set up root snapshots to configure Snapper. Verify a rescue environment before relying on system recovery.'))
        return state('System recovery requires a separately verified rescue/boot environment. Settings never rolls back a running root filesystem. Blankweave updates reuse the root Snapper configuration for paired snapshots.',
                     ['Root filesystem: ' + filesystem, 'Root Snapper configuration: ' + ('present' if configured else 'not configured')], actions, [filesystem, configured], notices)
    support = can_hibernate()
    modes = (read(Path('/sys/power/state')) or '').strip()
    resume = (read(Path('/sys/power/resume')) or 'unknown').strip()
    swaps = (read(Path('/proc/swaps')) or '').splitlines()
    disk_swaps = [line.split()[0] for line in swaps[1:] if not line.startswith('/dev/zram')]
    policy = read(Path('/etc/systemd/sleep.conf.d/60-blankweave.conf'))
    idle = read(config_home() / 'blankweave/idle-hibernate') == 'yes\n'
    actions = [action('policy', 'Set hibernation policy', [field('enabled', 'Permit hibernation', 'no' if policy and 'AllowHibernation=no' in policy else 'yes', [choice('yes'), choice('no')], input_type='toggle')], 'Changing policy does not create swap or configure boot-time resume. Recheck readiness afterward.')]
    actions.append(action('idle', 'Choose idle sleep mode', [field('enabled', 'Idle sleep', 'yes' if idle else 'no', [choice('no', 'Suspend'), choice('yes', 'Hibernate when supported')])], 'Managed idle sleep will use hibernation when logind supports it, falling back to suspend otherwise. Existing lock-before-sleep protection remains active.'))
    candidates = []
    for device in disk_swaps:
        if device.startswith('/dev/mapper/'): candidates.append(device)
        elif device.startswith('/dev/dm-'):
            name = read(Path('/sys/class/block') / Path(device).name / 'dm/name')
            if name and re.fullmatch(r'[A-Za-z0-9_-]+', name.strip()): candidates.append('/dev/mapper/' + name.strip())
    if support in ('yes', 'challenge') and disk_swaps and 'disk' in modes.split():
        actions.append(action('hibernate', 'Hibernate now', confirm='Save the running session to disk and power down. Use this to test resume only after boot configuration is ready.'))
    if candidates:
        actions.append(action('prepare', 'Prepare encrypted swap resume', [field('device', 'Existing encrypted swap', candidates[0], [choice(d) for d in candidates])], 'Configure resume for existing encrypted swap, rebuild initramfs images, and refresh Limine. Requires systemd/sd-encrypt hooks, passphrase-unlocked persistent swap, and regular non-UKI BLS entries. Unsupported layouts are rejected before changes. Reboot afterward.'))
    if Path('/var/lib/blankweave/hibernate-settings.json').exists():
        actions.append(action('revert', 'Revert resume preparation', confirm='Restore the command lines saved before Settings prepared resume, then rebuild boot files. Later boot-file changes block automatic revert.'))
    notices = []
    if not disk_swaps: notices.append(notice('not-configured', 'Hibernation needs disk-backed swap', 'RAM-backed zram cannot preserve a session after power-off. Configure suitable disk-backed swap and boot-time resume before using hibernation; Suspend remains available.'))
    elif 'disk' not in modes.split(): notices.append(notice('unsupported', 'The kernel does not offer hibernation', 'Use Suspend, or configure a kernel with hibernation support before checking readiness again.'))
    elif support not in ('yes', 'challenge'): notices.append(notice('not-configured', 'Hibernation is not ready', 'Review the hibernation policy, swap, and boot-time resume configuration below, then refresh. Enabling the policy alone does not configure resume.'))
    return state('Hibernation needs disk-backed swap, compatible encryption, and verified initramfs/boot resume configuration. Setup supports an existing encrypted swap partition; it does not repartition disks or create swap files. Enabling policy alone does not establish resume readiness.',
                 ['logind support: ' + support, 'Kernel sleep modes: ' + modes, 'Kernel resume device: ' + resume,
                  'Disk-backed swap: ' + (', '.join(disk_swaps) or 'none'),
                  'A successful real-machine hibernate/resume test is required before relying on this feature.'], actions, [support, resume, disk_swaps, policy, idle], notices)


def apply(domain, request):
    command = request['action']
    if domain == 'hibernate':
        if command == 'idle':
            value = select(request, 'enabled', ['yes', 'no'])
            if value == 'yes' and can_hibernate() not in ('yes', 'challenge'): raise ValueError('Verify hibernation readiness before enabling it for idle sleep.')
            atomic(config_home() / 'blankweave/idle-hibernate', value + '\n')
            return 'Idle sleep preference saved. The managed idle supervisor will reload it.'
        if command == 'hibernate':
            if can_hibernate() not in ('yes', 'challenge'): raise ValueError('Hibernation is no longer available.')
            run(['loginctl', 'lock-session'])
            return run(['systemctl', 'hibernate'], timeout=120)
        if command == 'prepare':
            from settings_operations import require
            return privileged('hibernate-prepare', device=require(request, 'device', r'/dev/mapper/[A-Za-z0-9_-]+'))
        if command == 'revert': return privileged('hibernate-revert')
        if command == 'policy': return privileged('hibernate-policy', enabled=select(request, 'enabled', ['yes', 'no']))
    elif domain == 'snapshots':
        if command in ('list', 'create', 'setup'): return privileged('snapshot-' + command)
        if command == 'schedule': return privileged('snapshot-schedule', enabled=select(request, 'enabled', ['yes', 'no']))
        if command == 'delete':
            from settings_operations import require
            number = require(request, 'number', r'[1-9][0-9]{0,9}')
            latest = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'blankweave/recovery/latest'
            if 'snapper_pre=' + number in (read(latest) or '').splitlines():
                raise ValueError('This snapshot is the recorded Blankweave recovery point. Keep it until a later successful update replaces it.')
            return privileged('snapshot-delete', number=number)
    raise ValueError('Unknown recovery operation.')


if __name__ == '__main__':
    import sys
    try:
        if sys.argv[1:] != ['idle']: raise ValueError('Usage: settings_recovery.py idle')
        preferred = read(config_home() / 'blankweave/idle-hibernate') == 'yes\n'
        try: supported = can_hibernate() in ('yes', 'challenge')
        except Exception: supported = False
        run(['systemctl', 'hibernate' if preferred and supported else 'suspend'], timeout=120)
    except Exception as error:
        print(str(error), file=sys.stderr); sys.exit(1)
