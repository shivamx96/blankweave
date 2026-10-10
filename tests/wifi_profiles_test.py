#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

PATH = Path(__file__).resolve().parents[1] / "defaults/shell/wifi-profiles.py"
SPEC = importlib.util.spec_from_file_location("wifi_profiles", PATH)
profiles = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(profiles)


class ProfilesTest(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.active = set()
        self.wifi = "11111111-1111-1111-1111-111111111111"
        self.other = "22222222-2222-2222-2222-222222222222"
        self.rows = {"/wifi": self.setting(self.wifi, "802-11-wireless", "Cafe: <b>network</b>"),
                     "/other": self.setting(self.other, "802-3-ethernet", "Ethernet")}
        self.patcher = patch.object(profiles.subprocess, "run", self.run_bus)
        self.patcher.start()
        self.addCleanup(self.patcher.stop)

    def setting(self, uuid, kind, name):
        return {"connection": {key: {"type": "s", "data": value} for key, value in
                               {"uuid": uuid, "type": kind, "id": name}.items()},
                "802-11-wireless": {"ssid": {"type": "ay", "data": list("Cafe\\\n☕".encode())}}}

    def run_bus(self, args, **kwargs):
        self.calls.append(args)
        self.assertEqual(args[:4], ["busctl", "--system", "--json=short", "--timeout=5"])
        self.assertEqual(kwargs["timeout"], 7)
        operation, service, path, interface, member, *params = args[4:]
        self.assertEqual(service, profiles.SERVICE)
        if member == "ActiveConnections":
            data = ["/active/" + uuid for uuid in self.active]
        elif member == "Uuid":
            data = path.removeprefix("/active/")
        elif member == "ListConnections":
            data = [list(self.rows)]
        elif member == "GetSettings":
            data = [self.rows[path]]
        elif member == "GetConnectionByUuid":
            data = [next(path for path, row in self.rows.items() if row["connection"]["uuid"]["data"] == params[1])]
        elif member == "Delete":
            del self.rows[path]
            return subprocess.CompletedProcess(args, 0, "", "")
        else:
            self.fail("Unexpected method: " + member)
        return subprocess.CompletedProcess(args, 0, json.dumps({"data": data}), "")

    def test_status_filters_and_preserves_names_without_secrets(self):
        self.active.add(self.wifi)
        result = profiles.status()
        self.assertEqual(result, [{"uuid": self.wifi, "name": "Cafe: <b>network</b>", "ssid": "Cafe\\\n☕", "active": True}])
        self.assertFalse(any("GetSecrets" in call for call in self.calls))

    def test_forget_exact_profile_even_with_duplicate_names(self):
        self.rows["/duplicate"] = self.setting("33333333-3333-3333-3333-333333333333", "802-11-wireless", "Cafe: <b>network</b>")
        profiles.forget(self.wifi)
        self.assertNotIn("/wifi", self.rows)
        self.assertIn("/duplicate", self.rows)
        self.assertIn("/other", self.rows)

    def test_active_profile_cannot_be_forgotten(self):
        self.active.add(self.wifi)
        with self.assertRaisesRegex(ValueError, "Disconnect"):
            profiles.forget(self.wifi)
        self.assertIn("/wifi", self.rows)

    def test_non_wifi_and_invalid_identity_cannot_be_deleted(self):
        with self.assertRaisesRegex(ValueError, "Invalid"):
            profiles.forget("--bad")
        self.assertEqual(self.calls, [])
        with self.assertRaisesRegex(ValueError, "no longer available"):
            profiles.forget(self.other)
        self.assertIn("/other", self.rows)

    def test_permission_errors_are_reported_without_command_output(self):
        with patch.object(profiles.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "", "private details")):
            with self.assertRaisesRegex(ValueError, "Check permissions") as error:
                profiles.status()
            self.assertNotIn("private details", str(error.exception))


if __name__ == "__main__":
    unittest.main()
