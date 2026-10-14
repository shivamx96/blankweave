#!/usr/bin/env python3
"""Manage XDG autostart enablement without launching or stopping applications."""
import configparser
import os
from pathlib import Path
import re
import shutil
from settings_support import atomic, check_revision, cli, config_home, digest, locked, read

MARKER = 'X-Blankweave-Startup-Override'


def parse(text):
    parser = configparser.ConfigParser(interpolation=None, delimiters=('=',), comment_prefixes=('#',), strict=True)
    parser.optionxform = str
    parser.read_string(text)
    if not parser.has_section('Desktop Entry'): raise ValueError('Missing Desktop Entry section.')
    return parser['Desktop Entry']


def set_key(text, key, value):
    output, inside, inserted = [], False, False
    for line in text.splitlines():
        if line.startswith('['):
            if inside and not inserted: output.append(f'{key}={value}'); inserted = True
            inside = line.strip() == '[Desktop Entry]'
        if inside and re.match(r'^\s*' + re.escape(key) + r'\s*=', line):
            if not inserted: output.append(f'{key}={value}'); inserted = True
        else: output.append(line)
    if inside and not inserted: output.append(f'{key}={value}')
    result = '\n'.join(output) + '\n'
    parse(result)
    return result


def entries():
    result = {}
    directories = [config_home()] + [Path(p) for p in os.environ.get('XDG_CONFIG_DIRS', '/etc/xdg').split(':') if p]
    for directory in directories:
        for path in sorted((directory / 'autostart').glob('*.desktop')):
            if path.name not in result: result[path.name] = path
    return result


def status():
    rows, fingerprints = [], []
    desktops = set(os.environ.get('XDG_CURRENT_DESKTOP', '').split(':'))
    for identifier, path in entries().items():
        text = read(path)
        fingerprints.append([str(path), text, path.is_symlink()])
        try:
            data = parse(text or '')
            reason = ''
            only = set(filter(None, data.get('OnlyShowIn', '').split(';')))
            exclude = set(filter(None, data.get('NotShowIn', '').split(';')))
            if only and not only & desktops: reason = 'Restricted to another desktop.'
            if exclude & desktops: reason = 'Excluded from this desktop.'
            if data.get('TryExec') and not shutil.which(data['TryExec']): reason = 'Required program is unavailable.'
            if data.get('Type') != 'Application' or not data.get('Exec'): reason = 'No supported application command.'
            user = path.parent == config_home() / 'autostart'
            rows.append(dict(id=identifier, name=data.get('Name', identifier), enabled=data.get('Hidden', 'false').lower() != 'true',
                             reason=reason, source='User' if user else 'System', writable=not (user and path.is_symlink()),
                             reset=user and data.get(MARKER) == 'true', command=data.get('Exec', '')))
        except (ValueError, configparser.Error):
            rows.append(dict(id=identifier, name=identifier, enabled=False, reason='Invalid desktop entry; edit its source.', source=str(path), writable=False, reset=False, command=''))
    return dict(rows=rows, revision=digest([fingerprints, sorted(desktops)]), message='Changes take effect at the next sign-in. Desktop-specific restrictions are preserved. Core compositor services are managed separately.')


def apply(request):
    with locked('startup'):
        state = status(); check_revision(request, state)
        row = next((r for r in state['rows'] if r['id'] == request.get('id')), None)
        if not row or not row['writable']: raise ValueError('This startup entry cannot be edited.')
        source = entries()[row['id']]
        target = config_home() / 'autostart' / row['id']
        if request.get('action') == 'reset' and row['reset']:
            if target.is_symlink(): raise ValueError('Entry changed to a symlink.')
            target.unlink()
        elif request.get('action') == 'enable' and type(request.get('enabled')) is bool:
            text = set_key(source.read_text(), 'Hidden', str(not request['enabled']).lower())
            if source != target: text = set_key(text, MARKER, 'true')
            atomic(target, text)
        else: raise ValueError('Invalid startup request.')


if __name__ == '__main__': cli(status, apply)
