# blankweave

Arch Linux + Hyprland bootstrap with automatic hardware detection. Deploys a complete desktop environment (Quickshell, Dunst, Ghostty, Fuzzel, PipeWire, etc.) across two host profiles: laptop (Intel Arc) and PC (NVIDIA).

## Architecture

```
blankweave/
  defaults/          # Universal configs, deployed to ~/.local/share/blankweave/
    hypr/            # Hyprland configs (keybindings, animations, window rules, etc.)
    quickshell/      # Native status bar, shared UI primitives, services, modules
    dunst/           # Notification daemon
    ghostty/         # Terminal emulator
    fuzzel/          # App launcher
    shell/           # Helper scripts (wallpaper, theme toggle, OSD popups, monitoring)
    wallpapers/      # Bundled wallpapers
    themes/          # Bundled themes: palette, lock treatment, wallpapers, splash art
    webapps/         # Manifest of bundled web apps (name, URL, icon URL)
    plymouth/        # Boot splash: script template, master artwork to tint
    fontconfig/      # Font fallback config
    xdg-desktop-portal/  # Portal routing (hyprland → gtk fallback)
  hosts/             # Hardware-specific overrides, deployed to ~/.config/
    laptop/          # Intel Arc: GPU drivers, monitor layout, power management
    pc/              # NVIDIA RTX: GPU drivers, monitor layout, power management
  packages/
    base.txt         # Required pacman packages (shared)
    aur.txt          # Required exact AUR packages (shared)
    profiles/        # Optional capability manifests by package source
    install.conf.example  # Versioned, non-executable selection example
  bin/blankweave       # User-facing version/update command
  bootstrap.sh       # First-install managed-checkout bootstrap
  migrations/        # Ordered, user-scoped, run-once migrations
  scripts/           # Installer/update support, wallpaper and splash renderers,
                     # theme-system.sh (root-side theme sync)
  install.sh         # Internal apply engine (also usable by developers)
```

### The rename from hyprarch

The rice was hyprarch until 2026-08-29. Everything user-facing now says
blankweave — the command, `~/.local/share/blankweave`,
`~/.config/blankweave`, the state and cache directories, and the Plymouth
theme — and the transition is handled in three places: `bin/hyprarch` is a
shim that execs `bin/blankweave`, because
an installed `hyprarch update` fast-forwards and then execs that path from
the new revision; `scripts/relocate-legacy.sh` (user-scoped, idempotent, run
by `install.sh` before anything is read) renames the old directories
wholesale so the theme selection, preferences, and user wallpapers carry
over, and `install.sh` then repoints `REPO_DIR` because the managed checkout
moved with them; and `bin/blankweave` and `bootstrap.sh` accept the old
GitHub remote as well as `shivamx96/blankweave`, because checkouts made
before the repository was renamed still carry it and GitHub redirects it.
Old migrations keep their old paths — they are history, and a fresh install
finds nothing at them.

### Install and update lifecycle

1. `bootstrap.sh` clones the trusted `main` branch to
   `~/.local/share/blankweave/repository`.
2. The repository CLI invokes `install.sh`, which deploys the public command to
   `~/.local/bin/blankweave` along with the desktop configuration.
3. `install.sh` runs `scripts/run-migrations.sh` as the normal user only after a
   successful apply. Applied migration filenames are recorded under
   `${XDG_STATE_HOME:-~/.local/state}/blankweave/`.
4. `blankweave update` validates the origin, branch, and clean worktree, performs
   a fast-forward-only update, then re-executes the newly fetched CLI.

Do not add a public `blankweave install` command. First installation is the
bootstrap's responsibility; subsequent convergence is `blankweave update`.

### Login and graphical session

Blankweave assumes its root filesystem is LUKS-encrypted. It configures
`getty@tty1` to log in the installed user automatically, and the managed shell
profile starts Hyprland with
`uwsm start -e -D Hyprland hyprland.desktop` only when
`uwsm check may-start` approves the local tty1 login. SDDM is neither installed
nor enabled. During an upgrade, it is disabled and uninstalled without stopping
the current SDDM-launched session; the console login takes over after reboot.

Do not restore a graphical-startup Hyprlock. The LUKS prompt is the boot-time
authentication boundary. Hyprlock remains in manual keybindings and in
Hypridle for idle, suspend, and resume protection.

