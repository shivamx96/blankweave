# Theme design tokens

The shell resolves a complete design from `defaults/themes/design-defaults.json`.
Existing color-only themes inherit those values unchanged. A theme can provide a
partial top-level `design` object and additional `modes.dark.design` and
`modes.light.design` objects. Resolution order is defaults, theme overrides, then
active-mode overrides. Missing tokens inherit; explicit zero and false remain
overrides. Null is invalid. There is no file-based or theme-to-theme inheritance.

```json
{
  "design": {
    "spacing": { "panel": 20 },
    "shape": { "panelRadius": 8 },
    "typography": { "headingWeight": 600 }
  },
  "modes": {
    "dark": {
      "design": {
        "materials": {
          "gradientEnabled": true,
          "gradientStart": "#71479966",
          "gradientEnd": "#bc657533",
          "gradientDirection": "vertical"
        }
      }
    }
  }
}
```

This is an override example, not a standalone theme. The existing complete
palettes and application companion fields remain required in each mode.

The defaults file is the authoritative token inventory:

| Group | Purpose | Accepted values |
| --- | --- | --- |
| `spacing` | Insets and gaps in logical pixels | Finite numbers, 0–64 |
| `shape` | Control/panel radii; border width | Radii 0–32; border width 0–3 |
| `sizes` | Bar/control heights and icon/metric dimensions | Heights 24–64; other dimensions 8–64 |
| `typography` | Font families, text sizes, text/heading weights | Nonempty names up to 100 characters using letters, numbers, spaces, dots, underscores, or hyphens; body sizes 9–24, heading 14–40; integer weights 100–900 |
| `motion` | Transition duration and easing | Duration 0–1000 ms; `linear`, `outCubic`, `inOutCubic` |
| `materials` | Optional gradient overlay | Boolean enabled; CSS hex endpoints; `vertical` or `horizontal` direction |

Unknown groups and keys, wrong types, out-of-range values, and malformed colors
are rejected before theme outputs are written. Both modes' overrides are
validated, including the inactive one. Invalid themes are marked in discovery
and excluded by Settings. The resolved state stores the complete `design` object
alongside the existing `colors` object.

Design tokens style shared components. They do not rearrange navigation or
change settings behavior. User text scaling, high contrast, and reduced motion
take precedence in the shell. Other applications continue receiving their
supported palette and companion settings; shell materials do not imply gradient
support in every toolkit.

The owned Hyprtoolkit sharing picker follows the theme's regular and monospace
font families and type sizes, retaining its existing optical size ratios and
applying user text scaling afterward. It has no matching font-weight setting,
so text and heading weight overrides apply to the shell only. The restricted
font-name grammar keeps values safe when emitted into Hyprlang configuration.
Personal Hyprtoolkit configurations remain authoritative. GTK font preferences
are preserved rather than overwritten; this theme format does not claim font
ownership for GTK applications.

Gradients are static overlays on the bar, popup and launcher surfaces, and Settings
header/sidebar. Controls and reading surfaces retain their palette backgrounds.
The owned picker maps panel/control radii to its own optical scale (panel 10/14,
control 1:1), with opaque colors instead of shell gradients. Shadows and arbitrary
layout overrides are not part of the current token inventory. Some specialized
geometry, such as chart dimensions and circular indicators, stays component-owned.
