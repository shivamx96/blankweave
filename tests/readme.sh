#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$repository" <<'PY'
import json, pathlib, re, subprocess, sys
root = pathlib.Path(sys.argv[1])
text = (root / 'README.md').read_text()
cli = root / 'bin/blankweave'
catalog = {x['id']: x for x in json.loads((root / 'defaults/shell/shortcut-catalog.json').read_text())}
normalize = lambda s: re.sub(r'\s+', '', s).lower()
for key, ident in re.findall(r'\| `([^`]+)` \|[^\n]*<!-- shortcut:([^ ]+) -->', text):
    assert ident in catalog and normalize(key) == normalize(catalog[ident]['default']), (key, ident)
valid_keys = {normalize(x['default']) for x in catalog.values()}
for key in re.findall(r'`(Super[^`]+)`', text):
    key = key.replace(',', 'comma').replace('/', 'slash')
    assert normalize(key) in valid_keys, 'unknown README key: ' + key
# Check every documented public invocation, including flags in fenced examples.
for match in re.finditer(r'(?<![\w/-])blankweave ([a-z][a-z-]*)([^`\n]*)', text):
    command, tail = match.groups()
    help_result = subprocess.run([str(cli), 'help', command], capture_output=True, text=True)
    assert help_result.returncode == 0, 'unknown README command: ' + command
    for flag in re.findall(r'(?<!\w)--[a-z][a-z-]*', tail.split('#')[0]):
        assert flag in help_result.stdout or flag == '--help', (command, flag)
    if command in ('theme', 'webapp'):
        sub = re.match(r'\s+([a-z][a-z-]*)', tail)
        if sub:
            result = subprocess.run([str(cli), 'help', command, sub[1]], capture_output=True)
            assert result.returncode == 0, (command, sub[1])
# Repository-relative links and inline paths, excluding explicitly pending screenshots.
for path in re.findall(r'\]\(([^)]+)\)', text) + re.findall(r'`((?:defaults|scripts|tests|packages|docs|archinstall|bin)/[^`]+)`', text):
    if '://' in path or path.startswith(('~', '/', '#')):
        continue
    if path.startswith('docs/screenshots/'):
        assert 'Owner action required' in text
        continue
    if '<' in path or '*' in path:
        continue
    assert (root / path).exists(), 'missing README path: ' + path
completion = (root / 'completions/_blankweave').read_text()
help_text = subprocess.check_output([str(cli), 'help'], text=True)
commands = re.findall(r'^  ([a-z]+)\s', help_text, re.M)
all_flags = {'--help', '--version'}
for command in commands:
    assert re.search(r'\b' + command + r'\b', completion), command
    output = subprocess.check_output([str(cli), 'help', command], text=True)
    all_flags.update(re.findall(r'--[a-z][a-z-]*', output))
    for flag in set(re.findall(r'--[a-z][a-z-]*', output)):
        assert flag in completion, (command, flag)
for flag in re.findall(r'`(--[a-z][a-z-]*)`', text):
    assert flag in all_flags, 'unknown standalone CLI flag: ' + flag
print('README command, key, path and completion scans passed.')
PY
