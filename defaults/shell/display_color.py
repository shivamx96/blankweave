"""Managed ICC imports. Called under monitor-layout.sh's writer lock."""
import ctypes
import hashlib
import json
import os
from pathlib import Path
import tempfile
from urllib.parse import unquote, urlparse


def validate_icc(data):
    if len(data) < 132 or len(data) > 16 * 1024 * 1024 or data[36:40] != b"acsp" or data[16:20] != b"RGB ":
        raise ValueError("Choose a valid RGB display ICC profile, up to 16 MB")
    if data[12:16] != b"mntr":
        raise ValueError("Choose a display profile, not a printer or input-device profile")
    library = ctypes.CDLL("liblcms2.so.2")
    signatures = {
        "cmsOpenProfileFromMem": ([ctypes.c_void_p, ctypes.c_uint32], ctypes.c_void_p),
        "cmsCreate_sRGBProfile": ([], ctypes.c_void_p), "cmsCreateXYZProfile": ([], ctypes.c_void_p),
        "cmsCloseProfile": ([ctypes.c_void_p], None),
        "cmsCreateTransform": ([ctypes.c_void_p, ctypes.c_uint32, ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32], ctypes.c_void_p),
        "cmsDeleteTransform": ([ctypes.c_void_p], None),
    }
    for name, (args, result) in signatures.items():
        function = getattr(library, name)
        function.argtypes, function.restype = args, result
    buffer = ctypes.create_string_buffer(data)
    profile = library.cmsOpenProfileFromMem(buffer, len(data))
    if not profile:
        raise ValueError("The color library could not open this ICC profile")
    rgb = library.cmsCreate_sRGBProfile()
    xyz = library.cmsCreateXYZProfile()
    try:
        rgb_float, xyz_float = (1 << 22) | (4 << 16) | (3 << 3) | 4, (1 << 22) | (9 << 16) | (3 << 3) | 4
        for source, source_type, destination, destination_type in [(rgb, rgb_float, profile, rgb_float), (profile, rgb_float, xyz, xyz_float)]:
            transform = library.cmsCreateTransform(source, source_type, destination, destination_type, 1, 0)
            if not transform:
                raise ValueError("This ICC profile cannot convert display colors")
            library.cmsDeleteTransform(transform)
    finally:
        for handle in (profile, rgb, xyz):
            if handle:
                library.cmsCloseProfile(handle)


class ColorProfiles:
    def __init__(self, directory):
        self.directory = Path(directory) / "color-profiles"
        self.index = self.directory / "profiles.json"

    def profiles(self):
        if not self.index.exists():
            return []
        rows = json.loads(self.index.read_text())
        if not isinstance(rows, list) or not all(isinstance(row, dict) and isinstance(row.get("id"), str)
            and len(row["id"]) == 64 and all(char in "0123456789abcdef" for char in row["id"])
            and isinstance(row.get("name"), str) for row in rows):
            raise ValueError("The saved color-profile list is invalid")
        return rows

    def path(self, identifier):
        if not any(row["id"] == identifier for row in self.profiles()):
            raise ValueError("This color profile is no longer available")
        return self.directory / (identifier + ".icc")

    def status(self):
        return [{**row, "path": str(self.path(row["id"])), "available": self.path(row["id"]).is_file()} for row in self.profiles()]

    def save_index(self, rows):
        self.directory.mkdir(parents=True, exist_ok=True)
        fd, stage = tempfile.mkstemp(prefix=".profiles-", dir=self.directory)
        with os.fdopen(fd, "w") as stream:
            json.dump(rows, stream, indent=2)
        os.replace(stage, self.index)

    def import_file(self, location):
        url = urlparse(location)
        if url.scheme not in ("", "file") or url.netloc not in ("", "localhost"):
            raise ValueError("Choose a local ICC file")
        path = Path(unquote(url.path) if url.scheme else location).expanduser()
        if not path.is_file() or path.stat().st_size > 16 * 1024 * 1024:
            raise ValueError("Choose a readable ICC file up to 16 MB")
        data = path.read_bytes()
        validate_icc(data)
        identifier = hashlib.sha256(data).hexdigest()
        rows = self.profiles()
        if any(row["id"] == identifier for row in rows):
            return
        self.directory.mkdir(parents=True, exist_ok=True)
        fd, stage = tempfile.mkstemp(prefix=".icc-", dir=self.directory)
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
        os.replace(stage, self.directory / (identifier + ".icc"))
        self.save_index(rows + [{"id": identifier, "name": path.stem}])

    def delete(self, identifier, entries):
        path = self.path(identifier)
        if any(row.get("icc") == str(path) for row in entries):
            raise ValueError("This profile is assigned to a display. Choose sRGB for that display before deleting it.")
        self.save_index([row for row in self.profiles() if row["id"] != identifier])
        path.unlink(missing_ok=True)
