#!/usr/bin/env python3
"""A stateful fake compositor, including mirrors missing from the default list."""
import json
import os
from pathlib import Path
import re
import sys

state = Path(os.environ["LAYOUT_TEST_STATE"])
rows = json.loads(state.read_text())
if sys.argv[1] == "monitors":
    print(json.dumps(rows if "all" in sys.argv else [row for row in rows if row.get("mirrorOf", "none") == "none"]))
    sys.exit(0)
if sys.argv[1] == "configerrors":
    print("")
    sys.exit(0)
if sys.argv[1] == "reload":
    for row in rows:
        row.pop("icc", None)
    rules = Path(os.environ["XDG_CONFIG_HOME"]) / "blankweave/monitors.lua"
    command = rules.read_text() if rules.exists() else ""
else:
    command = sys.argv[2]
if 'icc = ""' in command:
    sys.exit(1)  # Native Hyprland rejects empty ICC paths.
if os.environ.get("LAYOUT_REJECT_ICC") and 'icc = "' in command and 'icc = ""' not in command:
    sys.exit(1)
with open(os.environ["LAYOUT_TEST_LOG"], "a") as log:
    log.write(command + "\n")
if command.startswith("dofile"):
    path = json.loads(re.search(r'dofile\((".*")\)', command)[1])
    command = Path(path).read_text()
for rule in re.findall(r'hl.monitor\(\{ (.*?) \}\)', command):
    fields = {key: json.loads(value) for key, value in re.findall(r'(\w+) = ("[^"]*"|-?[\d.]+)', rule)}
    row = next((r for r in rows if "desc:" + r["description"] == fields["output"]), None)
    if row is None:
        continue
    if "mode" in fields and fields["mode"] != "preferred":
        width, height, rate = re.split('[x@]', fields["mode"])
        row.update(width=int(width), height=int(height), refreshRate=float(rate))
    if "scale" in fields:
        row["scale"] = fields["scale"] if fields["scale"] != "auto" else 1
    if "position" in fields and not fields["position"].startswith("auto"):
        row["x"], row["y"] = map(int, fields["position"].split("x"))
    for key in ("icc", "cm"):
        if key in fields:
            row[key] = fields[key]
    if "transform" in fields:
        row["transform"] = fields["transform"]
    if "mirror" in fields and not (fields["mirror"] and os.environ.get("LAYOUT_IGNORE_MIRROR")):
        source = next((r for r in rows if "desc:" + r["description"] == fields["mirror"]), None)
        row["mirrorOf"] = str(source["id"]) if source else "none"
    for mirror in rows:
        source = next((r for r in rows if str(r["id"]) == mirror.get("mirrorOf")), None)
        if source:
            mirror["x"], mirror["y"] = source["x"], source["y"]
stage = state.with_suffix(".stage")
stage.write_text(json.dumps(rows))
stage.replace(state)
print("ok")
