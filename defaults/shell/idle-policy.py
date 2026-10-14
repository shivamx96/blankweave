#!/usr/bin/env python3
"""User-owned idle preferences and supervision of one Hypridle child."""
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

DELAYS = (0, 60, 120, 150, 300, 360, 600, 900, 1800, 3600, 7200)

DPMS_ON = "hyprctl dispatch 'hl.dsp.dpms({action = \"on\"})'"
DPMS_OFF = "hyprctl dispatch 'hl.dsp.dpms({action = \"off\"})'"


def normalize(base):
    # Managed templates predate Lua-only dispatch. Keep their timing policy.
    return base.replace('hyprctl dispatch dpms on', DPMS_ON).replace('hyprctl dispatch dpms off', DPMS_OFF)


def save(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)


def validate(value):
    if (not isinstance(value, dict) or set(value) != {'version', 'ac', 'battery'}
            or type(value['version']) is not int or value['version'] != 1):
        raise ValueError('Invalid idle preferences. Check idle.json.')
    for mode in ('ac', 'battery'):
        row = value[mode]
        if (not isinstance(row, dict) or set(row) != {'dim', 'lock', 'screen', 'suspend'}
                or any(type(v) is not int or v not in DELAYS for v in row.values())):
            raise ValueError('Invalid idle timeout. Check idle.json.')
    return value


def supply(directory=Path('/sys/class/power_supply')):
    """Require positive AC evidence; an empty/unknown battery is not AC."""
    batteries, online = [], False
    for device in directory.iterdir() if directory.exists() else []:
        try:
            if (device / 'scope').exists() and (device / 'scope').read_text().strip() == 'Device':
                continue
            kind = (device / 'type').read_text().strip()
            if kind == 'Battery':
                if not (device / 'present').exists() or (device / 'present').read_text().strip() == '1':
                    batteries.append((device / 'status').read_text().strip())
            elif (device / 'online').exists() and (device / 'online').read_text().strip() == '1':
                online = True
        except OSError:
            # A disappearing or unreadable battery must not be mistaken for AC.
            return True, 'battery'
    if not batteries:
        return False, 'ac'
    if any(state == 'Discharging' for state in batteries):
        return True, 'battery'
    return True, 'ac' if online or all(state == 'Charging' for state in batteries) else 'battery'


