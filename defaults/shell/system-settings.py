#!/usr/bin/env python3
"""Read-only system details and explicitly requested, unprivileged diagnostics."""
import datetime
import json
import os
from pathlib import Path
import platform
import re
import subprocess
from settings_support import atomic, check_revision, cli, digest, locked, read

COMMAND = Path.home() / '.local/bin/blankweave'
STATE = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'blankweave'
REPORT = STATE / 'settings-diagnostics.json'


def details():
    try: distro = platform.freedesktop_os_release().get('PRETTY_NAME', 'Linux')
    except OSError: distro = 'Linux'
    cpu, memory = 'Unavailable', 'Unavailable'
    try:
        for line in Path('/proc/cpuinfo').read_text().splitlines():
            if line.startswith('model name') or line.startswith('Hardware'):
                cpu = line.split(':', 1)[1].strip(); break
        match = re.search(r'^MemTotal:\s+(\d+) kB', Path('/proc/meminfo').read_text(), re.M)
        if match: memory = f'{int(match[1]) / 1024 / 1024:.1f} GiB'
    except OSError: pass
    return [dict(label='Operating system', value=distro), dict(label='Kernel', value=platform.release()),
            dict(label='Architecture', value=platform.machine()), dict(label='Processor', value=cpu),
            dict(label='Memory', value=memory), dict(label='Desktop', value=os.environ.get('XDG_CURRENT_DESKTOP', 'Unknown')),
            dict(label='Installed Blankweave', value=(read(STATE / 'installed-version') or 'Not recorded').strip()),
            dict(label='Installed revision', value=(read(STATE / 'installed-revision') or 'Not recorded').strip())]


def status():
    report = json.loads(read(REPORT) or 'null')
    if report is not None and (not isinstance(report, dict) or not isinstance(report.get('text'), str)
                              or type(report.get('code')) is not int or not isinstance(report.get('time'), str)):
        raise ValueError('Saved diagnostics report is invalid.')
    return dict(details=details(), report=report, revision=digest(read(REPORT)), available=COMMAND.is_file() and os.access(COMMAND, os.X_OK),
                writable=not REPORT.is_symlink(), message='Diagnostics run only when requested, without elevation. Protected checks may be skipped. Reports remain on this computer until you copy them.')


def apply(request):
    with locked('system-diagnostics'):
        state = status(); check_revision(request, state)
        if not state['writable']: raise ValueError('Diagnostics report is symlinked; edit its source.')
        if request.get('action') != 'diagnose': raise ValueError('Invalid diagnostics request.')
        if not state['available']: raise ValueError('The Blankweave command is not installed.')
        result = subprocess.run([str(COMMAND), 'doctor', '--normal', '--report'], text=True, capture_output=True, timeout=90)
        # Doctor returns nonzero for findings. Preserve those findings instead of
        # turning a completed check into an empty error panel.
        text = (result.stdout + ('\n' + result.stderr if result.stderr else '')).strip()
        if not text: raise ValueError('Diagnostics produced no report.')
        if len(text) > 262144: text = text[:262144] + '\n[Report truncated]'
        report = dict(time=datetime.datetime.now().astimezone().isoformat(timespec='seconds'), code=result.returncode, text=text)
        atomic(REPORT, json.dumps(report, indent=2) + '\n')


if __name__ == '__main__': cli(status, apply)
