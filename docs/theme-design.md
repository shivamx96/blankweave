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
| `typography` | Font families, text sizes, text/heading weights | Nonempty names up to 100 characters; body sizes 9–24, heading 14–40; integer weights 100–900 |
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
