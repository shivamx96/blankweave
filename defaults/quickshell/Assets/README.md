# Interface marks

`marks.js` holds every vector mark the shell draws, as tokenised SVG templates.
A mark resolves `{fg}` to the caller's foreground and `{accent}` to the accent
detail colour, so one artwork serves both themes and follows a widget's active
and attention states exactly like the icon-font glyphs beside it. Secondary
detail carries its own stroke or fill opacity rather than a second baked
colour. Render marks through `Components/VectorMark.qml`; nothing should build
an image source by hand.

The processor, memory, and graphics-card symbols are original HyprArch assets.

The Tailscale connected and disconnected dot patterns follow the canonical
definitions in Tailscale's
[`client/systray/logo.go`](https://github.com/tailscale/tailscale/blob/main/client/systray/logo.go),
which is distributed under the repository's BSD-3-Clause license.

The Docker whale is sourced from Docker's
[`assets/icons/Whale.svg`](https://github.com/docker/docs/blob/main/assets/icons/Whale.svg)
under the docker/docs Apache-2.0 license.
