.pragma library

// Interface marks, kept as tokenised SVG templates so a single artwork serves
// both themes and every widget state. `{fg}` takes the caller's foreground and
// `{accent}` the accent detail colour; anything that should read as secondary
// carries its own stroke/fill opacity rather than a second baked colour.
//
// The blankweave mark and the processor, memory, and graphics-card symbols
// are original assets. The Tailscale dot patterns follow the canonical definitions in
// Tailscale's `client/systray/logo.go` (BSD-3-Clause), and the Docker whale is
// Docker's `assets/icons/Whale.svg` (Apache-2.0); see README.md.

const MARKS = {
    "blankweave": `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">
  <!-- The blankweave mark: cascaded translucent panes with the ribbon through them. -->
  <g fill="{fg}">
    <rect x="2" y="3" width="14" height="12" rx="2.4" fill-opacity="0.5"/>
    <rect x="5" y="6" width="14" height="12" rx="2.4" fill-opacity="0.72"/>
    <rect x="8" y="9" width="14" height="12" rx="2.4" fill-opacity="0.95"/>
  </g>
  <g stroke="{accent}" fill="none" stroke-linecap="round">
    <path d="M3 15.5C7.5 15.5 9 8.8 13.5 9.6S19.5 14 21 11.8" stroke-width="1.6"/>
    <path d="M4 12.6C7.5 12.6 9 6.4 13.5 7.2" stroke-width="0.7" stroke-opacity="0.7"/>
  </g>
</svg>`,
    "cpu": `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">
  <g transform="translate(0.834 0.834) scale(0.932)">
    <g stroke="{fg}" stroke-width="1.5" stroke-linecap="square" stroke-linejoin="miter">
      <path d="M8 2v3M12 2v3M16 2v3M8 19v3M12 19v3M16 19v3M2 8h3M2 12h3M2 16h3M19 8h3M19 12h3M19 16h3"/>
      <rect x="5" y="5" width="14" height="14"/>
    </g>
    <path d="M9 9h6v6H9zM11 11h2v2h-2z" stroke="{accent}" stroke-width="1.5" stroke-linejoin="miter"/>
  </g>
</svg>`,
    "docker": `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="{fg}">
  <g transform="translate(-1.008 -0.356) scale(1.003)">
    <!-- Canonical Docker whale mark from docker/docs (Apache-2.0). -->
    <path d="M5.82 13.103h3.647c.176 0 .319-.159.319-.356V9.128c0-.196-.143-.355-.32-.355H5.82c-.177 0-.32.159-.32.355v3.62c0 .196.143.355.32.355Zm5.714-5.773h3.647c.177 0 .32-.159.32-.355v-3.62c0-.196-.143-.355-.32-.355h-3.647c-.176 0-.32.159-.32.356v3.619c0 .196.144.355.32.355Zm0 5.773h3.647c.176 0 .32-.159.32-.356V9.128c0-.196-.144-.355-.32-.355h-3.647c-.177 0-.32.159-.32.355v3.62c0 .196.143.355.32.355Z"/>
    <path d="M22.803 12.808c-.055-.043-.561-.424-1.629-.424a5.24 5.24 0 0 0-.842.072c-.206-1.41-1.376-2.096-1.43-2.128l-.287-.164-.189.27c-.014.02-.346.502-.51 1.187-.19.805-.075 1.56.336 2.207-.496.275-1.288.347-1.452.349H3.626a.625.625 0 0 0-.626.62c-.005 1.205.195 2.37.578 3.37.454 1.184 1.13 2.055 2.007 2.59.984.6 2.587.945 4.397.945.847 0 1.69-.076 2.44-.22 1.182-.227 2.255-.615 3.19-1.152a8.74 8.74 0 0 0 2.174-1.772c1.044-1.175 1.666-2.488 2.128-3.65.063.003.124.004.184.004 1.143 0 1.846-.454 2.234-.836.42-.414.57-.826.586-.872l.082-.238-.197-.158Z"/>
  </g>
</svg>`,
    "gpu": `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">
  <g transform="translate(-0.2 -0.2) scale(0.978)">
    <g stroke="{fg}" stroke-width="1.5" stroke-linecap="square" stroke-linejoin="miter">
      <path d="M3 5h17v13H3V5zM20 8h2v7h-2M6 18v2M9 18v2M12 18v2"/>
      <circle cx="9" cy="11.5" r="3.5"/>
      <path d="M9 8v7M5.5 11.5h7"/>
    </g>
    <path d="M15 9h3M15 12h3M15 15h3" stroke="{accent}" stroke-width="1.5" stroke-linecap="square"/>
  </g>
</svg>`,
    "memory": `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">
  <g transform="translate(-0.314 -1.342) scale(1.028)">
    <g stroke="{fg}" stroke-width="1.5" stroke-linecap="square" stroke-linejoin="miter">
      <path d="M3 6h18v11h-7l-1 2h-2l-1-2H3V6z"/>
      <path d="M6 17v3M9 17v2M15 17v2M18 17v3"/>
    </g>
    <g fill="{accent}">
      <rect x="5.5" y="9" width="3" height="5"/>
      <rect x="10.5" y="9" width="3" height="5"/>
      <rect x="15.5" y="9" width="3" height="5"/>
    </g>
  </g>
</svg>`,
    "tailscale-connected": `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">
  <g transform="translate(1.165 1.165) scale(0.835)">
    <!-- Canonical connected dot pattern from Tailscale's BSD-3-Clause systray source. -->
    <g fill="{fg}" fill-opacity="0.42">
      <circle cx="4" cy="4" r="3"/><circle cx="13" cy="4" r="3"/><circle cx="22" cy="4" r="3"/>
      <circle cx="4" cy="13" r="3"/><circle cx="13" cy="13" r="3"/><circle cx="22" cy="13" r="3"/>
      <circle cx="4" cy="22" r="3"/><circle cx="13" cy="22" r="3"/><circle cx="22" cy="22" r="3"/>
    </g>
    <g fill="{fg}">
      <circle cx="4" cy="13" r="3"/><circle cx="13" cy="13" r="3"/><circle cx="22" cy="13" r="3"/>
      <circle cx="13" cy="22" r="3"/>
    </g>
  </g>
</svg>`,
    "tailscale-disconnected": `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">
  <g transform="translate(1.165 1.165) scale(0.835)">
    <!-- Canonical disconnected dot pattern from Tailscale's BSD-3-Clause systray source. -->
    <g fill="{fg}" fill-opacity="0.42">
      <circle cx="4" cy="4" r="3"/><circle cx="13" cy="4" r="3"/><circle cx="22" cy="4" r="3"/>
      <circle cx="4" cy="13" r="3"/><circle cx="13" cy="13" r="3"/><circle cx="22" cy="13" r="3"/>
      <circle cx="4" cy="22" r="3"/><circle cx="13" cy="22" r="3"/><circle cx="22" cy="22" r="3"/>
    </g>
  </g>
</svg>`,
    "weather-clear-day": `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">
  <g transform="translate(0.345 0.345) scale(0.973)">
    <circle cx="12" cy="12" r="4" stroke="{accent}" stroke-width="1.8"/>
    <path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.28 5.28l1.42 1.42M17.3 17.3l1.42 1.42M18.72 5.28 17.3 6.7M6.7 17.3l-1.42 1.42" stroke="{fg}" stroke-opacity="0.62" stroke-width="1.6" stroke-linecap="square"/>
  </g>
</svg>`,
    "weather-clear-night": `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">
  <g transform="translate(-0.419 -1.333) scale(1.075)">
    <path d="M19.4 15.25A8.2 8.2 0 0 1 8.75 4.6 8.35 8.35 0 1 0 19.4 15.25Z" stroke="{accent}" stroke-width="1.8" stroke-linejoin="miter"/>
    <path d="m17.7 4.2.42 1.04 1.04.42-1.04.42-.42 1.04-.42-1.04-1.04-.42 1.04-.42.42-1.04Z" fill="{fg}" fill-opacity="0.62"/>
  </g>
</svg>`,
    "weather-cloudy": `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">
  <g transform="translate(2 1.35) scale(0.897)">
    <path d="M5.2 18.6h12.4a3.8 3.8 0 0 0 .5-7.57A5.9 5.9 0 0 0 6.95 9.66 4.7 4.7 0 0 0 5.2 9.32a4.64 4.64 0 1 0 0 9.28Z" fill="{fg}" fill-opacity="0.08" stroke="{accent}" stroke-width="1.8" stroke-linejoin="miter"/>
    <path d="M8 8.3A4.4 4.4 0 0 1 15.9 7" stroke="{fg}" stroke-opacity="0.62" stroke-width="1.5" stroke-linecap="square"/>
  </g>
</svg>`,
    "weather-fog": `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">
  <g transform="translate(0.788 0.005) scale(1.01)">
    <path d="M6 14.2h11a3.2 3.2 0 0 0 .4-6.37A5.1 5.1 0 0 0 7.8 6.7 4 4 0 0 0 6 6.3a3.95 3.95 0 1 0 0 7.9Z" stroke="{accent}" stroke-width="1.7" stroke-linejoin="miter"/>
    <path d="M4 17.2h12M7 20.1h13" stroke="{fg}" stroke-opacity="0.62" stroke-width="1.6" stroke-linecap="square"/>
  </g>
</svg>`,
    "weather-partly-cloudy-day": `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">
  <g transform="translate(0.889 1.614) scale(0.966)">
    <circle cx="8.1" cy="8" r="3.1" stroke="{fg}" stroke-opacity="0.62" stroke-width="1.5"/>
    <path d="M8.1 2.7v1.4M3.55 3.85l1 1M2.8 8h1.4M12 4.7l1-1" stroke="{fg}" stroke-opacity="0.62" stroke-width="1.4" stroke-linecap="square"/>
    <path d="M6.3 18.7h11.2a3.55 3.55 0 0 0 .45-7.07A5.35 5.35 0 0 0 7.8 10.4a4.16 4.16 0 0 0-1.5-.28 4.29 4.29 0 0 0 0 8.58Z" fill="{fg}" fill-opacity="0.08" stroke="{accent}" stroke-width="1.7" stroke-linejoin="miter"/>
  </g>
</svg>`,
    "weather-partly-cloudy-night": `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">
  <g transform="translate(0.889 1.3) scale(0.966)">
    <path d="M12.1 8.4A4.9 4.9 0 0 1 6 2.8a5 5 0 0 0 6.1 7.6Z" stroke="{fg}" stroke-opacity="0.62" stroke-width="1.5" stroke-linejoin="miter"/>
    <path d="M6.3 19h11.2a3.55 3.55 0 0 0 .45-7.07A5.35 5.35 0 0 0 7.8 10.7a4.16 4.16 0 0 0-1.5-.28 4.29 4.29 0 0 0 0 8.58Z" fill="{fg}" fill-opacity="0.08" stroke="{accent}" stroke-width="1.7" stroke-linejoin="miter"/>
  </g>
</svg>`,
    "weather-rain": `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">
  <g transform="translate(2 1.977) scale(0.903)">
    <path d="M5.2 14.7h12.4a3.7 3.7 0 0 0 .48-7.37A5.7 5.7 0 0 0 7.3 6 4.5 4.5 0 0 0 5.2 5.5a4.6 4.6 0 1 0 0 9.2Z" fill="{fg}" fill-opacity="0.08" stroke="{accent}" stroke-width="1.7" stroke-linejoin="miter"/>
    <path d="m7.1 17.1-1 2.2M12.1 17.1l-1 2.2M17.1 17.1l-1 2.2" stroke="{fg}" stroke-opacity="0.62" stroke-width="1.7" stroke-linecap="square"/>
  </g>
</svg>`,
    "weather-snow": `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">
  <g transform="translate(2 1.819) scale(0.903)">
    <path d="M5.2 13.8h12.4a3.7 3.7 0 0 0 .48-7.37A5.7 5.7 0 0 0 7.3 5.1a4.5 4.5 0 0 0-2.1-.5 4.6 4.6 0 1 0 0 9.2Z" fill="{fg}" fill-opacity="0.08" stroke="{accent}" stroke-width="1.7" stroke-linejoin="miter"/>
    <path d="M7 17v4M5.3 18l3.4 2M8.7 18l-3.4 2M17 17v4M15.3 18l3.4 2M18.7 18l-3.4 2" stroke="{fg}" stroke-opacity="0.62" stroke-width="1.35" stroke-linecap="square"/>
  </g>
</svg>`,
    "weather-storm": `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">
  <g transform="translate(2 1.481) scale(0.903)">
    <path d="M5.2 14.3h12.4a3.7 3.7 0 0 0 .48-7.37A5.7 5.7 0 0 0 7.3 5.6a4.5 4.5 0 0 0-2.1-.5 4.6 4.6 0 1 0 0 9.2Z" fill="{fg}" fill-opacity="0.08" stroke="{accent}" stroke-width="1.7" stroke-linejoin="miter"/>
    <path d="m12.5 15.6-3 4.1h2.6l-1 2.3 4-4.8h-2.7l.1-1.6Z" fill="{fg}" fill-opacity="0.62"/>
  </g>
</svg>`,
}

function has(name) {
    return Object.prototype.hasOwnProperty.call(MARKS, name)
}

// Returns the mark's SVG markup with its colour tokens resolved.
function svg(name, fg, accent) {
    if (!has(name))
        return ""
    return MARKS[name].split("{fg}").join(fg).split("{accent}").join(accent)
}

// Returns a data URI an Image can load directly. Kept out of the components so
// every mark resolves its palette the same way.
function source(name, fg, accent) {
    const markup = svg(name, fg, accent)
    return markup ? "data:image/svg+xml;utf8," + encodeURIComponent(markup) : ""
}
