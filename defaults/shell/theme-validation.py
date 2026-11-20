#!/usr/bin/env python3
"""Read-only theme validation shared by discovery, lint and application."""
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import sys
sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location('design', Path(__file__).with_name('theme-design.py'))
design = importlib.util.module_from_spec(spec)
spec.loader.exec_module(design)
from theme_contrast import checks

COLORS = 'canvas barSurface barHighlight panelSurface surface surfaceRaised surfaceHover surfacePressed scrim text textMuted accent accentBright accentSurface outline outlineStrong divider success warning critical'.split()
LOCK = 'panelSurface panelBorder panelShadow hairline inputSurface placeholder text textMuted textShadow accent accentBright'.split()
NUMBERS = {'contrast': (0, 2), 'brightness': (0, 2), 'vibrancy': (0, 1), 'vibrancy_darkness': (0, 1)}
ROOT = {'name', 'description', 'folderColor', 'plymouth', 'modes', 'design'}
MODE = {'label', 'wallpaper', 'ghostty', 'iconTheme', 'cursorTheme', 'colors', 'lock', 'design'}


def validate(path, defaults, contrast=False):
    ident = path.parent.name
    mode = 'all'
    warnings = []
    def fail(key, message):
        raise ValueError(f'{ident} {mode} {key}: {message}')
    def warn(key, message):
        warnings.append(f'{ident} {mode} {key}: warning: {message}')
    def string(value, key):
        if not isinstance(value, str) or not value.strip() or any(ord(c) < 32 for c in value):
            fail(key, 'must be a non-empty string without control characters')
    def color(value, key):
        if not isinstance(value, str) or not re.fullmatch(r'#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?', value):
            fail(key, 'must be #rrggbb or #rrggbbaa')
        return value.lower()
    def artwork(value, key, required=True):
        string(value, key)
        root = path.parent.resolve()
        target = (root / value).resolve()
        if Path(value).is_absolute() or not target.is_relative_to(root):
            fail(key, 'must be a relative path inside the theme directory')
        if not target.is_file():
            # A personal theme without its own wallpaper has always applied,
            # leaving the current wallpaper in place; keep that, but say so.
            if required:
                fail(key, 'must be an existing file inside the theme directory')
            warn(key, 'file does not exist: ' + value)
    try:
        try:
            data = design.read_json(path)
        except ValueError as error:
            fail('theme.json', str(error))
        if not isinstance(data, dict):
            fail('theme', 'must be an object')
        for key in sorted(data.keys() - ROOT):
            warn(key, 'unknown key')
        string(data.get('name'), 'name')
        # A personal theme may leave out the two root-side treatments: the
        # folder colour and the boot splash then simply stay as they are.
        if 'folderColor' in data:
            string(data['folderColor'], 'folderColor')
        if 'plymouth' in data:
            plymouth = data['plymouth']
            if not isinstance(plymouth, dict):
                fail('plymouth', 'must be an object')
            for key in ('logo', 'progressBar'):
                artwork(plymouth.get(key), 'plymouth.' + key)
        modes = data.get('modes')
        if not isinstance(modes, dict):
            fail('modes', 'must be an object')
        for key in sorted(modes.keys() - {'dark', 'light'}):
            warn('modes.' + key, 'unknown key')
        for mode in ('dark', 'light'):
            row = modes.get(mode)
            if not isinstance(row, dict):
                fail('mode', 'must be an object')
            for key in sorted(row.keys() - MODE):
                warn(key, 'unknown key')
            for key in ('label', 'ghostty', 'iconTheme', 'cursorTheme'):
                string(row.get(key), key)
            for key in ('iconTheme', 'cursorTheme'):
                roots = [Path(os.environ.get('BLANKWEAVE_ICONS_DIR', '/usr/share/icons')), Path.home() / '.local/share/icons', Path.home() / '.icons']
                if not any((root / row[key]).is_dir() for root in roots):
                    warn(key, 'theme is not installed: ' + row[key])
            artwork(row.get('wallpaper'), 'wallpaper', required=False)
            for block, required in (('colors', COLORS), ('lock', LOCK)):
                values = row.get(block)
                if not isinstance(values, dict):
                    fail(block, 'must be an object')
                for key in required:
                    values[key] = color(values.get(key), block + '.' + key)
                for key, value in list(values.items()):
                    if block == 'lock' and key in NUMBERS:
                        low, high = NUMBERS[key]
                        if type(value) not in (int, float) or not math.isfinite(value) or not low <= value <= high:
                            fail(block + '.' + key, f'must be a finite number between {low} and {high}')
                    elif key not in required:
                        if block == 'colors' or isinstance(value, str):
                            values[key] = color(value, block + '.' + key)
                        else:
                            fail(block + '.' + key, 'unknown numeric lock value')
                if block == 'lock':
                    for key in ('contrast', 'brightness', 'vibrancy'):
                        if key not in values:
                            fail('lock.' + key, 'is required')
            try:
                design.resolve(defaults, data, mode)
            except (ValueError, TypeError, KeyError) as error:
                fail('design', str(error))
            if contrast:
                for key, actual, minimum in checks(row):
                    if actual < minimum:
                        fail(key, f'{actual:.3f}:1 < {minimum}:1')
        for warning in warnings:
            print(warning, file=sys.stderr)
        return data
    except (OSError, json.JSONDecodeError) as error:
        fail('theme.json', str(error))


def main():
    path, defaults = map(Path, sys.argv[1:3])
    data = validate(path, design.read_json(defaults), '--contrast' in sys.argv[3:])
    print(json.dumps(data, allow_nan=False))

if __name__ == '__main__':
    try:
        main()
    except (ValueError, TypeError, KeyError) as error:
        print(str(error).replace('\n', ' '), file=sys.stderr)
        sys.exit(1)
