"""Small shared primitives for Settings helpers; no commands are run on import."""
from runtime_paths import runtime_path
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def config_home():
    return Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def run(args, timeout=15):
    result = subprocess.run(args, text=True, capture_output=True, timeout=timeout)
    if result.returncode:
        raise ValueError(result.stderr.strip() or result.stdout.strip() or f'{args[0]} failed')
    return result.stdout.strip()


def atomic(path, text):
    path = Path(path)
    if path.is_symlink():
        raise file_refusal('This file is a symlink; edit its source instead.', path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.settings-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, path.stat().st_mode & 0o777 if path.exists() else 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)


def read(path):
    return path.read_text() if path.exists() else None


def restore(path, old, written):
    if not path.is_symlink() and read(path) == written:
        if old is None: path.unlink(missing_ok=True)
        else: atomic(path, old)


@contextmanager
def locked(name):
    path = runtime_path(name + '.lock')
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('a') as stream:
        try: fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error: raise ValueError('Another change is in progress. Try again.') from error
        yield


def check_revision(request, state):
    if not isinstance(request, dict) or request.get('revision') != state['revision']:
        raise ValueError('Settings changed. Refresh and try again.')


def cli(status, apply):
    request = {}
    try:
        if sys.argv[1:] == ['status']: print(json.dumps(status()))
        elif sys.argv[1:] == ['apply']:
            request = json.load(sys.stdin)
            apply(request)
        else: raise ValueError('Usage: status|apply')
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        secrets = [v for k, v in request.items() if any(word in k.lower() for word in ("password", "secret", "token", "credential"))] if isinstance(request, dict) else []
        print(json.dumps({"error": error_result(error, secrets)}))
        print(safe_detail(error, secrets), file=sys.stderr)
        sys.exit(1)


class SettingsError(ValueError):
    """A user sentence with optional diagnostic context and a field identity."""
    def __init__(self, message, detail='', field=None, cancelled=False):
        super().__init__(message)
        self.message, self.detail, self.field, self.cancelled = message, detail, field, cancelled


def safe_detail(text, secrets=()):
    import re
    text = str(text).replace(str(Path.home()), "~")
    for secret in secrets:
        if secret: text = text.replace(str(secret), '[redacted]')
    text = re.sub(r'/home/[^\s/]+(?:/[^\s\"\']*)?|/root(?:/[^\s\"\']*)?', '~', text)
    text = re.sub(r'(?i)(password|passwd|token|secret|psk|credential)(\s*[=:]\s*)[^\s,;]+', r'\1\2[redacted]', text)
    if 'Traceback (most recent call last)' in text: text = text.splitlines()[-1]
    return text[:4000]


class FileRefusal(SettingsError):
    """Session-only explanation naming a user file; never persist its path."""


def display_path(path):
    path = Path(path)
    try: return '~/' + str(path.relative_to(Path.home()))
    except ValueError: return str(path)


def file_refusal(message, *paths):
    return FileRefusal(message + ' File: ' + ', '.join(display_path(p) for p in paths))


def error_result(error, secrets=(), shareable=False):
    if shareable and isinstance(error, FileRefusal):
        return dict(message='A personal configuration file prevents this change.', detail='')
    raw = str(error)
    lower = raw.lower()
    cancelled = isinstance(error, SettingsError) and error.cancelled
    if isinstance(error, SettingsError): message = error.message
    elif any(x in lower for x in ('cancelled', 'canceled', 'dismissed', 'not authorized to perform operation')):
        message = 'Cancelled'; cancelled = True
    elif any(x in lower for x in ('secrets were required', 'wrong password', 'incorrect password', 'authentication failed', 'password was not accepted')):
        message = 'The password was not accepted.'
    elif any(x in lower for x in ('no longer in range', 'access point not found', 'no network with ssid')):
        message = 'That network is no longer in range.'
    elif 'networkmanager' in lower and any(x in lower for x in ('unavailable', 'reach', 'not running', 'failed', 'serviceunknown')):
        message = 'Could not reach NetworkManager.'
    elif isinstance(error, subprocess.TimeoutExpired): message = 'The service took too long to respond. Try again.'
    elif isinstance(error, PermissionError): message = 'You do not have permission to make this change.'
    elif isinstance(error, FileNotFoundError): message = 'A required file or program is unavailable.'
    elif raw.startswith(('Enter a valid ', 'Settings changed.', 'Another change is in progress.', 'Passwords do not match.', 'Review and confirm ')):
        message = raw
    else: message = 'Could not apply this change. Try again.'
    result = dict(message=safe_detail(message, secrets), detail=safe_detail(getattr(error, 'detail', '') or raw, secrets))
    if getattr(error, 'field', None): result['field'] = error.field
    if cancelled: result.update(cancelled=True, detail='')
    return result
