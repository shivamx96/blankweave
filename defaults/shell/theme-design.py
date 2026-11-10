#!/usr/bin/env python3
"""Resolve bounded, declarative design overrides without executing theme code."""

import copy
import json
import math
from pathlib import Path
import re
import sys


def read_json(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate key: {key}")
            result[key] = value
        return result

    return json.loads(Path(path).read_text(), object_pairs_hook=unique)


def bounds(group, key):
    if group == "spacing":
        return 0, 64
    if group == "shape":
        return (0, 3) if key == "borderWidth" else (0, 32)
    if group == "typography":
        return (14, 40) if key == "headingSize" else (9, 24)
    if group == "sizes":
        return (24, 64) if key in ("barHeight", "widgetHeight") else (8, 64)
    return 0, 1000


def validate_value(group, key, value, default):
    name = f"design.{group}.{key}"
    if type(default) is bool:
        if type(value) is not bool:
            raise ValueError(f"{name} must be a boolean")
    elif type(default) in (int, float):
        if key in ("textWeight", "headingWeight"):
            if type(value) is not int or not 100 <= value <= 900:
                raise ValueError(f"{name} must be an integer between 100 and 900")
            return
        low, high = bounds(group, key)
        if type(value) not in (int, float) or not math.isfinite(value) or not low <= value <= high:
            raise ValueError(f"{name} must be a finite number between {low} and {high}")
    elif not isinstance(value, str):
        raise ValueError(f"{name} must be a string")
    elif key in ("gradientStart", "gradientEnd"):
        if not re.fullmatch(r"#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?", value):
            raise ValueError(f"{name} must be a CSS hex color")
    elif key == "gradientDirection":
        if value not in ("vertical", "horizontal"):
            raise ValueError(f"{name} must be vertical or horizontal")
    elif key == "easing":
        if value not in ("linear", "outCubic", "inOutCubic"):
            raise ValueError(f"{name} must be linear, outCubic, or inOutCubic")
    elif not value.strip() or len(value) > 100 or not re.fullmatch(r"[\w .-]+", value):
        raise ValueError(f"{name} must be a nonempty font name using letters, numbers, spaces, dots, underscores, or hyphens (max 100 characters)")


def overlay(base, override, defaults):
    if not isinstance(override, dict):
        raise ValueError("design must be an object")
    for group, entries in override.items():
        if group not in defaults:
            raise ValueError(f"unknown design group: {group}")
        if not isinstance(entries, dict):
            raise ValueError(f"design.{group} must be an object")
        for key, value in entries.items():
            if key not in defaults[group]:
                raise ValueError(f"unknown design token: {group}.{key}")
            validate_value(group, key, value, defaults[group][key])
            base[group][key] = value
    return base


def resolve(defaults, theme, mode):
    if not isinstance(defaults, dict) or not isinstance(theme, dict):
        raise ValueError("defaults and theme must be objects")
    result = overlay(copy.deepcopy(defaults), defaults, defaults)
    overlay(result, theme.get("design", {}), defaults)
    modes = theme.get("modes")
    if not isinstance(modes, dict) or mode not in modes:
        raise ValueError(f"theme has no {mode} mode")
    # Reject malformed overrides even in the inactive mode: both variants are
    # one theme, and discovery must not advertise a partially usable choice.
    for name, variant in modes.items():
        if not isinstance(variant, dict):
            raise ValueError(f"theme mode {name} must be an object")
        overlay(copy.deepcopy(result), variant.get("design", {}), defaults)
    return overlay(result, modes[mode].get("design", {}), defaults)


def main():
    if len(sys.argv) != 4:
        raise ValueError("usage: theme-design.py DEFAULTS THEME MODE")
    print(json.dumps(resolve(read_json(sys.argv[1]), read_json(sys.argv[2]), sys.argv[3]), allow_nan=False))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, TypeError, KeyError) as error:
        print(f"theme-design: {error}", file=sys.stderr)
        sys.exit(1)
