#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'defaults/shell/system-sounds.py'
GTK = ROOT / 'defaults/shell/gtk_settings.py'


class SoundSettings(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.state = self.root / 'state.json'
        self.state.write_text(json.dumps({'event-sounds': True, 'input-feedback-sounds': False, 'theme-name': 'freedesktop'}))
        self.env = dict(os.environ, HOME=str(self.root), XDG_CONFIG_HOME=str(self.root / 'config'),
                        XDG_DATA_HOME=str(self.root / 'data'), XDG_DATA_DIRS=str(self.root / 'system'),
                        DBUS_SESSION_BUS_ADDRESS='unix:path=' + str(self.root / 'no-bus'),
                        SOUND_STATE=str(self.state), SOUND_LOG=str(self.root / 'calls'), PATH=str(self.bin) + ':' + os.environ['PATH'])
        self.script('gsettings', '''import ast,json,os,sys
from pathlib import Path
p=Path(os.environ['SOUND_STATE']); data=json.loads(p.read_text())
action, schema, key = sys.argv[1:4]
assert schema == 'org.gnome.desktop.sound'
with open(os.environ['SOUND_LOG'],'a') as log: log.write(json.dumps(sys.argv[1:])+'\\n')
if os.environ.get('FAIL') == action: sys.exit(1)
if action == 'get': print(repr(data[key]) if isinstance(data[key],str) else str(data[key]).lower())
elif action == 'writable': print('false' if os.environ.get('READ_ONLY') else 'true')
elif action == 'set' and not os.environ.get('IGNORE_WRITE'):
 data[key] = ast.literal_eval(sys.argv[4]) if key == 'theme-name' else sys.argv[4]=='true'; p.write_text(json.dumps(data))
''')
        self.script('canberra-gtk-play', '''import json,os,sys
with open(os.environ['SOUND_LOG'],'a') as log: log.write(json.dumps(sys.argv)+'\\n')
sys.exit(1 if os.environ.get('FAIL_PREVIEW') else 0)
''')
        self.theme('system', 'freedesktop', 'Default')
        self.theme('data', 'custom', 'Custom')

    def script(self, name, code):
        path = self.bin / name
        path.write_text('#!/usr/bin/env python3\n' + code)
        path.chmod(0o755)

    def theme(self, root, name, label):
        path = self.root / root / 'sounds' / name
        path.mkdir(parents=True, exist_ok=True)
        (path / 'index.theme').write_text('[Sound Theme]\nName=' + label + '\nDirectories=stereo\n')
        return path

    def call(self, *args, success=True, **environment):
        result = subprocess.run([sys.executable, str(HELPER), *args], env=dict(self.env, **environment), text=True, capture_output=True)
        self.assertEqual(result.returncode == 0, success, result.stderr)
        return result

    def test_discovery_and_status_are_read_only(self):
        self.theme('data', 'freedesktop', 'User default')
        (self.theme('data', 'hidden', 'Hidden') / 'index.theme').write_text('[Sound Theme]\nName=Hidden\nHidden=true\n')
        data = json.loads(self.call('status').stdout)
        self.assertEqual(data['themes'], [{'id':'custom','name':'Custom'}, {'id':'freedesktop','name':'User default'}])
        self.assertFalse(data['gtkSynced'])
        self.assertTrue(data['previewAvailable'])
        self.assertFalse((self.root / 'config').exists())

    def test_toggle_sync_and_theme_changes_preserve_other_settings(self):
        directory = self.root / 'config/gtk-3.0'
        directory.mkdir(parents=True)
        target = self.root / 'custom-gtk.ini'
        target.write_text('# Keep this comment\n[Settings]\ngtk-font-name=Custom 12\n[Other]\nvalue=hello\n')
        (directory / 'settings.ini').symlink_to(target)
        self.call('set', 'event-sounds', 'false')
        self.assertFalse(json.loads(self.state.read_text())['event-sounds'])
        self.assertTrue((directory / 'settings.ini').is_symlink())
        self.assertIn('gtk-enable-event-sounds=false', target.read_text())
        self.assertIn('gtk-font-name=Custom 12', target.read_text())
        self.assertIn('# Keep this comment', target.read_text())
        self.call('set', 'theme-name', 'custom')
        self.call('set', 'input-feedback-sounds', 'true')
        result = subprocess.run([sys.executable, str(GTK), 'gtk-theme-name=Adwaita', 'gtk-application-prefer-dark-theme=1'], env=self.env, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('gtk-sound-theme-name=custom', target.read_text())
        self.assertIn('gtk-enable-input-feedback-sounds=true', target.read_text())
        self.assertTrue(json.loads(self.call('status').stdout)['gtkSynced'])

    def test_invalid_readonly_or_disappeared_theme_never_writes(self):
        original = self.state.read_text()
        self.call('set', 'event-sounds', 'yes', success=False)
        self.call('set', 'unknown', 'true', success=False)
        self.call('set', 'event-sounds', 'false', success=False, READ_ONLY='1')
        self.call('set', 'theme-name', '../../escape', success=False)
        (self.root / 'data/sounds/custom/index.theme').unlink()
        self.call('set', 'theme-name', 'custom', success=False)
        self.assertEqual(self.state.read_text(), original)

    def test_malformed_gtk_file_prevents_partial_preference_change(self):
        path = self.root / 'config/gtk-4.0/settings.ini'
        path.parent.mkdir(parents=True)
        path.write_text('this is not an ini file')
        self.call('set', 'event-sounds', 'false', success=False)
        self.assertTrue(json.loads(self.state.read_text())['event-sounds'])
        self.assertEqual(path.read_text(), 'this is not an ini file')
        self.assertFalse((self.root / 'config/gtk-3.0/settings.ini').exists())

    def test_external_changes_and_readback_failure(self):
        self.call('sync')
        data = json.loads(self.state.read_text()); data['event-sounds'] = False
        self.state.write_text(json.dumps(data))
        status = json.loads(self.call('status').stdout)
        self.assertFalse(status['preferences']['event-sounds'])
        self.assertFalse(status['gtkSynced'])
        self.call('sync')
        self.assertTrue(json.loads(self.call('status').stdout)['gtkSynced'])
        self.call('set', 'event-sounds', 'true', success=False, IGNORE_WRITE='1')
        self.call('status', success=False, FAIL='get')

    def test_preview_uses_current_theme_and_obeys_mute(self):
        self.call('set', 'theme-name', 'custom')
        self.call('preview')
        calls = (self.root / 'calls').read_text()
        self.assertIn('--property=canberra.xdg-theme.name=custom', calls)
        self.call('preview', success=False, FAIL_PREVIEW='1')
        self.call('set', 'event-sounds', 'false')
        (self.root / 'calls').write_text('')
        self.call('preview', success=False)
        self.assertNotIn('canberra-gtk-play', (self.root / 'calls').read_text())


if __name__ == '__main__':
    unittest.main()
