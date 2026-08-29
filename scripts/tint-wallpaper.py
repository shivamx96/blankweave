#!/usr/bin/env -S uv run --quiet --with pillow python
"""Derive a theme wallpaper from another theme's by rotating its hue.

The bundled wallpapers share one rendered scene whose only saturated element
is the accent "river"; the neutrals carry a faint tint of the same hue. A
single hue rotation therefore moves both the accent and the tint to a new
theme's hue while leaving composition, lighting, and texture untouched.

    scripts/tint-wallpaper.py <source.png> <output.png> <from-hex> <to-hex>

The hex colours are the source and target accents; the rotation is the
difference between their hues.
"""

import colorsys
import sys

from PIL import Image


def hue_of(hex_colour: str) -> float:
    value = hex_colour.lstrip("#")
    r, g, b = (int(value[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return colorsys.rgb_to_hsv(r, g, b)[0]


def main() -> None:
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    source, output, from_hex, to_hex = sys.argv[1:]

    # Pillow's HSV mode stores hue in 8 bits, so the rotation is quantised to
    # 1/256 of a turn; that is well below what the eye resolves in a tint.
    shift = round((hue_of(to_hex) - hue_of(from_hex)) * 256)
    table = [(index + shift) % 256 for index in range(256)]

    image = Image.open(source).convert("RGB").convert("HSV")
    hue, saturation, value = image.split()
    Image.merge("HSV", (hue.point(table), saturation, value)).convert("RGB").save(
        output, optimize=True
    )


if __name__ == "__main__":
    main()
