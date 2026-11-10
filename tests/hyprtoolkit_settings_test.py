#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'defaults/shell'))
import hyprtoolkit_settings as toolkit
import gtk_settings


class ToolkitTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        env = patch.dict(os.environ, XDG_CONFIG_HOME=self.temp.name)
        env.start(); self.addCleanup(env.stop)
        self.root = Path(self.temp.name)
        self.path = self.root / 'hypr/hyprtoolkit.conf'
        self.state = self.root / 'blankweave'
        self.state.mkdir()
        self.theme = json.loads((ROOT / 'defaults/themes/obsidian/theme.json').read_text())['modes']['dark']
        self.theme['mode'] = 'dark'
        (self.state / 'theme.json').write_text(json.dumps(self.theme))

    def test_palette_and_sizes_are_shared_and_complete(self):
        for theme in ('obsidian', 'moss'):
            modes = json.loads((ROOT / f'defaults/themes/{theme}/theme.json').read_text())['modes']
            for mode, data in modes.items():
                for scale in (1, 1.15, 1.3):
                    text = toolkit.render(dict(data, mode=mode), {'text_scale': scale}, {})
                    self.assertTrue(toolkit.owned(text))
                    self.assertIn('background = rgba(' + data['colors']['canvas'][1:7] + 'ff)', text)
                    self.assertIn(f'font_size = {int(11 * scale + .5)}', text)
                    self.assertIn('font_family = Atkinson Hyperlegible Next', text)
                    self.assertNotIn('source =', text)

    def test_high_contrast_and_atomic_regular_file(self):
        gtk_settings.write(toolkit.prepare())
        self.assertFalse(self.path.is_symlink())
        first = self.path.read_text()
        gtk_settings.write(toolkit.prepare(interface={'text_scale': 1.3}, accessibility={'high_contrast': True}))
        text = self.path.read_text()
        self.assertNotEqual(text, first)
        self.assertIn('text = rgba(ffffffff)', text)
        self.assertIn('background = rgba(000000ff)', text)
        self.assertIn('font_size = 14', text)
        self.assertTrue(toolkit.owned(text))

    def test_theme_typography_and_user_scaling(self):
        self.theme['design'] = {'typography': {'fontFamily': 'Noto Sans', 'monoFontFamily': 'Noto Sans Mono',
                                             'textSize': 18, 'headingSize': 28, 'microTextSize': 14}}
        text = toolkit.render(self.theme, {'text_scale': 1.3}, {'high_contrast': True})
        self.assertIn('font_family = Noto Sans\n', text)
        self.assertIn('font_family_monospace = Noto Sans Mono\n', text)
        self.assertIn(f'font_size = {int(18 * 11 / 13 * 1.3 + .5)}\n', text)
        self.assertIn(f'h1_size = {int(28 * 19 / 22 * 1.3 + .5)}\n', text)
        self.assertIn('background = rgba(000000ff)', text)

    def test_theme_rounding_and_invalid_shape(self):
        self.theme['design'] = {'shape': {'panelRadius': 0, 'controlRadius': 8}}
        text = toolkit.render(self.theme, {}, {})
        self.assertIn('rounding_large = 0', text)
        self.assertIn('rounding_small = 8', text)
        for value in (None, [], {'panelRadius': -1}, {'controlRadius': True}):
            self.theme['design']['shape'] = value
            with self.assertRaises(ValueError):
                toolkit.render(self.theme, {}, {})

    def test_invalid_typography_never_rewrites_picker(self):
        gtk_settings.write(toolkit.prepare())
        original = self.path.read_bytes()
        for value in ('', 'Font\nsource = /tmp/untrusted', 'Font #comment', '$variable', 'Font{block}',
                      'Font\\name', 'Font=other', 'Font; other', 'x' * 101):
            with self.subTest(value=value):
                self.theme['design'] = {'typography': {'fontFamily': value}}
                with self.assertRaises(ValueError):
                    toolkit.prepare(theme=self.theme)
                self.assertEqual(self.path.read_bytes(), original)
        for value in (True, -1, 100, float('nan'), '13'):
            self.theme['design'] = {'typography': {'textSize': value}}
            with self.assertRaises(ValueError):
                toolkit.prepare(theme=self.theme)
        self.assertEqual(self.path.read_bytes(), original)

    def test_edited_configs_and_foreign_links_are_never_claimed(self):
        gtk_settings.write(toolkit.prepare())
        text = self.path.read_text() + '# My preference\n'
        self.path.write_text(text)
        self.assertEqual(toolkit.prepare(), [])
        self.assertIn('personal Hyprtoolkit', toolkit.ownership_message())
        self.assertEqual(self.path.read_text(), text)
        self.path.unlink()
        target = self.root / 'personal.conf'
        target.write_text(toolkit.render(self.theme, {}, {}))
        self.path.symlink_to(target)
        self.assertEqual(toolkit.prepare(), [])
        self.assertTrue(self.path.is_symlink())
        self.path.unlink(); self.path.symlink_to(self.root / 'missing')
        self.assertEqual(toolkit.prepare(), [])

    def test_unreadable_or_non_utf8_personal_config_is_preserved(self):
        self.path.parent.mkdir()
        self.path.write_bytes(b'\xffpersonal config')
        self.assertEqual(toolkit.prepare(), [])
        self.assertIn('personal Hyprtoolkit', toolkit.ownership_message())
        self.assertEqual(self.path.read_bytes(), b'\xffpersonal config')
        with patch.object(Path, 'read_text', side_effect=PermissionError('private file')):
            self.assertEqual(toolkit.prepare(), [])

    def test_bad_values_do_not_rewrite_existing_config(self):
        gtk_settings.write(toolkit.prepare())
        original = self.path.read_text()
        for interface, accessibility in [({'text_scale': 9}, {}), ({}, {'high_contrast': 'true'})]:
            with self.assertRaises(ValueError): toolkit.prepare(interface, accessibility)
        self.assertEqual(self.path.read_text(), original)
        (self.state / 'theme.json').unlink()
        self.assertEqual(toolkit.prepare(), [])


if __name__ == '__main__': unittest.main()
