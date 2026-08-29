#!/usr/bin/env -S uv run --quiet --with numpy --with pillow python
"""Render a theme mode's wallpaper from its palette.

    scripts/render-wallpaper.py <theme.json> <dark|light> <output.png> [seed]

The composition is fixed — a tilted field of soft colour with a luminous band
sweeping across it and a fine grain on top — and only the colours come from
the theme, so every rendered wallpaper belongs to the same family while each
theme reads as its own. Colour mixing happens in linear light so the blends
stay clean, and the grain is added last so it survives PNG quantisation.
"""

import json
import sys

import numpy as np
from PIL import Image

WIDTH, HEIGHT = 3840, 2160


def srgb_to_linear(hex_colour: str) -> np.ndarray:
    value = hex_colour.lstrip("#")[:6]
    rgb = np.array([int(value[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float64) / 255
    return np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(linear: np.ndarray) -> np.ndarray:
    linear = np.clip(linear, 0, 1)
    return np.where(linear <= 0.0031308, linear * 12.92, 1.055 * linear ** (1 / 2.4) - 0.055)


def blob(x, y, cx, cy, rx, ry, angle):
    """Soft elliptical falloff centred at (cx, cy), 1 at the centre."""
    c, s = np.cos(angle), np.sin(angle)
    u = ((x - cx) * c + (y - cy) * s) / rx
    v = (-(x - cx) * s + (y - cy) * c) / ry
    return np.exp(-(u * u + v * v))


def band(x, y, offset, slope, wave, width, power=2):
    """Ribbon following a gently waving diagonal, 1 on its centreline.

    power 2 is a soft Gaussian falloff for glows; a high power keeps the
    ribbon at full strength across its width and then drops off within a
    few pixels, which is what makes a line read as crisp rather than blurred.
    """
    centre = offset + slope * x + 0.05 * np.sin(2 * np.pi * (wave * x + 0.15))
    return np.exp(-(np.abs(y - centre) / width) ** power)


def mix(canvas, colour, weight):
    weight = weight[..., None]
    return canvas * (1 - weight) + colour * weight


def render(colors: dict, dark: bool, seed: int) -> Image.Image:
    y, x = np.mgrid[0:HEIGHT, 0:WIDTH].astype(np.float64)
    x /= WIDTH
    y /= HEIGHT

    canvas = srgb_to_linear(colors["canvas"])
    raised = srgb_to_linear(colors["surfaceRaised"])
    hover = srgb_to_linear(colors["surfaceHover"])
    pressed = srgb_to_linear(colors["surfacePressed"])
    accent = srgb_to_linear(colors["accent"])
    bright = srgb_to_linear(colors["accentBright"])

    # In a dark mode the accent is the light source: a deep halo of the accent
    # with the bright variant as the core. A light mode is lit already, so the
    # halo is the accent lifted towards white and the dark accent itself draws
    # the core, otherwise the ribbon reads as a grey smear on the pale field.
    if dark:
        halo, core = accent, bright
        halo_weight, core_weight, pool = 0.18, 0.80, 1.0
    else:
        halo, core = accent + (1 - accent) * 0.45, accent
        halo_weight, core_weight, pool = 0.55, 0.90, 1.7

    # A tilted base gradient so the field never reads as a flat fill.
    tilt = 0.6 * np.clip(0.15 + 0.55 * y + 0.30 * x, 0, 1)
    image = mix(np.broadcast_to(canvas, (HEIGHT, WIDTH, 3)).copy(), raised, tilt)

    # Broad pools of the surface tints, off-axis so the composition has weight
    # in the lower left and a counterweight top right.
    image = mix(image, hover, 0.50 * pool * blob(x, y, 0.18, 0.88, 0.55, 0.32, -0.35))
    image = mix(image, pressed, 0.35 * pool * blob(x, y, 0.86, 0.10, 0.50, 0.28, -0.25))
    image = mix(image, hover, 0.25 * pool * blob(x, y, 0.55, 0.45, 0.70, 0.22, -0.30))

    # The accent: a wide halo, a tight glow, and a crisp line at the centre
    # so the ribbon reads as a lit edge rather than a blur. A thinner second
    # line runs above it at lower strength.
    image = mix(image, halo, 0.55 * halo_weight * blob(x, y, 0.62, 0.68, 0.48, 0.20, -0.32))
    image = mix(image, halo, halo_weight * band(x, y, 0.86, -0.42, 0.9, 0.08))
    image = mix(image, core, 0.45 * core_weight * band(x, y, 0.86, -0.42, 0.9, 0.018))
    image = mix(image, core, core_weight * band(x, y, 0.86, -0.42, 0.9, 0.0035, power=8))
    image = mix(image, core, 0.35 * core_weight * band(x, y, 0.70, -0.30, 1.1, 0.006))
    image = mix(image, core, 0.55 * core_weight * band(x, y, 0.70, -0.30, 1.1, 0.0015, power=8))

    # Fine grain keeps large gradients from banding and gives the surface tooth.
    rng = np.random.default_rng(seed)
    grain = rng.normal(0, 0.008 if dark else 0.006, (HEIGHT, WIDTH, 1))
    image = image + grain * (0.35 + image.mean(axis=2, keepdims=True))

    return Image.fromarray((linear_to_srgb(image) * 255).round().astype(np.uint8), "RGB")


def main() -> None:
    if len(sys.argv) not in (4, 5):
        sys.exit(__doc__)
    theme_file, mode, output = sys.argv[1:4]
    seed = int(sys.argv[4]) if len(sys.argv) == 5 else 7
    with open(theme_file, encoding="utf-8") as handle:
        theme = json.load(handle)
    render(theme["modes"][mode]["colors"], mode == "dark", seed).save(output, optimize=True)


if __name__ == "__main__":
    main()