def render(base, row):
    """Render only managed templates; retain manual and pre-suspend protection."""
    import re
    # Only exact managed templates are passed here, never a user override.
    base = normalize(base)
    blocks = re.findall(r'^listener\s*\{.*?^}', base, re.MULTILINE | re.DOTALL)
    deadlines = [row[key] for key in ('screen', 'suspend') if row[key]]
    lock = min([row['lock']] + [max(1, v - 1) for v in deadlines]) if row['lock'] else 0
    general = re.search(r'^general\s*\{.*?^}', base, re.MULTILINE | re.DOTALL)[0]
    if 'after_sleep_cmd' not in general:
        general = general[:-1] + '    after_sleep_cmd = ' + DPMS_ON + '\n}'
    result = [general]
    for block in blocks:
        if 'brightness.sh dim' in block and row['dim']:
            delay = min([row['dim']] + [max(1, v // 2) for v in deadlines + ([lock] if lock else [])])
            result.append(re.sub(r'timeout\s*=\s*\d+', f'timeout = {delay}', block, count=1))
    if lock:
        result.append(f'listener {{\n    timeout = {lock}\n    on-timeout = loginctl lock-session\n}}')
    if row['screen']:
        result.append(f"listener {{\n    timeout = {row['screen']}\n    on-timeout = {DPMS_OFF}\n    on-resume = {DPMS_ON}\n}}")
    if row['suspend']:
        result.append(f"listener {{\n    timeout = {row['suspend']}\n    on-timeout = systemctl suspend\n}}")
    if len(result) == 1:
        result.append('listener {\n    timeout = 86400\n    on-timeout = /usr/bin/true\n}')
    return '\n\n'.join(result) + '\n'


class Policy:
    def __init__(self):
        config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
        data = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share'))
        self.config = config / 'blankweave/idle.json'
        self.entry = config / 'hypr/hypridle.conf'
        self.base = data / 'blankweave/hypr/hypridle.conf'
        self.runtime = Path(os.environ.get('XDG_RUNTIME_DIR', '/nonexistent')) / 'blankweave-idle'

    def managed(self):
        return self.entry.is_symlink() and self.entry.resolve() == self.base and self.base.is_file()

    def settings(self):
        if self.config.exists():
            return validate(json.loads(self.config.read_text()))
        # Preserve today's installed policy until the user changes a control.
        battery_defaults = 'timeout = 360' in self.base.read_text() if self.base.exists() else False
        row = {'dim': 150 if battery_defaults else 300, 'lock': 300 if battery_defaults else 600,
               'screen': 360 if battery_defaults else 0, 'suspend': 1800 if battery_defaults else 0}
        return {'version': 1, 'ac': dict(row), 'battery': dict(row)}

    def revision(self):
        return hashlib.sha256(self.config.read_bytes() if self.config.exists() else b'').hexdigest()

    @contextmanager
    def locked(self, name):
        self.runtime.mkdir(parents=True, exist_ok=True, mode=0o700)
        with (self.runtime / name).open('a') as stream:
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise ValueError('Another idle settings operation is running.') from error
            yield

    def running(self):
        try:
            with (self.runtime / 'runner.lock').open('a') as stream:
                try:
                    fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    return False
                except BlockingIOError:
                    return True
        except OSError:
            return False

    def status(self):
        settings = self.settings()
        battery, mode = supply()
        state = {}
        try:
            state = json.loads((self.runtime / 'status.json').read_text())
        except (OSError, ValueError):
            pass
        running = self.running()
        fresh = running and 0 <= time.monotonic() - state.get('time', 0) < 15
        managed = self.managed()
        applied = fresh and state.get('revision') == self.revision() and not state.get('error')
        message = ('Your custom Hypridle configuration controls idle behavior.' if not managed else
                   'Sign out and back in to start the updated idle service.' if not running else
                   state.get('error', '') if fresh and state.get('error') else
                   'Idle settings are active.' if applied else 'Waiting for the idle service to apply saved settings…')
        return {'settings': settings, 'revision': self.revision(), 'managed': managed,
                'running': running, 'applied': bool(applied), 'battery': battery,
                'source': mode, 'message': message}

    def configure(self, request):
        if not isinstance(request, dict) or set(request) != {'revision', 'settings'}:
            raise ValueError('Invalid idle settings request.')
        settings = validate(request['settings'])
        with self.locked('write.lock'):
            if not self.managed():
                raise ValueError('A custom Hypridle configuration is active; it has not been changed.')
            if not self.running():
                raise ValueError('The idle service is not running. Sign out and back in first.')
            if request['revision'] != self.revision():
                raise ValueError('Idle settings changed elsewhere. Refresh and try again.')
            save(self.config, json.dumps(settings) + '\n')

    def desired(self):
        if not self.managed() or not self.config.exists():
            return normalize(self.entry.read_text()) if self.managed() else self.entry.read_text(), self.revision()
        settings = self.settings()
        _, mode = supply()
        return render(self.base.read_text(), settings[mode]), self.revision()

    def run(self):
        stop = False
        def finish(_signum, _frame):
            nonlocal stop
            stop = True
        signal.signal(signal.SIGTERM, finish)
        signal.signal(signal.SIGINT, finish)
        with self.locked('runner.lock'):
            child, current, revision, error = None, None, '', ''
            rejected = None
            def terminate():
                if child is not None and child.poll() is None:
                    child.terminate()
                    try:
                        child.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        child.kill()
                        child.wait()
            try:
                while not stop:
                    try:
                        desired, wanted_revision = self.desired()
                        if desired == rejected and child is not None and child.poll() is None:
                            raise ValueError('Hypridle rejected the new policy. The previous installed policy is running; change a timeout or sign in again to retry.')
                        if child is None or child.poll() is not None or desired != current:
                            # Restore any dimming before replacing our own child. Never pkill.
                            if child is not None and self.managed():
                                subprocess.run([str(Path(__file__).with_name('brightness.sh')), 'restore'],
                                               check=False, timeout=5, stdout=subprocess.DEVNULL)
                                subprocess.run(['hyprctl', 'dispatch', 'hl.dsp.dpms({action = "on"})'], check=False,
                                               timeout=5, stdout=subprocess.DEVNULL)
                            terminate()
                            generated = self.runtime / 'hypridle.conf'
                            save(generated, desired)
                            # Custom configs retain their original path and include semantics.
                            path = generated if self.managed() else self.entry
                            child = subprocess.Popen(['hypridle', '-c', str(path)])
                            time.sleep(0.3)
                            if child.poll() is not None:
                                rejected = desired
                                raise ValueError('Hypridle could not start. The installed policy will be used; change a timeout or sign in again to retry.')
                            current = desired
                            rejected = None
                        revision, error = wanted_revision, ''
                    except (OSError, ValueError, subprocess.SubprocessError) as failure:
                        error = str(failure)
                        # If preferences are malformed at login, retain the installed lock policy.
                        if child is None or child.poll() is not None:
                            fallback = self.entry
                            if self.managed():
                                fallback = self.runtime / 'fallback.conf'
                                save(fallback, normalize(self.entry.read_text()))
                            child = subprocess.Popen(['hypridle', '-c', str(fallback)])
                            current = None
                    save(self.runtime / 'status.json', json.dumps({'revision': revision,
                         'error': error, 'time': time.monotonic()}))
                    for _ in range(20):
                        if stop:
                            break
                        time.sleep(0.1)
            finally:
                terminate()
                (self.runtime / 'status.json').unlink(missing_ok=True)


def main():
    policy = Policy()
    if sys.argv[1:] == ['status']:
        print(json.dumps(policy.status()))
    elif sys.argv[1:] == ['configure']:
        policy.configure(json.load(sys.stdin))
    elif sys.argv[1:] == ['run']:
        policy.run()
    else:
        raise ValueError('Usage: idle-policy.py status|configure|run')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
