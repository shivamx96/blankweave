#!/usr/bin/python3 -I
"""Root-owned, allowlisted Settings operations. Never import user code."""
import fcntl
import grp
import json
import os
from pathlib import Path
import pwd
import re
import stat
import subprocess
import sys
import tempfile


def run(args, input=None, codes=(0,), timeout=7200):
    result = subprocess.run(args, input=input, text=True, capture_output=True, timeout=timeout,
                            env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C', 'HOME': '/root'})
    if result.returncode not in codes:
        raise ValueError((result.stderr or result.stdout or 'System operation failed.').strip()[:2000])
    return result.stdout.strip()


def text(data, key, pattern, maximum=4096):
    value = data.get(key)
    if not isinstance(value, str) or len(value) > maximum or not re.fullmatch(pattern, value):
        raise ValueError('Invalid ' + key + '.')
    return value


def exact(data, keys):
    if not isinstance(data, dict) or set(data) != set(keys): raise ValueError('Invalid request fields.')


def atomic(path, content, mode=0o644):
    path = Path(path)
    if path.is_symlink(): raise ValueError('Refusing a symlinked system configuration.')
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(content); stream.flush(); os.fsync(stream.fileno())
        os.chmod(name, mode); os.replace(name, path)
    finally:
        if os.path.exists(name): os.unlink(name)


def local_account(name):
    if name not in {line.split(':')[0] for line in Path('/etc/passwd').read_text().splitlines()}:
        raise ValueError('Only local accounts can be changed.')
    account = pwd.getpwnam(name)
    if not 1000 <= account.pw_uid < 65534: raise ValueError('System accounts cannot be changed here.')
    return account


def protect_administrator(name, caller):
    account = local_account(name)
    if account.pw_uid == caller: raise ValueError('The current account cannot be removed or demoted.')
    administrators = set(grp.getgrnam('wheel').gr_mem)
    shadow = {parts[0]: parts[1] for line in Path('/etc/shadow').read_text().splitlines() if len(parts := line.split(':')) > 1}
    usable = [n for n in administrators - {name} if shadow.get(n) and not shadow[n].startswith(('!', '*'))]
    if name in administrators and not usable: raise ValueError('Keep at least one usable administrator account.')


HIBERNATE_RECORD = Path('/var/lib/blankweave/hibernate-settings.json')


def resume_options(content, token, bls=False):
    lines = content.splitlines()
    indexes = [i for i, line in enumerate(lines) if line.startswith('options ')] if bls else [0]
    if len(indexes) != 1 or not lines or (not bls and len(lines) != 1):
        raise ValueError('Expected one literal boot command line.')
    index = indexes[0]
    words = lines[index].split()
    if any(word.startswith('resume_offset=') or (word.startswith('resume=') and word != token) for word in words):
        raise ValueError('A custom resume configuration already exists; review it manually.')
    if token not in words: words.append(token)
    lines[index] = ' '.join(words)
    return '\n'.join(lines) + '\n'


def hibernate_prepare(device):
    if HIBERNATE_RECORD.exists(): raise ValueError('A saved hibernation setup already exists. Revert it before preparing another device.')
    if Path('/var/lib/pacman/db.lck').exists(): raise ValueError('Wait for the package transaction to finish.')
    if not re.fullmatch(r'/dev/mapper/[A-Za-z0-9_-]+', device): raise ValueError('Setup requires an existing encrypted swap mapping.')
    swaps = json.loads(run(['/usr/bin/swapon', '--show', '--json', '--bytes', '--output', 'NAME,TYPE,SIZE']))['swapdevices']
    match = next((item for item in swaps if os.path.realpath(item['name']) == os.path.realpath(device) and item['type'] == 'partition'), None)
    memory = int(re.search(r'^MemTotal:\s+(\d+)', Path('/proc/meminfo').read_text(), re.M).group(1)) * 1024
    if not match or int(match['size']) < memory: raise ValueError('Select active encrypted disk swap at least as large as installed memory.')
    if run(['/usr/bin/lsblk', '-dn', '-o', 'TYPE', device]) != 'crypt': raise ValueError('The swap mapping is not encrypted.')
    mapping = Path(device).name
    crypttab = Path('/etc/crypttab.initramfs')
    entries = [line.split() for line in crypttab.read_text().splitlines() if line.strip() and not line.lstrip().startswith('#')]
    entry = next((row for row in entries if row[0] == mapping), None)
    if not entry or len(entry) < 3 or not entry[1].startswith('UUID=') or entry[2] not in ('none', '-') or (len(entry) > 3 and any(option in ('swap', 'plain') for option in entry[3].split(','))):
        raise ValueError('Encrypted swap must be persistently unlocked from a UUID entry in crypttab.initramfs, using a passphrase and no swap/plain option.')
    hooks_text = Path('/etc/mkinitcpio.conf').read_text()
    hooks = re.findall(r'^HOOKS=\(([^)]*)\)', hooks_text, re.M)
    if len(hooks) != 1 or not {'systemd', 'sd-encrypt'}.issubset(set(hooks[0].split())):
        raise ValueError('Automatic preparation requires literal systemd and sd-encrypt initramfs hooks.')
    identifier = run(['/usr/bin/blkid', '-s', 'UUID', '-o', 'value', device])
    if not re.fullmatch(r'[A-Fa-f0-9-]+', identifier): raise ValueError('Swap has no stable UUID.')
    esp = Path(run(['/usr/bin/bootctl', '--print-esp-path']))
    if not esp.is_absolute() or esp.is_symlink(): raise ValueError('Unsupported EFI System Partition path.')
    entries = sorted((esp / 'loader/entries').glob('*.conf'))
    if not entries: raise ValueError('No Boot Loader Specification entries found for the existing Limine setup.')
    paths = [Path('/etc/kernel/cmdline'), *entries]
    records = []
    token = 'resume=UUID=' + identifier
    for path in paths:
        if path.is_symlink() or not path.is_file(): raise ValueError('Boot configuration must consist of regular files.')
        old = path.read_text()
        if path in entries and not re.search(r'^linux\s+', old, re.M): raise ValueError('Only non-UKI Linux BLS entries are supported.')
        records.append(dict(path=str(path), before=old, after=resume_options(old, token, path in entries)))
    # Save recovery material before the first boot-file mutation.
    atomic(HIBERNATE_RECORD, json.dumps({'device': device, 'files': records, 'phase': 'preparing'}), mode=0o600)
    try:
        for item in records: atomic(item['path'], item['after'])
        run(['/usr/bin/mkinitcpio', '-P'])
        run(['/usr/local/lib/blankweave/configure-limine'])
        atomic(HIBERNATE_RECORD, json.dumps({'device': device, 'files': records, 'phase': 'prepared'}), mode=0o600)
    except Exception:
        for item in records: atomic(item['path'], item['before'])
        # Keep the record if restoring the generated boot artifacts also fails.
        try:
            run(['/usr/bin/mkinitcpio', '-P'])
            run(['/usr/local/lib/blankweave/configure-limine'])
        except Exception: raise ValueError('Preparation failed; original command lines were restored, but rebuilding recovery boot files failed. Review the saved hibernation record before rebooting.') from None
        HIBERNATE_RECORD.unlink()
        raise
    return 'Encrypted swap resume configuration prepared. Reboot, recheck readiness, and test resume before relying on hibernation.'


def hibernate_revert():
    data = json.loads(HIBERNATE_RECORD.read_text())
    for item in data['files']:
        path = Path(item['path'])
        if path.is_symlink() or path.read_text() != item['after']:
            raise ValueError('Boot files changed since setup. Automatic revert would overwrite those edits; review the saved record instead.')
    for item in data['files']: atomic(item['path'], item['before'])
    run(['/usr/bin/mkinitcpio', '-P'])
    run(['/usr/local/lib/blankweave/configure-limine'])
    HIBERNATE_RECORD.unlink()
    return 'Previous resume configuration restored. Reboot to use it.'


def execute(command, data, caller):
    if command == 'package':
        exact(data, ['kind', 'package', 'packages'])
        kind = text(data, 'kind', r'install|remove')
        package = text(data, 'package', r'[a-zA-Z0-9@][a-zA-Z0-9@._+:-]{0,127}')
        if not isinstance(data['packages'], list) or not all(isinstance(p, str) for p in data['packages']): raise ValueError('Invalid transaction.')
        flag = '-Sp' if kind == 'install' else '-Rp'
        proposed = sorted(run(['/usr/bin/pacman', flag, '--print-format', '%n %v', '--', package]).splitlines())
        if proposed != data['packages'] or not proposed: raise ValueError('Package transaction changed. Review it again.')
        if kind == 'remove':
            protected = set(Path('/usr/share/blankweave/settings-protected-packages').read_text().splitlines())
            protected |= {'pacman', 'sudo', 'systemd', 'linux', 'linux-lts', 'glibc', 'bash', 'python'}
            if any(row.split()[0] in protected for row in proposed): raise ValueError('A required desktop/system package cannot be removed from Settings.')
        return run(['/usr/bin/pacman', '-S' if kind == 'install' else '-R', '--noconfirm', '--', package])
    if command.startswith('printer-'):
        exact(data, ['name', 'uri'] if command == 'printer-add' else ['name'])
        name = text(data, 'name', r'[A-Za-z0-9][A-Za-z0-9_-]{0,63}')
        if command == 'printer-add':
            uri = text(data, 'uri', r'ipps?://[^\s\x00]+')
            from urllib.parse import urlsplit
            if urlsplit(uri).username or not urlsplit(uri).hostname: raise ValueError('Invalid printer URI.')
            run(['/usr/bin/systemctl', 'enable', '--now', 'cups.service'])
            return run(['/usr/bin/lpadmin', '-p', name, '-E', '-v', uri, '-m', 'everywhere'])
        if command == 'printer-remove': return run(['/usr/bin/lpadmin', '-x', name])
    if command.startswith('disk-'):
        exact(data, ['device'])
        device = text(data, 'device', r'/dev/[A-Za-z0-9_/-]+')
        resolved = Path(device).resolve(strict=True)
        if not str(resolved).startswith('/dev/') or not stat.S_ISBLK(resolved.stat().st_mode): raise ValueError('Select a block device.')
        if command == 'disk-self-test': return run(['/usr/bin/smartctl', '-t', 'short', str(resolved)])
        if command == 'disk-health':
            # smartctl's health-failure bits are findings, not command failure.
            result = subprocess.run(['/usr/bin/smartctl', '-a', '-j', str(resolved)], capture_output=True, text=True, timeout=60,
                                    env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'})
            if result.returncode & 3: raise ValueError('This drive does not expose readable SMART data through this connection.')
            value = json.loads(result.stdout)
            health = value.get('smart_status', {}).get('passed')
            temperature = value.get('temperature', {}).get('current')
            return json.dumps({'health': 'passed' if health is True else 'FAILED' if health is False else 'unknown',
                               'temperatureC': temperature, 'powerOnHours': value.get('power_on_time', {}).get('hours'),
                               'selfTest': value.get('ata_smart_self_test_log', value.get('nvme_self_test_log', 'Unavailable'))}, indent=2)
    if command.startswith('account-'):
        if command == 'account-signin':
            exact(data, ['enabled'])
            enabled = text(data, 'enabled', r'yes|no')
            name = pwd.getpwuid(caller).pw_name
            local_account(name)
            atomic('/etc/blankweave/signin.conf', enabled + '\n')
            return run(['/usr/lib/blankweave/configure-console-autologin', name])
        keys = ['name', 'password'] if command in ('account-create', 'account-password') else ['name', 'role'] if command == 'account-role' else ['name']
        exact(data, keys)
        name = text(data, 'name', r'[a-z_][a-z0-9_-]{0,30}')
        if command == 'account-create':
            password = text(data, 'password', r'[^\x00\r\n]{1,4096}')
            run(['/usr/bin/useradd', '--create-home', '--shell', '/bin/bash', '--', name])
            try: run(['/usr/bin/chpasswd'], input=name + ':' + password + '\n')
            except Exception:
                raise ValueError('The account was created but its password could not be set. It remains locked; use Change password to finish setup.') from None
            return 'Account created.'
        local_account(name)
        if command == 'account-password':
            password = text(data, 'password', r'[^\x00\r\n]{1,4096}')
            run(['/usr/bin/chpasswd'], input=name + ':' + password + '\n'); return 'Password changed.'
        if command == 'account-role':
            role = text(data, 'role', r'admin|standard')
            if role == 'admin': return run(['/usr/bin/usermod', '-a', '-G', 'wheel', '--', name])
            protect_administrator(name, caller)
            return run(['/usr/bin/gpasswd', '-d', name, 'wheel'])
        if command == 'account-delete':
            protect_administrator(name, caller)
            return run(['/usr/bin/userdel', '--', name])
    if command == 'sharing-setup':
        exact(data, ['password'])
        password = text(data, 'password', r'[^\x00\r\n]{1,4096}')
        name = pwd.getpwuid(caller).pw_name
        local_account(name)
        config = Path('/etc/samba/smb.conf')
        previous = config.read_text() if config.exists() else ''
        begin, end = '# BEGIN Blankweave usershares', '# END Blankweave usershares'
        if previous.count(begin) != previous.count(end) or previous.count(begin) > 1: raise ValueError('Invalid managed Samba configuration block.')
        block = begin + '\n[global]\nusershare path = /var/lib/samba/usershares\nusershare max shares = 100\nusershare allow guests = no\nusershare owner only = yes\n' + end
        content = re.sub(re.escape(begin) + '.*?' + re.escape(end), lambda _: block, previous, flags=re.S) if begin in previous else previous + '\n' + block + '\n'
        try: group = grp.getgrnam('blankweave-share')
        except KeyError:
            run(['/usr/bin/groupadd', '--system', 'blankweave-share'])
            group = grp.getgrnam('blankweave-share')
        directory = Path('/var/lib/samba/usershares')
        if directory.is_symlink(): raise ValueError('Refusing a symlinked usershare directory.')
        directory.mkdir(parents=True, exist_ok=True)
        os.chown(directory, 0, group.gr_gid); os.chmod(directory, 0o1770)
        atomic(config, content)
        try: run(['/usr/bin/testparm', '-s', str(config)])
        except Exception:
            atomic(config, previous); raise
        run(['/usr/bin/usermod', '-a', '-G', 'blankweave-share', '--', name])
        run(['/usr/bin/smbpasswd', '-s', '-a', name], input=password + '\n' + password + '\n')
        run(['/usr/bin/systemctl', 'enable', '--now', 'smb.service'])
        run(['/usr/bin/smbcontrol', 'all', 'reload-config'])
        return 'Authenticated Samba sharing configured. Sign in again before adding shares. Configure your firewall to permit SMB only on trusted networks.'
    if command.startswith('snapshot-'):
        if command == 'snapshot-list':
            exact(data, []); return run(['/usr/bin/snapper', '-c', 'root', 'list'])
        if command == 'snapshot-create':
            exact(data, []); return run(['/usr/bin/snapper', '-c', 'root', 'create', '--description', 'Blankweave manual snapshot', '--cleanup-algorithm', 'number', '--print-number'])
        if command == 'snapshot-delete':
            exact(data, ['number'])
            number = text(data, 'number', r'[1-9][0-9]{0,9}')
            return run(['/usr/bin/snapper', '-c', 'root', 'delete', number])
        if command == 'snapshot-schedule':
            exact(data, ['enabled'])
            enabled = text(data, 'enabled', r'yes|no')
            run(['/usr/bin/snapper', '-c', 'root', 'set-config', 'TIMELINE_CREATE=' + enabled])
            if enabled == 'yes': run(['/usr/bin/systemctl', 'enable', '--now', 'snapper-timeline.timer', 'snapper-cleanup.timer'])
            return 'Snapshot scheduling saved.'
        if command == 'snapshot-setup':
            exact(data, [])
            filesystem = run(['/usr/bin/findmnt', '-n', '-o', 'FSTYPE', '/'])
            if filesystem != 'btrfs': raise ValueError('Automatic setup supports an existing Btrfs root filesystem only.')
            if Path('/.snapshots').exists(): raise ValueError('An existing /.snapshots layout needs administrator review.')
            return run(['/usr/bin/snapper', '-c', 'root', 'create-config', '/'])
    if command == 'hibernate-prepare':
        exact(data, ['device'])
        return hibernate_prepare(text(data, 'device', r'/dev/mapper/[A-Za-z0-9_-]+'))
    if command == 'hibernate-revert':
        exact(data, [])
        return hibernate_revert()
    if command == 'hibernate-policy':
        exact(data, ['enabled'])
        enabled = text(data, 'enabled', r'yes|no')
        atomic('/etc/systemd/sleep.conf.d/60-blankweave.conf', '# Managed by Blankweave Settings\n[Sleep]\nAllowHibernation=' + enabled + '\n')
        return 'Hibernation policy saved. Hardware and resume support are still required.'
    raise ValueError('Unsupported system operation.')


def main():
    if os.geteuid() != 0: raise ValueError('Administrator authorization is required.')
    caller = int(os.environ.get('PKEXEC_UID', '-1'))
    if caller < 1000 or caller >= 65534: raise ValueError('A local desktop user must request this operation.')
    if len(sys.argv) != 2: raise ValueError('Choose one system operation.')
    raw = sys.stdin.read(65537)
    if len(raw) > 65536: raise ValueError('Request is too large.')
    data = json.loads(raw)
    with open('/run/blankweave-settings.lock', 'w') as lock:
        os.chmod(lock.name, 0o600)
        try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error: raise ValueError('Another system Settings operation is in progress.') from error
        print(execute(sys.argv[1], data, caller))


if __name__ == '__main__':
    try: main()
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr); sys.exit(1)
