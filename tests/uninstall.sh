#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
sandbox=$(mktemp -d)
trap 'rm -rf -- "$sandbox"' EXIT
export BLANKWEAVE_SYSTEM_ROOT=$sandbox BLANKWEAVE_USER_HOME=$sandbox/home
mkdir -p "$sandbox/home/.config/blankweave/themes" "$sandbox/etc/profile.d" "$sandbox/etc/systemd/logind.conf.d"
printf 'original\n' > "$sandbox/etc/profile.d/blankweave-session.sh"
mkdir -p "$sandbox/boot/loader/entries" "$sandbox/home/.config/hypr"
printf 'options root=private rw\n' > "$sandbox/boot/loader/entries/arch.conf"
python3 "$repository/scripts/uninstall-footprint.py" before "$sandbox" "$sandbox/home"
printf 'managed\n' > "$sandbox/etc/profile.d/blankweave-session.sh"
printf 'managed\n' > "$sandbox/etc/systemd/logind.conf.d/50-blankweave.conf"
printf 'source ~/.local/share/blankweave/shell/profile\npersonal_profile=1\n' > "$sandbox/home/.zprofile"
printf 'personal\n' > "$sandbox/home/.config/blankweave/themes/personal"
printf 'options root=private rw quiet splash\n' > "$sandbox/boot/loader/entries/arch.conf"
ln -s "$sandbox/home/.local/share/blankweave/hypr/entry.lua" "$sandbox/home/.config/hypr/hyprland.lua"
python3 "$repository/scripts/uninstall-footprint.py" after "$sandbox" "$sandbox/home"
"$repository/scripts/uninstall.sh" > "$sandbox/preview"
grep -Fq 'Restore:' "$sandbox/preview"
grep -Fq 'Packages: never removed' "$sandbox/preview"
grep -Fxq managed "$sandbox/etc/profile.d/blankweave-session.sh"
if "$repository/scripts/uninstall.sh" --apply < /dev/null > "$sandbox/refused" 2>&1; then exit 1; fi
grep -Fq -- '--yes' "$sandbox/refused"
printf 'modified\n' > "$sandbox/etc/systemd/logind.conf.d/50-blankweave.conf"
"$repository/scripts/uninstall.sh" --apply --yes > "$sandbox/applied"
grep -Fxq personal_profile=1 "$sandbox/home/.zprofile"
if grep -Fq blankweave/shell/profile "$sandbox/home/.zprofile"; then exit 1; fi
[[ ! -L $sandbox/home/.config/hypr/hyprland.lua ]]
grep -Fxq 'options root=private rw' "$sandbox/boot/loader/entries/arch.conf"
grep -Fxq original "$sandbox/etc/profile.d/blankweave-session.sh"
grep -Fxq modified "$sandbox/etc/systemd/logind.conf.d/50-blankweave.conf"
grep -Fq 'Kept modified' "$sandbox/applied"
[[ -f $sandbox/home/.config/blankweave/themes/personal ]]
"$repository/scripts/uninstall.sh" --apply --yes --purge-config > /dev/null
[[ ! -e $sandbox/home/.config/blankweave ]]
"$repository/scripts/uninstall.sh" --apply --yes > /dev/null
# Exercise terminal cancellation with a private PTY; all paths remain sandboxed.
python3 - "$repository" <<'PYTTY'
import os, pathlib, pty, subprocess, sys
master, slave = pty.openpty()
process = subprocess.Popen([sys.argv[1] + '/scripts/uninstall.sh', '--apply'], stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
os.close(slave)
os.write(master, b'n\n')
stdout, stderr = process.communicate(timeout=10)
os.close(master)
assert process.returncode == 0, stderr
assert b'[y/N]' in stdout
PYTTY
python3 - "$repository" <<'PY' 
import importlib.util, pathlib, sys
r=pathlib.Path(sys.argv[1]); spec=importlib.util.spec_from_file_location('footprint', r/'scripts/uninstall-footprint.py'); m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
# Every literal installer system-file deployment must be within the shared scope.
import re
for name in ['install.sh'] + [str(p.relative_to(r)) for p in (r/'scripts').glob('configure-*.sh')]:
    source=(r/name).read_text()
    # Read-only inputs and package-owned binaries are explicitly distinguished.
    read_only = {'/etc/xdg/Thunar/uca.xml', '/etc/pacman.d/mirrorlist'}
    for line in source.splitlines():
        if line.lstrip().startswith('#'):
            continue
        for path in re.findall(r'(/(?:etc|usr/lib/blankweave|usr/local/lib/blankweave|usr/share/(?:blankweave|polkit-1/actions|plymouth/themes/blankweave))/[\w./@-]+)', line):
            assert path in read_only or any(path == p or path.startswith(p+'/') or p.startswith(path+'/') for p in m.SYSTEM_FILES), (name,path)

assert 'uninstall-footprint.py" before' in (r/'install.sh').read_text()
assert 'uninstall-footprint.py" after' in (r/'install.sh').read_text()
PY
printf 'Sandbox uninstall tests passed.\n'
