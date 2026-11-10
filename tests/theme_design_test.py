#!/usr/bin/env python3
"""Theme inheritance contracts and resolver boundary checks in an isolated home."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("theme_design", REPO / "defaults/shell/theme-design.py")
design = importlib.util.module_from_spec(spec)
spec.loader.exec_module(design)
DEFAULTS = design.read_json(REPO / "defaults/themes/design-defaults.json")
THEME = design.read_json(REPO / "defaults/themes/obsidian/theme.json")


class DesignTests(unittest.TestCase):
    def test_existing_themes_inherit_complete_defaults(self):
        for path in (REPO / "defaults/themes").glob("*/theme.json"):
            theme = design.read_json(path)
            if "design" not in theme:
                for mode in ("dark", "light"):
                    self.assertEqual(design.resolve(DEFAULTS, theme, mode), DEFAULTS)

    def test_mode_override_wins_without_losing_siblings(self):
        theme = copy.deepcopy(THEME)
        theme["design"] = {"spacing": {"panel": 20}, "shape": {"panelRadius": 8}}
        theme["modes"]["light"]["design"] = {"spacing": {"panel": 24}}
        self.assertEqual(design.resolve(DEFAULTS, theme, "dark")["spacing"]["panel"], 20)
        light = design.resolve(DEFAULTS, theme, "light")
        self.assertEqual(light["spacing"]["panel"], 24)
        self.assertEqual(light["spacing"]["xs"], 4)
        self.assertEqual(light["shape"]["panelRadius"], 8)
        self.assertEqual(DEFAULTS["spacing"]["panel"], 18)

    def test_invalid_overrides_are_rejected_in_either_mode(self):
        invalid = [None, [], {"unknown": {}}, {"spacing": None},
                   {"spacing": {"panel": True}}, {"spacing": {"panel": -1}},
                   {"spacing": {"panel": 65}}, {"spacing": {"panel": float("nan")}},
                   {"shape": {"panelRadius": "8"}}, {"shape": {"borderWidth": 4}},
                   {"typography": {"fontFamily": "bad\nfont"}},
                   {"typography": {"fontFamily": "Font #comment"}},
                   {"typography": {"monoFontFamily": "$injected"}},
                   {"typography": {"iconFontFamily": "Font=other"}},
                   {"typography": {"textWeight": 400.5}},
                   {"materials": {"gradientEnabled": 1}},
                   {"materials": {"gradientStart": "red"}},
                   {"materials": {"gradientDirection": "diagonal"}},
                   {"motion": {"easing": "execute()"}}, {"motion": {"duration": 1001}}]
        for override in invalid:
            with self.subTest(override=override):
                theme = copy.deepcopy(THEME)
                theme["modes"]["light"]["design"] = override
                with self.assertRaises(ValueError):
                    design.resolve(DEFAULTS, theme, "dark")

    def test_explicit_zero_and_false_are_preserved(self):
        theme = copy.deepcopy(THEME)
        theme["design"] = {"shape": {"panelRadius": 0}, "materials": {"gradientEnabled": True}}
        theme["modes"]["dark"]["design"] = {"materials": {"gradientEnabled": False}}
        value = design.resolve(DEFAULTS, theme, "dark")
        self.assertEqual(value["shape"]["panelRadius"], 0)
        self.assertFalse(value["materials"]["gradientEnabled"])

    def test_script_resolves_and_rejects_before_outputs_change(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            data = home / ".local/share/blankweave"
            config = home / ".config/blankweave"
            for directory in ("shell", "themes"):
                shutil.copytree(REPO / "defaults" / directory, data / directory)
            config.mkdir(parents=True)
            env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"),
                       BLANKWEAVE_ICONS_DIR=str(home / "icons"),
                       BLANKWEAVE_PLYMOUTH_DIR=str(home / "plymouth"))
            env.pop("BLANKWEAVE_SETUP_THEME", None)
            env.pop("BLANKWEAVE_SETUP_MODE", None)
            script = data / "shell/theme-apply.sh"
            result = subprocess.run(["bash", script, "status"], env=env, capture_output=True, text=True, check=True)
            self.assertEqual(json.loads(result.stdout)["design"], DEFAULTS)
            custom = config / "themes/custom"
            custom.mkdir(parents=True)
            theme = copy.deepcopy(THEME)
            theme["design"] = {"spacing": {"panel": 22}}
            (custom / "theme.json").write_text(json.dumps(theme))
            env["BLANKWEAVE_SETUP_THEME"] = "custom"
            result = subprocess.run(["bash", script, "status"], env=env, capture_output=True, text=True, check=True)
            self.assertEqual(json.loads(result.stdout)["design"]["spacing"]["panel"], 22)
            state = config / "theme.json"
            state.write_text('{"theme":"obsidian","mode":"dark"}\n')
            rendered = config / "theme.lua"
            rendered.write_text("existing rendered output\n")
            before = (state.read_bytes(), rendered.read_bytes())
            theme["design"]["spacing"]["panel"] = -1
            (custom / "theme.json").write_text(json.dumps(theme))
            result = subprocess.run(["bash", script, "set", "custom"], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("design.spacing.panel", result.stderr)
            self.assertEqual((state.read_bytes(), rendered.read_bytes()), before)
            result = subprocess.run(["bash", script, "list"], env=env, capture_output=True, text=True, check=True)
            row = next(row for row in json.loads(result.stdout) if row["id"] == "custom")
            self.assertTrue(row["invalid"])


if __name__ == "__main__":
    unittest.main()
