#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$repository" <<'PY'
import importlib.util, pathlib, sys, types
from unittest.mock import Mock, patch
root = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(root / 'defaults/shell'))
spec = importlib.util.spec_from_file_location('defaults', root / 'defaults/shell/default-apps.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
app = Mock()
app.get_executable.return_value = 'browser'
with patch.object(helper.Gio.AppInfo, 'get_default_for_type', return_value=app) as resolve, patch.object(helper.shutil, 'which', return_value='/stub/browser'), patch.object(helper.subprocess, 'Popen') as launch:
    assert helper.open_role('browser', ['https://example.test/a%20b']) == 0
    resolve.assert_called_once_with('x-scheme-handler/https', False)
    app.launch_uris.assert_called_once_with(['https://example.test/a%20b'], None)
    # URLs stay one GIO argument, even with shell metacharacters and spaces.
    app.launch_uris.reset_mock()
    url = 'https://example.test/a b?x=$(touch /tmp/never);y=%s'
    assert helper.open_role('browser', [url]) == 0
    app.launch_uris.assert_called_once_with([url], None)
    assert helper.open_role('files', []) == 0
    app.launch.assert_called_once_with([], None)
    assert helper.open_role('terminal', []) == 0
    launch.assert_called_once_with(['ghostty'])
with patch.object(helper.Gio.AppInfo, 'get_default_for_type', return_value=None), patch.object(helper.subprocess, 'run', return_value=types.SimpleNamespace(stdout='default\n')) as notify, patch.object(helper.subprocess, 'Popen') as settings:
    assert helper.open_role('browser', []) == 1
    assert notify.call_count == 1
    args = notify.call_args.args[0]
    assert '--hint=int:transient:1' in args and '--action=default=Open Settings' in args
    assert 'No web browser is installed.' in args[-1]
    settings.assert_called_once_with(['blankweave', 'settings', 'defaults'])
with patch.object(helper.shutil, 'which', return_value=None), patch.object(helper.subprocess, 'run', return_value=types.SimpleNamespace(stdout='')) as notify:
    assert helper.open_role('command', ['ghostty', '-e', 'nvtop']) == 1
    assert notify.call_count == 1
    assert 'nvtop' in notify.call_args.args[0][-1]
# GIO retains Exec field codes while a terminal entry is wrapped in Ghostty.
import tempfile
with tempfile.TemporaryDirectory() as directory:
    desktop = pathlib.Path(directory) / 'terminal.desktop'
    desktop.write_text('[Desktop Entry]\nType=Application\nName=Terminal app\nTerminal=true\nExec=editor %U\nPath=/tmp/work space\n')
    launched = Mock()
    class TerminalApp:
        def get_executable(self): return 'editor'
        def get_boolean(self, key): return True
        def get_filename(self): return str(desktop)
        def get_string(self, key): return '/tmp/work space'
        @staticmethod
        def new_from_keyfile(key):
            assert key.get_boolean('Desktop Entry', 'Terminal') is False
            command = key.get_string('Desktop Entry', 'Exec')
            assert command.startswith('ghostty --working-directory=')
            assert command.endswith('-e editor %U')
            return launched
    with patch.object(helper.Gio.AppInfo, 'get_default_for_type', return_value=TerminalApp()), patch.object(helper.GioUnix, 'DesktopAppInfo', TerminalApp), patch.object(helper.shutil, 'which', return_value='/stub/tool'):
        assert helper.open_role('browser', ['https://example.test']) == 0
        launched.launch_uris.assert_called_once_with(['https://example.test'], None)
print('Default-role resolution, launch and transient notification stubs passed.')
PY
