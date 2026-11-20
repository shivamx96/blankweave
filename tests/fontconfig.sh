#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for command in fc-match fc-list python3; do
    if ! command -v "$command" >/dev/null; then
        printf 'SKIP fontconfig: %s is unavailable.\n' "$command"
        exit 0
    fi
done
if [[ ! -f /etc/fonts/fonts.conf ]]; then
    printf 'SKIP fontconfig: system defaults /etc/fonts/fonts.conf are unavailable.\n'
    exit 0
fi
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
export HOME=$test_root/home
export XDG_CONFIG_HOME=$HOME/.config
export XDG_CACHE_HOME=$test_root/cache
export XDG_DATA_HOME=$HOME/.local/share
export FONTCONFIG_FILE=$test_root/fonts.conf
export FONTCONFIG_PATH=/etc/fonts
unset FONTCONFIG_SYSROOT
mkdir -p "$XDG_CONFIG_HOME/fontconfig/conf.d" "$XDG_CACHE_HOME"
# Include the actual system defaults, but relocate every cache to the sandbox.
# Absolute includes preserve fonts.conf's /etc/fonts-relative include semantics.
python3 - "$FONTCONFIG_FILE" "$XDG_CACHE_HOME" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
root = ET.parse('/etc/fonts/fonts.conf').getroot()
for node in root.findall('cachedir'):
    root.remove(node)
for node in root.findall('include'):
    if not node.get('prefix') and node.text and not node.text.startswith(('~', '/')):
        node.text = str(Path('/etc/fonts') / node.text)
ET.SubElement(root, 'cachedir').text = sys.argv[2]
ET.ElementTree(root).write(sys.argv[1], encoding='unicode')
PY
config_dir=$XDG_CONFIG_HOME/fontconfig/conf.d
cp "$repository/defaults/fontconfig/50-blankweave.conf" "$config_dir/local.conf"
families=(sans-serif serif monospace system-ui ui-sans-serif ui-serif ui-monospace)
expected=('Atkinson Hyperlegible Next' 'Noto Serif' 'JetBrains Mono' 'Atkinson Hyperlegible Next' 'Atkinson Hyperlegible Next' 'Noto Serif' 'JetBrains Mono')
patterns=("${families[@]}" 'sans-serif:charset=4e2d' 'sans-serif:charset=1f600')
printf 'Before (ignored conf.d/local.conf):\n'
for pattern in "${patterns[@]}"; do
    printf '  %s -> %s\n' "$pattern" "$(fc-match -f '%{family}\n' ":family=$pattern")"
done
mv "$config_dir/local.conf" "$config_dir/50-blankweave.conf"
printf 'After (conf.d/50-blankweave.conf):\n'
for pattern in "${patterns[@]}"; do
    printf '  %s -> %s\n' "$pattern" "$(fc-match -f '%{family}\n' ":family=$pattern")"
done
installed=$(fc-list -f '%{family}\n' | tr ',' '\n' | sort -u)
assert_family() {
    local pattern=$1 family=$2 actual
    if ! grep -Fxq "$family" <<< "$installed"; then
        printf 'SKIP family assertion %s: named font "%s" is not installed.\n' "$pattern" "$family"
        return
    fi
    actual=$(fc-match -f '%{family}' ":family=$pattern")
    if [[ $actual != "$family" && $actual != "$family,"* ]]; then
        printf 'Expected %s -> %s, got %s\n' "$pattern" "$family" "$actual" >&2
        exit 1
    fi
}
for index in "${!families[@]}"; do
    assert_family "${families[index]}" "${expected[index]}"
done
# Explicit application choices must survive the generic preference rules.
assert_family 'Noto Sans' 'Noto Sans'
assert_family 'JetBrainsMono Nerd Font' 'JetBrainsMono Nerd Font'
assert_family 'sans-serif:charset=4e2d' 'Noto Sans CJK JP'
assert_family 'sans-serif:charset=1f600' 'Noto Color Emoji'
printf 'Fontconfig sandbox tests passed.\n'
