#!/usr/bin/env python3
"""Check rendered geometry and per-mode shadow against resolved theme state."""
import json
from pathlib import Path
import sys

state = json.loads(Path(sys.argv[1]).read_text())
hypr, dunst, lock = (Path(p).read_text() for p in sys.argv[2:5])
shape = state["design"]["shape"]
shadow = state["windowShadow"]
assert f'rounding = {shape["windowRadius"]},' in hypr
assert f'border_size = {shape["windowBorderWidth"]},' in hypr
assert f'corner_radius = {shape["notificationRadius"]}\n' in dunst
assert f'frame_width = {shape["borderWidth"]}\n' in dunst
assert f'$panel_radius = {shape["panelRadius"]}\n' in lock
assert f'$lock_field_radius = {shape["lockFieldRadius"]}\n' in lock
assert f'$border_width = {shape["borderWidth"]}\n' in lock
expected_color = (state["colors"]["text"] if state["mode"] == "light" else state["colors"]["canvas"])[:7]
expected_color += "18" if state["mode"] == "light" else "55"
assert shadow["color"] == expected_color
assert f'shadow_color = "rgba({expected_color[1:]})",' in hypr
assert shadow["range"] == (12 if state["mode"] == "light" else 8)
assert f'shadow_range = {shadow["range"]},' in hypr
assert 'shadow_offset = { 0, 2 },' in hypr

# Explicit legacy geometry, independent of the template-token assertions above.
keys = ("windowRadius", "windowBorderWidth", "notificationRadius", "borderWidth", "panelRadius", "lockFieldRadius")
if state["theme"] in ("obsidian", "moss"):
    assert tuple(shape[k] for k in keys) == (10, 2, 0, 1, 14, 10)
elif state["theme"] == "aurora":
    assert tuple(shape[k] for k in keys) == (8, 2, 8, 1, 8, 5)
elif state["theme"] == "shape-test":
    assert tuple(shape[k] for k in keys) == ((6, 1, 4, 2, 9, 8) if state["mode"] == "dark" else (5, 3, 2, 3, 7, 6))
base_lock = (Path(__file__).resolve().parents[1] / "defaults/hypr/hyprlock.conf").read_text()
assert "rounding = $lock_field_radius" in base_lock
assert "rounding = $panel_radius" in base_lock
assert "border_size = $border_width" in base_lock
assert "outline_thickness = $border_width" in base_lock

fallback = (Path(__file__).resolve().parents[1] / "defaults/hypr/hyprland.lua").read_text()
assert "rounding = theme.rounding or 10," in fallback
assert "border_size = theme.border_size or 2," in fallback

typography = state['design']['typography']
assert f"$lock_font = {typography['fontFamily']}\n" in lock
assert f"$lock_icon_font = {typography['iconFontFamily']}\n" in lock
assert '$lock_time = $TIME' in lock if len(sys.argv) <= 5 else True
if len(sys.argv) > 5:
    assert f'$lock_time = {sys.argv[5]}\n' in lock
    assert f'$lock_time_size = {88 if sys.argv[5] == chr(36) + "TIME12" else 120}\n' in lock
assert 'cmd[update:1000] date' not in base_lock
assert 'text = $lock_time' in base_lock
assert 'Caps Lock' in (Path(__file__).resolve().parents[1] / 'defaults/shell/lock-caps.sh').read_text()
assert 'fail_text = Incorrect password — attempt $ATTEMPTS' in base_lock
assert 'font_family = Atkinson' not in base_lock
