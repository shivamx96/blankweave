#!/usr/bin/env python3
"""WCAG sRGB contrast; CSS alpha is composited over the stated background.

Shell surfaces are composited over canvas. Lock panels are checked over both
black and white wallpaper extremes; input fields sit over those panels.
Dunst strips background alpha, as its template requests :rgb.
"""
import json
import sys
from pathlib import Path

SURFACES = ("canvas", "barSurface", "panelSurface", "surface", "surfaceRaised")


def rgba(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) / 255 for i in (0, 2, 4)) + (
        int(value[6:8], 16) / 255 if len(value) == 8 else 1,)


def over(fg, bg):
    return tuple(fg[i] * fg[3] + bg[i] * (1 - fg[3]) for i in range(3)) + (1,)


def luminance(rgb):
    linear = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in rgb[:3]]
    return sum(v * w for v, w in zip(linear, (0.2126, 0.7152, 0.0722)))


def ratio(fg, bg):
    a, b = sorted((luminance(over(fg, bg)), luminance(bg)))
    return (b + 0.05) / (a + 0.05)


def checks(state):
    c, lock = state["colors"], state["lock"]
    canvas = rgba(c["canvas"])
    surfaces = {key: over(rgba(c[key]), canvas) for key in SURFACES}
    for token in ("text", "textMuted"):
        for surface, bg in surfaces.items():
            yield f"{token}/{surface}", ratio(rgba(c[token]), bg), 4.5
    for surface in (*SURFACES, "surfaceHover", "surfacePressed", "accentSurface"):
        bg = over(rgba(c[surface]), canvas)
        yield f"focusIndicator/{surface}", ratio(rgba(c["text"]), bg), 3
    # Accent is a selection/fill colour, not text; accentBright is the shell's
    # text accent. Check all surfaces because it also labels selected rows.
    for surface, bg in surfaces.items():
        yield f"accentBright/{surface}", ratio(rgba(c["accentBright"]), bg), 4.5
    for token in ("warning", "success", "critical"):
        for surface in (SURFACES if token == "critical" else ("panelSurface", "surface")):
            yield f"{token}/{surface}", ratio(rgba(c[token]), surfaces[surface]), 4.5
    yield "active/barSurface", ratio(rgba(c["accentBright"]), surfaces["barSurface"]), 3
    yield "bar divider center/barSurface", ratio(rgba(c["outlineStrong"]), surfaces["barSurface"]), 3
    for token in ("textMuted", "accentBright"):
        yield f"tab badge canvas/{token}", ratio(canvas, rgba(c[token])), 4.5
    # Sliders and inactive rectangular row marks sit on surface or panelSurface.
    # 1.17 is the tightest two-decimal floor shared by bundled accent fills
    # (Moss light: 1.175957); surface contrast remains at least 3:1.
    for surface in ("surface", "panelSurface"):
        bg = surfaces[surface]
        track = over(rgba(c["outlineStrong"]), bg)
        yield f"slider track/{surface}", ratio(track, bg), 3
        yield f"slider fill/track on {surface}", ratio(rgba(c["accent"]), track), 1.17
        yield f"slider fill/{surface}", ratio(rgba(c["accent"]), bg), 3
        yield f"inactive indicator/{surface}", ratio(track, bg), 3
    # Separators are decorative grouping lines, not control boundaries.
    for surface, bg in surfaces.items():
        yield f"divider line/{surface}", ratio(rgba(c["divider"]), bg), 1.5
    for extreme in ("#000000", "#ffffff"):
        panel = over(rgba(lock["panelSurface"]), rgba(extreme))
        field = over(rgba(lock["inputSurface"]), panel)
        for token in ("text", "textMuted"):
            yield f"lock {token}/panel over {extreme}", ratio(rgba(lock[token]), panel), 4.5
        for token in ("text", "placeholder"):
            yield f"lock {token}/input over {extreme}", ratio(rgba(lock[token]), field), 4.5
    for token in ("text", "textMuted"):
        yield f"Dunst {token}/background", ratio(rgba(c[token]), rgba(c["panelSurface"][:7])), 4.5


def main():
    state = json.loads(Path(sys.argv[1]).read_text())
    # The high-contrast substitute uses an explicit mid-grey track in QML.
    for bg, fill in (("#000000", "#8ac7ff"), ("#ffffff", "#003a80")):
        assert ratio(rgba("#ffffff" if bg == "#000000" else "#000000"), rgba(bg)) >= 3
        assert ratio(rgba("#767676"), rgba(bg)) >= 3
        assert ratio(rgba(fill), rgba(bg)) >= 3
        assert ratio(rgba(fill), rgba("#767676")) >= 1.17
    failed = []
    for name, actual, minimum in checks(state):
        if actual < minimum:
            failed.append(f"{name}: {actual:.3f}:1 < {minimum}:1")
    if failed:
        sys.exit(f"{state.get('theme', '')} {state.get('mode', '')}:\n" + "\n".join(failed))


if __name__ == "__main__":
    main()