### Config deployment flow

1. `install.sh` detects hardware via `lspci` (Intel Arc → "laptop", NVIDIA → "pc")
2. Copies `defaults/` → `~/.local/share/blankweave/`
3. Copies `hosts/$HOST/hypr/` → `~/.config/hypr/` (Lua env/monitors, Hypridle)
4. Launches Quickshell directly from `~/.local/share/blankweave/quickshell/`
5. Symlinks app configs: `~/.config/{dunst,ghostty,fuzzel}/` → `~/.local/share/blankweave/`
6. Runs `theme-apply.sh` as the user, rendering `dunstrc`, `fuzzel.ini`,
   `ghostty/config`, `hyprlock-theme.conf`, and `~/.config/blankweave/theme.lua`
   from their `.tmpl` sources and writing `~/.config/blankweave/theme.json`

### Hyprland config hierarchy

```
~/.config/hypr/hyprland.lua         # Generated by install.sh, requires:
  ├─ ~/.local/share/blankweave/hypr/hyprland.lua   # Main config, requires:
  │    ├─ env.lua                   # Global env vars (Wayland, cursor size)
  │    ├─ keybindings.lua           # All keybinds
  │    ├─ windowrules.lua
  │    ├─ input.lua
  │    ├─ animations.lua
  │    ├─ autostart.lua             # hyprland.start event commands
  │    └─ ~/.config/blankweave/theme.lua  # Window borders from the active theme,
  │                                   # rendered by theme-apply.sh; pcall + fallback
  ├─ ~/.config/hypr/env.lua         # Host-specific GPU driver env vars
  ├─ ~/.config/hypr/monitors.lua    # Host-specific display config
  └─ ~/.config/blankweave/monitors.lua  # User monitor arrangement, generated by
                                      # monitor-layout.sh; loaded via pcall, absent until used

~/.config/hypr/{hyprlock,hypridle}.conf remain Hyprlang configs for the
companion tools; only the Hyprland compositor config uses Lua.
```

## Key patterns

### defaults/ vs hosts/

