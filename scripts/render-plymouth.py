#!/usr/bin/env -S uv run --quiet --with numpy --with pillow python
"""Tint the Plymouth boot-splash artwork with a theme's palette.

    scripts/render-plymouth.py <theme.json> <output-dir>

The master artwork under defaults/plymouth/artwork/ is drawn in two hues: the
Arch mark in the accent and the arcs and wordmark drifting towards a lighter
second hue. Each pixel is placed on that axis by its hue and recoloured
between the theme's dark-mode accent and accentBright, keeping its alpha, so
every theme's splash shares one drawing and differs only in colour. The boot
splash always uses the dark mode: the firmware and console around it are
dark, whatever mode the desktop lands in.
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ARTWORK = Path(__file__).resolve().parent.parent / "defaults" / "plymouth" / "artwork"
PRIMARY_HUE, SECONDARY_HUE = 220.0, 270.0


def srgb_to_linear(hex_colour: str) -> np.ndarray:
    value = hex_colour.lstrip("#")[:6]
    rgb = np.array([int(value[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float64) / 255
    return np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(linear: np.ndarray) -> np.ndarray:
    linear = np.clip(linear, 0, 1)
    return np.where(linear <= 0.0031308, linear * 12.92, 1.055 * linear ** (1 / 2.4) - 0.055)


def hue(rgb: np.ndarray) -> np.ndarray:
    """Hue in degrees for an (..., 3) array of sRGB values in 0–1."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    high, low = rgb.max(axis=-1), rgb.min(axis=-1)
    chroma = np.where(high - low == 0, 1, high - low)
    h = np.where(high == r, (g - b) / chroma % 6,
        np.where(high == g, (b - r) / chroma + 2, (r - g) / chroma + 4))
    return np.where(high == low, PRIMARY_HUE, h * 60)


def tint(source: Path, accent: np.ndarray, bright: np.ndarray) -> Image.Image:
    image = np.asarray(Image.open(source).convert("RGBA"), dtype=np.float64) / 255
    position = np.clip((hue(image[..., :3]) - PRIMARY_HUE) / (SECONDARY_HUE - PRIMARY_HUE), 0, 1)
    colour = accent * (1 - position[..., None]) + bright * position[..., None]
    tinted = np.concatenate([linear_to_srgb(colour), image[..., 3:4]], axis=-1)
    return Image.fromarray((tinted * 255).round().astype(np.uint8), "RGBA")


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    theme_file, output_dir = Path(sys.argv[1]), Path(sys.argv[2])
    with open(theme_file, encoding="utf-8") as handle:
        colors = json.load(handle)["modes"]["dark"]["colors"]
    accent, bright = srgb_to_linear(colors["accent"]), srgb_to_linear(colors["accentBright"])
    output_dir.mkdir(parents=True, exist_ok=True)
    for name in ("logo.png", "progress_bar.png"):
        tint(ARTWORK / name, accent, bright).save(output_dir / name, optimize=True)


if __name__ == "__main__":
    main()
