#!/usr/bin/env python3
"""Root-owned before/after ledger. Never infer ownership from a filename alone."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import sys
import subprocess

# Shared by installer recording and uninstall; boot loader binaries/firmware stay.
SYSTEM_FILES = '''/etc/blankweave/signin.conf
/etc/profile.d/blankweave-session.sh
/etc/systemd/logind.conf.d/50-blankweave.conf
/etc/systemd/system/getty@tty1.service.d/autologin.conf
/etc/systemd/system/plymouth-quit.service.d/blankweave.conf
/etc/systemd/system/plymouth-quit.service
/etc/systemd/system/plymouth-quit-wait.service
/etc/issue.d/blankweave-cursor.issue
/etc/sudoers.d/blankweave-install
/etc/pacman.d/hooks/90-blankweave-intel-gpu-top.hook
/etc/pacman.d/hooks/95-blankweave-limine.hook
/etc/modprobe.d/nvidia.conf
/etc/pacman.conf
/etc/mkinitcpio.conf
/etc/plymouth/plymouthd.conf
/usr/share/plymouth/themes/default.plymouth
/etc/sddm.conf.d/autologin.conf
/etc/pam.d/blankweave-lock
/etc/pam.d/hyprarch-lock
/usr/lib/blankweave
/usr/local/lib/blankweave
/usr/share/blankweave
/usr/share/plymouth/themes/blankweave
/usr/share/polkit-1/actions/org.blankweave.theme-sync.policy
/usr/share/polkit-1/actions/org.blankweave.settings.policy'''.splitlines()
BOOT_TOKEN_PREFIXES = ('quiet', 'splash', 'loglevel=', 'systemd.show_status=', 'rd.systemd.show_status=', 'udev.log_', 'rd.udev.log_', 'vt.global_cursor_default=', 'vt.default_')

SERVICES = ['NetworkManager.service', 'bluetooth.service', 'paccache.timer', 'tailscaled.service', 'docker.service', 'getty@tty1.service', 'voxtype.service', 'gcr-ssh-agent.socket']

def safe(path):
    return not any(p.is_symlink() for p in path.parents)

def identity(path):
    if not safe(path):
        return None
    try:
        mode = path.lstat().st_mode
        if stat.S_ISLNK(mode):
            return {'link': os.readlink(path)}
        if stat.S_ISREG(mode):
            return {'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'mode': stat.S_IMODE(mode), 'uid': path.stat().st_uid, 'gid': path.stat().st_gid}
    except FileNotFoundError:
        pass
    return None

def paths(root, home):
    result = [root / p.lstrip('/') for p in SYSTEM_FILES]
    result += [home / p for p in ['.local/share/blankweave', '.local/bin/blankweave', '.zshrc', '.zprofile', '.local/share/zsh/site-functions/_blankweave', '.local/share/bash-completion/completions/blankweave', '.local/share/applications/blankweave-settings.desktop', '.local/share/icons/hicolor/scalable/apps/blankweave-settings.svg']]
    # Entry points only; never record personal Blankweave preferences or keyrings.
    for d in ['hypr', 'dunst', 'ghostty', 'fontconfig', 'xdg-desktop-portal', 'voxtype', 'MangoHud']:
        result += [home / '.config' / d]
    result += [home / '.config/spotify-launcher.conf']
    # Enablement links are ownership evidence; do not stop shared running services.
    for base in [root / 'etc/systemd/system', home / '.config/systemd/user']:
        if base.is_dir() and safe(base):
            for parent, dirs, files in os.walk(base, followlinks=False):
                result += [Path(parent) / n for n in files if n in SERVICES and (Path(parent) / n).is_symlink()]
    for p in (home / '.local/share/applications').glob('blankweave-webapp-*.desktop'):
        if not p.is_symlink() and safe(p) and 'X-Blankweave-Webapp=bundled' in p.read_text():
            result.append(p)
            result += list((home / '.local/share/icons/hicolor').glob('*/apps/' + p.stem + '.*'))
    found = set()
    for p in result:
        if p.is_dir() and not p.is_symlink() and safe(p):
            for parent, dirs, files in os.walk(p, followlinks=False):
                dirs[:] = [d for d in dirs if d != 'repository']
                found.update(Path(parent) / n for n in files + dirs if identity(Path(parent) / n))
        elif identity(p):
            found.add(p)
    return sorted(found)

def boot_tokens(root):
    result = {}
    for pattern in ['boot/loader/entries/*.conf', 'efi/loader/entries/*.conf', 'boot/efi/loader/entries/*.conf', 'boot/EFI/blankweave/limine.conf']:
        for path in root.glob(pattern):
            if not safe(path) or path.is_symlink() or not path.is_file():
                continue
            tokens = set()
            for line in path.read_text().splitlines():
                fields = line.split()
                if fields and fields[0] in ('options', 'cmdline:'):
                    tokens.update(t for t in fields[1:] if t.startswith(BOOT_TOKEN_PREFIXES))
            result[str(path)] = sorted(tokens)
    return result


def main():
    action, root_arg, home_arg = sys.argv[1:4]
    root, home = Path(root_arg or '/').absolute(), Path(home_arg).absolute()
    ledger = root / 'var/lib/blankweave/uninstall' / str(home.stat().st_uid)
    # A sandbox root may only contain its own sandbox home.
    if root != Path('/') and not home.is_relative_to(root):
        raise SystemExit('sandbox home must be inside sandbox root')
    if not safe(ledger) or ledger.is_symlink():
        raise SystemExit('unsafe ledger path')
    if action in ('before', 'after'):
        ledger.mkdir(parents=True, exist_ok=True)
        blob = ledger / 'backups'
        blob.mkdir(mode=0o700, exist_ok=True)
        records = {str(p): identity(p) for p in paths(root, home)}
        boot = boot_tokens(root)
        (ledger / ('boot-' + action + '.json')).write_text(json.dumps(boot))
        if root == Path('/'):
            packages = subprocess.run(['pacman', '-Qq'], capture_output=True, text=True, check=True).stdout.splitlines()
            (ledger / ('packages-' + action + '.json')).write_text(json.dumps(packages))
        if action == 'before':
            for p, item in records.items():
                if 'sha256' in item:
                    dest = blob / item['sha256']
                    if not dest.exists():
                        shutil.copyfile(p, dest)
                        dest.chmod(0o600)
        (ledger / (action + '.json')).write_text(json.dumps(records))
        if action == 'after':
            before = json.loads((ledger / 'before.json').read_text())
            existing = json.loads((ledger / 'owned.json').read_text()) if (ledger / 'owned.json').exists() else {}
            for p in set(before) | set(records):
                if before.get(p) != records.get(p):
                    existing[p] = {'before': existing.get(p, {}).get('before', before.get(p)), 'after': records.get(p)}
            (ledger / 'owned.json').write_text(json.dumps(existing, indent=2))
            old_boot = json.loads((ledger / 'boot-before.json').read_text())
            boot_owned_path = ledger / 'boot-owned.json'
            boot_owned = json.loads(boot_owned_path.read_text()) if boot_owned_path.exists() else {}
            for name, tokens in boot.items():
                boot_owned[name] = sorted(set(boot_owned.get(name, [])) | (set(tokens) - set(old_boot.get(name, []))))
            boot_owned_path.write_text(json.dumps(boot_owned))
            zsh = home / '.zshrc'
            if identity(zsh) and not zsh.is_symlink():
                marker = b'### ANY CUSTOM CONFIGS GO BELOW THIS LINE'
                deployed = zsh.read_bytes()
                if marker in deployed:
                    (ledger / 'zsh-deployed-prefix').write_bytes(deployed.split(marker, 1)[0])
                    (ledger / 'zsh-deployed-prefix').chmod(0o644)
            if (ledger / 'packages-before.json').exists():
                installed = set(json.loads((ledger / 'packages-after.json').read_text())) - set(json.loads((ledger / 'packages-before.json').read_text()))
                previous = set(json.loads((ledger / 'packages-installed.json').read_text())) if (ledger / 'packages-installed.json').exists() else set()
                (ledger / 'packages-installed.json').write_text(json.dumps(sorted(installed | previous)))
        return
    print('User files: managed data (checkout retained), config entry points, command, completion, desktop entry/icon, zshrc/profile (unchanged ledger matches only).')
    print('State/cache: retained (may contain recovery records and personal data).')
    print('System files:')
    for p in SYSTEM_FILES:
        print('  ' + p)
    print('Services enabled or seeded (only recorded new enablement links removed; running services are not stopped): ' + ', '.join(SERVICES))
    if (ledger / 'packages-installed.json').exists():
        print('Recorded newly installed packages (retained): ' + ', '.join(json.loads((ledger / 'packages-installed.json').read_text())))
    print('Packages: never removed; see packages/base.txt, packages/aur.txt and selected profile/capability manifests; installed package history: /var/log/pacman.log')
    print('Boot entries: remove only recorded added styling tokens; boot loader, firmware entries, initramfs, folder colours, GPU capabilities, groups and login shell require manual review.')
    print('After reviewing restored mkinitcpio configuration, rebuild initramfs manually before rebooting. Review service enablement; running services are left alone.')
    print('Set up a display manager or another session before rebooting: automatic sign-in is going away.')
    profile = home / '.zprofile'
    if safe(profile) and profile.is_file() and not profile.is_symlink():
        known = {b'source ~/.local/share/blankweave/shell/profile', b'. ~/.local/share/blankweave/shell/profile', b'source "$HOME/.local/share/blankweave/shell/profile"', b'. "$HOME/.local/share/blankweave/shell/profile"'}
        content = profile.read_bytes()
        kept = b''.join(line for line in content.splitlines(keepends=True) if line.rstrip(b'\r\n') not in known)
        if kept != content:
            print('Remove exact managed .zprofile source line; retain other contents: ' + str(profile))
            if action == 'apply':
                profile.write_bytes(kept)
    source = ledger / 'owned.json' 
    if not source.exists():
        print('Kept unrecorded files: no ownership ledger (older install). Reapply once to record future changes; pre-existing state cannot be reconstructed.')
        return
    records = json.loads(source.read_text())
    for name, record in records.items():
        path = Path(name)
        # Trust only paths inside this root/home and never traverse symlink parents.
        if not path.is_absolute() or '..' in path.parts or not path.is_relative_to(root) or not safe(path):
            print('Kept unsafe path: ' + name)
            continue
        current = identity(path)
        if current == record['before']:
            continue
        if path == home / '.zshrc' and current != record['after'] and current and 'sha256' in current and (ledger / 'zsh-deployed-prefix').exists():
            marker = b'### ANY CUSTOM CONFIGS GO BELOW THIS LINE'
            deployed = (ledger / 'zsh-deployed-prefix').read_bytes()
            content = path.read_bytes()
            if marker in content:
                prefix, tail = content.split(marker, 1)
                expected = deployed
                if prefix == expected:
                    print('Remove managed zshrc prefix; retain custom tail: ' + name)
                    if action == 'apply':
                        # The separator following the marker is managed too.
                        tail = tail.lstrip(b'\r\n')
                        lines = tail.splitlines(keepends=True)
                        if lines and lines[0].strip(b'#\r\n') == b'':
                            tail = b''.join(lines[1:])
                        path.write_bytes(tail)
                    continue
        if current != record['after']:
            print('Kept modified or missing: ' + name)
            continue
        if path.is_relative_to(home / '.local/share/blankweave/repository'):
            continue
        print(('Restore: ' if record['before'] else 'Remove: ') + name)
        if action != 'apply':
            continue
        old = record['before']
        if old is None:
            path.unlink(missing_ok=True)
        elif 'link' in old:
            path.unlink(missing_ok=True)
            path.symlink_to(old['link'])
        else:
            backup = ledger / 'backups' / old['sha256']
            if not backup.is_file() or hashlib.sha256(backup.read_bytes()).hexdigest() != old['sha256']:
                print('Kept: backup missing or invalid: ' + name)
                continue
            path.unlink(missing_ok=True)
            shutil.copyfile(backup, path)
            path.chmod(old['mode'])
            if os.geteuid() == 0:
                os.chown(path, old['uid'], old['gid'])
    if (ledger / 'boot-owned.json').exists():
        boot_owned = json.loads((ledger / 'boot-owned.json').read_text())
        for name, tokens in boot_owned.items():
            path = Path(name)
            if not path.is_relative_to(root) or not safe(path) or path.is_symlink() or not path.is_file():
                print('Kept inaccessible boot tokens: ' + name)
                continue
            owned = {t for t in tokens if t.startswith(BOOT_TOKEN_PREFIXES)}
            content = path.read_text()
            lines = []
            for line in content.splitlines(keepends=True):
                fields = line.split()
                if fields and fields[0] in ('options', 'cmdline:') and owned.intersection(fields[1:]):
                    print('Remove recorded boot tokens: ' + name + ': ' + ', '.join(sorted(owned.intersection(fields[1:]))))
                    indent = line[:len(line) - len(line.lstrip())]
                    line = indent + ' '.join([fields[0]] + [t for t in fields[1:] if t not in owned]) + ('\n' if line.endswith('\n') else '')
                lines.append(line)
            if action == 'apply' and ''.join(lines) != content:
                path.write_text(''.join(lines))
    if '--purge-config' in sys.argv and action == 'apply':
        config = home / '.config/blankweave'
        if safe(config) and not config.is_symlink() and config.is_dir():
            shutil.rmtree(config)
    else:
        print('Kept ~/.config/blankweave: personal overrides, themes, wallpapers and preferences (use --purge-config to delete).')

if __name__ == '__main__':
    main()
