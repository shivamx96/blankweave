#!/usr/bin/env python3
"""Persist night-light settings and run a Quickshell-owned hyprsunset instance."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

DEFAULTS = {"mode": "off", "temperature": 4500, "start": "21:00", "end": "07:00"}


def validate(value):
    if value.get("mode") not in ("off", "always", "schedule"):
        raise ValueError("Choose Off, Always on, or Scheduled")
    if type(value.get("temperature")) is not int or not 2500 <= value["temperature"] <= 6500:
        raise ValueError("Choose a temperature between 2500 K and 6500 K")
    for key in ("start", "end"):
        if not isinstance(value.get(key), str) or not re.fullmatch(r'(?:[01][0-9]|2[0-3]):[0-5][0-9]', value[key]):
            raise ValueError("Use 24-hour times such as 21:00 and 07:00")
    if value["start"] == value["end"]:
        raise ValueError("Start and end times must differ; use Always on for all day")
    return {key: value[key] for key in DEFAULTS}


def configuration(value):
    if value["mode"] == "schedule":
        return (f'profile {{\n time = {value["start"]}\n temperature = {value["temperature"]}\n}}\n'
            f'profile {{\n time = {value["end"]}\n identity = true\n}}\n')
    return f'profile {{\n time = 00:00\n temperature = {value["temperature"]}\n}}\n'


def atomic_write(path, data):
    fd, stage = tempfile.mkstemp(prefix=".night-light-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(data)
        os.replace(stage, path)
    finally:
        if os.path.exists(stage):
            os.unlink(stage)


def ipc(*args):
    try:
        result = subprocess.run(["hyprctl", "hyprsunset", *args], capture_output=True, text=True, timeout=2)
        return result.stdout.strip() if result.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def main():
    directory = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "blankweave"
    path = directory / "night-light.json"
    value = validate(json.loads(path.read_text()) if path.exists() else DEFAULTS)
    command = sys.argv[1]
    binary = shutil.which("hyprsunset")
    # A graphical session may have inherited PATH before user-local tools were installed.
    local_binary = Path.home() / ".local/bin/hyprsunset"
    if not binary and local_binary.is_file() and os.access(local_binary, os.X_OK):
        binary = str(local_binary)
    if command == "status":
        temperature = ipc("temperature")
        identity = ipc("identity", "get") if temperature.isdigit() else ""
        print(json.dumps({"preferences": value, "available": bool(binary),
            "revision": hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest(),
            "temperature": int(temperature) if temperature.isdigit() else -1,
            "identity": identity == "true" if identity in ("true", "false") else None}))
    elif command == "set":
        if len(sys.argv) != 6:
            raise ValueError("Provide mode, temperature, start and end time")
        value = validate(dict(zip(DEFAULTS, [sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5]])))
        if value["mode"] != "off" and not binary:
            raise ValueError("Install hyprsunset to enable night light")
        directory.mkdir(parents=True, exist_ok=True)
        atomic_write(path, json.dumps(value, indent=2))
    elif command == "run":
        if value["mode"] == "off":
            return
        if not binary:
            raise ValueError("Install hyprsunset to enable night light")
        directory.mkdir(parents=True, exist_ok=True)
        lock = os.open(directory / ".night-light.lock", os.O_CREAT | os.O_RDWR, 0o600)
        for attempt in range(20):
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if attempt == 19:
                    raise ValueError("Another Blankweave night-light instance is running") from None
                time.sleep(.1)
        if ipc("temperature").isdigit():
            raise ValueError("Another night-light service is running. Stop it before enabling Blankweave night light.")
        # hyprsunset 0.4.0's --config parser fails to consume its argument.
        # Use its normal XDG lookup inside a private config root instead, without
        # overwriting the user's ~/.config/hypr/hyprsunset.conf.
        config_root = directory / "night-light-runtime"
        config = config_root / "hypr/hyprsunset.conf"
        config.parent.mkdir(parents=True, exist_ok=True)
        atomic_write(config, configuration(value))
        os.set_inheritable(lock, True)
        os.execve(binary, [binary], {**os.environ, "XDG_CONFIG_HOME": str(config_root)})
    else:
        raise ValueError("Unknown night-light command")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
