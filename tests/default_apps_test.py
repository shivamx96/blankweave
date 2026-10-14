"""Real GIO association transactions in a disposable XDG environment."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HELPER = Path(__file__).resolve().parents[1] / 'defaults/shell/default-apps.py'
TYPES = ['x-scheme-handler/http', 'x-scheme-handler/https', 'text/html']


class DefaultAppsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.env = dict(os.environ, HOME=str(self.root), XDG_CURRENT_DESKTOP='TestDesk')
        for name in ['XDG_CONFIG_HOME', 'XDG_CONFIG_DIRS', 'XDG_DATA_HOME', 'XDG_DATA_DIRS']:
            path = self.root / name
            path.mkdir()
            self.env[name] = str(path)
        self.apps = Path(self.env['XDG_DATA_HOME']) / 'applications'
        self.apps.mkdir()
        for name in ['one', 'two']:
            (self.apps / f'{name}.desktop').write_text(
                f'[Desktop Entry]\nType=Application\nName={name}\nExec=/usr/bin/touch {self.root}/LAUNCHED\nMimeType={";".join(TYPES)};\n')
        (self.apps / 'mimeinfo.cache').write_text('[MIME Cache]\n' + ''.join(f'{mime}=one.desktop;two.desktop;\n' for mime in TYPES))
        system = Path(self.env['XDG_DATA_DIRS']) / 'applications'
        system.mkdir()
        (system / 'mimeapps.list').write_text('[Default Applications]\n' + ''.join(f'{mime}=one.desktop;\n' for mime in TYPES))
        self.path = Path(self.env['XDG_CONFIG_HOME']) / 'mimeapps.list'

    def call(self, command, request=None, success=True):
        result = subprocess.run([sys.executable, str(HELPER), command], input=json.dumps(request) if request else None,
                                env=self.env, text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode == 0, success, result.stderr)
        self.assertFalse((self.root / 'LAUNCHED').exists(), 'Discovery or apply launched an app')
        return result

    def status(self):
        return json.loads(self.call('status').stdout)

    def row(self, status=None):
        return next(r for r in (status or self.status())['rows'] if r['id'] == 'browser')

    def request(self, application='two.desktop'):
        status = self.status()
        return dict(revision=status['revision'], context=status['context'], group='browser', application=application)

    def test_grouped_apply_preserves_fallbacks_and_reset_inherits(self):
        original = '# keep me\n[Default Applications]\ntext/plain=editor.desktop;\nx-scheme-handler/http=one.desktop;\n[Added Associations]\ntext/plain=editor.desktop;\n'
        self.path.write_text(original)
        self.path.chmod(0o640)
        self.assertEqual({a['id'] for a in self.row()['choices']}, {'one.desktop', 'two.desktop'})
        self.call('apply', self.request())
        self.assertTrue(all(a['id'] == 'two.desktop' for a in self.row()['current']))
        self.assertIn('x-scheme-handler/http=two.desktop;one.desktop;', self.path.read_text())
        self.assertIn('# keep me', self.path.read_text())
        self.assertIn('[Added Associations]\ntext/plain=editor.desktop;', self.path.read_text())
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o640)
        self.call('apply', self.request(None))
        self.assertFalse(self.row()['local'])
        self.assertTrue(all(a['id'] == 'one.desktop' for a in self.row()['current']))
        self.assertIn('text/plain=editor.desktop;', self.path.read_text())

    def test_higher_priority_override_rolls_back_exact_bytes(self):
        original = '# original\n[Default Applications]\ntext/plain=editor.desktop;\n'
        self.path.write_text(original)
        self.path.with_name('testdesk-mimeapps.list').write_text('[Default Applications]\nx-scheme-handler/https=one.desktop;\n')
        result = self.call('apply', self.request(), success=False)
        self.assertIn('Previous associations restored', result.stderr)
        self.assertEqual(self.path.read_text(), original)
        self.path.unlink()
        self.call('apply', self.request(), success=False)
        self.assertFalse(self.path.exists())

    def test_stale_app_identity_and_external_preferences(self):
        request = self.request()
        with (self.apps / 'two.desktop').open('a') as file: file.write('Comment=Changed app\n')
        self.call('apply', request, success=False)
        self.assertFalse(self.path.exists())
        request = self.request()
        self.path.write_text('# external change\n')
        self.call('apply', request, success=False)
        self.assertEqual(self.path.read_text(), '# external change\n')

    def test_unavailable_and_partially_supported_apps(self):
        self.call('apply', self.request('missing.desktop'), success=False)
        cache = self.apps / 'mimeinfo.cache'
        cache.write_text(cache.read_text().replace('text/html=one.desktop;two.desktop;', 'text/html=one.desktop;'))
        self.assertEqual([a['id'] for a in self.row()['choices']], ['one.desktop'])
        (self.apps / 'two.desktop').unlink()
        self.assertEqual([a['id'] for a in self.row()['choices']], ['one.desktop'])
        music = next(r for r in self.status()['rows'] if r['id'] == 'music')
        self.assertEqual(music['choices'], [])
        self.assertEqual(music['current'][0]['id'], '')

    def test_symlink_malformed_and_context_rejected(self):
        target = self.root / 'owned'
        target.write_text('# preserved\n')
        self.path.symlink_to(target)
        self.assertFalse(self.status()['writable'])
        self.call('apply', self.request(), success=False)
        self.assertEqual(target.read_text(), '# preserved\n')
        self.path.unlink()
        request = self.request()
        request['context'] = 'another desktop'
        self.call('apply', request, success=False)
        self.path.write_text('[Default Applications]\ntext/html=one.desktop;\ntext/html=two.desktop;\n')
        self.call('status', success=False)


if __name__ == '__main__': unittest.main()
