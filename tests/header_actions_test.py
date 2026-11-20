#!/usr/bin/env python3
"""Scan literal header action models, including both sides of conditional models."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


def headers(source):
    for match in re.finditer(r'ControlPanelHeader\s*\{', source):
        depth = 1
        start = pos = match.end()
        while depth:
            if source[pos] == "{":
                depth += 1
            elif source[pos] == "}":
                depth -= 1
            pos += 1
        yield source[start:pos - 1]


class HeaderActions(unittest.TestCase):
    def test_labels_and_switch_contract(self):
        count = 0
        for path in (ROOT / "defaults/quickshell").rglob("*.qml"):
            for block in headers(path.read_text()):
                for action in re.findall(r'\{[^{}]*"id"\s*:[^{}]*\}', block):
                    count += 1
                    self.assertRegex(action, r'"label"\s*:\s*(?:"[^"]+?"|root\.)', str(path))
                    if '"switch"' in action:
                        self.assertIn('"checked":', action)
                    self.assertNotRegex(action, r'[󰅖󰜺]', str(path))
        self.assertGreater(count, 20)

    def test_panel_ids_come_from_popups(self):
        ids = []
        for path in (ROOT / "defaults/quickshell/Modules").glob("*.qml"):
            source = path.read_text()
            if "ControlPopup {" in source:
                ids += re.findall(r'ControlPopup\s*\{\s*panelId: "([a-z-]+)"', source)
        self.assertEqual(len(ids), 18)
        self.assertEqual(len(ids), len(set(ids)))
        self.assertTrue({"audio", "network", "bluetooth", "display", "system", "power"}.issubset(ids))
        popup = (ROOT / "defaults/quickshell/Components/ControlPopup.qml").read_text()
        self.assertIn("session.registerPanel(root)", popup)
        self.assertIn("session.unregisterPanel(root)", popup)

    def test_radio_and_vpn_switches_are_pending_aware(self):
        for name in ("Network", "Bluetooth", "Tailscale"):
            block = next(headers((ROOT / f"defaults/quickshell/Modules/{name}Widget.qml").read_text()))
            power = re.search(r'\{[^{}]*"id": "power"[^{}]*\}', block).group()
            for field in ('"kind": "switch"', '"checked":', '"pending":'):
                self.assertIn(field, power)


if __name__ == "__main__":
    unittest.main()
