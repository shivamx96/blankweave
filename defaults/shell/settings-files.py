#!/usr/bin/env python3
"""Read-only storage metadata for Settings; never edits a configuration file."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def resolve(value):
    if value.startswith('~/.config/'):
        return Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config') / value[len('~/.config/'):]
    raise ValueError('Expected a catalog configuration path')


def display(path):
    return str(path).replace(str(Path.home()) + '/', '~/', 1) if path.is_relative_to(Path.home()) else str(path)


def info(value):
    path = resolve(value)
    return dict(path=str(path), display=display(path), exists=path.is_file(), folder=str(path.parent))


def metadata():
    catalog = Path(__file__).parent.parent / 'quickshell/Settings/Catalog.js'
    values = set(re.findall(r'"(~/.config/[^"\n]+)"', catalog.read_text()))
    files = {value: info(value) for value in values}
    overrides = {}
    def add(ids, path):
        if path.is_file():
            for id in ids.split(): overrides.setdefault(id, []).append(dict(path=str(path), display=display(path)))
    config = resolve('~/.config/blankweave')
    hypr = 'scale arrangement mirroring resolution color-profile display-presets layouts shortcuts pointer cursor fonts large-text contrast motion sound-alerts'
    add(hypr, config / 'overrides/hyprland.lua')
    add('theme mode', config / 'overrides/ghostty.conf')
    add('theme mode dnd notifications', config / 'overrides/dunst.conf')
    data = Path(os.environ.get('XDG_DATA_HOME') or Path.home() / '.local/share') / 'blankweave'
    for ids, entry, managed in [('screen-off', 'hypr/hypridle.conf', 'hypr/hypridle.conf'),
                                (hypr, 'hypr/hyprland.lua', 'hypr/entry.lua'),
                                ('theme mode', 'ghostty/config', 'ghostty/config'),
                                ('theme mode dnd notifications', 'dunst/dunstrc', 'dunst/dunstrc')]:
        path = resolve('~/.config/' + entry)
        if path.exists() and path.resolve() != (data / managed).resolve(): add(ids, path)
    try:
        theme = json.loads((config / 'theme.json').read_text())['theme']
        if re.fullmatch('[a-zA-Z0-9_-]+', theme): add('theme mode wallpaper', config / 'themes' / theme / 'theme.json')
    except (OSError, ValueError, KeyError, TypeError): pass
    return dict(files=files, overrides=overrides)


if __name__ == '__main__':
    if sys.argv[1:] == ['status']:
        print(json.dumps(metadata()))
    elif len(sys.argv) == 3 and sys.argv[1] == 'open':
        value = metadata()['files'].get(sys.argv[2])
        if not value or not value['exists']: sys.exit(1)
        subprocess.run(['xdg-open', value['folder']], check=True)
    else: sys.exit(2)
