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
STATE = Path(os.environ.get('XDG_RUNTIME_DIR', str(config_home() / 'blankweave/runtime'))) / 'blankweave/notifications-state.json'
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


def set_paused(value):
    if paused() != value: run(['dunstctl', 'set-paused', str(value).lower()])
    if paused() != value: raise ValueError('Dunst did not accept the pause state.')


def observation(actual, period):
    raw = read(STATE)
    state = json.loads(raw) if raw else dict(paused=actual, quiet=period, owned=False)
    if not isinstance(state, dict) or set(state) != {'paused', 'quiet', 'owned'} or any(type(v) is not bool for v in state.values()):
        raise ValueError('Invalid notification session state.')
    if state['paused'] != actual:
        # Another controller owns this decision, even during quiet hours.
        state['owned'] = False
    return state


def transition(state, actual, period):
    state = dict(state)
    wanted = actual
    if period and not state['quiet'] and not actual:
        wanted = True
        state['owned'] = True
    elif not period and state['quiet'] and state['owned']:
        wanted = False
        state['owned'] = False
    state.update(paused=wanted, quiet=period)
    return state


def reconcile(value):
    actual = paused()
    period = quiet(value)
    old_state, old_policy = read(STATE), read(PATH)
    state = observation(actual, False)
    value = dict(value)
    if old_state is None:
        # Restore saved manual DND once per login, never continuously enforce it.
        actual = actual or value['manual']
    elif state['paused'] != actual:
        value['manual'] = actual
    state = transition(state, actual, period)
    written_state = json.dumps(state) + '\n'
    written_policy = json.dumps(value, indent=2) + '\n'
    original_pause = paused()
    try:
        set_paused(state['paused'])
        if old_policy != written_policy: atomic(PATH, written_policy)
        if old_state != written_state: atomic(STATE, written_state)
    except Exception:
        restore(PATH, old_policy, written_policy); restore(STATE, old_state, written_state)
        set_paused(original_pause)
        raise


def status():
    value = policy()
    actual = paused()
    history = json.loads(run(['dunstctl', 'history']))
    names = [r.get('appname', {}).get('data', '') for r in history.get('data', [[]])[0]]
    apps = sorted(set(a for a in names + value['blocked'] if valid_app(a)), key=str.casefold)
    return dict(revision=digest([read(PATH), read(RULES), read(STATE), config_files(), actual]), policy=value,
                paused=actual, quiet=quiet(value), apps=apps, writable=not PATH.is_symlink() and not RULES.is_symlink() and not STATE.is_symlink())


def apply(request):
    with locked('notifications'):
        current = status()
        check_revision(request, current)
        if not current['writable']: raise ValueError('Notification preferences are symlinked; edit their source.')
        value = dict(current['policy'])
        old_state = read(STATE)
        state = observation(current['paused'], current['quiet'])
        # Preserve an existing external pause on the first preferences edit.
        # An observed external change supersedes a previously saved manual value.
        if old_state is None or state['paused'] != current['paused']:
            value['manual'] = current['paused']
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
        if action == 'manual':
            state.update(paused=value['manual'], quiet=quiet(value), owned=False)
        elif action == 'schedule':
            state = transition(state, current['paused'], quiet(value))
        else:
            state['paused'] = current['paused']
        written_state = json.dumps(state) + '\n'
        try:
            atomic(RULES, generated)
            run(['dunstctl', 'reload'])
            atomic(PATH, written)
            set_paused(state['paused'])
            atomic(STATE, written_state)
        except Exception:
            restore(PATH, old, written); restore(RULES, old_rules, generated); restore(STATE, old_state, written_state)
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
                apply(dict(revision=state['revision'], action='manual', value=not state['paused']))
            elif PATH.exists():
                with locked('notifications'): reconcile(policy())
        except Exception as error:
            print(str(error), file=sys.stderr); sys.exit(1)
    else: cli(status, apply)
