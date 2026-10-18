"""Encrypted restic backups, persistent user schedules, and separate-folder restore."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
from settings_support import atomic, config_home, locked, read
from settings_operations import missing, notice, action, choice, field, installed, path_value, require, run, select, state

CONFIG = config_home() / 'blankweave/backup.json'
UNITS = config_home() / 'systemd/user'
SHELL = Path(__file__).resolve().parent


def validate(data):
    if not isinstance(data, dict) or set(data) not in ({'repository', 'source', 'keep', 'schedule'}, {'repository', 'source', 'keep', 'schedule', 'exclude'}): raise ValueError('Invalid backup configuration.')
    repository = require(data, 'repository')
    if not repository.startswith('/') and not re.fullmatch(r'sftp:[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+:/[^\s]+', repository):
        raise ValueError('Use an absolute local repository path or sftp:user@host:/path. Configure SSH keys separately.')
    source = path_value(data, 'source', directory=True).resolve()
    if repository.startswith('/'):
        target = Path(repository).resolve()
        if target.is_relative_to(source) or source.is_relative_to(target): raise ValueError('Backup repository and source must be separate directories.')
    if type(data['keep']) is not int or not 1 <= data['keep'] <= 365: raise ValueError('Keep between 1 and 365 backups.')
    if data['schedule'] not in ('off', 'daily', 'weekly'): raise ValueError('Invalid backup schedule.')
    exclusions = data.get('exclude', [])
    if not isinstance(exclusions, list) or len(exclusions) > 100 or any(not isinstance(value, str) or not value or len(value) > 4096 or '\0' in value or '\n' in value for value in exclusions): raise ValueError('Invalid exclusion patterns.')
    return data


def config():
    return validate(json.loads(CONFIG.read_text())) if CONFIG.exists() else None


def credential_id(repository):
    return hashlib.sha256(repository.encode()).hexdigest()


def restic(data, args, timeout=7200):
    # Secret Service controls unlocking; no password is persisted in preferences,
    # unit files, arguments, or operation reports.
    env = {k: v for k, v in os.environ.items() if not k.startswith('RESTIC_')}
    env.update(LC_ALL='C', RESTIC_PASSWORD_COMMAND='secret-tool lookup application blankweave-backup repository ' + credential_id(data['repository']))
    result = subprocess.run(['restic', '-r', data['repository'], *args], env=env, capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)
    if result.returncode:
        raise ValueError('Backup operation failed (exit ' + str(result.returncode) + '). ' + result.stderr[-2500:] + (' Some source files were unreadable; the backup is incomplete.' if result.returncode == 3 else ''))
    return result.stdout[-14000:]


def schedule(data):
    service = UNITS / 'blankweave-backup.service'
    timer = UNITS / 'blankweave-backup.timer'
    if data['schedule'] == 'off':
        run(['systemctl', '--user', 'disable', '--now', 'blankweave-backup.timer'], codes=(0, 1, 5))
        return
    executable = str(SHELL / 'operations-settings.py').replace('%', '%%').replace('\\', '\\\\').replace('"', '\\"')
    atomic(service, '[Unit]\nDescription=Blankweave encrypted file backup\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/python3 "' + executable + '" backup scheduled\n')
    atomic(timer, '[Unit]\nDescription=Scheduled Blankweave file backup\n\n[Timer]\nOnCalendar=' + data['schedule'] + '\nPersistent=true\nRandomizedDelaySec=5m\n\n[Install]\nWantedBy=timers.target\n')
    run(['systemctl', '--user', 'daemon-reload'])
    run(['systemctl', '--user', 'enable', '--now', 'blankweave-backup.timer'])


def status(domain):
    if not installed('restic', 'secret-tool'): return state('Backup passwords are stored in the session keyring.', notices=[missing(*[package for command, package in [('restic', 'restic'), ('secret-tool', 'libsecret')] if not installed(command)])])
    data = config()
    notices = [] if data else [notice('not-configured', 'Backups are not set up' if domain == 'backup' else 'Set up backups before restoring files', 'Choose Set up backups to select a source folder, destination, and password.' if domain == 'backup' else 'Open Scheduled file backups to configure or connect an encrypted backup repository.', '' if domain == 'backup' else 'backup')]
    details = [] if not data else ['Repository: ' + data['repository'], 'Source: ' + data['source'], f'Retention: {data["keep"]} backups per source/host', 'Schedule: ' + data['schedule']]
    if domain == 'backup':
        actions = [action('configure', 'Save backup settings', [field('repository', 'Repository (local path or sftp:user@host:/path)', data['repository'] if data else ''),
                   field('source', 'Source directory', data['source'] if data else str(Path.home())),
                   field('exclude', 'Excluded paths or patterns (one per line)', '\n'.join(data.get('exclude', [])) if data else '', multiline=True),
                   field('keep', 'Backups to keep', data['keep'] if data else '14'),
                   field('schedule', 'Schedule', data['schedule'] if data else 'off', [choice('off'), choice('daily'), choice('weekly')]),
                   field('password', 'Repository password (leave blank to keep the saved password)', secret=True)],
                   'Store the repository password in your keyring and save this schedule. Keep a separate copy of the password; backups cannot be decrypted without it.')]
        if data:
            actions += [action('init', 'Initialize repository', confirm='Create a new encrypted repository at the configured destination? Existing repositories are never overwritten.'),
                        action('backup', 'Back up now'), action('check', 'Check repository integrity', cancellable=True),
                        action('retention', 'Apply backup retention', confirm=f'Keep the latest {data["keep"]} Blankweave backups per source/host and prune older data?')]
    else:
        actions = [] if not data else [action('list', 'List backup snapshots', cancellable=True),
            action('browse', 'Browse snapshot files', [field('snapshot', 'Snapshot ID'), field('path', 'Path within snapshot', '/')], cancellable=True),
            action('restore', 'Restore files', [field('snapshot', 'Snapshot ID'), field('include', 'File or folder inside snapshot (absolute path; / for all)', '/'),
                                              field('folder', 'Destination parent directory', str(Path.home()))],
                   'Restore into a new separate folder beneath this destination. Existing files will not be overwritten.')]
    if domain == 'restore' and not data:
        return state(notices=notices)
    return state('Scheduled backups run while your user manager is active and the keyring is unlocked. Missed timers run at the next opportunity. An unavailable destination or locked keyring causes a reported failure; it never creates an unencrypted fallback.', details, actions, data, notices)


def apply(domain, request):
    with locked('backup-provider'):
        command = request['action']
        if command == 'configure':
            data = validate(dict(repository=require(request, 'repository'), source=str(path_value(request, 'source', directory=True).resolve()),
                                 keep=int(require(request, 'keep', r'\d{1,3}')), schedule=select(request, 'schedule', ['off', 'daily', 'weekly']), exclude=request.get('exclude', '').splitlines()))
            previous = read(CONFIG)
            old_data = json.loads(previous) if previous else None
            password = request.get('password', '')
            if not isinstance(password, str) or any(c in password for c in ('\0', '\n', '\r')) or len(password) > 4096:
                raise ValueError('Invalid repository password.')
            if not password and (not old_data or old_data['repository'] != data['repository']):
                raise ValueError('Enter a password for the new repository.')
            if password:
                existing = (old_data and old_data['repository'] == data['repository']) or (data['repository'].startswith('/') and (Path(data['repository']) / 'config').is_file())
                if existing:
                    env = {key: value for key, value in os.environ.items() if not key.startswith('RESTIC_')}
                    result = subprocess.run(['restic', '-r', data['repository'], '--password-file', '/dev/stdin', 'cat', 'config'], input=password,
                                            text=True, capture_output=True, timeout=60, env=env)
                    if result.returncode: raise ValueError('Could not unlock the existing repository with this password. The saved credential was preserved.')
                run(['secret-tool', 'store', '--label=Blankweave backup', 'application', 'blankweave-backup', 'repository', credential_id(data['repository'])], input=password, timeout=60)
            unit_paths = [UNITS / 'blankweave-backup.service', UNITS / 'blankweave-backup.timer']
            old_units = [(path, read(path)) for path in unit_paths]
            try:
                atomic(CONFIG, json.dumps(data))
                schedule(data)
            except Exception as error:
                if previous is None: CONFIG.unlink(missing_ok=True)
                else: atomic(CONFIG, previous)
                for path, content in old_units:
                    if content is None: path.unlink(missing_ok=True)
                    else: atomic(path, content)
                try:
                    run(['systemctl', '--user', 'daemon-reload'])
                    schedule(old_data or {'schedule': 'off'})
                except Exception:
                    raise ValueError(str(error) + ' Preferences were restored, but restoring the previous timer failed; review the backup schedule.') from error
                raise
            return 'Backup settings saved. Initialize a new repository or run Back up now for an existing repository.'
        data = config()
        if not data: raise ValueError('Configure a backup repository first.')
        if command == 'init':
            if data['repository'].startswith('/'):
                path = Path(data['repository'])
                if not path.parent.is_dir(): raise ValueError('The destination parent is unavailable. Mount the backup drive first.')
                if path.exists() and any(path.iterdir()): raise ValueError('Repository directory is not empty.')
            return restic(data, ['init'])
        if data['repository'].startswith('/') and not (Path(data['repository']) / 'config').is_file():
            raise ValueError('Repository is unavailable or uninitialized. Mount its drive or initialize it first.')
        if command == 'backup': return restic(data, ['backup', '--tag', 'blankweave', '--one-file-system', *[part for pattern in data.get('exclude', []) for part in ('--exclude', pattern)], '--', data['source']])
        if command == 'check': return restic(data, ['check'])
        if command == 'retention': return restic(data, ['forget', '--tag', 'blankweave', '--keep-last', str(data['keep']), '--prune'])
        if command == 'list': return restic(data, ['snapshots'])
        snapshot = require(request, 'snapshot', r'[a-f0-9]{8,64}')
        if command == 'browse':
            path = require(request, 'path')
            if not path.startswith('/'): raise ValueError('Enter an absolute snapshot path.')
            return restic(data, ['ls', snapshot, path])
        if command == 'restore':
            include = require(request, 'include')
            if not include.startswith('/') or '..' in Path(include).parts: raise ValueError('Choose an absolute snapshot path without parent traversal.')
            folder = path_value(request, 'folder', directory=True)
            target = folder / ('Restored-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
            target.mkdir(mode=0o700)
            try: output = restic(data, ['restore', snapshot, '--target', str(target), '--include', include, '--verify'])
            except Exception as error: raise ValueError(str(error) + '\nPartial restore retained at ' + str(target)) from error
            return output + '\nRestored to ' + str(target)
        raise ValueError('Unknown backup operation.')
