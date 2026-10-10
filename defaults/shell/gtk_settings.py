#!/usr/bin/env python3
"""Merge Blankweave's GTK settings without discarding unrelated preferences."""
import configparser
import contextlib
import fcntl
import os
from pathlib import Path
import re
import stat
import sys
import tempfile


def config_root():
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))


@contextlib.contextmanager
def locked():
    directory = config_root() / "blankweave"
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / "gtk-settings.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def read(path):
    text = path.read_text() if path.exists() else ""
    parser = configparser.ConfigParser(interpolation=None)
    parser.optionxform = str
    parser.read_string(text)
    return text, dict(parser["Settings"]) if parser.has_section("Settings") else {}


def prepare(updates):
    if any("\n" in value or "\r" in value for value in updates.values()):
        raise ValueError("GTK settings must be single-line values")
    result = []
    for version in ("gtk-3.0", "gtk-4.0"):
        # Preserve an existing user symlink, updating its target atomically.
        path = (config_root() / version / "settings.ini").resolve()
        text, _ = read(path)
        lines = text.splitlines(keepends=True)
        output, remaining, inside, found = [], dict(updates), False, False
        for line in lines:
            header = re.match(r"^\s*\[([^]]+)\]", line)
            if header:
                if inside:
                    output.extend(f"{key}={value}\n" for key, value in remaining.items())
                    remaining.clear()
                inside = header[1] == "Settings"
                found |= inside
            key = re.match(r"^\s*([^#;\s=]+)\s*=", line)
            if inside and key and key[1] in remaining:
                output.append(f"{key[1]}={remaining.pop(key[1])}\n")
            else:
                output.append(line if line.endswith("\n") else line + "\n")
        if not found:
            output.append("[Settings]\n")
        output.extend(f"{key}={value}\n" for key, value in remaining.items())
        result.append((path, "".join(output)))
    return result


def write(prepared):
    for path, text in prepared:
        path.parent.mkdir(parents=True, exist_ok=True)
        mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
        descriptor, temporary = tempfile.mkstemp(prefix=".settings-", dir=path.parent)
        try:
            with os.fdopen(descriptor, "w") as stream:
                stream.write(text)
                stream.flush()
                os.fsync(stream.fileno())
            os.chmod(temporary, mode)
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)


if __name__ == "__main__":
    try:
        updates = dict(argument.split("=", 1) for argument in sys.argv[1:])
        allowed = {"gtk-application-prefer-dark-theme", "gtk-theme-name", "gtk-icon-theme-name",
                   "gtk-cursor-theme-name", "gtk-cursor-theme-size"}
        if not updates or set(updates) - allowed or any("\n" in value or "\r" in value for value in updates.values()):
            raise ValueError("Invalid GTK appearance settings")
        with locked():
            write(prepare(updates))
    except (OSError, ValueError, configparser.Error) as error:
        print(f"Could not update GTK settings: {error}", file=sys.stderr)
        sys.exit(1)
