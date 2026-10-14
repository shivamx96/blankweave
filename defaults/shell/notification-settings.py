#!/usr/bin/env python3
"""Persistent notification policy shared by Settings and the desktop bar."""
import datetime
import json
import os
from pathlib import Path
import re
import sys
from settings_support import atomic, check_revision, cli, config_home, digest, locked, read, restore, run

PATH = config_home() / 'blankweave/notifications.json'
RULES = config_home() / 'dunst/dunstrc.d/90-blankweave-notifications.conf'
DEFAULT = dict(manual=False, schedule=False, start='22:00', end='08:00', blocked=[])


def policy():
    value = json.loads(read(PATH) or json.dumps(DEFAULT))
    if set(value) != set(DEFAULT) or any(type(value[k]) is not bool for k in ['manual', 'schedule']):
        raise ValueError('Invalid notification preferences.')
    for key in ['start', 'end']:
        if not isinstance(value[key], str) or not re.fullmatch(r'(?:[01][0-9]|2[0-3]):[0-5][0-9]', value[key]):
            raise ValueError('Use a time between 00:00 and 23:59.')
    if value['start'] == value['end']: raise ValueError('Quiet hours must have different start and end times.')
    if not isinstance(value['blocked'], list) or any(not valid_app(a) for a in value['blocked']):
        raise ValueError('Unsupported notification application name.')
    return value


def valid_app(name):
    return isinstance(name, str) and 0 < len(name) <= 200 and not any(c in name for c in '\n\r\t"\\')


def quiet(value, now=None):
    minute = (now or datetime.datetime.now()).strftime('%H:%M')
    start, end = value['start'], value['end']
    return value['schedule'] and (start <= minute < end if start < end else minute >= start or minute < end)


def config_files():
    bases = [Path(p) for p in os.environ.get('XDG_CONFIG_DIRS', '/etc/xdg').split(':') if p]
    result = []
    for base in list(reversed(bases)) + [config_home()]:
        for path in [base / 'dunst/dunstrc'] + sorted((base / 'dunst/dunstrc.d').glob('*.conf')):
            if path != RULES and path.exists(): result.append((str(path), path.read_text()))
    return result


def rules(value):
    regex = False
    pcre = False
    for _, text in config_files():
        for key, setting in re.findall(r'^\s*(enable_posix_regex|enable_pcre_regex)\s*=\s*(true|false)', text, re.M):
            if key == 'enable_posix_regex': regex = setting == 'true'
            else: pcre = setting == 'true'
    lines = ['# Managed by Blankweave notification settings.\n']
    for app in sorted(set(value['blocked'])):
        pattern = '^' + re.escape(app) + '$' if regex or pcre else ''.join({'[': '[[]', '*': '[*]', '?': '[?]'}.get(c, c) for c in app)
        lines.append(f'[blankweave-muted-{digest(app)[:16]}]\nappname = "{pattern}"\nskip_display = true\n')
    return '\n'.join(lines)


def paused():
    value = run(['dunstctl', 'is-paused'])
    if value not in ['true', 'false']: raise ValueError('Dunst returned an invalid pause state.')
    return value == 'true'


def reconcile(value):
    wanted = value['manual'] or quiet(value)
    if paused() != wanted: run(['dunstctl', 'set-paused', str(wanted).lower()])
    if paused() != wanted: raise ValueError('Dunst did not accept the pause state.')


def status():
    value = policy()
    actual = paused()
    history = json.loads(run(['dunstctl', 'history']))
    names = [r.get('appname', {}).get('data', '') for r in history.get('data', [[]])[0]]
    apps = sorted(set(a for a in names + value['blocked'] if valid_app(a)), key=str.casefold)
    return dict(revision=digest([read(PATH), read(RULES), config_files(), actual]), policy=value,
                paused=actual, quiet=quiet(value), apps=apps, writable=not PATH.is_symlink() and not RULES.is_symlink())


def apply(request):
    with locked('notifications'):
        current = status()
        check_revision(request, current)
        if not current['writable']: raise ValueError('Notification preferences are symlinked; edit their source.')
        value = dict(current['policy'])
        action = request.get('action')
        if action == 'manual' and type(request.get('value')) is bool: value['manual'] = request['value']
        elif action == 'schedule':
            value.update(schedule=request.get('enabled'), start=request.get('start'), end=request.get('end'))
        elif action == 'app' and valid_app(request.get('app')) and type(request.get('blocked')) is bool:
            app = request['app']
            if app not in current['apps']: raise ValueError('Application is no longer in notification history.')
            value['blocked'] = sorted((set(value['blocked']) | {app}) if request['blocked'] else (set(value['blocked']) - {app}))
        else: raise ValueError('Invalid notification request.')
        # Validate the entire candidate before touching any file.
        old, old_rules = read(PATH), read(RULES)
        written = json.dumps(value, indent=2) + '\n'
        # policy validation is reusable without reading a candidate from disk.
        validate(value)
        generated = rules(value)
        try:
            atomic(RULES, generated)
            run(['dunstctl', 'reload'])
            atomic(PATH, written)
            reconcile(value)
        except Exception:
            restore(PATH, old, written); restore(RULES, old_rules, generated)
            run(['dunstctl', 'reload'])
            run(['dunstctl', 'set-paused', str(current['paused']).lower()])
            raise


def validate(value):
    if type(value['schedule']) is not bool: raise ValueError('Invalid quiet-hours state.')
    for key in ['start', 'end']:
        if not isinstance(value[key], str) or not re.fullmatch(r'(?:[01][0-9]|2[0-3]):[0-5][0-9]', value[key]):
            raise ValueError('Use HH:MM in 24-hour time.')
    if value['start'] == value['end']: raise ValueError('Quiet hours need different start and end times.')


if __name__ == '__main__':
    if sys.argv[1:] in [['tick'], ['toggle']]:
        try:
            if sys.argv[1] == 'toggle':
                state = status()
                apply(dict(revision=state['revision'], action='manual', value=not state['policy']['manual']))
            elif PATH.exists():
                with locked('notifications'): reconcile(policy())
        except Exception as error:
            print(str(error), file=sys.stderr); sys.exit(1)
    else: cli(status, apply)
