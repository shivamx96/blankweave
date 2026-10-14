#!/usr/bin/env python3
"""Native Settings adapter for the existing Blankweave web-app manager."""
import configparser
import os
from pathlib import Path
import re
import shutil
from urllib.parse import urlsplit
from settings_support import check_revision, cli, digest, locked, run

DATA = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share'))
APPS = DATA / 'applications'
PREFIX = 'blankweave-webapp-'
HELPER = Path(__file__).with_name('webapp.sh')


def status():
    rows, files = [], []
    for path in sorted(APPS.glob(PREFIX + '*.desktop')):
        text = path.read_text()
        files.append([path.name, text, path.is_symlink()])
        parser = configparser.ConfigParser(interpolation=None, delimiters=('=',), comment_prefixes=('#',))
        parser.optionxform = str
        try:
            parser.read_string(text); data = parser['Desktop Entry']
            origin = data.get('X-Blankweave-Webapp', '')
            rows.append(dict(id=path.stem[len(PREFIX):], name=data.get('Name', path.stem), url=data.get('Comment', ''),
                             origin=origin, removable=origin == 'user' and not path.is_symlink()))
        except (configparser.Error, KeyError):
            rows.append(dict(id=path.stem[len(PREFIX):],name=path.name,url='',origin='Invalid entry',removable=False))
    browser = shutil.which(os.environ.get('BLANKWEAVE_WEBAPP_BROWSER', 'helium-browser'))
    return dict(rows=rows, revision=digest(files), browser=bool(browser), message='Web apps open in Helium and share its browser session. Bundled apps are managed by installation updates.' if browser else 'Helium is not installed. Existing entries can be removed, but creating apps requires Helium.')


def slug(name):
    return re.sub('[^a-z0-9]+', '-', name.lower()).strip('-')


def apply(request):
    with locked('webapps'):
        state = status(); check_revision(request, state)
        if request.get('action') == 'create':
            name, url = request.get('name'), request.get('url')
            if not isinstance(name, str) or not name.strip() or len(name) > 100 or any(ord(c) < 32 for c in name):
                raise ValueError('Enter a single-line application name (up to 100 characters).')
            name = name.strip(); identifier = slug(name)
            if not identifier: raise ValueError('The name needs at least one ASCII letter or number.')
            if not isinstance(url, str) or len(url) > 4096 or not re.fullmatch(r'''https?://[^\s"'\\`$]+''', url):
                raise ValueError('Enter an HTTP or HTTPS URL without spaces, quotes, or shell characters.')
            parsed = urlsplit(url)
            if not parsed.hostname or parsed.username or parsed.password: raise ValueError('Use a website address without embedded credentials.')
            if not state['browser']: raise ValueError('Install Helium before adding a web app.')
            path = APPS / (PREFIX + identifier + '.desktop')
            if path.exists() or path.is_symlink(): raise ValueError('An application with this name already exists. Choose another name.')
            run(['bash', str(HELPER), 'install', name, url, '-'], timeout=30)
            if not path.is_file(): raise ValueError('The desktop entry was not created.')
        elif request.get('action') == 'remove':
            row = next((r for r in state['rows'] if r['id'] == request.get('id')), None)
            if not row or not row['removable'] or not re.fullmatch('[a-z0-9-]+', row['id']):
                raise ValueError('Only user-created Blankweave web apps can be removed here.')
            run(['bash', str(HELPER), 'remove', row['id']])
        else: raise ValueError('Invalid web-app request.')


if __name__ == '__main__': cli(status, apply)
