"""Small shared primitives for Settings helpers; no commands are run on import."""
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
        raise ValueError(f'{path.name} is a symlink; edit its source instead.')
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
    path = config_home() / 'blankweave' / (name + '.lock')
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('a') as stream:
        try: fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error: raise ValueError('Another change is in progress. Try again.') from error
        yield


def check_revision(request, state):
    if not isinstance(request, dict) or request.get('revision') != state['revision']:
        raise ValueError('Settings changed. Refresh and try again.')


def cli(status, apply):
    try:
        if sys.argv[1:] == ['status']: print(json.dumps(status()))
        elif sys.argv[1:] == ['apply']: apply(json.load(sys.stdin))
        else: raise ValueError('Usage: status|apply')
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
