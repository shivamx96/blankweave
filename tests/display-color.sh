#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin"
export XDG_CONFIG_HOME=$test_root/config
export LAYOUT_TEST_STATE=$test_root/monitors.json
export LAYOUT_TEST_LOG=$test_root/commands
export PATH=$test_root/bin:$PATH
ln -s "$repository/tests/fixtures/hyprctl-layout.py" "$test_root/bin/hyprctl"
cat > "$LAYOUT_TEST_STATE" <<'JSON'
[{"id":0,"name":"eDP-1","description":"Laptop","width":2880,"height":1800,"refreshRate":60,"scale":1.5,"x":0,"y":0,"mirrorOf":"none","transform":0,"availableModes":["2880x1800@90.00Hz","2880x1800@60.00Hz"]}]
JSON
python3 - "$repository" "$test_root" <<'PY'
import ctypes, json, os, pathlib, subprocess, sys
repo, root = map(pathlib.Path, sys.argv[1:])
sys.path.insert(0, str(repo / 'defaults/shell'))
from display_color import validate_icc
lib = ctypes.CDLL('liblcms2.so.2')
lib.cmsCreate_sRGBProfile.restype = ctypes.c_void_p
lib.cmsSaveProfileToFile.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lib.cmsCloseProfile.argtypes = [ctypes.c_void_p]
profile = lib.cmsCreate_sRGBProfile()
source = root / 'Review RGB.icc'
assert lib.cmsSaveProfileToFile(profile, str(source).encode())
lib.cmsCloseProfile(profile)
data = source.read_bytes()
validate_icc(data)
for bad in [b'not a profile', data[:100], data[:16] + b'CMYK' + data[20:], data[:12] + b'prtr' + data[16:]]:
    try: validate_icc(bad)
    except ValueError: pass
    else: raise AssertionError('invalid profile accepted')
helper = repo / 'defaults/shell/monitor-layout.sh'
def run(*args, fail=False, env=None):
    result = subprocess.run([str(helper), *args], text=True, capture_output=True, env=env)
    assert (result.returncode != 0) == fail, (args, result.stdout, result.stderr)
    return result.stdout
config = root / 'config/blankweave'
def status(): return json.loads(run('status'))
run('profile-import', source.as_uri())
run('profile-import', str(source))
assert len(status()['colorProfiles']) == 1
row = status()['colorProfiles'][0]
identifier = row['id']
assert pathlib.Path(row['path']).read_bytes() == data
run('profile-import', 'https://example.com/profile.icc', fail=True)
run('profile-set', 'missing', identifier, fail=True)
run('profile-set', 'eDP-1', identifier, env={**os.environ, 'LAYOUT_REJECT_ICC':'1'}, fail=True)
assert not (config / 'monitors.json').exists()
run('preset-save', 'Before color')
preset = status()['presets'][0]['id']
run('profile-set', 'eDP-1', identifier)
assert status()['monitors'][0]['colorProfile'] == row['path']
run('profile-delete', identifier, fail=True)
run('set-scale', 'eDP-1', '1.5')
run('mode-preview', 'eDP-1', '2880x1800@90.00')
run('profile-set', 'eDP-1', 'none', fail=True)
run('mode-confirm', status()['preview']['token'])
run('preset-preview', preset)
run('mode-confirm', status()['preview']['token'])
assert status()['monitors'][0]['colorProfile'] == row['path']
assert json.loads(pathlib.Path(os.environ['LAYOUT_TEST_STATE']).read_text())[0]['icc'] == row['path']
assert 'icc = ' in (config / 'monitors.lua').read_text()
run('profile-set', 'eDP-1', 'none')
assert not status()['monitors'][0]['colorProfile']
assert not json.loads(pathlib.Path(os.environ['LAYOUT_TEST_STATE']).read_text())[0].get('icc')
run('profile-delete', identifier)
assert not status()['colorProfiles'] and not pathlib.Path(row['path']).exists() and source.exists()
print('Display ICC validation, import, assignment, rollback, layout preservation and removal passed.')
PY
