"""Software inventory, reviewed pacman transactions and sandbox permissions."""
import json
import os
from pathlib import Path
import subprocess
from settings_support import atomic, config_home, digest, read
from settings_operations import missing, notice, action, choice, field, installed, privileged, require, run, select, state

PLAN = config_home() / 'blankweave/settings-package-plan.json'
COMMAND = Path.home() / '.local/bin/blankweave'
RECOVERY = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'blankweave/recovery'


def flatpaks():
    return [line.split('\t')[0] for line in run(['flatpak', '--user', 'list', '--app', '--columns=application']).splitlines()]


def packages():
    return run(['pacman', '-Q']).splitlines()


def transaction(kind, package):
    flag = '-Sp' if kind == 'install' else '-Rp'
    return sorted(run(['pacman', flag, '--print-format', '%n %v', '--', package]).splitlines())


def status(domain):
    if domain == 'installed':
        if not installed('pacman'): return state(notices=[notice('unsupported', 'Native package management is unavailable', 'This computer needs the Arch pacman package manager to manage native packages in Settings.')])
        rows = packages()
        plan = json.loads(read(PLAN) or 'null')
        actions = [action('search', 'Search software', [field('query', 'Search packages')], cancellable=True),
                   action('inventory', 'List installed packages', cancellable=True),
                   action('review-install', 'Review package installation', [field('package', 'Repository package name')]),
                   action('review-remove', 'Review package removal', [field('package', 'Installed package name')])]
        details = [f'{len(rows)} native packages installed. Search results and inventory appear in the operation report.']
        if plan:
            details += ['Pending transaction: ' + plan['kind']] + plan['packages']
            actions.append(action('commit', 'Apply reviewed package transaction', confirm='Apply exactly the package transaction listed above? Administrator authorization is required.'))
        if installed('flatpak'):
            actions += [action('flatpak-install', 'Install Flatpak', [field('remote', 'Configured remote'), field('app', 'Application ID')], 'Install this application and required runtimes in your user account?'),
                        action('flatpak-list', 'List Flatpak applications')]
            apps = flatpaks()
            if apps: actions.append(action('flatpak-remove', 'Remove user Flatpak', [field('app', 'Application', apps[0], [choice(a) for a in apps])], 'Uninstall this application from your user installation? Saved application data is retained.'))
        return state('Native installations use existing repository metadata. AUR packages appear in inventory but must be built and reviewed with your AUR helper; Settings does not run unreviewed build scripts.', details, actions, [digest(rows), plan])
    if domain == 'permissions':
        if not installed('flatpak'): return state('These controls apply to sandboxed Flatpak applications, not native packages.', notices=[missing('flatpak')])
        apps = flatpaks()
        actions = []
        if apps:
            target = field('app', 'Application', apps[0], [choice(a) for a in apps])
            actions = [action('inspect', 'Inspect permissions', [target]),
                       action('revoke', 'Restrict application access', [target, field('scope', 'Permission', 'files', [choice('files', 'Direct host files'), choice('audio', 'Audio playback and microphone'), choice('devices', 'Direct device access'), choice('network', 'Network')])], 'Apply a user override. Restart the application. Existing portal grants are managed separately.'),
                       action('reset', 'Reset overrides', [target], 'Remove this user’s permission overrides and restore application defaults?'),
                       action('portal-reset', 'Reset portal decisions', [target], 'Forget saved portal decisions for this application. It may ask for access again.')]
        return state('Flatpak controls apply only to sandboxed applications. Audio access includes playback and microphone together. Device restrictions are not a universal camera switch. Native applications remain outside this permission model.', apps, actions, apps, [] if apps else [notice('not-configured', 'No user Flatpak applications installed', 'Open Installed applications to install a user Flatpak. Native packages and system-wide Flatpaks are not managed by these permission controls.', 'installed')])
    if domain == 'updates':
        release = release_status()
        actions = [action('check', 'Check for updates', cancellable=True)] if COMMAND.is_file() else []
        if release['restartRequired']: actions.append(action('restart', 'Restart', confirm='Restart this computer to finish updating? Save your work first.'))
        result = state('Applying updates opens Ghostty: the updater needs sudo and prints a plan you must confirm. Blankweave rollback does not downgrade Arch packages.',
                       ['Installed release: ' + release['installed'], 'Newest release: ' + release['newest']] + (['Restart required to finish updating.'] if release['restartRequired'] else []) + release['notes'], actions, release)
        result['release'] = release
        return result
    raise ValueError('Unknown application provider.')


