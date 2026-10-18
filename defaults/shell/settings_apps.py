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
        version = run([str(COMMAND), 'version']) if COMMAND.is_file() else 'Blankweave command is not installed.'
        actions = []
        if COMMAND.is_file():
            actions += [action('check', 'Check Blankweave updates', cancellable=True),
                        action('release-notes', 'Read release notes', cancellable=True),
                        action('update', 'Apply Blankweave update', confirm='Open the existing interactive updater for authorization and progress. It preserves release validation and recovery records.')]
        if installed('checkupdates'): actions.append(action('package-check', 'Check repository updates', cancellable=True))
        if installed('pacman', 'ghostty'): actions.append(action('package-update', 'Update system packages', confirm='Open a full pacman system upgrade for transaction review and administrator authorization.'))
        if installed('flatpak'): actions.append(action('flatpak-update', 'Update user Flatpaks', confirm='Update applications and runtimes in your user installation?'))
        notices = [] if COMMAND.is_file() else [notice('missing-software', 'Blankweave updater is not installed', 'Complete or repair the Blankweave installation, then refresh. Available package-manager actions can still be used.')]
        if not actions: notices.append(notice('missing-software', 'No update tools are available', 'Install the Blankweave desktop profile to restore its updater and package-management tools.'))
        return state('Blankweave configuration rollback does not downgrade Arch packages. Interactive system updates continue in their own terminal when Settings closes.', [version], actions, str(COMMAND), notices)
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
        if command == 'check': return run([str(COMMAND), 'update', '--dry-run'], timeout=180)
        if command == 'release-notes':
            import urllib.request
            request_url = urllib.request.Request('https://api.github.com/repos/shivamx96/blankweave/releases/latest', headers={'Accept': 'application/vnd.github+json', 'User-Agent': 'Blankweave-Settings'})
            with urllib.request.urlopen(request_url, timeout=30) as response:
                release = json.loads(response.read(262144))
            return str(release.get('tag_name', 'Latest release')) + '\n' + str(release.get('body') or 'No published release notes.') + '\n' + str(release.get('html_url', ''))
        if command == 'package-check': return run(['checkupdates'], timeout=180, codes=(0, 2)) or 'No package updates.'
        if command == 'flatpak-update': return run(['flatpak', 'update', '--user', '--noninteractive'], timeout=7200)
        if command in ('update', 'package-update'):
            args = [str(COMMAND), 'update'] if command == 'update' else ['sudo', 'pacman', '-Syu']
            subprocess.Popen(['ghostty', '-e', *args], start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return 'Updater opened in its own terminal. Review its transaction and completion there; this message does not indicate a successful update.'
    raise ValueError('Unknown application operation.')
