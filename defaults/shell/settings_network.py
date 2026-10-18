"""Private networking and explicitly enabled user file shares."""
import json
from pathlib import Path
from settings_operations import missing, notice, action, choice, field, installed, path_value, privileged, require, run, select, state

SHELL = Path(__file__).resolve().parent


def profiles():
    # UUIDs and connection types contain no colons; names are queried separately.
    rows = []
    for line in run(['nmcli', '-t', '-f', 'UUID,TYPE', 'connection', 'show']).splitlines():
        uid, kind = line.split(':', 1)
        if kind in ('vpn', 'wireguard'):
            name = run(['nmcli', '-g', 'connection.id', 'connection', 'show', 'uuid', uid])
            rows.append(choice(uid, name))
    return rows


def status(domain):
    if domain == 'sharing': return sharing_status()
    details, actions, identity, notices = [], [], {}, []
    if installed('nmcli'):
        rows = profiles(); identity['profiles'] = rows
        active = run(['nmcli', '-t', '-f', 'UUID', 'connection', 'show', '--active']).splitlines()
        details += [p['label'] + (' · connected' if p['value'] in active else ' · disconnected') for p in rows]
        identity['active'] = sorted(active)
        actions.append(action('import', 'Import VPN profile', [field('type', 'VPN type', 'openvpn', [choice('openvpn'), choice('wireguard')]), field('file', 'Profile file (absolute path)')]))
        if not rows: notices.append(notice('not-configured', 'No VPN profiles saved', 'Choose Import VPN profile and select a configuration supplied by your VPN provider.'))
        if rows:
            target = field('uuid', 'Private network', rows[0]['value'], rows)
            actions += [action('connect', 'Connect VPN', [target, field('password', 'VPN password (optional; not saved)', secret=True)]),
                        action('disconnect', 'Disconnect VPN', [target]),
                        action('remove', 'Remove VPN profile', [target], 'Remove the selected saved VPN profile?')]
    if not installed('nmcli'): notices.append(missing('networkmanager', 'networkmanager-openvpn'))
    if not installed('tailscale'): notices.append(missing('tailscale'))
    if installed('tailscale'):
        data = json.loads(run([str(SHELL / 'tailscale-status.sh')]))
        identity['tailscale'] = data.get('backend')
        details.append('Tailscale: ' + str(data.get('backend', 'Unknown')))
        for peer in data.get('peers', [])[:30]:
            details.append(str(peer.get('name', peer.get('hostname', 'Peer'))))
        actions += [action('tailscale-login', 'Sign in to Tailscale'), action('tailscale-up', 'Connect Tailscale'), action('tailscale-down', 'Disconnect Tailscale'),
                    action('tailscale-logout', 'Sign out of Tailscale', confirm='Remove this device’s Tailscale login?')]
    return state('VPN imports require the matching NetworkManager plugin. Tailscale login may return a browser authentication URL.' if actions else '', details, actions, identity, notices)


