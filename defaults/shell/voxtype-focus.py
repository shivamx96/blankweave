#!/usr/bin/env python3
"""Classify the active Hyprland target without treating uncertainty as failure.

Exit 0 means an editable target is present, 1 means it is definitely absent,
and 2 means the application does not expose enough accessibility information.
"""

import json
import os
import sys


forced = os.environ.get("BLANKWEAVE_VOXTYPE_FOCUS", "").strip().lower()
if forced:
    sys.exit(
        {
            "editable": 0,
            "none": 1,
            "unknown": 2,
            "timeout": 124,
            "failure": 126,
        }.get(forced, 2)
    )

try:
    window = json.load(sys.stdin)
except (json.JSONDecodeError, OSError):
    sys.exit(2)

address = str(window.get("address") or "")
pid = int(window.get("pid") or 0)
window_class = str(window.get("class") or "").lower()
if not address or address == "0x0" or pid <= 0:
    sys.exit(1)

# Terminal surfaces are editable even when their accessibility tree exposes a
# canvas/panel rather than a conventional text role.
terminal_classes = (
    "alacritty",
    "com.mitchellh.ghostty",
    "foot",
    "kitty",
    "org.gnome.console",
    "org.gnome.terminal",
    "wezterm",
)
if any(name in window_class for name in terminal_classes):
    sys.exit(0)

try:
    import gi

    gi.require_version("Atspi", "2.0")
    from gi.repository import Atspi
except (ImportError, ValueError):
    sys.exit(2)


def parent_pid(process_id: int) -> int:
    try:
        with open(f"/proc/{process_id}/stat", encoding="utf-8") as stat_file:
            stat = stat_file.read()
        return int(stat[stat.rfind(")") + 2 :].split()[1])
    except (OSError, ValueError, IndexError):
        return 0


def belongs_to_window(process_id: int) -> bool:
    """Accept an AT-SPI process that is the window PID or a descendant of it."""
    seen = set()
    while process_id > 1 and process_id not in seen:
        if process_id == pid:
            return True
        seen.add(process_id)
        process_id = parent_pid(process_id)
    return False


focused_seen = False
editable_seen = False
visited = 0


def inspect(node) -> None:
    global editable_seen, focused_seen, visited
    if visited >= 2500 or editable_seen:
        return
    visited += 1
    try:
        states = node.get_state_set()
        if states.contains(Atspi.StateType.FOCUSED):
            focused_seen = True
            if states.contains(Atspi.StateType.EDITABLE):
                editable_seen = True
                return
        child_count = node.get_child_count()
        for index in range(child_count):
            inspect(node.get_child_at_index(index))
            if editable_seen:
                return
    except Exception:
        # A disappearing or unresponsive accessibility node makes the result
        # uncertain, never proof that the user has no editable target.
        return


matched_application = False
try:
    for desktop_index in range(Atspi.get_desktop_count()):
        desktop = Atspi.get_desktop(desktop_index)
        for app_index in range(desktop.get_child_count()):
            application = desktop.get_child_at_index(app_index)
            if not belongs_to_window(application.get_process_id()):
                continue
            matched_application = True
            inspect(application)
except Exception:
    sys.exit(2)

if editable_seen:
    sys.exit(0)
if matched_application and focused_seen:
    sys.exit(1)
sys.exit(2)
