#!/usr/bin/env python3
"""Discover effective GIO defaults and atomically edit user MIME preferences."""
from runtime_paths import runtime_path
from settings_support import display_path
from contextlib import contextmanager
import configparser
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import shutil
import subprocess
import sys
import tempfile
import gi
gi.require_version('Gio', '2.0')
gi.require_version('GioUnix', '2.0')
from gi.repository import Gio, GioUnix, GLib

GROUPS = [
    ('browser', 'Web browser', ['x-scheme-handler/http', 'x-scheme-handler/https', 'text/html']),
    ('email', 'Email links', ['x-scheme-handler/mailto']),
    ('files', 'File manager', ['inode/directory']),
    ('pdf', 'PDF documents', ['application/pdf']),
    ('text', 'Plain text', ['text/plain']),
    ('images', 'PNG and JPEG images', ['image/png', 'image/jpeg']),
    ('music', 'MP3 audio', ['audio/mpeg']),
    ('video', 'MP4 video', ['video/mp4']),
    ('archives', 'ZIP archives', ['application/zip']),
]
SECTION = 'Default Applications'


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def parse(text):
    parser = configparser.ConfigParser(interpolation=None, delimiters=('=',), comment_prefixes=('#',), strict=True)
    parser.optionxform = str
    parser.read_string(text)
    return parser


def merge(text, types, application):
    """Only change selected default keys; retain comments and other sections."""
    parser = parse(text)
    updates = {}
    for mime in types:
        old = parser.get(SECTION, mime, fallback='').split(';')
        updates[mime] = application + ';' + ''.join(item + ';' for item in old if item and item != application) if application else None
    output, remaining, inside, found = [], dict(updates), False, False
    for line in text.splitlines(keepends=True):
        header = re.match(r'^\s*\[([^]]+)\]', line)
        if header:
            if inside:
                output.extend(f'{key}={value}\n' for key, value in remaining.items() if value is not None)
                remaining.clear()
            inside = header[1] == SECTION
            found |= inside
        key = re.match(r'^\s*([^#\s=]+)\s*=', line)
        if inside and key and key[1] in remaining:
            value = remaining.pop(key[1])
            if value is not None:
                output.append(f'{key[1]}={value}\n')
        else:
            output.append(line if line.endswith('\n') else line + '\n')
    if not found and application:
        output.append('[' + SECTION + ']\n')
    output.extend(f'{key}={value}\n' for key, value in remaining.items() if value is not None)
    result = ''.join(output)
    parse(result)
    return result


def atomic_write(path, text, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix='.mimeapps-', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'w') as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)



def effective_default(mime):
    """One effective-handler lookup for Settings and application shortcuts."""
    return Gio.AppInfo.get_default_for_type(mime, False)


def app_info(app):
    identifier = app.get_id()
    if not isinstance(identifier, str) or not identifier.endswith('.desktop') or any(c in identifier for c in '\n\r;='):
        return None
    filename = app.get_filename() if isinstance(app, GioUnix.DesktopAppInfo) else None
    if not filename or not Path(filename).is_file():
        return None
    return {'id': identifier, 'name': app.get_display_name() or identifier,
            'signature': hashlib.sha256(Path(filename).read_bytes()).hexdigest()}


