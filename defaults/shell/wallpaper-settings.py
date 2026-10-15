#!/usr/bin/env python3
"""Persistent per-display wallpaper overrides on top of theme wallpapers."""
import json
from pathlib import Path
import re
import sys
from settings_support import atomic, check_revision, cli, config_home, digest, locked, read, restore, run

PATH = config_home() / 'blankweave/wallpapers.json'
FITS = ['crop', 'fit', 'stretch', 'no']


def preferences():
    value = json.loads(read(PATH) or '{}')
    if not isinstance(value, dict): raise ValueError('Invalid wallpaper preferences.')
    for key, row in value.items():
        if not isinstance(row, dict) or row.get('fit') not in FITS or not isinstance(row.get('path'), str):
            raise ValueError('Invalid saved wallpaper.')
    return value


def monitors():
    rows = json.loads(run(['hyprctl', 'monitors', '-j']))
    result = []
    for row in rows:
        name = row['name']
        if not re.fullmatch(r'[A-Za-z0-9_-]+', name): continue
        identity = row.get('description') or name
        # Identical displays without unique EDID descriptions need connector keys.
        if sum((r.get('description') or r['name']) == identity for r in rows) > 1: identity += ' @ ' + name
        result.append(dict(name=name, id=identity, label=identity + ' (' + name + ')'))
    return result


def theme_path():
    value = json.loads(read(config_home() / 'blankweave/theme.json') or '{}').get('wallpaper', '')
    return value


def current_images():
    images = {}
    for line in run(['awww', 'query']).splitlines():
        match = re.match(r'^:?\s*([^:]+):.*currently displaying: image: (.*)$', line)
        if match: images[match[1]] = match[2]
    return images


def status():
    saved, screens, images = preferences(), monitors(), current_images()
    rows = []
    for screen in screens:
        custom = saved.get(screen['id'])
        rows.append(dict(**screen, custom=custom is not None, path=custom['path'] if custom else theme_path(),
                         fit=custom['fit'] if custom else 'crop', current=images.get(screen['name'], '')))
    return dict(rows=rows, revision=digest([read(PATH), screens, theme_path(), images]), writable=not PATH.is_symlink(),
                message='Custom images persist across theme changes and reconnects. Reset follows the theme. The lock screen continues to use the theme/cycle wallpaper.')


def paint(name, path, fit):
    path = Path(path).expanduser().resolve()
    if not path.is_file() or path.suffix.lower() not in ['.png', '.jpg', '.jpeg', '.webp']:
        raise ValueError('Choose an existing PNG, JPEG, or WebP image.')
    if any(c in str(path) for c in '\r\n'): raise ValueError('Image paths cannot contain newlines.')
    run(['awww', 'img', str(path), '--outputs', name, '--resize', fit, '--transition-type', 'none'], timeout=30)
    if current_images().get(name) != str(path): raise ValueError('Wallpaper daemon did not confirm the image.')


def apply(request):
    with locked('wallpaper'):
        state = status(); check_revision(request, state)
        if not state['writable']: raise ValueError('Wallpaper preferences are symlinked; edit their source.')
        row = next((r for r in state['rows'] if r['id'] == request.get('id')), None)
        if not row: raise ValueError('Display disconnected. Refresh and try again.')
        saved = preferences()
        if request.get('action') == 'reset':
            saved.pop(row['id'], None); path, fit = theme_path(), 'crop'
        elif request.get('action') == 'set' and request.get('fit') in FITS and isinstance(request.get('path'), str):
            path, fit = str(Path(request['path']).expanduser().resolve()), request['fit']
            saved[row['id']] = dict(path=path, fit=fit)
        else: raise ValueError('Invalid wallpaper request.')
        old = read(PATH); written = json.dumps(saved, indent=2) + '\n'
        try:
            paint(row['name'], path, fit)
            atomic(PATH, written)
        except Exception:
            restore(PATH, old, written)
            if row['current'] and any(s['id'] == row['id'] and s['name'] == row['name'] for s in monitors()):
                paint(row['name'], row['current'], row['fit'])
            raise


def restore_saved(output=''):
    with locked('wallpaper'):
        saved = preferences()
        for screen in monitors():
            if output and screen['name'] != output: continue
            if screen['id'] in saved:
                row = saved[screen['id']]
                paint(screen['name'], row['path'], row['fit'])


if __name__ == '__main__':
    if sys.argv[1:2] == ['restore']:
        try:
            if PATH.exists(): restore_saved(sys.argv[2] if len(sys.argv) > 2 else '')
        except Exception as error: print(str(error), file=sys.stderr); sys.exit(1)
    else: cli(status, apply)
