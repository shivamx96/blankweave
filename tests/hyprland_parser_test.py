#!/usr/bin/env python3
"""Validate installer-generated Lua using the real compositor, without a session.

CI uses rolling Arch packages with a minimum supported parser of 0.57.1. This
deliberately tests the available newer parser too, rather than pinning Arch's
interdependent packages to a partial-upgrade snapshot.
"""
import importlib.util
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
sys.path.insert(0, str(REPOSITORY / 'defaults/shell'))


def provider(filename):
    spec = importlib.util.spec_from_file_location(filename.replace('-', '_'),
                                                 REPOSITORY / 'defaults/shell' / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class HyprlandParserTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.geteuid() == 0:
            raise RuntimeError('Run the compositor parser gate as an unprivileged user.')
        cls.parser = shutil.which('hyprland') or shutil.which('Hyprland')
        if not cls.parser:
            raise RuntimeError('Install Hyprland >= 0.57.1 to run the compositor parser gate.')
        version = subprocess.check_output([cls.parser, '--version'], text=True, timeout=10)
        match = re.search(r'^Hyprland (\d+)\.(\d+)\.(\d+)\b', version)
        if not match or tuple(map(int, match.groups())) < (0, 57, 1):
            raise RuntimeError('The compositor parser gate requires Hyprland >= 0.57.1.')

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='blankweave-parser-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.home = self.root / 'home'
        self.config = self.home / '.config'
        self.preferences = self.config / 'blankweave'
        self.dots = self.home / '.local/share/blankweave'
        self.runtime = self.root / 'runtime'
        for directory in (self.preferences / 'overrides', self.config / 'hypr', self.runtime):
            directory.mkdir(parents=True)
        self.runtime.chmod(0o700)
        shutil.copytree(REPOSITORY / 'defaults/hypr', self.dots / 'hypr')
        self.override = self.preferences / 'overrides/hyprland.lua'
        self.override.write_text('-- Isolated personal override\n')
        self.environment = {
            'PATH': '/usr/bin:/bin', 'HOME': str(self.home),
            'XDG_CONFIG_HOME': str(self.config),
            'XDG_DATA_HOME': str(self.home / '.local/share'),
            'XDG_CACHE_HOME': str(self.home / '.cache'),
            'XDG_STATE_HOME': str(self.home / '.local/state'),
            'XDG_RUNTIME_DIR': str(self.runtime),
            'XDG_DATA_DIRS': '/usr/share', 'LANG': 'C.UTF-8',
            'DBUS_SESSION_BUS_ADDRESS': 'unix:path=' + str(self.runtime / 'absent-bus'),
            'DBUS_SYSTEM_BUS_ADDRESS': 'unix:path=' + str(self.runtime / 'absent-system-bus'),
            'USER': 'blankweave-parser', 'LOGNAME': 'blankweave-parser',
        }
        # Execute the same entry-point generator as install.sh, in a fresh HOME.
        subprocess.run(['bash', '-c', 'source "$1"; user_config_install_hyprland_entry "$2" "$3" "$4"',
                        'bash', str(REPOSITORY / 'scripts/user-config.sh'), str(self.dots),
                        str(self.config), 'false'], env=self.environment, check=True, timeout=10)
        self.wrapper = self.root / 'verify.lua'
        self.wrapper.write_text('''
-- --verify-config must never execute startup commands or launch a session.
local function denied() error("Parser test attempted command execution") end
hl.exec_cmd = denied
os.execute = denied
io.popen = denied
require(os.getenv("HOME") .. "/.config/hypr/hyprland")
''')
        self.hardware('generic', 'internal')

    def hardware(self, gpu, display):
        shutil.copyfile(REPOSITORY / f'defaults/hardware/env-{gpu}.lua', self.config / 'hypr/env.lua')
        shutil.copyfile(REPOSITORY / f'defaults/hardware/monitors-{display}.lua', self.config / 'hypr/monitors.lua')

    def verify(self, expected=True):
        result = subprocess.run([self.parser, '--verify-config', '--config', str(self.wrapper)],
                                cwd=self.root, env=self.environment, capture_output=True,
                                text=True, timeout=20)
        output = result.stdout + result.stderr
        self.assertNotIn('Parser test attempted command execution', output, output)
        if expected:
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('config ok', output.lower(), output)
        else:
            self.assertNotEqual(result.returncode, 0, output)
        return output

    def test_default_hardware_and_voice_profiles(self):
        for gpu, display in [('generic', 'external'), ('intel', 'internal'), ('nvidia', 'external')]:
            with self.subTest(gpu=gpu, display=display):
                self.hardware(gpu, display)
                self.verify()
        subprocess.run(['bash', '-c', 'source "$1"; user_config_install_hyprland_entry "$2" "$3" true',
                        'bash', str(REPOSITORY / 'scripts/user-config.sh'), str(self.dots),
                        str(self.config)], env=self.environment, check=True, timeout=10)
        self.verify()

    def test_generated_saved_preferences(self):
        examples = {
            'pointer': {'version': 1, 'global': {'sensitivity': 0.2, 'accel_profile': 'flat'},
                        'touchpad': {'natural_scroll': True, 'tap_to_click': True, 'disable_while_typing': True},
                        'devices': {'fixture-pointer': {'left_handed': True}}},
            'keyboard': {'version': 1, 'values': {'kb_layout': 'us,de', 'kb_variant': ',',
                                                'kb_options': 'grp:alt_shift_toggle'}},
            'shortcuts': {'version': 1, 'bindings': {'terminal': 'SUPER + CTRL + F8'}},
            'accessibility': {'version': 1, 'reduced_motion': True, 'high_contrast': True},
            'interface': {'version': 1, 'text_scale': 1.3, 'cursor_size': 48},
        }
        for name, data in examples.items():
            (self.preferences / f'{name}.lua').write_text(provider(f'{name}-settings.py').render(data))
        monitor = provider('monitor-setups.py')
        rules = monitor.render({'description': 'Fixture display', 'mode': '1920x1080@60',
                                'position': 'auto-right', 'scale': 1.5, 'transform': 1, 'cm': 'srgb'})
        rules += '\n' + monitor.render({'description': 'Fixture mirror', 'mode': '1920x1080@60',
                                        'position': 'auto', 'scale': 'auto', 'mirror': 'Fixture display'})
        (self.preferences / 'monitors.lua').write_text(rules + '\n')
        # Entry intentionally pcall-loads layouts. Assert execution, not merely
        # parser success, so a swallowed generated-file error cannot pass CI.
        with (self.preferences / 'monitors.lua').open('a') as stream:
            stream.write('_G.parser_monitor_loaded = true\n')
        self.override.write_text('''
assert(_G.parser_monitor_loaded, "Saved monitor rules did not load")
for _, name in ipairs({"pointer", "keyboard", "shortcuts", "accessibility", "interface"}) do
    local revision = _G["blankweave_" .. name .. "_revision"]
    assert(type(revision) == "string" and revision ~= "defaults", name .. " did not load")
end
''')
        self.verify()

    def test_invalid_api_and_option_are_rejected(self):
        for invalid in ['hl.no_such_blankweave_api()',
                        'hl.config({ general = { blankweave_invalid_option = true } })',
                        'hl.bind("SUPER + F10", hl.dsp.window.close)',
                        'hl.dsp.window.close({}, "excess argument")']:
            with self.subTest(config=invalid):
                self.override.write_text(invalid + '\n')
                self.verify(expected=False)


if __name__ == '__main__':
    unittest.main()
