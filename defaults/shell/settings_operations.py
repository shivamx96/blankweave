"""Shared presentation and validation for native system Settings providers."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


def run(args, timeout=20, input=None, codes=(0,)):
    result = subprocess.run(args, input=input, text=True, capture_output=True,
                            timeout=timeout, env={**os.environ, 'LC_ALL': 'C'})
    if result.returncode not in codes:
        raise ValueError((result.stderr or result.stdout or f'{args[0]} failed').strip()[:3000])
    return result.stdout.strip()


def installed(*commands):
    return all(shutil.which(command) for command in commands)


def field(key, label, value='', options=None, secret=False, multiline=False):
    return dict(key=key, label=label, value=str(value), options=options or [], secret=secret, multiline=multiline)


def choice(value, label=None):
    return dict(value=str(value), label=str(label if label is not None else value))


def action(key, label, fields=(), confirm='', cancellable=False):
    return dict(key=key, label=label, fields=list(fields), confirm=confirm,
                cancellable=cancellable)


def state(message='', details=(), actions=(), identity=None):
    return dict(message=message, details=list(details), actions=list(actions), identity=identity)


def require(request, key, pattern=None, maximum=4096):
    value = request.get(key)
    if not isinstance(value, str) or not value or len(value) > maximum or '\0' in value or '\n' in value or '\r' in value:
        raise ValueError(f'Enter a valid {key}.')
    if pattern and not re.fullmatch(pattern, value):
        raise ValueError(f'Invalid {key}.')
    return value


def path_value(request, key, exists=True, directory=False):
    path = Path(require(request, key)).expanduser()
    if not path.is_absolute(): raise ValueError(f'{key} must be an absolute path.')
    if exists and not path.exists(): raise ValueError(f'{key} does not exist.')
    if directory and exists and not path.is_dir(): raise ValueError(f'{key} must be a directory.')
    return path


def select(request, key, values):
    value = require(request, key)
    if value not in values: raise ValueError(f'{key} changed or is unavailable. Refresh and try again.')
    return value


def privileged(action_name, **values):
    return run(['pkexec', '/usr/lib/blankweave/settings-system', action_name],
               input=json.dumps(values), timeout=7200)