- **defaults/**: Universal configs that work on any hardware. All app configs, scripts, keybindings, styling.
- **hosts/**: Only hardware-specific things: GPU driver env vars (`env.lua`), monitor layout (`monitors.lua`), power management (`hypridle.conf`), GPU-specific packages (`packages.txt`).

### Symlink strategy

Dunst, Ghostty, Fuzzel, and Fontconfig are symlinked from `~/.config/` back to `~/.local/share/blankweave/`. Quickshell runs directly from the deployed defaults. This means:
- Running `blankweave update` updates the managed checkout and reapplies configs
- Users can break a symlink and replace it with a custom file to override

### Secret Service and keyring unlock

`gnome-keyring` is the D-Bus Secret Service behind `libsecret` (Slack, Bruno,
T3 Connect, and anything using Clerk-style token persistence). Automatic login
never supplies a password to `pam_gnome_keyring`, so a fresh install provisions
a passwordless `Default_keyring` through
`scripts/configure-default-keyring.sh`. LUKS is the at-rest protection for that
collection. The helper recognises only GNOME Keyring's plaintext key-file
format as passwordless and never overwrites an existing encrypted collection.

Seahorse is the lossless migration path for an older encrypted Login keyring:
change its password to empty, then re-run the installer. The helper detects the
converted plaintext collection and makes it the explicit default. The installer
stops before changing login/session management if the keyring is not ready;
there is no Hyprlock-specific PAM service or second boot password.

Electron applications only reach that keyring when Chromium's `os_crypt`
recognises the desktop. `XDG_CURRENT_DESKTOP=Hyprland` is unknown to it, so it
would select the `basic_text` backend, `safeStorage.isEncryptionAvailable()`
would be false, and Clerk-style logins (T3 Code) drop their tokens and 401.
`env.lua` therefore sets the legacy `GNOME_DESKTOP_SESSION_ID`, Chromium's last
fallback, which flips the backend to `gnome_libsecret` without touching
`XDG_CURRENT_DESKTOP`. Verify any change here with
`safeStorage.getSelectedStorageBackend()` under a scratch `electron` script
rather than by reasoning about it.

### Package placement

- `packages/base.txt` — required official repository packages, shared across all hosts
- `packages/providers.txt` — required concrete providers for virtual dependencies
- `packages/aur.txt` — required exact AUR packages (installed via paru), shared
- `packages/profiles/<profile>.txt` — optional official packages
- `packages/profiles/<profile>.providers.txt` — optional concrete providers
- `packages/profiles/<profile>.aur.txt` — optional exact AUR packages
- `hosts/$HOST/packages.txt` — host-specific official repository packages
- `hosts/$HOST/aur.txt` — optional host-specific exact AUR packages
- `hosts/$HOST/profiles/` — host-specific additions to an optional profile
- Anything the bar shells out to at runtime belongs in the required manifests,
  never an optional profile: a core widget must not depend on a profile the
  user may have deselected
- Check with `pacman -Si <package>` before choosing a manifest; use `aur.txt`
  only when the exact package is absent from the configured repositories
- When pacman offers multiple implementations for a virtual dependency, record
  the concrete choice in the required or corresponding profile provider manifest

Installer choices live in `~/.config/blankweave/install.conf` as a deliberately
small `key=value` format. Never source this user-owned file. Extend
`scripts/installer-config.sh` with explicit parsing and validation when the
schema changes. Core and detected hardware packages are mandatory; optional
profiles are additive and deselection never implies package removal.

### Shell scripts

All scripts live in `defaults/shell/`, deployed to `~/.local/share/blankweave/shell/`. Referenced in configs via that path. `install.sh` runs `chmod +x` on all `*.sh` files.

### Quickshell modules

The full-width bar is split into three aligned sections in `defaults/quickshell/Bar/Bar.qml`.
Each feature is an internal QML module under `defaults/quickshell/Modules/`.
Reusable presentation lives under `Components/`, and process-backed data goes
through `Services/ScriptPoller.qml`.

Bar icons share one optical size, `theme.barIconSize` — every glyph and mark
carries about 15.8px of ink on its long axis. A Nerd Font glyph fills roughly
7/8 of its em box and a vector mark 5/6 of its keyline, which is why the frame
defaults to `barIconSize` for glyphs and `barIconSize + 1` for marks. Glyphs
that deviate from that fill (the volume, power, and window marks run small; the
brightness and network marks run large) correct with `iconPixelSize`; measure
the rendered ink before adding one, and never move `barIconSize` itself to fix a
single widget. `theme.iconSize` remains the smaller size used inside panels.

`WidgetFrame.iconImage` is the one exception to the bar's monochrome language:
it draws icon-theme artwork for a specific application, resolved through
`DesktopEntries` and `Quickshell.iconPath(name, true)`. Use it only where the
widget is about one identifiable app, and always keep a glyph fallback for when
nothing resolves.

Vector artwork lives in `Assets/marks.js` as tokenised SVG templates and is
drawn through `Components/VectorMark.qml`, which resolves `{fg}` to the caller's
foreground and `{accent}` to the accent detail. Marks are drawn to a shared
keyline — ink centred in the 24-unit viewBox, spanning 20 units on the long
axis — so a mark's rendered size is its optical size. A mark therefore follows the
theme and a widget's active state exactly like an icon-font glyph; never add a
per-theme image file or build an image source by hand. Because marks now honour
`foreground`, a widget's `active` must mean the panel is open or the state is
genuinely transient — a steady-state condition such as "the daemon is running"
would leave the mark permanently accented.

`Components/ControlPopup.qml` provides the anchored, keyboard-dismissible panel
surface used by interactive status widgets. `ControlSlider.qml` provides the
shared angular slider treatment. Interactive panels compose
`ControlPanelHeader`, `ControlValueRow`, `ControlDivider`,
`ControlSectionLabel`, and `ControlAction`; extend those primitives instead of
recreating panel headers, value rows, section labels, or footer actions inside
individual widgets. `ControlTabs.qml` provides the panel-level tab strip with
optional per-tab badge counts; use it when a widget owns two peer views with
independent refresh semantics, not to separate sections of one view. Widget-wide controls belong in `ControlPanelHeader.actions`;
reserve `ControlAction` footer rows for secondary navigation. The audio widget
uses PipeWire's logical default sink and
discovers available output nodes at runtime; never encode host card IDs or
device names in the shell.

A choice the user makes inside a widget's own bar entry, such as the clock's
right-click representation, is a preference and must survive a restart.
`Services/ShellPreferences.qml` owns those: it reads and writes
`~/.config/blankweave/shell.json` through a `FileView` and a `JsonAdapter`, is
instantiated once in `shell.qml`, and is reached from a widget as
`bar.shell.preferences`. Declare a new preference in that adapter's schema —
anything absent from it is dropped the next time the file is written — and never
open a second `FileView` over the same path, because the two would race.
Widget configuration with a real schema and network work behind it keeps its own
file and its own script instead, the way the weather location lives in
`~/.config/blankweave/weather.json` and is written only by `weather-status.sh`, so
every file has exactly one writer. A persisted preference is still a
steady state, so it changes a widget's form, never its `active` accent.

The rightmost power control is a native panel. Lock and suspend are immediate;
logout, reboot, and shutdown require a second confirmation click and must clear
their armed state whenever the panel closes.

Brightness is also runtime-selected: internal eDP/LVDS/DSI panels use
`brightnessctl`, while external displays use DDC/CI VCP `0x10`. Pass the
Quickshell screen's DRM connector to `brightness.sh`; it resolves and caches the
corresponding I²C bus because `/dev/i2c-*` numbering is not stable. Each screen's
state lives in a `Services/DisplayBrightness.qml` instance: the bar entry and
scroll gesture are about the screen the bar is drawn on and keep that instance
polling, while the panel lists every screen and instantiates the others with
`active` bound to the panel being open, so a closed bar never spends DDC/CI
round-trips on displays it is not showing. `Quickshell.screens` changes on
hotplug and a bar's `screen` is cleared before the bar is destroyed, so guard
against a null screen in anything derived from it. The display panel also owns
the global dark/light toggle as an inline header action.

Bluetooth uses Quickshell's native BlueZ model for live state, but device rows
must contain primitive snapshots rather than `BluetoothDevice` objects because
discovery can invalidate those objects while delegates are incubating. Resolve
actions back to a live device by address. A panel-owned discovery session must
also be stopped after close so scanning cannot degrade Bluetooth audio. Power
changes go through `bluetooth-power.sh` for rfkill persistence, and successful
audio-device connections become the preferred PipeWire output.

Network controls use Quickshell's native NetworkManager model. As with
Bluetooth discovery, Wi-Fi scan results must be copied into primitive rows and
actions resolved back to live network objects by SSID, because scan churn can
invalidate wrapper objects during delegate creation. Scanning belongs to the
open panel and must be released on close. Keep passphrases out of process
arguments; the enterprise helper accepts secrets only through stdin. The same
widget must gracefully collapse to wired connection details on machines with no
Wi-Fi hardware. Public-address lookups run only when the panel is opened and
are cached until the active interface changes. DNS choices modify only the
active NetworkManager connection and must never replace ISP/DHCP DNS unless the
user explicitly selects a provider.

The Git widget lists repositories under `~/IdeaProjects` and the pull requests
attached to the signed-in GitHub account. The two concerns stay in separate
scripts because they have different costs: `git-repos.sh` is local-only and may
be re-run freely while the panel is open, whereas `git-prs.sh` spends GitHub
search requests and therefore caches to
`${XDG_CACHE_HOME:-~/.cache}/blankweave/`, serves the cache until it ages out,
falls back to stale results when the network fails, and guards every `gh` call
with `timeout`. Pull requests are searched account-wide (authored plus
review-requested), so rows are cross-referenced against the local scan by
`owner/name` to decide whether an IDE action is offered. Authentication is
delegated entirely to `gh`; never read or pass a token yourself. Poll the pull
request script slowly while the panel is closed so the review badge stays live
without burning the search budget. Cache files are keyed by the active GitHub
host and login so switching `gh` accounts cannot reuse another account's data.
Only offer the IntelliJ project action when `git-repos.sh` reports that `idea`
is available; otherwise use the required `xdg-open` fallback.

Workspaces follow focus rather than belonging to a monitor. `Super+N` and a
click in the bar dispatch `hl.dsp.focus({ workspace = N, on_current_monitor = true })`,
which brings workspace N to the focused monitor and swaps out whatever it was
showing, so any workspace can be pulled to any screen. Repeating the press
while N is already showing on the focused monitor dispatches
`hl.dsp.workspace.move({ monitor = "+1" })` instead, sending it on to the next
monitor with focus following, so repeated presses cycle a workspace through
the displays; the keybinding is a Lua function (`summon_workspace` in
`keybindings.lua`) and the bar mirrors that logic in `activateWorkspace`,
so keep the two in step. Each bar's
`WorkspacesWidget` therefore lists only the workspaces on its own monitor
(the 1–5 placeholders plus anything else living there, minus anything shown on
another monitor). Under the Lua config, `hyprctl dispatch` takes Lua and the
Hyprlang dispatcher names are rejected; the Lua option table is not validated,
so confirm a new option behaviourally (a headless output plus
`hyprctl workspaces -j`) rather than trusting an "ok".

Monitor arrangement is a display-panel choice, persisted by
`defaults/shell/monitor-layout.sh`, the sole writer of
`~/.config/blankweave/monitors.json` (source of truth) and of the
`~/.config/blankweave/monitors.lua` rules generated from it. Entries are keyed by
EDID description and emitted as `desc:` rules — connector names such as
`DP-3` change with the port or dock — and freeze the monitor's current scale so
choosing a position never resizes anything. Positions are Hyprland's relative
`auto-left|right|up|down`, applied live with `hyprctl eval` and again on every
start because the generated `hyprland.lua` loads the file after the host's
`monitors.lua`. Only external displays get the control; the internal panel is
what they are placed against, so `DisplayBrightness` names it "Built-in
display" and the panel's section label says what the position is relative to.

The right section is grouped into process-aware application indicators,
icon-only system controls, and hardware metrics plus power. Add watched apps
through `ApplicationIndicatorsWidget.qml` using `ProcessIndicator.qml`.

Process-backed modules (CPU, GPU, memory, network) use scripts that output JSON:

```json
{"text":"7","tooltip":"GPU: 7%\nTemp: 44°C\nVRAM: 1.4/32 GB"}
```

`MetricWidget.qml` reads the `text` and `tooltip` fields. See `gpu-usage.sh`,
`cpu-usage.sh`, and `memory-usage.sh` as references. Prefer native Quickshell
services for reactive state such as Hyprland workspaces, PipeWire, Bluetooth,
and UPower.

### Theme system

A theme is a directory holding `theme.json` with two modes, `dark` and
`light`. `Super+D` flips the mode of the active theme and never changes the
theme itself. Bundled themes live in `defaults/themes/<id>/` (mirrored to
`~/.local/share/blankweave/themes/`), and a user theme in
`~/.config/blankweave/themes/<id>/` shadows a bundled one with the same id. The
default is `obsidian`: Obsidian in dark mode, Porcelain in light; `moss` is
the bundled green counterpart (Moss and Sage).

Each mode carries:

- `colors`: the shell palette, exactly the tokens `Theme.qml` exposes
  (`canvas`, `barSurface`, `barHighlight`, `panelSurface`, `surface`,
  `surfaceRaised`, `surfaceHover`, `surfacePressed`, `scrim`, `text`,
  `textMuted`, `accent`, `accentBright`, `accentSurface`, `outline`,
  `outlineStrong`, `divider`, `success`, `warning`, `critical`). All are
  required, as CSS `#rrggbb` or `#rrggbbaa`. The neutrals are tinted towards
  the accent, so a theme is a whole palette, not one accent colour.
- `lock`: the Hyprlock treatment. It sits on the wallpaper, so it carries its
  own text, accent, and surface values plus the `contrast`, `brightness`, and
  `vibrancy` applied to the wallpaper.
- `wallpaper` (relative to the theme directory), `ghostty` (a Ghostty theme
  name), `iconTheme`, `cursorTheme` (an installed XCursor/Hyprcursor theme;
  the bundled themes pair Bibata Modern Ice with dark and Modern Classic with
  light), and `label` (the mode's display name).

Two things belong to the theme rather than a mode: `folderColor`, a Papirus
folder colour name applied to every installed Papirus variant, and
`plymouth`, the `logo` and `progressBar` PNGs (relative to the theme
directory) for the boot splash, which always uses the dark mode's canvas and
accent because the firmware and console around it are dark. Both need root,
so `theme-apply.sh` only stages them: it renders
`plymouth/blankweave/blankweave.script` from its template next to a copy of the
artwork under `~/.local/share/blankweave/`, and `status` reports
`system.pending` when the installed folder colour or splash differ from the
stage. `scripts/theme-system.sh` (root) installs them: `papirus-folders` per
Papirus variant, the staged splash into `/usr/share/plymouth/themes/blankweave`
with an initramfs rebuild only when a file changed, and the `vt.default_*`
console colours in the systemd-boot entries. `install.sh` runs it on every
apply, `blankweave theme set` runs it through sudo, and `blankweave theme sync`
runs it alone for a switch made from the bar, which cannot prompt.

`defaults/shell/theme-apply.sh` is the only writer of
`~/.config/blankweave/theme.json` — the persisted `{theme, mode}` selection
together with the resolved values of the active mode — and of every config
rendered from a `.tmpl`: `dunst/dunstrc`, `fuzzel/fuzzel.ini`,
`ghostty/config`, and `hypr/hyprlock-theme.conf` next to their templates under
`~/.local/share/blankweave/`, plus `~/.config/blankweave/theme.lua`, which
`hyprland.lua` loads through `pcall` for the window border colours and the
cursor theme with a built-in fallback. Templates use `{{path}}` placeholders
resolved against the resolved theme (`{{colors.accent}}`, `{{lock.contrast}}`,
`{{modes.light.ghostty}}`, `{{modes.dark.colors.canvas:plymouth}}`; the
resolved state carries both modes' palettes for that). Substitution is
single-pass, an unknown placeholder or a missing token aborts the render
before any output is touched, and outputs are staged and renamed so a reader
never sees a half-written file. The script then sets the portal colour
scheme, icon theme, and cursor theme through `gsettings`, writes the GTK 3/4
`settings.ini` with the same three, sets the mode's wallpaper, touches the
config symlinks for inotify readers, reloads Dunst in place, runs `hyprctl
reload`, and switches the running compositor's cursor with `hyprctl
setcursor` (`env()` in the config only seeds a new session; running GTK apps
keep their cursor until relaunched). Those side effects are guarded by `command -v`,
`WAYLAND_DISPLAY`, and `HYPRLAND_INSTANCE_SIGNATURE`, so the same script runs
from `install.sh` (as the user, after ownership is fixed) with no session.
The GTK theme name is pinned to `Adwaita` in both modes; the mode reaches
GTK 3 through `gtk-application-prefer-dark-theme` in `settings.ini` and
everything else through the portal colour scheme (see the Electron gotcha).

`Theme.qml` reads `~/.config/blankweave/theme.json` through a watched
`FileView`, converts CSS `#rrggbbaa` to Qt's `#aarrggbb`, and exposes `dark`,
`mode`, and `themeId` alongside the colour tokens; until the first apply it
falls back to the bundled default's dark mode, and a mid-write read keeps the
last good palette. The state file is rewritten in place with a single write
rather than renamed, because Quickshell watches that path. `wallpaper.sh
theme` reads the same file at startup. Ghostty is not re-rendered per mode:
its template emits `theme = light:…,dark:…` from both modes and Ghostty
follows the portal colour scheme. A theme switch changes that pair, and a
surface that is already open keeps the pair it resolved at creation even
after Ghostty's own file-watch reload, so the script activates Ghostty's
`reload-config` D-Bus action — guarded by `NameHasOwner`, because the name is
activatable and a bare call would launch a terminal. GTK3 apps (Thunar) still
only pick a change up on restart.

`blankweave theme list|status|set <id>|mode dark|light|toggle|sync` is the
public entry point and delegates to the deployed script, adding the sudo
step after `set`. The display panel hosts the same choice: its theme row is
built from `theme-apply.sh list` (whose entries carry each mode's accent for
the swatch), runs `theme-apply.sh set <id>`, and shows a hint while `status`
reports `system.pending`. Fonts, geometry, translucency, animations, and the
cursor size are deliberately not part of a theme; they are the rice's
identity and stay in `Theme.qml`, `hyprland.lua`, and `env.lua`.

### Web apps

A web app is a site run in Helium's `--app=<url>` mode, the way Omarchy does
it with Chromium: a window with no browser chrome that joins the running
Helium instance (so it shares the browser's logins) and carries the class
`chrome-<host>__<path>-Default`, the path's slashes turned into underscores.
`defaults/shell/webapp.sh` is the single owner of the entries: `install`,
`remove`, and `list` manage `~/.local/share/applications/blankweave-webapp-<slug>.desktop`
with the icon installed into the user's hicolor theme under the same name and
`StartupWMClass` set to that class, and `sync` converges the entries tagged
`X-Blankweave-Webapp=bundled` on `defaults/webapps/webapps.tsv` (tab-separated
name, URL, icon URL) while leaving user-installed entries alone. `install.sh`
runs `sync` as the user after the theme apply; it is a no-op without
`helium-browser`, because Helium ships in the optional `desktop` profile, and a
failed icon download degrades to the theme's `web-browser` icon rather than
failing the apply. The URL goes into a desktop `Exec` line, so the script
refuses anything that would need Exec quoting instead of escaping it. Gecko
browsers (Firefox, Zen) have no equivalent of `--app`, which is why this is
tied to Helium. `blankweave webapp` is the public entry point.

### Hardware detection

`install.sh` uses `lspci | grep` to detect GPU:
- `Intel.*Arc` → host = "laptop"
- `NVIDIA` → host = "pc"
- Fallback → "laptop"

GPU monitoring script (`gpu-usage.sh`) auto-detects at runtime: tries `nvidia-smi` first, falls back to Intel sysfs frequency.

## Common tasks

### Adding a new app config

1. Create `defaults/<app>/` with config files
   (a file that carries colours is a `<name>.tmpl` registered with
   `theme-apply.sh`; see "Adding a themed config")
2. In `install.sh`: add `cp -rv` line in "COPYING DEFAULTS" section
3. In `install.sh`: add `mkdir -p` + `rm -f` + `ln -s` in "SYMLINKING CONFIGS" section

### Adding a new host

1. Create `hosts/<hostname>/hypr/` with `env.lua`, `monitors.lua`, `hypridle.conf`
2. Create `hosts/<hostname>/packages.txt` for repository packages and
   `hosts/<hostname>/aur.txt` when required host-specific AUR packages exist;
   add optional capability packages under `hosts/<hostname>/profiles/`
3. Update `detect_host()` in `install.sh` with a new `lspci` pattern

### Adding a new Quickshell module

1. Create `defaults/quickshell/Modules/<Name>Widget.qml`
2. Build on `Components/WidgetFrame.qml` for standard bar behavior; set `icon`
   for a Nerd Font glyph or `iconMark` for a vector mark from `Assets/marks.js`
3. Use a native Quickshell service where available; otherwise use `ScriptPoller`
4. Add the module to the appropriate island in `Bar/Bar.qml`
5. Keep colors and geometry in `Theme.qml` instead of defining them per module
6. Persist any user-facing choice the widget offers through
   `Services/ShellPreferences.qml` rather than a plain widget property

### Adding a new shell script

1. Create in `defaults/shell/<name>.sh` with `#!/usr/bin/env bash`
2. It will be auto-deployed and made executable by `install.sh`
3. Reference in configs as `~/.local/share/blankweave/shell/<name>.sh`

### Adding a migration

1. Add an executable `migrations/YYYYMMDD-description.sh`.
2. Keep it user-scoped, non-privileged, host-independent, and idempotent.
3. Leave packages and declarative configuration in `install.sh`; migrations are
   only for one-time state transitions that cannot be expressed by redeployment.

### Adding a theme

1. Copy `defaults/themes/obsidian/` to `defaults/themes/<id>/`, or to
   `~/.config/blankweave/themes/<id>/` for a personal theme, and edit
   `theme.json`. Both modes and every palette token are required; wallpaper
   paths are relative to the theme directory.
2. Render the wallpapers with `scripts/render-wallpaper.py <theme.json>
   <dark|light> <output>` (runs under `uv`, needs no install). The
   composition is fixed — a tilted field with a luminous ribbon and fine
   grain — and only the colours come from the palette, so a rendered
   wallpaper is always in keeping with its theme; Obsidian keeps its
   original renders. Tune the palette, not the script, when the result is
   off, and view both modes: a light mode needs far stronger weights than
   a dark one because its accent is mixed into a near-white field.
3. Retune `lock` for the new wallpapers instead of copying the palette into
   it; the lock screen needs more contrast than the bar.
4. Render the boot splash artwork with `scripts/render-plymouth.py
   <theme.json> defaults/themes/<id>/plymouth`. It tints the master drawing
   in `defaults/plymouth/artwork/` — drawn in two hues, 220° for the mark
   and 270° for the ribbon and wordmark — between the dark mode's `accent`
   and `accentBright`, so change the artwork there, never per theme. Pick
   `folderColor` from `papirus-folders -l` and a `cursorTheme` that is
   installed by the package manifests.
5. Check both modes with `theme-apply.sh set <id>` and `theme-apply.sh mode
   light`; the renderer rejects a missing token before touching any output.
   `tests/theme-apply.sh` renders every bundled theme in both modes and
   `tests/theme-system.sh` exercises the root-side sync against a sandbox.

### Adding a bundled web app

1. Append a tab-separated `name`, `URL`, `icon URL` line to
   `defaults/webapps/webapps.tsv`; the icon must be a PNG or SVG (the
   `homarr-labs/dashboard-icons` CDN carries most services).
2. Verify the class Helium gives the window (`hyprctl clients -j`) matches
   the entry's `StartupWMClass` if the URL carries a path.
3. `tests/webapp.sh` lints the manifest and exercises the script against
   stand-ins for the browser and the download.

### Adding a themed config

1. Name the source `<file>.tmpl` and reference tokens as
   `{{colors.<token>}}`; never write a hex value into a template.
2. Add a `render_template <format> <template> <output>` line to `render_all`
   in `theme-apply.sh`, choosing the consumer's colour notation as the
   file-level format and overriding single placeholders with
   `{{token:format}}` where one file mixes notations.
3. Symlink the rendered output, never the template, from `~/.config/`, and
   cover the rendered lines in `tests/theme-apply.sh`.

## Gotchas

- Colour notation differs per consumer and is handled by the renderer's
  formats, never by hand: `css` (`#rrggbb[aa]`, Dunst), `fuzzel` (`rrggbbaa`,
  no `#`), `hypr` (`rgba(rrggbbaa)`, Hyprland and Hyprlock), `rgb` (opaque
  `#rrggbb`), `plymouth` (`r, g, b` as 0–1 floats for
  `Window.SetBackground*Color`). Hyprlock needs `##` before a Pango hex colour, so that template
  writes `#{{lock.placeholder:rgb}}`
- Quickshell colours come from the resolved theme through `Theme.qml`;
  geometry and fonts stay in `Theme.qml`
- GTK3 apps (Thunar) don't react to live gsettings changes on Hyprland — only libadwaita apps do
- Never switch `gtk-theme` between `Adwaita` and `Adwaita-dark` to express the
  mode. Chromium, and so every Electron app, derives the colour scheme it
  gives the page from the window background of the GTK theme it has loaded
  and recomputes it on every `gtk-theme-name` change; `Adwaita-dark`
  evaluates light there and overrides the portal's `color-scheme`, so
  Obsidian and T3 Code followed the first `Super+D` after launch and ignored
  every later one. The name stays `Adwaita` and the portal's `SetDarkTheme`
  flips GTK's prefer-dark-theme itself. GTK 3 never restyled on the name
  flip anyway. Verify Electron behaviour by launching the app with
  `--remote-debugging-port` and reading `matchMedia('(prefers-color-scheme:
  dark)')` over CDP while toggling; unset `ELECTRON_RUN_AS_NODE` first when
  running from inside an Electron-hosted shell
- Commands registered by `autostart.lua` run in parallel; chain with `&&` for ordering
- `awww img` only paints the outputs that exist when it runs, and the daemon's cache is keyed by connector name, so a monitor plugged in after startup stays black. `autostart.lua` subscribes to `monitor.added` (the callback receives the compositor's monitor object; its `.name` is the connector) and runs `wallpaper.sh restore <output>`, which repaints the current wallpaper without a transition once awww lists the output. Test hotplug paths with `hyprctl output create headless` / `hyprctl output remove HEADLESS-N`, and register hooks at runtime with `hyprctl eval` rather than reloading the config
- `force_default_wallpaper = 0` and `disable_hyprland_logo = true` in `hyprland.lua` — otherwise Hyprland flashes its own wallpaper on startup
- `focus_on_activate = true` in `hyprland.lua` — otherwise Hyprland drops xdg-activation requests, so clicking a link opens the tab in the already-running browser without ever moving you to its workspace. Hyprland exposes no per-window rule for this, so the setting is necessarily global and any app that requests activation can pull focus