class Defaults:
    def __init__(self):
        self.config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
        self.path = self.config / 'mimeapps.list'
        self.context = digest({key: os.environ.get(key, '') for key in
            ('HOME', 'XDG_CONFIG_HOME', 'XDG_CONFIG_DIRS', 'XDG_DATA_HOME', 'XDG_DATA_DIRS', 'XDG_CURRENT_DESKTOP')})

    @contextmanager
    def locked(self):
        directory = self.config / 'blankweave'
        directory.mkdir(parents=True, exist_ok=True)
        with (runtime_path('default-apps.lock')).open('a') as stream:
            try: fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error: raise ValueError('Another default-app change is in progress. Try again.') from error
            yield

    def seed(self):
        """Seed missing defaults only; browsers in the desktop profile's order of intent."""
        with self.locked():
            desktops = [d.lower() for d in os.environ.get('XDG_CURRENT_DESKTOP', '').split(':') if d]
            data = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share'))
            paths = [directory / name for directory in (self.config, data / 'applications')
                     for name in ['mimeapps.list'] + [d + '-mimeapps.list' for d in desktops]]
            # A symlink or malformed user file makes the whole seed read-only.
            if any(path.is_symlink() for path in paths):
                print('Skipping MIME defaults: user file is symlinked: ' + ', '.join(display_path(p) for p in paths if p.is_symlink()), file=sys.stderr)
                return
            try:
                parsers = [parse(path.read_text()) for path in paths if path.exists()]
            except (configparser.Error, UnicodeError):
                print('Skipping MIME defaults: malformed user file.', file=sys.stderr)
                return
            old = self.path.read_text() if self.path.exists() else ''
            written = old
            for identifier, prefix in [('mpv.desktop', ('audio/', 'video/')),
                                       ('org.gnome.Loupe.desktop', ('image/',)),
                                       ('org.gnome.Papers.desktop', ('application/pdf',))]:
                try:
                    app = GioUnix.DesktopAppInfo.new(identifier)
                except TypeError:  # PyGObject raises for an absent desktop entry.
                    continue
                if not app:
                    continue
                for mime in app.get_supported_types() or []:
                    if (mime.startswith(prefix) and
                            not any(parser.has_option(SECTION, mime) for parser in parsers)):
                        written = merge(written, [mime], identifier)
            # The desktop profile's browsers. Zen leads because it was the browser
            # key's original target; Helium is last because it also hosts web apps.
            browsers = ['zen.desktop', 'firefox.desktop', 'helium.desktop', 'helium-browser.desktop']
            available = {app.get_id(): app for app in Gio.AppInfo.get_all_for_type('x-scheme-handler/https')
                         if app.should_show()}
            browser = next((key for key in browsers if key in available), None)
            if browser is None:
                browser = next(iter(sorted(available)), None)
            for identifier, types in [(browser, ['x-scheme-handler/http', 'x-scheme-handler/https', 'text/html']),
                                      ('thunar.desktop', ['inode/directory'])]:
                if not identifier:
                    continue
                try:
                    app = GioUnix.DesktopAppInfo.new(identifier)
                except TypeError:
                    continue
                if not app:
                    continue
                for mime in types:
                    if not any(parser.has_option(SECTION, mime) for parser in parsers):
                        written = merge(written, [mime], identifier)
            if written != old:
                mode = stat.S_IMODE(self.path.stat().st_mode) if self.path.exists() else 0o600
                atomic_write(self.path, written, mode)

    def status(self):
        text = self.path.read_text() if self.path.exists() else ''
        parser = parse(text)
        rows = []
        for identifier, label, types in GROUPS:
            choices, current = None, []
            for mime in types:
                apps = {}
                for app in Gio.AppInfo.get_all_for_type(mime):
                    info = app_info(app)
                    if info and app.should_show(): apps[info['id']] = info
                choices = apps if choices is None else {key: val for key, val in choices.items() if key in apps}
                default = effective_default(mime)
                current.append({'type': mime, 'id': default.get_id() or '' if default else '',
                                'name': default.get_display_name() or default.get_id() or '' if default else ''})
            rows.append({'id': identifier, 'label': label, 'types': types, 'current': current,
                         'choices': sorted(choices.values(), key=lambda app: (app['name'].casefold(), app['id'])),
                         'local': any(parser.has_option(SECTION, mime) for mime in types)})
        return {'rows': rows, 'revision': digest([text, rows]), 'context': self.context,
                'writable': not self.path.is_symlink(),
                'message': f'{display_path(self.path)} is a user-owned symlink. Manage it at its source.' if self.path.is_symlink() else ''}

    def fresh_status(self):
        # GIO caches MIME data in-process. Verify in a fresh process after the
        # atomic replacement so a successful write cannot report stale defaults.
        result = subprocess.run([sys.executable, str(Path(__file__).resolve()), 'status'], text=True, capture_output=True, timeout=15)
        if result.returncode:
            raise ValueError(result.stderr.strip() or 'Could not verify default applications.')
        return json.loads(result.stdout)

    def apply(self, request):
        if not isinstance(request, dict) or set(request) != {'revision', 'context', 'group', 'application'}:
            raise ValueError('Invalid default-app request.')
        with self.locked():
            status = self.status()
            if not status['writable']:
                raise ValueError(status['message'])
            if request['revision'] != status['revision'] or request['context'] != self.context:
                raise ValueError('Applications or associations changed. Refresh and try again.')
            row = next((r for r in status['rows'] if r['id'] == request['group']), None)
            if not row:
                raise ValueError('Unknown default-app category.')
            application = request['application']
            if application is not None and (not isinstance(application, str) or application not in [a['id'] for a in row['choices']]):
                raise ValueError('This application is unavailable or does not support every listed type.')
            old = self.path.read_text() if self.path.exists() else None
            mode = stat.S_IMODE(self.path.stat().st_mode) if self.path.exists() else 0o600
            written = merge(old or '', row['types'], application)
            try:
                atomic_write(self.path, written, mode)
                verified = self.fresh_status()
                result = next(r for r in verified['rows'] if r['id'] == row['id'])
                if application and any(r['id'] != application for r in result['current']):
                    raise ValueError('A higher-priority association overrides this choice. Edit the desktop-specific configuration first.')
                if application is None and result['local']:
                    raise ValueError('The user default could not be cleared.')
            except (OSError, ValueError, subprocess.SubprocessError) as failure:
                if not self.path.is_symlink() and self.path.exists() and self.path.read_text() == written:
                    if old is None: self.path.unlink()
                    else: atomic_write(self.path, old, mode)
                    raise ValueError(str(failure) + ' Previous associations restored.') from failure
                raise ValueError(str(failure) + ' Associations changed externally; those changes were preserved.') from failure



