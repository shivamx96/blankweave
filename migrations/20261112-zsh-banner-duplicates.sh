#!/usr/bin/env bash
# Repair only the old generated separator; never follow user-managed links.
set -euo pipefail
python3 - "$HOME/.zshrc" <<'PY'
import os
import pathlib
import stat
import sys
import tempfile
path = pathlib.Path(sys.argv[1])
try:
    metadata = path.lstat()
except FileNotFoundError:
    sys.exit(0)
if not stat.S_ISREG(metadata.st_mode):
    sys.exit(0)
original = path.read_bytes()
banner = b'#############################################################################'
lines = original.split(b'\n')
result = []
for line in lines:
    if line == banner and result and result[-1] == banner:
        continue
    result.append(line)
updated = b'\n'.join(result)
if original.endswith(b'\n') and not updated.endswith(b'\n'):
    updated += b'\n'
elif not original.endswith(b'\n'):
    updated = updated.rstrip(b'\n')
if updated != original:
    fd, temporary = tempfile.mkstemp(prefix='.blankweave-zsh-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(updated)
            os.fchmod(stream.fileno(), stat.S_IMODE(metadata.st_mode))
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
PY
