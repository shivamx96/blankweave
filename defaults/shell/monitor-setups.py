#!/usr/bin/env python3
"""Layout operations for monitor-layout.sh; its flock serializes every writer."""
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import uuid


def require(condition, message):
    if not condition:
        raise ValueError(message)


def live_monitors():
    rows = json.loads(subprocess.check_output(["hyprctl", "monitors", "all", "-j"], timeout=5))
    rows = [row for row in rows if not row.get("disabled", False)]
    for row in rows:
        source = str(row.get("mirrorOf", "none"))
        row["mirrorConnector"] = next((other["name"] for other in rows
            if str(other.get("id", "")) == source or other["name"] == source), "") if source != "none" else ""
        require(source == "none" or row["mirrorConnector"], "Could not identify a mirrored display's source")
    return rows


def safe_description(value):
    return isinstance(value, str) and re.fullmatch(r'[\x20-\x21\x23-\x5b\x5d-\x7e]+', value)


def validate_entry(row):
    require(safe_description(row.get("description")), "This display needs a unique, usable description")
    require(re.fullmatch(r'(preferred|[1-9][0-9]*x[1-9][0-9]*@[0-9]+(?:\.[0-9]+)?)', row.get("mode", "preferred")), "Invalid display mode")
    scale = row.get("scale")
    require(scale == "auto" or (type(scale) in (int, float) and math.isfinite(scale) and scale > 0), "Invalid display scale")
    require(re.fullmatch(r'(auto(?:-left|-right|-up|-down)?|-?[0-9]+x-?[0-9]+)', row.get("position", "")), "Invalid display position")
    require(type(row.get("transform", 0)) is int and 0 <= row.get("transform", 0) <= 7, "Invalid display rotation")
    require(not row.get("mirror") or safe_description(row["mirror"]), "Invalid mirror source")


def render(row):
    validate_entry(row)
    fields = [f'output = "desc:{row["description"]}"', f'mode = "{row.get("mode", "preferred")}"',
        f'position = "{row["position"]}"', f'scale = {json.dumps(row["scale"])}']
    if "transform" in row:
        fields.append(f'transform = {row["transform"]}')
    if "mirror" in row:
        fields.append('mirror = ' + json.dumps("desc:" + row["mirror"] if row["mirror"] else ""))
    return "hl.monitor({ " + ", ".join(fields) + " })"


def snapshot(live):
    require(live, "No connected displays to save")
    require(len({row["description"] for row in live}) == len(live), "These displays have identical descriptions; a setup cannot distinguish them")
    names = {row["name"]: row["description"] for row in live}
    result = []
    for row in live:
        entry = {"description": row["description"], "mode": f'{row["width"]}x{row["height"]}@{row["refreshRate"]}',
            "position": f'{row["x"]}x{row["y"]}', "scale": row["scale"], "scaleExplicit": True,
            "transform": row.get("transform", 0), "mirror": names.get(row["mirrorConnector"], "")}
        validate_entry(entry)
        result.append(entry)
    return result


def read_json(path, default):
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text())
    except (ValueError, OSError) as error:
        raise ValueError("Could not read saved display setups; the file was left unchanged") from error


