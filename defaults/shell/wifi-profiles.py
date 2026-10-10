#!/usr/bin/env python3
"""List and forget saved Wi-Fi profiles without requesting their secrets."""
import json
import re
import subprocess
import sys

SERVICE = "org.freedesktop.NetworkManager"
ROOT = "/org/freedesktop/NetworkManager"
SETTINGS = SERVICE + ".Settings"
CONNECTION = SETTINGS + ".Connection"


def bus(operation, path, interface, member, *arguments):
    result = subprocess.run(["busctl", "--system", "--json=short", "--timeout=5", operation,
                             SERVICE, path, interface, member, *arguments],
                            capture_output=True, text=True, timeout=7, check=False)
    if result.returncode:
        raise ValueError("NetworkManager could not complete the request. Check permissions and retry.")
    return json.loads(result.stdout)["data"] if result.stdout.strip() else None


def settings(path):
    return bus("call", path, CONNECTION, "GetSettings")[0]


def value(section, key, default=None):
    return section.get(key, {}).get("data", default)


def active_uuids():
    paths = bus("get-property", ROOT, SERVICE, "ActiveConnections")
    return {bus("get-property", path, SERVICE + ".Connection.Active", "Uuid") for path in paths}


def status():
    active = active_uuids()
    paths = bus("call", ROOT + "/Settings", SETTINGS, "ListConnections")[0]
    rows = []
    for path in paths:
        data = settings(path)
        connection = data.get("connection", {})
        if value(connection, "type") != "802-11-wireless":
            continue
        uuid = value(connection, "uuid")
        ssid = bytes(value(data.get("802-11-wireless", {}), "ssid", [])).decode("utf-8", "replace")
        rows.append({"uuid": uuid, "name": value(connection, "id", ssid), "ssid": ssid, "active": uuid in active})
    return sorted(rows, key=lambda row: (row["name"].casefold(), row["uuid"]))


def forget(uuid):
    if not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", uuid):
        raise ValueError("Invalid saved network identity.")
    path = bus("call", ROOT + "/Settings", SETTINGS, "GetConnectionByUuid", "s", uuid)[0]
    connection = settings(path).get("connection", {})
    if value(connection, "uuid") != uuid or value(connection, "type") != "802-11-wireless":
        raise ValueError("That saved Wi-Fi network is no longer available.")
    if uuid in active_uuids():
        raise ValueError("Disconnect this network before forgetting it.")
    bus("call", path, CONNECTION, "Delete")


if __name__ == "__main__":
    try:
        if sys.argv[1:] == ["status"]:
            print(json.dumps(status()))
        elif len(sys.argv) == 3 and sys.argv[1] == "forget":
            forget(sys.argv[2])
        else:
            raise ValueError("Usage: wifi-profiles.py status | forget UUID")
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(f"Could not update saved networks: {error}", file=sys.stderr)
        sys.exit(1)
