#!/usr/bin/env python3
"""Desktop sound preferences in GSettings, mirrored to GTK's fallback files."""
import ast
import configparser
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

import gtk_settings

SCHEMA = "org.gnome.desktop.sound"
KEYS = {"event-sounds": "gtk-enable-event-sounds", "input-feedback-sounds": "gtk-enable-input-feedback-sounds",
        "theme-name": "gtk-sound-theme-name"}


def run(arguments):
    result = subprocess.run(arguments, capture_output=True, text=True, timeout=8, check=False)
    if result.returncode:
        raise ValueError("Desktop sound command failed. Check the sound service and try again.")
    return result.stdout.strip()


def read_preferences():
    result = {}
    for key in KEYS:
        raw = run(["gsettings", "get", SCHEMA, key])
        value = ast.literal_eval(raw) if key == "theme-name" else {"true": True, "false": False}.get(raw)
        if (key == "theme-name" and not isinstance(value, str)) or value is None:
            raise ValueError("Could not read desktop sound preferences.")
        result[key] = value
    return result


def themes():
    roots = [Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))]
    roots += [Path(path) for path in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":") if path]
    found = {}
    for root in roots:
        directory = root / "sounds"
        if not directory.is_dir():
            continue
        for child in sorted(directory.iterdir()):
            if child.name in found or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", child.name):
                continue
            parser = configparser.ConfigParser(interpolation=None)
            try:
                parser.read_string((child / "index.theme").read_text())
                section = parser["Sound Theme"]
                if section.getboolean("Hidden", fallback=False):
                    continue
                found[child.name] = {"id": child.name, "name": section.get("Name", child.name)}
            except (OSError, UnicodeError, KeyError, configparser.Error, ValueError):
                continue
    return sorted(found.values(), key=lambda theme: (theme["name"].casefold(), theme["id"]))


def gtk_values(preferences):
    return {KEYS[key]: str(value).lower() if isinstance(value, bool) else value for key, value in preferences.items()}


def status():
    preferences = read_preferences()
    expected = gtk_values(preferences)
    synced = True
    for version in ("gtk-3.0", "gtk-4.0"):
        try:
            _, values = gtk_settings.read(gtk_settings.config_root() / version / "settings.ini")
            synced &= all(values.get(key) == value for key, value in expected.items())
        except (OSError, UnicodeError, configparser.Error):
            synced = False
    return {"preferences": preferences, "themes": themes(), "gtkSynced": synced,
            "writable": {key: run(["gsettings", "writable", SCHEMA, key]) == "true" for key in KEYS},
            "previewAvailable": shutil.which("canberra-gtk-play") is not None}


def apply(key=None, value=None):
    with gtk_settings.locked():
        preferences = read_preferences()
        if key is not None:
            if key not in KEYS or run(["gsettings", "writable", SCHEMA, key]) != "true":
                raise ValueError("This sound preference is read-only.")
            if key == "theme-name":
                if value not in [theme["id"] for theme in themes()]:
                    raise ValueError("That sound theme is no longer installed. Refresh and choose another.")
            elif value not in ("true", "false"):
                raise ValueError("Invalid sound preference.")
            preferences[key] = value if key == "theme-name" else value == "true"
        # Validate both fallback files before changing GSettings.
        prepared = gtk_settings.prepare(gtk_values(preferences))
        if key is not None:
            run(["gsettings", "set", SCHEMA, key, repr(value) if key == "theme-name" else value])
            if read_preferences()[key] != preferences[key]:
                raise ValueError("The desktop did not accept the sound preference.")
        gtk_settings.write(prepared)


def preview():
    preferences = read_preferences()
    if not preferences["event-sounds"]:
        raise ValueError("Enable event sounds before playing a preview.")
    theme = preferences["theme-name"]
    if theme not in [row["id"] for row in themes()]:
        raise ValueError("The selected sound theme is not installed.")
    run(["canberra-gtk-play", "--id=dialog-information", "--description=Blankweave sound preview",
         "--volume=-12", "--property=canberra.enable=1", "--property=canberra.xdg-theme.name=" + theme])


def main():
    arguments = sys.argv[1:]
    if arguments == ["status"]:
        print(json.dumps(status()))
    elif len(arguments) == 3 and arguments[0] == "set":
        apply(arguments[1], arguments[2])
    elif arguments == ["sync"]:
        apply()
    elif arguments == ["preview"]:
        preview()
    else:
        raise ValueError("Usage: system-sounds.py status | set KEY VALUE | sync | preview")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, SyntaxError, UnicodeError, configparser.Error, subprocess.SubprocessError) as error:
        print(f"Could not apply sound settings: {error}", file=sys.stderr)
        sys.exit(1)
