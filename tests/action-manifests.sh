#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$repository" <<'PY'
from pathlib import Path
import re, sys
root = Path(sys.argv[1])
required = set()
for name in ('base.txt', 'aur.txt'):
    required.update(line.split('#')[0].strip() for line in (root/'packages'/name).read_text().splitlines())
# Every literal executable in default bindings and direct bar actions is reviewed.
providers = {
    'ghostty': 'ghostty', 'qs': 'quickshell', 'wpctl': 'wireplumber',
    'hyprctl': 'hyprland', 'jq': 'jq', 'playerctl': 'playerctl',
    'pavucontrol': 'pavucontrol', 'btop': 'btop', 'fastfetch': 'fastfetch',
    'bash': 'bash', 'gh': 'github-cli', 'python3': 'python',
    'dunstctl': 'dunst', 'systemctl': 'systemd', 'loginctl': 'systemd',
    'sh': 'bash', 'uwsm': 'uwsm', 'cliphist': 'cliphist', 'notify-send': 'libnotify', 'satty': 'satty',
    'grim': 'grim', 'slurp': 'slurp', 'wl-copy': 'wl-clipboard',
}
# systemd is the Arch/UWSM session prerequisite, rather than an optional profile.
guarded = {'idea', 'docker', 'intel_gpu_top', 'nvtop'}
assistive = (root/'defaults/shell/settings_session.py').read_text()
assert "'open-default.sh'" in assistive and "'assistive'" in assistive
assert "'orca'" in assistive and "'wvkbd-mobintl'" in assistive
lua = (root/'defaults/hypr/keybindings.lua').read_text()
assert 'zen-browser' not in lua and 'blueman-manager' not in lua
commands = re.findall(r'hl\.dsp\.exec_cmd\((?:"|\x27|\[\[)([^\s"\x27]+)', lua)
qml = '\n'.join(p.read_text() for p in (root/'defaults/quickshell/Modules').glob('*.qml'))
assert '"xdg-open"' not in qml
commands += re.findall(r'bar\.run\(\[\s*"([^"]+)"', qml)
power_actions = (root/'defaults/quickshell/Services/PowerActions.js').read_text()
commands += re.findall(r'return \["([^"]+)"', power_actions)
# Nested monitor/action argv and launcher's system actions.
commands += ['btop', 'fastfetch', 'gh', 'docker', 'intel_gpu_top', 'nvtop',
             'playerctl', 'pavucontrol', 'satty', 'grim', 'slurp', 'wl-copy', 'cliphist']
for command in commands:
    if command.startswith(('~/.local/', 'root.')):
        continue  # deployed helper or IPC into the required shell
    assert command in providers or command in guarded, 'Unreviewed action: ' + command
    if command in providers:
        assert providers[command] in required or providers[command] == 'systemd', command
bar = (root/'defaults/quickshell/Bar/Bar.qml').read_text()
assert '/open-default.sh", "command"].concat(command)' in bar
for name in ('GitWidget', 'TailscaleWidget'):
    assert 'open-default.sh' in (root/f'defaults/quickshell/Modules/{name}.qml').read_text()
for package in ['ghostty', 'thunar', 'btop', 'pavucontrol', 'satty', 'playerctl', 'libnotify']:
    assert package in required
assert 'firefox' not in required
assert 'firefox' in (root/'packages/profiles/desktop.txt').read_text().splitlines()
print('Default binding/bar command manifest and degradation coverage passed.')
PY
