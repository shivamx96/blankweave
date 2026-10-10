#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

state = Path(os.environ["SETTINGS_WIFI_PROFILES_STATE"])
rows = json.loads(state.read_text()) if state.exists() else [
    {"uuid": "profile-test", "name": "Saved offline", "ssid": "Saved offline", "active": False},
    {"uuid": "profile-fail", "name": "Permission denied", "ssid": "Permission denied", "active": False}]
if sys.argv[1:] == ["status"]:
    print(json.dumps(rows))
elif sys.argv[1:] == ["forget", "profile-fail"]:
    print("Permission denied by fixture", file=sys.stderr)
    sys.exit(1)
elif sys.argv[1:] == ["forget", "profile-test"]:
    state.write_text(json.dumps([row for row in rows if row["uuid"] != "profile-test"]))
else:
    sys.exit(2)
