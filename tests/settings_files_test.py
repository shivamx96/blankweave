#!/usr/bin/env python3
"""Storage metadata and private coordination regressions; no live session access."""
import ast
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
SHELL = REPO / 'defaults/shell'
sys.path.insert(0, str(SHELL))
from runtime_paths import runtime_path
from settings_support import error_result, file_refusal
spec = importlib.util.spec_from_file_location('files', SHELL / 'settings-files.py')
files = importlib.util.module_from_spec(spec); spec.loader.exec_module(files)


class FilesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = patch.dict(os.environ, HOME=str(self.root), XDG_CONFIG_HOME=str(self.root / 'config'),
                              XDG_STATE_HOME=str(self.root / 'state'), XDG_RUNTIME_DIR=str(self.root / 'run'))
        self.env.start(); self.addCleanup(self.env.stop)

    def test_runtime_languages_agree_and_private(self):
        for runtime in ('', str(self.root / 'run')):
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime):
                expected = self.root / ('run/blankweave' if runtime else 'state/blankweave/locks') / 'interface.lock'
                self.assertEqual(runtime_path('interface.lock'), expected)
                result = subprocess.check_output(['bash', '-c', 'source "$1"; blankweave_runtime_path interface.lock',
                    'test', str(SHELL / 'runtime-paths.sh')], text=True, stdin=subprocess.DEVNULL)
                self.assertEqual(result.strip(), str(expected))
                self.assertEqual(stat.S_IMODE(expected.parent.stat().st_mode), 0o700)
                self.assertFalse((self.root / 'config').exists())

    def test_sessionless_caller_shares_the_session_runtime(self):
        from runtime_paths import session_runtime
        run_root = self.root / 'run-user'
        (run_root / str(os.getuid())).mkdir(parents=True)
        with patch.dict(os.environ, XDG_RUNTIME_DIR=''):
            # The installer's sudo drops the variable but keeps the real home.
            real = (os.getuid(), os.environ['HOME'])
            self.assertEqual(session_runtime(run_root, real), run_root / str(os.getuid()))
            # An isolated home, a missing directory, or another owner: fall back.
            self.assertIsNone(session_runtime(run_root, (os.getuid(), '/home/someone-else')))
            self.assertIsNone(session_runtime(self.root / 'absent', real))
            self.assertIsNone(session_runtime(run_root, (os.getuid() + 1, os.environ['HOME'])))
        with patch.dict(os.environ, XDG_RUNTIME_DIR=str(self.root / 'run')):
            self.assertEqual(session_runtime(run_root, real), self.root / 'run')

    def test_catalog_paths_and_readme_match_writers(self):
        catalog = (REPO / 'defaults/quickshell/Settings/Catalog.js').read_text()
        paths = set(re.findall(r'"(~/.config/[^"\n]+)"', catalog))
        sources = list(SHELL.glob('*')) + list((REPO / 'defaults/quickshell/Services').glob('*.qml'))
        literals = []
        for p in sources:
            if not p.is_file(): continue
            if p.suffix == '.py':
                literals += [node.value for node in ast.walk(ast.parse(p.read_text()))
                             if isinstance(node, ast.Constant) and isinstance(node.value, str)]
            else:
                literals += re.findall(r'[\"\']([^\"\'\n]+)[\"\']', p.read_text())
        source = '\n'.join(literals)
        readme = (REPO / 'README.md').read_text()
        writers = {'shell': 'quickshell/Services/ShellPreferences.qml', 'theme': 'shell/theme-apply.sh',
                   'monitors': 'shell/monitor-layout.sh', 'monitor-setups': 'shell/monitor-setups.py',
                   'interface': 'shell/interface-settings.py', 'accessibility': 'shell/accessibility-settings.py',
                   'keyboard': 'shell/keyboard-settings.py', 'pointer': 'shell/pointer-settings.py',
                   'shortcuts': 'shell/shortcuts-settings.py', 'wallpapers': 'shell/wallpaper-settings.py',
                   'night-light': 'shell/night-light.py', 'notifications': 'shell/notification-settings.py',
                   'idle': 'shell/idle-policy.py', 'power-profiles': 'shell/power_policy.py',
                   'backup': 'shell/settings_backup.py', 'mimeapps': 'shell/default-apps.py',
                   'system-bell': 'shell/system_bell.py', 'magnifier': 'shell/settings_session.py',
                   'idle-hibernate': 'shell/settings_recovery.py'}
        for path in paths:
            name = Path(path).name
            writer = REPO / 'defaults' / writers[Path(path).stem]
            content = writer.read_text()
            expected = '~/.config/' + ('' if name == 'mimeapps.list' else 'blankweave/') + name
            self.assertEqual(path, expected)
            self.assertIn(name, content, str(writer))
            self.assertIn('blankweave', content, str(writer))
            self.assertIn(name, source, path)
            self.assertIn('`' + path + '`', readme, path)
            self.assertEqual(files.resolve(path), self.root / 'config' / path[len('~/.config/'):])

    def test_override_and_existing_file_metadata(self):
        path = files.resolve('~/.config/blankweave/overrides/hyprland.lua')
        path.parent.mkdir(parents=True); path.write_text('-- personal')
        data = files.metadata()
        self.assertEqual(data['overrides']['shortcuts'][0]['display'], '~/' + str(path.relative_to(self.root)))
        self.assertFalse(data['files']['~/.config/blankweave/idle.json']['exists'])
        entry = files.resolve('~/.config/hypr/hypridle.conf')
        entry.parent.mkdir(parents=True); entry.write_text('# custom')
        theme = files.resolve('~/.config/blankweave/themes/personal/theme.json')
        theme.parent.mkdir(parents=True); theme.write_text('{}')
        selection = files.resolve('~/.config/blankweave/theme.json')
        selection.write_text('{"theme":"personal"}')
        data = files.metadata()
        self.assertEqual(data['overrides']['screen-off'][0]['path'], str(entry))
        self.assertIn(str(theme), [row['path'] for row in data['overrides']['theme']])
        idle = files.resolve('~/.config/blankweave/idle.json'); idle.write_text('{}')
        self.assertTrue(files.metadata()['files']['~/.config/blankweave/idle.json']['exists'])

    def test_opener_is_argument_vector_and_only_existing_catalog_files(self):
        idle = files.resolve('~/.config/blankweave/idle.json'); idle.parent.mkdir(parents=True); idle.write_text('{}')
        binary = self.root / 'bin'; binary.mkdir()
        log = self.root / 'opened'
        opener = binary / 'xdg-open'
        opener.write_text('#!/bin/sh\nprintf "%s" "$1" > "$OPEN_LOG"\n'); opener.chmod(0o700)
        env = dict(os.environ, PATH=str(binary) + ':' + os.environ['PATH'], OPEN_LOG=str(log))
        subprocess.run([sys.executable, str(SHELL / 'settings-files.py'), 'open', '~/.config/blankweave/idle.json'], env=env, check=True, stdin=subprocess.DEVNULL)
        self.assertEqual(log.read_text(), str(idle.parent))
        idle.unlink(); log.unlink()
        result = subprocess.run([sys.executable, str(SHELL / 'settings-files.py'), 'open', '~/.config/blankweave/idle.json'], env=env, stdin=subprocess.DEVNULL)
        self.assertNotEqual(result.returncode, 0); self.assertFalse(log.exists())

    def test_local_refusal_does_not_enter_job_record(self):
        path = self.root / 'config/blankweave/overrides/hyprland.lua'
        error = file_refusal('A personal configuration overrides this setting.', path)
        local = error_result(error)
        self.assertIn('~/config/blankweave/overrides/hyprland.lua', local['message'])
        self.assertNotIn(str(self.root), json.dumps(local))
        job = error_result(error, shareable=True)
        self.assertNotIn('hyprland.lua', json.dumps(job))
        self.assertNotIn(str(self.root), json.dumps(job))

    def test_all_shared_locks_leave_config_clean(self):
        from settings_support import locked
        config = self.root / 'config/blankweave'
        config.mkdir(parents=True)
        for runtime in ('', str(self.root / 'run')):
            with patch.dict(os.environ, XDG_RUNTIME_DIR=runtime):
                for name in ('notifications', 'webapps', 'wallpaper', 'system-bell', 'startup',
                             'system-diagnostics', 'backup-provider', 'operations-backup', 'worker-backup'):
                    with locked(name): pass
                self.assertEqual(list(config.iterdir()), [])
        for name, literal in [('monitor-layout.sh', '$config_dir/.monitor-layout.lock'),
                              ('theme-apply.sh', '$BLANKWEAVE_CONFIG_DIR/interface.lock')]:
            self.assertNotIn(literal, (SHELL / name).read_text())
        for name in ('interface-settings.py', 'accessibility-settings.py', 'gtk_settings.py',
                     'keyboard-settings.py', 'shortcuts-settings.py', 'pointer-settings.py',
                     'default-apps.py', 'night-light.py'):
            source = (SHELL / name).read_text()
            for match in re.finditer(r"(?:self\.)?directory / ['\"]([^'\"]+\.lock)['\"]", source):
                self.fail(name + ' still stores a configuration lock: ' + match[0])

    def test_migration_removes_known_leaves_only(self):
        config = self.root / 'config/blankweave'; config.mkdir(parents=True)
        for name in ('interface.lock', 'gtk-settings.lock', '.keyboard.lock', 'precious.lock', 'idle.json'):
            (config / name).write_text('keep?')
        runtime = config / 'night-light-runtime/hypr'; runtime.mkdir(parents=True)
        (runtime / 'hyprsunset.conf').write_text('scratch')
        (runtime / 'personal').write_text('keep')
        script = REPO / 'migrations/20261112-settings-runtime-paths.sh'
        for _ in range(2): subprocess.run(['bash', str(script)], check=True, stdin=subprocess.DEVNULL)
        self.assertFalse((config / 'interface.lock').exists())
        self.assertFalse((config / '.keyboard.lock').exists())
        self.assertTrue((config / 'precious.lock').exists()); self.assertTrue((config / 'idle.json').exists())
        self.assertTrue((runtime / 'personal').exists())
        import shutil
        shutil.rmtree(config / 'night-light-runtime')
        outside = self.root / 'personal-runtime'; outside.mkdir()
        (outside / 'hypr').mkdir()
        (config / 'night-light-runtime').symlink_to(outside)
        subprocess.run(['bash', str(script)], check=True, stdin=subprocess.DEVNULL)
        self.assertTrue((outside / 'hypr').is_dir())


if __name__ == '__main__': unittest.main()