def apply(domain, request):
    if domain == 'sharing': return sharing_apply(request)
    command = request['action']
    if command == 'tailscale-login':
        import subprocess
        from urllib.parse import urlsplit
        process = subprocess.Popen([str(SHELL / 'tailscale-auth.sh'), 'login'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        opened = False
        try:
            for line in process.stdout:
                if line.startswith('auth-url\t'):
                    url = line.split('\t', 1)[1].strip()
                    parsed = urlsplit(url)
                    if parsed.scheme != 'https' or parsed.hostname != 'login.tailscale.com':
                        raise ValueError('Tailscale returned an unexpected authentication address.')
                    run(['xdg-open', url]); opened = True
                elif line.startswith('error\t'):
                    raise ValueError('Tailscale authentication failed. Try signing in again.')
            if process.wait(timeout=200): raise ValueError('Tailscale sign-in did not complete. Try again.')
        finally:
            if process.poll() is None: process.terminate()
        return 'Tailscale authentication finished.' if opened else 'Tailscale login is already available.'
    if command.startswith('tailscale-'):
        subcommand = {'tailscale-up': 'connect', 'tailscale-down': 'disconnect', 'tailscale-logout': 'logout'}.get(command)
        if not subcommand: raise ValueError('Unknown Tailscale operation.')
        return run([str(SHELL / 'tailscale-auth.sh'), subcommand], timeout=90)
    if command == 'import':
        kind = select(request, 'type', ['openvpn', 'wireguard'])
        return run(['nmcli', 'connection', 'import', 'type', kind, 'file', str(path_value(request, 'file'))])
    if command not in ('connect', 'disconnect', 'remove'): raise ValueError('Unknown VPN operation.')
    uid = select(request, 'uuid', [p['value'] for p in profiles()])
    if command == 'connect':
        password = request.get('password', '')
        if not isinstance(password, str) or '\n' in password or '\0' in password: raise ValueError('Invalid VPN password.')
        # Pass secrets over an inherited anonymous pipe, never argv or disk.
        import os
        import subprocess
        readfd, writefd = os.pipe()
        try:
            if len(password) > 2048: raise ValueError('VPN password is too long.')
            os.write(writefd, ('vpn.secrets.password:' + password + '\n').encode() if password else b'')
            os.close(writefd); writefd = -1
            result = subprocess.run(['nmcli', '--wait', '60', 'connection', 'up', 'uuid', uid, 'passwd-file', f'/proc/self/fd/{readfd}'],
                                    pass_fds=(readfd,), capture_output=True, text=True, timeout=70)
            if result.returncode: raise ValueError('VPN activation failed. Check profile credentials and the installed VPN plugin.')
            return 'VPN connected.'
        finally:
            os.close(readfd)
            if writefd >= 0: os.close(writefd)
    if command == 'disconnect': return run(['nmcli', 'connection', 'down', 'uuid', uid])
    if command == 'remove': return run(['nmcli', 'connection', 'delete', 'uuid', uid])
    raise ValueError('Unknown VPN operation.')


def shares():
    text = run(['net', 'usershare', 'info'])
    return [line[1:-1] for line in text.splitlines() if line.startswith('[') and line.endswith(']')]


def sharing_status():
    actions, names, message, notices = [], [], '', []
    if installed('net'):
        try: names = shares()
        except ValueError as error:
            message = str(error) + ' '
            notices.append(notice('service-unavailable', 'Network sharing is not ready', 'Choose Set up authenticated sharing. If already configured, check the Samba service and sign in again to refresh group access.'))
        actions += [action('setup', 'Set up authenticated sharing', [field('password', 'Network sharing password for your account', secret=True)],
                           'Enable Samba network sharing for this computer and set your network password. Other devices on reachable networks can contact Samba. Sign in again after setup to gain usershare access.'),
                    action('share', 'Share a folder', [field('name', 'Share name'), field('folder', 'Folder (absolute path)')],
                           'Allow your authenticated Samba account to read this folder on the network. Folder permissions still apply.')]
        if not names and not message: notices.append(notice('not-configured', 'No folders are shared', 'Choose Share a folder after authenticated sharing has been set up. Only folders you explicitly select will be shared.'))
        if names: actions.append(action('unshare', 'Stop sharing', [field('name', 'Share', names[0], [choice(n) for n in names])]))
    else: notices.append(missing('samba'))
    if installed('localsend'): actions.append(action('nearby', 'Open nearby transfers'))
    else: notices.append(notice('missing-software', 'Nearby transfers need LocalSend', 'Install the communication profile or LocalSend, then refresh this section.'))
    return state(message + 'Shares grant read access; guest access is disabled. LocalSend asks the recipient to accept each transfer.', names, actions, names, notices)


def sharing_apply(request):
    command = request['action']
    if command == 'setup': return privileged('sharing-setup', password=require(request, 'password'))
    if command == 'nearby':
        import subprocess
        subprocess.Popen(['localsend'], start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return 'Nearby transfers opened.'
    name = require(request, 'name', r'[A-Za-z0-9][A-Za-z0-9_-]{0,63}')
    if command == 'share':
        import getpass
        path = path_value(request, 'folder', directory=True).resolve()
        if not path.is_relative_to(Path.home().resolve()): raise ValueError('Share a folder inside your home directory.')
        return run(['net', 'usershare', 'add', name, str(path), 'Blankweave shared folder', f'{getpass.getuser()}:R', 'guest_ok=n'])
    if command == 'unshare':
        select(request, 'name', shares())
        return run(['net', 'usershare', 'delete', name])
    raise ValueError('Unknown sharing operation.')