def missing(role, detail=None, setting=None):
    labels = {'browser': ('web browser', 'defaults'), 'files': ('file manager', 'defaults'),
              'terminal': ('terminal', 'defaults')}
    label, target = labels.get(role, (detail or role, 'about'))
    target = setting or target
    message = ('No ' + label + ' is installed. Install one, or choose a default in Settings › Apps.'
               if role in labels else label + ' is not installed. Install it to use this action.')
    # One transient notification per attempt; Dunst does not store transient hints.
    result = subprocess.run(['notify-send', '--app-name=Blankweave', '--hint=int:transient:1',
                             '--action=default=Open Settings', '--expire-time=8000', '--wait', 'Application unavailable', message],
                            text=True, capture_output=True, timeout=12)
    if result.stdout.strip() == 'default':
        subprocess.Popen(['blankweave', 'settings', target])
    return 1


def open_role(role, arguments):
    if role == 'missing' and len(arguments) == 2:
        return missing('command', arguments[0], arguments[1])
    if role == 'terminal':
        if not shutil.which('ghostty'):
            return missing(role)
        subprocess.Popen(['ghostty', *arguments])
        return 0
    if role == 'command':
        if not arguments:
            raise ValueError('A command is required.')
        executable = arguments[0]
        nested = arguments[2] if executable == 'ghostty' and len(arguments) > 2 and arguments[1] == '-e' else executable
        if not shutil.which(executable) or not shutil.which(nested):
            return missing(role, nested)
        subprocess.Popen(arguments)
        return 0
    mime = {'browser': 'x-scheme-handler/https', 'files': 'inode/directory'}.get(role)
    if not mime:
        raise ValueError('Unknown application role.')
    app = effective_default(mime)
    if not app or not shutil.which(app.get_executable()):
        return missing(role)
    # Let GIO expand desktop Exec field codes and honour Path. Wrap terminal
    # entries just like Launcher/Launch.js, but retain GIO's URI expansion.
    if isinstance(app, GioUnix.DesktopAppInfo) and app.get_boolean('Terminal'):
        if not shutil.which('ghostty'):
            return missing('terminal')
        key = GLib.KeyFile()
        key.load_from_file(app.get_filename(), GLib.KeyFileFlags.NONE)
        key.set_boolean('Desktop Entry', 'Terminal', False)
        directory = app.get_string('Path')
        prefix = 'ghostty ' + ('--working-directory=' + GLib.shell_quote(directory.replace('%', '%%')) + ' ' if directory else '')
        command = key.get_string('Desktop Entry', 'Exec')
        # The in-memory copy has no filename. Preserve %k's original identity;
        # leave escaped percent signs and all other field codes to GIO.
        command = re.sub(r'%%|%k', lambda match: '%%' if match[0] == '%%'
                         else GLib.shell_quote(app.get_filename().replace('%', '%%')), command)
        key.set_string('Desktop Entry', 'Exec', prefix + '-e ' + command)
        app = GioUnix.DesktopAppInfo.new_from_keyfile(key)
    try:
        if arguments:
            uris = [Gio.File.new_for_path(value).get_uri() if role == 'files' and not GLib.uri_parse_scheme(value) else value
                    for value in arguments]
            app.launch_uris(uris, None)
        else:
            app.launch([], None)
    except GLib.Error:
        return missing(role)
    return 0


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == 'open':
        sys.exit(open_role(sys.argv[2], sys.argv[3:]))
    defaults = Defaults()
    if sys.argv[1:] == ['status']: print(json.dumps(defaults.status()))
    elif sys.argv[1:] == ['seed']: defaults.seed()
    elif sys.argv[1:] == ['apply']: defaults.apply(json.load(sys.stdin))
    else: raise ValueError('Usage: default-apps.py status|apply|seed|open <role> [arguments]')


if __name__ == '__main__':
    try: main()
    except (OSError, ValueError, configparser.Error, GLib.Error, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