def apply(domain, request):
    command = request['action']
    if domain == 'installed':
        if command == 'inventory':
            foreign = set(run(['pacman', '-Qmq'], codes=(0, 1)).splitlines())
            return '\n'.join(row + (' [foreign/AUR]' if row.split()[0] in foreign else '') for row in packages())
        if command == 'search':
            query = require(request, 'query', maximum=100)
            return run(['pacman', '-Ss', '--', query], codes=(0, 1)) or 'No matching packages.'
        if command.startswith('review-'):
            package = require(request, 'package', r'[a-zA-Z0-9@][a-zA-Z0-9@._+:-]{0,127}')
            kind = command.removeprefix('review-')
            if kind not in ('install', 'remove'): raise ValueError('Unknown transaction.')
            rows = transaction(kind, package)
            if not rows: raise ValueError('No package changes are needed.')
            atomic(PLAN, json.dumps(dict(kind=kind, package=package, packages=rows)))
            return 'Review the exact transaction above, then choose Apply reviewed package transaction.'
        if command == 'commit':
            plan = json.loads(read(PLAN) or 'null')
            if not plan or transaction(plan['kind'], plan['package']) != plan['packages']: raise ValueError('Package transaction changed. Review it again.')
            result = privileged('package', **plan)
            PLAN.unlink(missing_ok=True)
            return result
        if command == 'flatpak-list': return run(['flatpak', 'list', '--app'])
        if command == 'flatpak-install':
            remote = select(request, 'remote', run(['flatpak', 'remotes', '--user', '--columns=name']).splitlines())
            app = require(request, 'app', r'[A-Za-z][A-Za-z0-9_.-]+')
            return run(['flatpak', 'install', '--user', '--noninteractive', remote, app], timeout=7200)
        if command == 'flatpak-remove':
            app = select(request, 'app', flatpaks())
            return run(['flatpak', 'uninstall', '--user', '--noninteractive', app], timeout=600)
    if domain == 'permissions':
        app = select(request, 'app', flatpaks())
        if command == 'inspect':
            return run(['flatpak', 'info', '--show-permissions', app]) + '\nUser overrides:\n' + run(['flatpak', 'override', '--user', '--show', app]) + '\nPortal decisions:\n' + run(['flatpak', 'permission-show', app])
        if command == 'revoke':
            option = {'files': '--nofilesystem=host:reset', 'audio': '--nosocket=pulseaudio', 'devices': '--nodevice=all', 'network': '--unshare=network'}[select(request, 'scope', ['files', 'audio', 'devices', 'network'])]
            run(['flatpak', 'override', '--user', option, app])
            return run(['flatpak', 'override', '--user', '--show', app])
        if command == 'reset': return run(['flatpak', 'override', '--user', '--reset', app])
        if command == 'portal-reset': return run(['flatpak', 'permission-reset', app])
    if domain == 'updates':
        if command == 'check': return run([str(COMMAND), 'update', '--check'], timeout=180)
        if command == 'restart': return run(['systemctl', 'reboot'])
        if command == 'package-check': return run(['checkupdates'], timeout=180, codes=(0, 2)) or 'No package updates.'
        if command == 'flatpak-update': return run(['flatpak', 'update', '--user', '--noninteractive'], timeout=7200)
    raise ValueError('Unknown application operation.')


def release_status():
    repository = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'blankweave/repository'
    state_dir = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'blankweave'
    installed_tag = (read(state_dir / 'installed-release-tag') or 'Unknown').strip()
    newest = 'Unknown — check for updates'
    notes = []
    try:
        # Reuse the updater's annotated-tag, ancestry and VERSION validation, read-only.
        newest = run(['bash', '-c', 'source "$1/scripts/release-version.sh"; blankweave_release_select "$1" origin/main', 'settings', str(repository)])
        notes = release_notes(read(repository / 'RELEASES.md') or '', installed_tag, newest)
        if not notes and installed_tag != newest:
            notes = tag_notes(run(['git', '-C', str(repository), 'tag', '-l', '--merged=' + newest, '--format=%(refname:short)%09%(objecttype)%09%(contents)%1e', 'v*']), installed_tag, newest)
    except (ValueError, OSError): pass
    runtime = os.environ.get('XDG_RUNTIME_DIR')
    return dict(installed=installed_tag, newest=newest, notes=notes,
                restartRequired=bool(runtime and (Path(runtime) / 'blankweave/restart-required').is_file()))


def release_notes(text, installed_tag, newest):
    import re
    def version(value):
        match = re.fullmatch(r'v?(\d+)\.(\d+)\.(\d+)', value)
        return tuple(map(int, match.groups())) if match else None
    low, high = version(installed_tag), version(newest)
    if low is None or high is None: return []
    sections = re.split(r'(?m)^## (?:v)?(\d+\.\d+\.\d+)\s*$', text)
    return ['Version ' + sections[i] + '\n' + sections[i+1].strip()
            for i in range(1, len(sections), 2) if low < version(sections[i]) <= high]


def tag_notes(text, installed_tag, newest):
    import re
    def version(tag):
        return tuple(map(int, tag.lstrip('v').split('.')))
    if not re.fullmatch(r'v?\d+\.\d+\.\d+', installed_tag): return []
    selected = []
    for record in text.split('\x1e'):
        fields = record.strip().split('\t', 2)
        if len(fields) != 3: continue
        tag, kind, body = fields
        if kind == 'tag' and re.fullmatch(r'v\d+\.\d+\.\d+', tag) and version(installed_tag) < version(tag) <= version(newest):
            selected.append((version(tag), tag + '\n' + body))
    return [note for _, note in sorted(selected)] or ['No release notes available.']