def atomic_write(path, text):
    fd, stage = tempfile.mkstemp(prefix=".monitor-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(text)
        os.replace(stage, path)
    finally:
        if os.path.exists(stage):
            os.unlink(stage)


def mode_supported(entry, monitor):
    width, height, rate = re.split('[x@]', entry["mode"])
    for mode in monitor.get("availableModes", []):
        match = re.fullmatch(r'(\d+)x(\d+)@([0-9.]+)Hz', mode)
        if match and int(match[1]) == int(width) and int(match[2]) == int(height) and abs(float(match[3]) - float(rate)) < .006:
            return True
    return False


def compatible(entries, live):
    require(len({row["description"] for row in live}) == len(live), "Connected displays have identical descriptions")
    require({row["description"] for row in entries} == {row["description"] for row in live}, "Connect the same displays that were used to save this setup")
    require(entries and len({row["description"] for row in entries}) == len(entries), "Invalid saved display list")
    for entry in entries:
        validate_entry(entry)
        require(entry["mode"] != "preferred" and type(entry["scale"]) in (int, float)
            and re.fullmatch(r'-?[0-9]+x-?[0-9]+', entry["position"]), "Invalid saved display geometry")
        monitor = next(row for row in live if row["description"] == entry["description"])
        require(mode_supported(entry, monitor), "A saved resolution or refresh rate is no longer supported")
        if entry.get("mirror"):
            source = next((row for row in entries if row["description"] == entry["mirror"]), None)
            require(source is not None and source is not entry and not source.get("mirror"), "The saved mirror source is unavailable")


def matches(entries, live, restoring=False):
    by_description = {row["description"]: row for row in live}
    by_name = {row["name"]: row["description"] for row in live}
    for entry in entries:
        row = by_description.get(entry["description"])
        if not row:
            if restoring:
                continue
            return False
        width, height, rate = re.split('[x@]', entry["mode"])
        if row["width"] != int(width) or row["height"] != int(height) or abs(row["refreshRate"] - float(rate)) >= .006:
            return False
        if abs(row["scale"] - entry["scale"]) > .0001 or row.get("transform", 0) != entry.get("transform", 0):
            return False
        source = entry.get("mirror", "")
        if restoring and source not in by_description:
            source = ""
        if by_name.get(row["mirrorConnector"], "") != source:
            return False
        if not source and entry["position"] != f'{row["x"]}x{row["y"]}':
            return False
    return True


def verify(entries, restoring=False):
    for _ in range(20):
        if matches(entries, live_monitors(), restoring):
            return True
        time.sleep(.1)
    return False


def evaluate(command):
    subprocess.run(["hyprctl", "eval", command], check=True, capture_output=True, timeout=5)


def apply_layout(entries):
    # Remove old mirror relationships before changing sources. Read-back between
    # phases prevents the compositor coalescing a source change into a cycle.
    live = live_monitors()
    descriptions = {entry["description"] for entry in entries}
    for row in live:
        if row["mirrorConnector"] and row["description"] in descriptions:
            evaluate(f'hl.monitor({{ output = "desc:{row["description"]}", mirror = "" }})')
    for _ in range(20):
        if not any(row["mirrorConnector"] and row["description"] in descriptions for row in live_monitors()):
            break
        time.sleep(.1)
    else:
        raise ValueError("Could not extend the displays before applying the setup")
    for mirrored in (False, True):
        for entry in entries:
            if bool(entry.get("mirror")) == mirrored:
                evaluate(render(entry))
        # Let source modes settle before attaching their mirrors.
        if not mirrored:
            time.sleep(.15)


class Setups:
    def __init__(self, directory, shell):
        self.directory = Path(directory)
        self.shell = shell
        self.store = self.directory / "monitor-setups.json"
        self.pending = self.directory / ".monitor-mode-preview.json"

    def presets(self):
        rows = read_json(self.store, {"setups": []})["setups"]
        require(isinstance(rows, list) and all(isinstance(row, dict) and isinstance(row.get("name"), str) and isinstance(row.get("id"), str)
            and isinstance(row.get("monitors"), list) for row in rows), "Invalid saved display setups")
        return rows

    def status(self, live):
        result = []
        for preset in self.presets():
            reason = ""
            try:
                compatible(preset["monitors"], live)
            except (ValueError, TypeError, KeyError) as error:
                reason = str(error)
            result.append({"id": preset["id"], "name": preset["name"], "available": not reason,
                "reason": reason, "summary": f'{len(preset["monitors"])} {"display" if len(preset["monitors"]) == 1 else "displays"} · modes, scaling, positions and mirroring'})
        return result

    def save(self, name):
        require(not self.pending.exists(), "Keep or revert the current preview first")
        name = name.strip()
        require(0 < len(name) <= 60 and all(ord(char) >= 32 and ord(char) != 127 for char in name), "Use a setup name of 1–60 characters")
        presets = self.presets()
        require(not any(row["name"].casefold() == name.casefold() for row in presets), "A setup with that name already exists; choose another name")
        presets.append({"id": str(uuid.uuid4()), "name": name, "monitors": snapshot(live_monitors())})
        atomic_write(self.store, json.dumps({"setups": presets}, indent=2))

    def delete(self, identifier):
        require(not self.pending.exists(), "Keep or revert the current preview first")
        presets = self.presets()
        require(any(row["id"] == identifier for row in presets), "This saved setup no longer exists")
        atomic_write(self.store, json.dumps({"setups": [row for row in presets if row["id"] != identifier]}, indent=2))

    def preview(self, entries, previous, label, persist_descriptions=None):
        require(not self.pending.exists(), "Keep or revert the current preview first")
        token = str(uuid.uuid4())
        pending = {"kind": "layout", "label": label, "token": token, "mode": "", "connector": "",
            "deadline": int(time.time()) + 20, "entries": entries, "previousLayout": previous,
            "persistDescriptions": persist_descriptions or [row["description"] for row in entries]}
        atomic_write(self.pending, json.dumps(pending))
        with (self.directory / ".mode-preview.log").open("w") as log:
            subprocess.Popen(["bash", self.shell, "mode-watch", token], stdin=subprocess.DEVNULL,
                stdout=log, stderr=log, start_new_session=True, close_fds=True)
        try:
            apply_layout(entries)
            require(verify(entries), "The displays did not accept the setup")
        except (ValueError, subprocess.SubprocessError):
            self.revert(token)
            raise ValueError("The displays did not accept the setup; the previous layout was restored") from None

    def restore(self, identifier):
        preset = next((row for row in self.presets() if row["id"] == identifier), None)
        require(preset is not None, "This saved setup no longer exists")
        live = live_monitors()
        compatible(preset["monitors"], live)
        self.preview(preset["monitors"], snapshot(live), f'Restore “{preset["name"]}”')

    def mirror(self, connector, source):
        live = live_monitors()
        previous = snapshot(live)
        target = next((row for row in live if row["name"] == connector), None)
        require(target is not None, "The selected display disconnected")
        entries = [dict(row) for row in previous]
        entry = next(row for row in entries if row["description"] == target["description"])
        saved = read_json(self.directory / "monitors.json", {"monitors": []})["monitors"]
        saved_target = next((row for row in saved if row["description"] == target["description"]), {})
        if source != "none":
            source_row = next((row for row in live if row["name"] == source), None)
            require(source_row is not None and source != connector, "Choose another connected display to mirror")
            require(not source_row["mirrorConnector"], "A mirrored display cannot be used as a source")
            require(not any(row["mirrorConnector"] == connector for row in live), "Extend this display's mirrors before changing its source")
            entry["mirror"] = source_row["description"]
            if not target["mirrorConnector"]:
                entry["extendedPosition"] = entry["position"]
        else:
            entry["mirror"] = ""
            if target["mirrorConnector"]:
                others = [row for row in live if row["name"] != connector and not row["mirrorConnector"]]
                right = max(row["x"] + (row["height"] if row.get("transform", 0) % 2 else row["width"]) / row["scale"] for row in others)
                entry["position"] = saved_target.get("extendedPosition", f'{round(right)}x0')
                require(re.fullmatch(r'-?[0-9]+x-?[0-9]+', entry["position"]), "Invalid saved desktop position")
        self.preview(entries, previous, "Extend desktop" if source == "none" else f'Mirror {source} on {connector}', [target["description"]])

    def revert(self, token):
        pending = read_json(self.pending, None)
        if not pending or pending["token"] != token:
            return
        apply_layout(pending["previousLayout"])
        require(verify(pending["previousLayout"], restoring=True), "Could not restore the previous setup; choose Revert to retry")
        self.pending.unlink()

    def confirm(self, token):
        pending = read_json(self.pending, None)
        require(pending is not None and pending["token"] == token, "This preview has already ended")
        if time.time() >= pending["deadline"]:
            self.revert(token)
            raise ValueError("The preview expired and was reverted")
        require(verify(pending["entries"]), "The preview is no longer active; revert and try again")
        if time.time() >= pending["deadline"]:
            self.revert(token)
            raise ValueError("The preview expired and was reverted")
        path = self.directory / "monitors.json"
        old = read_json(path, {"monitors": []})["monitors"]
        entries = {row["description"]: row for row in old}
        for row in pending["entries"]:
            if row["description"] not in pending["persistDescriptions"]:
                continue
            entries[row["description"]] = {**entries.get(row["description"], {}), **row}
        rows = sorted(entries.values(), key=lambda row: bool(row.get("mirror")))
        rules = "-- Generated by monitor-layout.sh from monitors.json. Do not edit;\n" + "\n".join(render(row) for row in rows) + "\n"
        atomic_write(path, json.dumps({"monitors": rows}, indent=2))
        atomic_write(self.directory / "monitors.lua", rules)
        self.pending.unlink()


def main():
    directory, shell, command, *args = sys.argv[1:]
    backend = Setups(directory, shell)
    if command == "live":
        print(json.dumps(live_monitors()))
    elif command == "render":
        for entry in sorted(json.load(sys.stdin), key=lambda row: bool(row.get("mirror"))):
            print(render(entry))
    elif command == "status":
        print(json.dumps(backend.status(json.load(sys.stdin))))
    else:
        {"preset-save": backend.save, "preset-delete": backend.delete, "preset-preview": backend.restore,
            "mirror-preview": backend.mirror, "revert": backend.revert, "confirm": backend.confirm}[command](*args)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(str(error) if isinstance(error, ValueError) else "Could not update the display setup; refresh and try again", file=sys.stderr)
        sys.exit(1)
