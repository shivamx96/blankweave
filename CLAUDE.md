# blankweave

Arch Linux + Hyprland bootstrap with capability-based hardware detection. Deploys a complete desktop environment (Quickshell, Dunst, Ghostty, PipeWire, etc.) across Intel, AMD, and NVIDIA systems without machine-class branches.

## Architecture

```
blankweave/
  defaults/          # Universal configs, deployed to ~/.local/share/blankweave/
    hypr/            # Hyprland configs (keybindings, animations, window rules, etc.)
    quickshell/      # Native status bar and launcher, shared UI primitives, services, modules
    dunst/           # Notification daemon
    ghostty/         # Terminal emulator
    shell/           # Helper scripts (wallpaper, theme toggle, OSD popups, monitoring)
    themes/          # Bundled themes: palette, lock treatment, wallpapers, splash art
    webapps/         # Manifest of bundled web apps (name, URL, icon URL)
    plymouth/        # Boot splash: script template, master artwork to tint
    fontconfig/      # Font fallback config
    xdg-desktop-portal/  # Portal routing (hyprland → gtk fallback)
    applications/    # Desktop entries (Settings)
    spotify-launcher/  # Wayland launch flags (desktop profile)
    mangohud/        # Default overlay layout (gaming profile)
  packages/
    base.txt         # Required pacman packages (shared)
    aur.txt          # Required exact AUR packages (shared)
    profiles/        # Optional user-selected package profiles
    capabilities/    # Packages selected by detected hardware capabilities
    install.conf.example  # Versioned, non-executable selection example
    setup.conf.example    # Versioned, non-secret first-run choices example
  bin/blankweave       # User-facing version/update command
  bootstrap.sh       # First-install managed-checkout bootstrap
  migrations/        # Ordered, user-scoped, run-once migrations
  scripts/           # Installer/update support, wallpaper and splash renderers,
                     # theme-system.sh (root-side theme sync)
  install.sh         # Internal apply engine (also usable by developers)
  VERSION            # Intended stable SemVer for the release commit
  MIN_ROLLBACK_VERSION # Oldest supported configuration rollback release
  RELEASES.md        # Release, annotated-tag, and rollback-floor policy
```

### The rename from hyprarch

The rice was hyprarch until 2026-08-29. Everything user-facing now says
blankweave — the command, `~/.local/share/blankweave`,
`~/.config/blankweave`, the state and cache directories, and the Plymouth
theme — and the transition is handled in two places: `bin/hyprarch` is a
shim that execs `bin/blankweave`, because
an installed `hyprarch update` fast-forwards and then execs that path from
the new revision; and `scripts/relocate-legacy.sh` (user-scoped, idempotent, run
by `install.sh` before anything is read) renames the old directories
wholesale so the theme selection, preferences, and user wallpapers carry
over, and `install.sh` then repoints `REPO_DIR` because the managed checkout
moved with them. `bin/blankweave` and `bootstrap.sh` accept only
`shivamx96/blankweave`.
Old migrations keep their old paths — they are history, and a fresh install
finds nothing at them.

### Install and update lifecycle

1. `bootstrap.sh` clones the trusted `main` branch to
   `~/.local/share/blankweave/repository` and hands off to `blankweave setup`.
2. Guided setup reviews profiles, theme, optional Git identity, and local SSH
   key generation before saving strict data configs and invoking `install.sh`,
   which deploys the public command to
   `~/.local/bin/blankweave` along with the desktop configuration.
3. `install.sh` runs `scripts/run-migrations.sh` as the normal user only after a
   successful apply. Applied migration filenames are recorded under
   `${XDG_STATE_HOME:-~/.local/state}/blankweave/`.
   Managed Quickshell and shell-helper trees are staged beside their destination
   and atomically exchanged by `scripts/deploy-tree.sh`; never delete the live
   Quickshell tree before replacement because its watcher reloads immediately.
4. `blankweave update` validates the origin, branch, clean worktree, target
   ancestry, matching annotated `v<VERSION>` release tag, installer config, and
   package manifests before applying a fast-forward-only update. The target
   version must advance and its rollback floor must include the current release.
   `--check` only fetches and reports; `--dry-run` also validates and prints the
   target install plan.
5. A real update writes the previous/target revisions and private diagnostic
   logs under `~/.local/state/blankweave/recovery/`. Recovery metadata pairs
   each revision with its SemVer release and enforces `MIN_ROLLBACK_VERSION`.
   An existing root Snapper
   configuration receives paired pre/post snapshots. The postflight doctor
   must pass before the recovery state is marked complete.

`blankweave doctor` delegates to `scripts/doctor.sh` and is strictly read-only:
checks may report warnings or failures but must not repair files, restart
services, or contact the network. Interactive use offers a full scan by default
and may prompt for sudo only to run the root-owned boot helper installed at
`/usr/lib/blankweave/doctor-boot`; the rest of the checks remain in the invoking
user's context. `--full` explicitly requests that path, `--normal` forbids
elevation, and non-interactive use defaults to normal. Update preflight and
postflight checks must pass `--normal`. A failure exits non-zero; warnings alone
do not. `--report` may include versions and session types, but must not expose
usernames, home paths, hostnames, network addresses, disk identifiers, UUIDs,
or hardware serial numbers.

`blankweave rollback` is deliberately a Blankweave configuration rollback. It
resets only the already-validated, clean managed checkout to the recorded
previous commit and runs that revision's installer to converge managed files.
It does not downgrade packages, delete user data, or automatically restore a
Snapper snapshot. Applied migrations remain forward-only and are not removed
from their ledger. Keep this boundary explicit in help and failure messages.

`VERSION` is a stable `MAJOR.MINOR.PATCH` declaration, not a config schema. A
commit becomes a release only when the matching annotated
`vMAJOR.MINOR.PATCH` tag points to that exact commit; lightweight tags and
untagged commits are not releases. Follow `RELEASES.md` for every release and
treat `MIN_ROLLBACK_VERSION` as an explicit compatibility decision.

Do not add a public `blankweave install` command. First installation is the
bootstrap plus `blankweave setup`; subsequent convergence is `blankweave
update`. `setup --non-interactive` requires both saved configs and is the
repeatable-provisioning path.

### Login and graphical session

Blankweave assumes its root filesystem is LUKS-encrypted. It configures
`getty@tty1` to log in the installed user automatically, and the managed shell
profile starts Hyprland with
`uwsm start -e -D Hyprland hyprland.desktop` only when
`uwsm check may-start` approves the local tty1 login. SDDM is neither installed
nor enabled. During an upgrade, it is disabled and uninstalled without stopping
the current SDDM-launched session; the console login takes over after reboot.
The getty uses `--skip-login --nonewline --noissue` so Arch's issue banner does
not appear between Plymouth and Hyprland; tty2 and the other consoles remain
normal recovery logins. The boot command line hides the VT cursor globally, so
`/etc/issue.d/blankweave-cursor.issue` restores it on those recovery gettys;
tty1 suppresses issue files and remains clean during the graphical handoff.
The profile sends the small UWSM controller's stdout/stderr to
`~/.local/state/blankweave/uwsm-session.log`; compositor and application units
still log normally through the user journal.

Do not restore a graphical-startup Hyprlock. The LUKS prompt is the boot-time
authentication boundary. Hyprlock remains in manual keybindings and in
Hypridle for idle, suspend, and resume protection.

### Config deployment flow

1. `hardware-capabilities.sh` detects GPU vendors, battery/display controls,
   Bluetooth, audio firmware, and gaming support
2. Copies `defaults/` → `~/.local/share/blankweave/` and records
   `hardware-capabilities.json`
3. Selects GPU environment, monitor, and Hypridle configuration from those capabilities
4. Launches Quickshell directly from `~/.local/share/blankweave/quickshell/`
5. Symlinks app configs: `~/.config/{dunst,ghostty}/` → `~/.local/share/blankweave/`,
   plus the profile-gated `spotify-launcher.conf` and `MangoHud/MangoHud.conf`
6. Runs `theme-apply.sh` as the user, rendering `dunstrc`,
   `ghostty/config`, `hyprlock-theme.conf`, and `~/.config/blankweave/theme.lua`
   from their `.tmpl` sources and writing `~/.config/blankweave/theme.json`

### Hyprland config hierarchy

```
~/.config/hypr/hyprland.lua         # Managed symlink to hypr/entry.lua; requires:
  ├─ ~/.local/share/blankweave/hypr/hyprland.lua   # Main config, requires:
  │    ├─ env.lua                   # Global env vars (Wayland, cursor size)
  │    ├─ keybindings.lua           # All keybinds
  │    ├─ windowrules.lua
  │    ├─ input.lua
  │    ├─ animations.lua
  │    ├─ autostart.lua             # hyprland.start event commands
  │    └─ ~/.config/blankweave/theme.lua  # Window borders from the active theme,
  │                                   # rendered by theme-apply.sh; pcall + fallback
  ├─ ~/.config/hypr/env.lua         # Capability-selected GPU driver env vars
  ├─ ~/.config/hypr/monitors.lua    # Capability-selected display config
  ├─ ~/.config/blankweave/monitors.lua  # User monitor arrangement, generated by
                                      # monitor-layout.sh; loaded via pcall, absent until used
  ├─ managed voxtype.lua              # Only when the voice profile is enabled
  └─ managed user-overrides.lua       # Loads ~/.config/blankweave/overrides/hyprland.lua last

~/.config/hypr/{hyprlock,hypridle}.conf remain Hyprlang configs for the
companion tools; only the Hyprland compositor config uses Lua.
```

## Key patterns

### Universal vs capability-selected state

- **defaults/** contains universal configs plus the small hardware config variants.
- **packages/capabilities/** contains additive manifests for detected hardware.
- Machine labels and host directories are forbidden; add or consume a capability instead.

### Symlink strategy

Dunst, Ghostty, and Fontconfig are symlinked from `~/.config/` back to `~/.local/share/blankweave/`. Quickshell runs directly from the deployed defaults. This means:
- Running `blankweave update` updates the managed checkout and reapplies configs
- Users can break a symlink and replace it with a custom file to override

`scripts/user-config.sh` owns deployment of user-facing config entry points.
Use `user_config_link` instead of deleting existing files or foreign symlinks.
Only Blankweave's exact symlink or a byte-identical known legacy generated file
may be adopted. Unknown regular files, directories, and foreign symlinks
(including dangling links) stay untouched. Hyprland's generated root entry and
capability-selected configs now live under the managed `hypr/` directory;
the matching paths under `~/.config/hypr/` link to them on fresh installs.

Seed `~/.config/blankweave/overrides/` from `defaults/overrides/` only for missing
files. Its Lua settings load after all compositor defaults, including voice
bindings. Missing Lua overrides are optional, but syntax/runtime/read errors in
an existing file must reach the compositor validator. Ghostty includes its
override with native `config-file`; Dunst links its override as a native
`dunstrc.d/99-blankweave-user.conf` snippet. Reload Dunst without explicit config
arguments so both full user configs and snippets remain effective. Zsh sources
`overrides/zsh.zsh` before its legacy marked custom tail, preserved verbatim.
Fully custom config entry points retain responsibility for loading overrides.

### HiDPI and XWayland

`hyprland.lua` sets `xwayland.force_zero_scaling`, the Hyprland wiki's HiDPI
treatment: XWayland cannot scale itself, so a scaled compositor would otherwise
stretch its 1x output into a blurry window and hand the client a shrunken
screen (a 4K panel at 1.5 looks like 2560x1440 to a Proton game, which then
cannot offer its native resolution). Unscaled XWayland windows are sharp and
see the physical panel, at the cost that a client which cannot read the
compositor scale draws small. The session's own toolkits are already steered
to Wayland by `env.lua`, so the holdouts are Steam (X11 only) and CEF
applications such as Spotify.

- Steam has no Wayland mode and, as of client build 1788652215, no longer
  honours `STEAM_FORCE_DESKTOPUI_SCALING` or `-forcedesktopscaling`; its
  interface scale is the persistent client setting under Settings >
  Accessibility > UI scale, which the user sets once. Do not shadow its
  desktop entry or wrap its launch for scaling.
- Spotify gets Wayland flags through a managed
  `~/.config/spotify-launcher.conf` (desktop profile). That file shadows
  `/etc/spotify-launcher.conf` entirely, so the managed copy is complete.
- MangoHud's default layout is linked to `~/.config/MangoHud/MangoHud.conf`
  (gaming profile); the overlay itself stays opt-in per game.

Do not bump the global `XCURSOR_SIZE` or add `GDK_SCALE` to compensate:
Wayland clients multiply those by the compositor scale themselves, and
`GDK_SCALE` only takes whole numbers.

`windowrules.lua` marks `steam_app_*` windows render-unfocused. A game
presents through the compositor, so a window on an off-screen workspace never
gets its buffers back, Present blocks, and the game's main thread stalls with
it (Cities: Skylines II loaded one prefab a minute that way, with no CPU,
disk, or network activity and DXVK's submit thread parked on a GPU sync
object). `misc.render_unfocused_fps` bounds the cost.

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

- `packages/base.txt` — required official repository packages, shared across all systems
- `packages/providers.txt` — required concrete providers for virtual dependencies
- `packages/aur.txt` — required exact AUR packages (installed via paru), shared
- `packages/profiles/<profile>.txt` — optional official packages
- `packages/profiles/<profile>.providers.txt` — optional concrete providers
- `packages/profiles/<profile>.aur.txt` — optional exact AUR packages
- `packages/capabilities/<capability>/packages.txt` — detected-hardware packages
- `packages/capabilities/<capability>/profiles/` — hardware additions to optional profiles
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

The other non-secret guided choices live in
`~/.config/blankweave/setup.conf`, parsed only by `scripts/setup-config.sh`.
Keep this separate from `install.conf` because setup selections such as the
initial theme are not ongoing package convergence policy. Setup seeds the chosen
theme once; ordinary updates must not force it back after the user switches
themes. Git keys are generated locally only when explicitly selected and are
never uploaded.

### Shell scripts

All scripts live in `defaults/shell/`, deployed to `~/.local/share/blankweave/shell/`. Referenced in configs via that path. `install.sh` runs `chmod +x` on all `*.sh` files.

### Quickshell modules

The full-width bar is split into three aligned sections in `defaults/quickshell/Bar/Bar.qml`.
Each feature is an internal QML module under `defaults/quickshell/Modules/`.
Reusable presentation lives under `Components/`, and process-backed data goes
through `Services/ScriptPoller.qml`.

Bar position and visibility are shared shell preferences exposed in the system
overview panel. The bar can anchor to either vertical screen edge. Every
`ControlPopup` and tooltip must flip its anchor and gravity with that edge, and
bar-edge indicators must face the desktop. The fullscreen policy follows
`Hyprland.monitorFor(screen).activeWorkspace.hasFullscreen`, so each monitor
reacts to its own workspace. Auto-hide always uses a zero exclusive zone to
avoid moving tiled windows during reveal; fullscreen hide releases its zone only
while fullscreen is active. Both leave an invisible two-pixel input strip at the
selected edge, separate from the painted bar. The input region follows the slide
animation while the painted bar moves completely offscreen and fades with its
visible height, preventing its accent border from lingering at the edge. Reveal
eases out and concealment eases in. An open control popup holds the bar visible
until it closes. A bar on a fullscreen workspace uses the overlay layer so the
always-visible policy and both reveal strips remain above the fullscreen client.

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
shares the shell's `AudioService` with Settings. `AudioOutput` derives live
output state from PipeWire's logical default sink and discovers audio outputs
at runtime; never encode host card IDs or device names. Bind nodes through
`PwObjectTracker` before using volume/mute, and disable writes until channel
volumes arrive. Device preference is a request: show the actual default and
explain when it differs from the preferred one. Delegates keep primitive rows
and resolve the live node for each action. Freeze menu rows through activation
so hotplug cannot retarget an open choice. `AudioVolumeControl` captures the
output generation during a drag, preventing a disconnect or default-device
change from applying that gesture to another device. PipeWire/WirePlumber own
volume, mute, and preference persistence; do not add a competing config file.
`tests/qml/tst_sound.qml` covers selection, hotplug, external changes, connection
loss, and gesture cancellation without touching the developer's audio server.
`AudioInput`, owned by the same `AudioService`, applies those safeguards to the
logical default source. Both input and output implement `setVolume` for the
shared slider. `SettingsWindow` activates the native `PwNodePeakMonitor` only
while the input controls are shown, excluding minimized windows and searches
that show another page. Muting, losing, or switching the input releases the
old monitor; never save microphone samples. Native peak values are measured
before software gain, so do not multiply them by the volume setting or present
them as a recording test. `tests/qml/tst_sound_input.qml` covers microphone
writes and meter state, and the native-window fixture checks visibility scope.

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

Bluetooth uses one shell-owned `BluetoothService` and Quickshell's native BlueZ
model for live state, but device rows
must contain primitive snapshots rather than `BluetoothDevice` objects because
discovery can invalidate those objects while delegates are incubating. Resolve
actions back to a live device by its BlueZ path and adapter. Discovery is shared
by requesting views and must stop after the last closes, including delayed
start replies, so scanning cannot degrade Bluetooth audio. Power
changes go through `bluetooth-power.sh` for rfkill persistence, and successful
audio-device connections become the preferred PipeWire output.
`bluetooth-action.py` performs device-scoped D-Bus actions and reports results
instead of swallowing failures. Its temporary pairing agent serves only the
requested device and BlueZ sender; it never becomes the system default agent.
Pairing prompts and replies use JSON over stdout/stdin, with request identities
to reject stale replies. Closing the originating view cancels pairing. Keep
tests on a private D-Bus with fake BlueZ, or inject native fixture providers;
never pair, remove, power off, or disconnect a real device during validation.

Network controls share one `NetworkWifi` service owned by `shell.qml`, backed
by Quickshell's native NetworkManager model. As with
Bluetooth discovery, Wi-Fi scan results must be copied into primitive rows and
actions resolved back to live network objects by SSID, because scan churn can
invalidate wrapper objects during delegate creation. Settings actions capture
adapter, SSID, and security together and re-resolve that identity before use.
Scanning is requested by each open bar panel and the visible, non-minimized
Network Settings page; release only that view's request on close, and stop
scanning when the final owner leaves. Keep passphrases out of process
arguments; the enterprise helper accepts secrets only through stdin. The same
widget must gracefully collapse to wired connection details on machines with no
Wi-Fi hardware. Public-address lookups run only when the panel is opened and
are cached until the active interface changes. DNS choices modify only the
active NetworkManager connection and must never replace ISP/DHCP DNS unless the
user explicitly selects a provider.

Ethernet and DNS use the shell-owned `NetworkConnections` backend shared by
Settings and the bar. Poll only while a requesting view is open. Its
`network-connections.py` helper captures the NetworkManager owner, device path,
interface, active-connection path, and UUID; revalidate those before every
mutation so hotplug, reconnects, or daemon restarts cannot retarget a click.
Ethernet activates an explicitly selected compatible profile, or creates an
automatic DHCP profile only when none exists. Disconnect addresses the captured
activation. Never request connection secrets. DNS persistence uses nmcli's
partial update; live application patches only DNS in `GetAppliedConnection`
with its version guard and preserves external addresses. Read back both saved
and applied DNS. On live failure, report that the profile was saved but needs
reconnection; never silently reconnect it. Disabled IP families stay untouched.
Network UI tests use an injected helper, and helper tests mock the bus and
nmcli. Never change host DNS or real connections for validation.

`WirelessControls` owns airplane and hotspot operations. It serializes them with
Wi-Fi, Bluetooth, and connection actions; native Wi-Fi scanning stops in AP mode.
`wireless-controls.py` snapshots rfkill blocks and Bluetooth power before blocking
radios, keeps restoration data after partial failure, and restores by radio
name/type and Bluetooth address rather than a reused rfkill index. Hardware
blocks remain visible. A radio enabled elsewhere is shown as an override, never
silently presented as blocked. Status is read-only.
Hotspots use `AddAndActivateConnection2` with volatile persistence, autoconnect
disabled, WPA2/CCMP, and IPv4 sharing. Require AP/RSN/CCMP support and the mandatory
dnsmasq/nftables dependencies. Capture and recheck adapter and activation identity;
require explicit confirmation before replacing an active Wi-Fi connection. Pass
passwords only on stdin and D-Bus, clear fields on submit/close/device change, and
never request or display saved secrets. Stop only the captured Blankweave-owned
hotspot; failed-start cleanup touches only the profile created by that request.
All radio/hotspot mutation tests use mocks or an injected helper. Never run a
real rfkill mutation or start a real access point while validating this slice.

`wifi-profiles.py` lists saved Wi-Fi profiles through NetworkManager's D-Bus
settings API using `busctl` JSON, including profiles without a nearby access
point. Never request secrets for this list. Forget by UUID after rechecking the
connection type and active state, with explicit confirmation in Settings.
Native Wi-Fi tests inject fake providers and profile helpers; never toggle the
host radio, disconnect a real network, or delete a real profile during tests.

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

`Services/AgentUsage.qml` owns one collector for all screens. The Python helper
`agent-usage.py` reads Codex's app-server account/rate-limit RPCs without starting
a conversation or reading tokens. Provider checks have a five-minute cache and
a nonblocking lock; manual refresh has a 15-second floor. Keep window durations
provider-driven, missing values unknown, and expired windows awaiting an update.
Stale values must never trigger the low-allowance indicator. Old Codex usage may
survive a network error only after verifying the same account is still active.
Claude uses the experimental stream-JSON `get_usage` control request with
`skip_behaviors`, safe mode, no tools/MCP servers, and no session persistence.
Never send a user message or touch status-line settings. Prefer named server
`limits` rows, with legacy windows and `model_scoped` as fallbacks; retain both
All models and Fable-only weekly limits without duplicating them. Max 5×/20×
comes from non-secret `.claude.json` profile metadata only when its email and
organization match the CLI's current login. Unknown tiers remain Max. Cache
only quota fields and hashed account identity, never session content or credentials.
The helper uses standard-library Python from the mandatory base manifest; neither
agent is a required dependency. Tests live in `tests/agent_usage_test.py` and run
through `tests/agent-usage.sh` in the existing validation workflow.

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

Monitor arrangement and scaling are display-panel choices, persisted by
`defaults/shell/monitor-layout.sh`, the sole writer of
`~/.config/blankweave/monitors.json` (source of truth) and of the
`~/.config/blankweave/monitors.lua` rules generated from it. Entries are keyed by
EDID description and emitted as `desc:` rules — connector names such as
`DP-3` change with the port or dock. Position-only entries freeze the monitor's
current scale so moving it never resizes anything; `scaleExplicit` distinguishes
that snapshot from a scale the user selected. The panel offers Hyprland's
PPI-derived `auto` setting and a curated set of fractional values filtered to
those that divide the active physical resolution into whole logical pixels.
Scaling is available for every display and remains independent of position.
Positions are Hyprland's relative
`auto-left|right|up|down`, applied live with `hyprctl eval` and again on every
start because the generated `hyprland.lua` loads the file after the host's
`monitors.lua`. Only external displays get the position control; the internal
panel is what they are placed against, so `DisplayBrightness` names it "Built-in
display" and the panel's section label says what the position is relative to.

The right section is grouped into process-aware application indicators,
icon-only system controls, and hardware metrics plus power. Optional features
remain present in the universal Quickshell tree but derive visibility from the
strict installer config. Voice dictation is the reference: `Services/Voxtype.qml`
owns its single status watcher and `VoxtypeWidget.qml` consumes that shared
state on every screen. Settings also consumes that same instance: do not start a
second status follower. `Voxtype.record` and `restart` serialize bar/Settings
actions, gate restart on a stopped or confirmed-idle daemon, and require state
confirmation after command success. Treat streaming as busy. Settings recording
uses `voxtype-record.sh start-clipboard` so it cannot type into its own search
field; retain the helper's delivery metadata and disable auto-submit for that
recording. Model/device/shortcut readouts must not imply editable controls or
create another configuration writer. Test actions against the isolated voice
fixture in `tests/settings.sh`, never the developer's daemon.

`Services/ActiveWindow.qml` owns one focus listener and one startup
`hyprctl -j activewindow` query per shell. Bars consume it through
`bar.shell.activeWindow`; never seed focus from Quickshell's cached
`Hyprland.activeToplevel` alone, which can retain a window after an empty focus
event. New focus events invalidate pending startup results. Window addresses
are compared as strings, not JavaScript numbers. `tests/active-window.sh`
covers widget recreation, shell initialization, and startup/event races without
contacting the running compositor.

Process-backed modules (CPU, GPU, memory, network) use scripts that output JSON:

```json
{"text":"7","tooltip":"GPU: 7%\nTemp: 44°C\nVRAM: 1.4/32 GB"}
```

`MetricWidget.qml` reads the `text` and `tooltip` fields. See `gpu-usage.sh`,
`cpu-usage.sh`, and `memory-usage.sh` as references. Prefer native Quickshell
services for reactive state such as Hyprland workspaces, PipeWire, Bluetooth,
and UPower.

### Launcher

`Launcher/ApplicationLauncher.qml` is the only launcher; Fuzzel was removed on
2026-09-02 and there is no dmenu in the rice. It is a layer-shell overlay with
exclusive keyboard focus, instantiated per screen by `Variants` in `shell.qml`
and shown only on the focused monitor. It carries two peer views selected
through `Components/ControlTabs.qml`: applications, ranked from
`DesktopEntries` with a favourites order ahead of an empty query, and clipboard
history, read from `cliphist list` once per open. `Ctrl+Tab` cycles the views
from the keyboard, so the tab strip is never the only way to reach one; plain
`Tab` still steps the selection. The bar has no launcher
button — `Super+Space` and `Super+Shift+V` are the entry points, and both go
through the `blankweave` IPC handler (`launcher`, `clipboard`) rather than
spawning anything.

Because the surface is per-screen, the open state and the active view live on
`ShellRoot`, not on the launcher: `toggleLauncher(mode)` switches views when
the requested one is not already showing and only closes when it is, so the
clipboard key never dismisses an open application list. A clipboard row is
copied by passing its cliphist id as an argument to `sh -c`, never by splicing
it into the command string, because a preview is arbitrary clipboard content.

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
console colours in the systemd-boot entries. The Plymouth message callback
renders status text only in `boot` and `resume` modes; shutdown/reboot/halt keep
the full splash clean. `scripts/configure-kernel-command-line.sh` reconciles
the quiet kernel, systemd, udev, and cursor tokens in every Linux systemd-boot
entry without replacing unrelated options or the active theme's console
colour. `install.sh` runs these on every
apply, `blankweave theme set` runs it through sudo, and `blankweave theme sync`
runs it alone for a switch made from the bar, which cannot prompt.

`scripts/configure-plymouth-transition.sh` restores the package-provided
`plymouth-quit{,-wait}.service` units if a former display-manager
handoff masked them, then overrides only the quit command with Plymouth's
`deactivate` followed by `quit --retain-splash`. Getty waits on the existing
quit synchronization point, so Hyprland replaces the retained framebuffer
without a text-mode frame. Once Hyprland owns DRM,
`clear-boot-console.sh` clears tty1's hidden text and scrollback buffers; when
the compositor releases DRM during shutdown, the theme-coloured blank VT is
shown until the package-provided shutdown Plymouth service takes over. Do not
add sleeps, a custom shutdown service, or shortened global stop timeouts.

`defaults/shell/theme-apply.sh` is the only writer of
`~/.config/blankweave/theme.json` — the persisted `{theme, mode}` selection
together with the resolved values of the active mode — and of every config
rendered from a `.tmpl`: `dunst/dunstrc`,
`ghostty/config`, `hypr/hyprlock-theme.conf`, and the optional
`voxtype/config.toml` next to their templates under
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
theme` reads the same file at startup. `Super+Shift+W` cycles that wallpaper
together with extras in `~/.config/blankweave/wallpapers`, which the installer
never deploys or wipes; an empty extras folder is a no-op back onto the theme.
Ghostty is not re-rendered per mode:
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

`scripts/hardware-capabilities.sh` is the single detector used by setup,
installer, update preflight, and doctor. It emits stable additive identifiers
for Intel/AMD/NVIDIA GPUs, Intel audio firmware, battery, internal display and
backlight, DDC display, Bluetooth, and gaming support. The installer persists
the result as `~/.local/share/blankweave/hardware-capabilities.json`.

GPU monitoring remains runtime-adaptive: NVIDIA uses `nvidia-smi`, AMD uses
amdgpu sysfs telemetry, and Intel uses `intel_gpu_top` with `CAP_PERFMON`.
The installer applies that capability and installs a pacman hook to restore it
after `intel-gpu-tools` upgrades. If live Intel telemetry is inaccessible, the
widget keeps the GPU visible with its sysfs clock data and marks utilization
unavailable; it must never derive utilization from the requested clock ratio.

## Common tasks

### Adding a new app config

1. Create `defaults/<app>/` with config files
   (a file that carries colours is a `<name>.tmpl` registered with
   `theme-apply.sh`; see "Adding a themed config")
2. In `install.sh`: add `cp -rv` line in "COPYING DEFAULTS" section
3. In `install.sh`: use `user_config_link` in "SYMLINKING CONFIGS"; never remove user configs

### Adding a hardware capability

1. Add its detection and a fixture to `scripts/hardware-capabilities.sh` and
   `tests/hardware-capabilities.sh`.
2. Put additive packages under `packages/capabilities/<capability>/`.
3. Branch on the capability only where configuration cannot adapt at runtime;
   never introduce a machine name or combined laptop/desktop profile.

### Extending Settings

The native Settings window lives in `defaults/quickshell/Settings/` and is
instantiated once in `shell.qml`. Open it through `blankweave settings`, the
`settings` shell IPC method, or the system overview action. `Catalog.js` owns
category and setting IDs, descriptions, and preview controls; it must never
execute commands or write configuration. `SettingsContent.qml` is the view,
and `Services/SettingsAppearance.qml` adapts the existing theme helper and the
single shared `ShellPreferences` instance. Do not introduce another writer for
`shell.json` or theme selection. Only controls backed by implemented services
may be enabled; preview values must remain clearly labeled and never imply
observed hardware state. Add later page backends independently, and extend the
row control types when their functionality becomes available. Settings tests
run through `tests/settings.sh`, using offscreen Qt tests and isolated Quickshell
processes so validation cannot modify the developer's desktop.

`Services/SettingsDisplays.qml` reads connected monitors through
`monitor-layout.sh status` while the Displays page is visible and refreshes
after every scale, position, or mode command. That helper remains the sole monitor-config writer.
Selection follows connector identity across refreshed lists; the helper persists
choices by display description. Numeric scale controls show the compositor's
effective scale, with a separate notice when a saved preference differs. Empty,
unreachable, and malformed status disable writes. Keep backend tests isolated
from the real compositor using `tests/fixtures/settings-displays.sh`.
Position controls require an external display and at least two connected
monitors. The menu represents saved relative placement, not inferred live
geometry; show current coordinates separately. Revalidate queued commands
after discovery completes, so a disconnected target or lone display is not
positioned. `SettingsRow` supports optional backend `canApply(id)` and
`description(id)` methods for per-control availability and explanations.

Resolution and refresh choices come from each monitor's reported modes. A mode
preview changes only live state; `mode-confirm` saves it by description, while
`mode-revert` restores the previous mode, scale, and coordinates. A detached
20-second watchdog performs rollback even if Settings exits. The helper locks
all monitor mutations while a preview is pending; token checks keep delayed
watchdogs from affecting newer previews. Mode fields must survive subsequent
scale and position changes. The confirmation controls stay visible by scrolling
to the top of the page; leaving Displays requests an early revert. Test this
lifecycle with `tests/monitor-modes.sh` against a fake compositor.

`monitor-setups.py` is the monitor helper’s internal layout module; invoke it
through `monitor-layout.sh`, which owns the shared writer lock and watchdog.
It normalizes compositor mirror IDs to connectors using `monitors all`, renders
validated Lua rules, and stores named snapshots in `monitor-setups.json`.
Snapshots include active modes, numeric scales, coordinates, rotation, and
mirror sources by display description. Restoring requires the same connected
displays and supported modes. Missing hardware is explained in the saved-setup
list. Mirroring and setup restore share the mode preview token/countdown and
confirm/revert commands, but restore the whole previous layout on cancellation.
Read back geometry and mirror relationships before confirmation. Mirroring
only persists the selected output; a setup restore persists the entire snapshot.
Mirrored outputs remain selectable for brightness and extending, while their
independent mode/scale/position controls are disabled. Never permit mirror chains
or a source to mirror one of its own outputs. `tests/monitor-setups.sh` exercises
these paths with an isolated, stateful compositor fixture.

`SettingsNightLight` owns a hyprsunset process for the lifetime of the shell,
including while Settings is hidden. `night-light.py` validates and atomically
saves `night-light.json`, generates native schedule profiles, and refuses to
replace a foreign daemon. Only read-only IPC queries belong in status; bare
`hyprctl hyprsunset identity` is a mutation. Restart on preference changes and
allow explicit retry after failure. `tests/night-light.sh` checks ownership and
Off → On → Off → On lifecycle against an isolated daemon fixture.

ICC imports go through `monitor-layout.sh profile-import/profile-set/profile-delete`
and its existing lock. `display_color.py` validates RGB display profiles using
Little CMS and copies them into a content-addressed user library. Assignments
are per display description and use SDR sRGB output. Hyprland does not expose
the active ICC path, so show saved assignments, never verified active profiles.
Clearing an ICC assignment reloads compositor configuration because Hyprland
rejects empty ICC paths; reapply the live layout afterward. Preserve assignments
through layout previews, rollback, and setup restore;
saved setups capture geometry, not color assignments. Prevent removal while
assigned, including to a disconnected display. `tests/display-color.sh` checks
validation, failure handling, import/removal, and layout preservation.

Settings reuses `DisplayBrightness` for the selected monitor, active only on the
visible Displays page. Its captured connector/generation isolates slow reads
and writes from later selections. It coalesces slider requests, cancels queued
work when hidden or disconnected, and reads back after writes before accepting
the level as confirmed. The same failure recovery applies to bar controls.
Only the selected monitor gets additional polling (10 seconds); do not attach
brightness reads to the layout service's faster poll. Test helper failures,
readback mismatches, and display-switch races with the isolated brightness
fixture. Slider rows use `value`, `adjust`, `apply`, and `hold` backend methods.

System appearance is an explicit Settings action. It uses `pkexec` with the
root-owned `/usr/lib/blankweave/theme-system` installed by `install.sh`, never a
user-writable script. Its polkit action requires administrator authentication
for an active local session. `--progress` emits stable stage markers; Settings
distinguishes cancellation, failure, and verification, and only confirms success
after refreshing theme status. A failed boot-image rebuild leaves `.sync-pending`
in the installed Plymouth directory so status remains pending and retries really
rebuild the boot image. Keep that marker until a successful rebuild.

`SettingsSystemSounds` reads desktop sound preferences only while Sound is open.
`system-sounds.py` uses the desktop GSettings store as the source of truth,
revalidates installed themes and writable keys before changing them, reads back
writes, and reports preview failures. Status is read-only. `gtk_settings.py`
merges GTK 3/4 fallback settings atomically under a shared lock; both appearance
and sound updates use it so they preserve each other's keys and user settings.
Do not imply these preferences control Dunst notifications or VoxType cues.
Tests mock GSettings and playback and isolate the native Settings backend.

`PowerService` shares power-profile state and writes between Settings and every
battery panel. Read saved automation once at startup; poll manual profile status
only while a view requests it. `power-profiles.py` reads the
running daemon without activation, supports the current and legacy D-Bus names,
and offers only reported profiles. Capture its unique owner when opening a
selection menu, recheck before writing, and verify the resulting active profile.
Never claim a requested profile is active before readback. Show unavailable
services, failed writes, performance degradation, and application profile holds;
manual profile changes release holds according to the daemon's own policy.
All mutation tests use an injected helper or fake bus; never switch the host's
power profile during validation. This control does not change idle or lock policy.

`power_policy.py` owns opt-in automatic profiles in `power-profiles.json`, with
atomic writes and a shared lock for preference changes, manual choices, and ticks.
The shell runs ticks every ten seconds while enabled, including with Settings
hidden; open profile menus pause polling and ticks only while Power Settings is
visible and not minimized. UPower's aggregate battery state and `OnBattery`
determine plugged-in, battery, and low-battery states. Empty/discharging states
remain on battery policy even when `OnBattery` is false; inferring AC requires
a charging, fully charged, or pending-charge state. Unknown
or absent battery data must never be treated as AC. A five-point recovery margin
prevents threshold oscillation. Persist successful transition identities across
shell reloads, including the boot ID and daemon owners; do not continually force a profile
when another tool changes it. Application holds defer pending transitions.
Revalidate the source and holds immediately before applying an automatic profile.
Manual choices from Settings or the bar durably disable automation before
writing (including an unchanged profile or failed write). Disabling alone leaves
the active profile in place. Saved preferences use compare-and-swap to reject stale
edits; corrupt files remain untouched. All tests use fake system buses, isolated
config/state directories, or the injected Settings helper.

`SettingsBattery` reads individual present system batteries through UPower only
while the Power page is visible and not minimized. `battery-health.py` excludes
peripheral, UPS, and aggregate devices; unknown health, energy, cycles, and
thresholds remain unknown. Charge-limit actions capture the daemon owner,
object path, and a hash of hardware identity, revalidate before calling
`EnableChargeThreshold`, and read back the resulting enabled state. Never expose
serial numbers or silently retarget a removed/replaced battery. UPower owns the
configured thresholds and their persistence: support its on/off control without
writing sysfs or inventing a percentage for firmware-managed charging. All
mutation tests use fake buses/helpers; never change host charging limits in tests.

`SettingsIdle` exposes separate AC/battery dim, lock, screen-off, and suspend delays through
`idle-policy.py`. Preferences are strict, atomic, compare-and-swap JSON in
`idle.json`. The Hyprland autostart wrapper supervises only its own Hypridle
child, persists across Settings closing, and switches generated runtime configs
on power-source changes. Until the first edit, retain the installed policy.
Never overwrite custom Hypridle entry files or foreign symlinks; those make the
Settings controls unavailable. Preserve manual locking and lock-before-sleep. Each idle action can be Never;
short screen-off/suspend delays move enabled locking/dimming earlier.
Settings must distinguish saved/pending state from acknowledged application.
Tests use fake Hypridle/hyprctl processes and isolated XDG paths, never host idle,
lock, screen-off, or suspend actions.

`SettingsPointer` uses `pointer-settings.py` for live global options and saved
per-device overrides. The helper owns `pointer.json` and its generated
`pointer.lua`; `hypr/input.lua` loads it before personal overrides and publishes
an acknowledgement revision. Never infer effective per-device values from global
options: label them as saved overrides. Classify touchpads using udev properties,
not name substrings. Capture the compositor session, config revision, device name,
and address before writes; reject stale/replaced or ambiguous devices. Changes
reload configuration, verify global readback and the loaded revision, and roll
back files/live state on failure. Keep tests on mocked IPC or fixture helpers;
never mutate host input settings from automated tests.

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
  formats, never by hand: `css` (`#rrggbb[aa]`, Dunst),
  `hypr` (`rgba(rrggbbaa)`, Hyprland and Hyprlock), `rgb` (opaque
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

`Services/SettingsKeyboard.qml` reads installed XKB layouts/variants and live
keyboard state through `keyboard-settings.py`. Input-page visibility controls
polling; writes refresh even after the page is hidden. The editor snapshots the
live config, saved revision, and compositor session, so stale drafts are rejected.
It supports one to four unique layout/variant pairs, reordering, reset, and XKB
group-switch shortcuts while preserving other options. Custom keymap files and
custom rule sets are read-only. `keyboard.json` and generated `keyboard.lua` live
under the Blankweave config directory; `hypr/input.lua` loads them before personal
overrides. Writes use atomic replacement, reload/readback, and rollback on failure.
Per-device layout switching checks name, address, layout list, and session before
switching; it does not persist device overrides. Input-method installation is out
of scope. Tests use `tests/fixtures/settings-keyboard.py`, never real input devices.

`Services/SettingsShortcuts.qml` exposes the bundled desktop actions through
`shortcuts-settings.py` and `shortcut-catalog.json`. Stable IDs in
`hypr/keybindings.lua` attach `blankweave:<id>` descriptions to live bindings;
the wrapper selects a saved key combination without replacing the dispatcher,
workspace callback, or repeat flags. Keep the catalog and Lua declarations in
sync: `tests/shortcuts_settings_test.py` executes the real Lua against harmless
stubs and checks every default. Personal and optional dictation bindings are
read-only. Custom commands and disabling actions are not part of this editor.

Shortcut preferences live in `shortcuts.json` and generated `shortcuts.lua` under
the Blankweave config directory. Saves snapshot the revision, session, live bind
list, and XKB options; validate known keys; check reported compositor conflicts;
then reload and verify the tagged binding, rolling back on failure. Personal
keycode bindings conservatively reserve their modifier combination because their
logical key depends on the layout. Application-local shortcuts cannot be checked.
Input-page visibility controls polling, and writes refresh even when hidden.
Native tests use `tests/fixtures/settings-shortcuts.py`, never real shortcuts.

`Services/SettingsInterface.qml` owns text/pointer size controls on Appearance
and Input & Accessibility through `interface-settings.py`. Text presets are
100%, 115%, and 130%; pointer presets are 24, 32, and 48 px. The helper owns
`interface.json` and generated `interface.lua`; `Theme.qml` only watches the JSON
and scales shared text tokens. Compatible applications receive the GSettings
text-scaling-factor; applications with independent font controls may not follow
it. Display scale and typeface are separate. Cursor updates reach Hyprland,
GSettings, and both GTK settings files through the existing locked GTK writer.

`hypr/env.lua` loads saved pointer-size environment defaults for future sessions.
`theme-apply.sh` reads the saved cursor size under the same `interface.lock`, so
switching themes cannot reset or race sizing changes. Theme application leaves
text scaling alone. Preference writes validate session/revision/desktop/theme,
verify reload and desktop readback, and roll back files and desktop values on
failure. Cursor UI reports the saved preference and desktop-setting drift;
Hyprland has no direct live cursor-size query. Tests use isolated compositor and
GSettings fixtures, and `settings-interface.qml` verifies live Theme font updates.

`Services/SettingsAccessibility.qml` controls reduced motion and high contrast
through `accessibility-settings.py`. The helper owns `accessibility.json` and
`accessibility.lua`, sharing `interface.lock` with sizing/theme changes and the
existing GTK writer lock. `hypr/animations.lua` loads saved animation preferences
after defaults, before personal overrides. Writes verify compositor animations
and GSettings, reject stale requests, and restore previous files/settings on failure.

`Theme.qml` watches accessibility preferences independently of the selected theme:
high contrast substitutes an opaque light/dark shell palette, and disabling it
restores the original palette. GSettings signals contrast to compatible apps;
legacy applications may not honor it. Reduced motion zeroes explicit shell
animation durations, disables compositor animations, writes the desktop/GTK
animation preference, and makes wallpaper changes immediate. Do not zero polling
or notification timers. New explicit UI animations must honor `theme.reducedMotion`.
Theme changes preserve accessibility preferences and GTK animation keys. Native
tests check both palettes' text/background contrast, restoration, and immediate
control transitions; helper and wallpaper tests never touch the host session.

`Services/SettingsDefaultApps.qml` and `default-apps.py` expose effective GIO
handlers for web/email links, folders, PDF, plain text, PNG/JPEG, MP3, MP4, and
ZIP. Choices intersect registered, visible desktop applications across every
listed MIME type; application launch shortcuts remain independently configured.
The helper atomically edits only selected `[Default Applications]` keys in
`$XDG_CONFIG_HOME/mimeapps.list`, retaining comments, unrelated associations,
fallback IDs, and file permissions. Reset removes selected user default keys.
Symlinked or malformed user files are not rewritten. A locked revision/context
check includes application identities and desktop-entry contents. Verification
uses a fresh GIO process; higher-priority overrides trigger rollback, preserving
external changes. Discovery and selection never launch applications. Native
controls freeze popup identities and revisions, refresh after hidden writes,
and only poll on the visible Apps page. Real GIO tests use disposable XDG trees.

Notifications in Settings and the bar share `notification-settings.py`. It owns
`notifications.json` and one Dunst drop-in, leaving personal rules untouched.
Daily quiet hours use local time and may cross midnight; the shell reconciles
manual DND OR quiet hours every 30 seconds even while Settings is closed. Until
preferences exist, reconciliation is inert. Muted app names come from Dunst
history; new matching notifications skip popups but remain in history. Rules
honor the configured regex/glob mode. Writes lock, reject stale revisions, and
restore managed files/pause state after failures. `SettingsTask` is the common
JSON helper adapter for subsequent Settings pages, with no optimistic updates.
The temporary Keep awake preview was removed; idle timeouts remain authoritative.

`startup-settings.py` manages existing XDG autostart desktop entries for the next
sign-in, never launches/stops processes, and leaves core Hyprland services alone.
System entries are disabled through user copies with Hidden=true; only copies
marked by Blankweave offer reset to the inherited system entry. Personal entries
keep their other keys, localized names, desktop restrictions, and commands.
Symlinked user entries and malformed files are read-only. Revisions include
source contents and the current desktop; settings follow XDG directory precedence.

`wallpaper-settings.py` owns `wallpapers.json`: per-display PNG/JPEG/WebP paths and
crop/fit/stretch/center modes. Unique monitor descriptions survive connector
changes; identical descriptions use connector-qualified keys. Writes reject stale
monitor snapshots, confirm awww image readback, and restore the previous image on
failure. Theme/cycle/hotplug painting re-applies custom overrides afterward;
reset follows the active theme. Missing custom files report errors without
silently deleting preferences. Lock-screen wallpaper still follows the shared
base theme/cycle source. Native image selection snapshots the target/revision.

Bar widget visibility and within-section ordering share the existing
`ShellPreferences` writer (`shell.json`). Normalization drops unknown/duplicate
IDs, appends newly introduced widgets, and keeps system/power menus available.
`WidgetSection` loads only enabled widgets and retains compact-window/battery
availability behavior; all displays use the same preferences. Settings exposes
left/center/right sections and reset without creating another file writer.

`webapps-settings.py` adapts the existing `webapp.sh` installer/remover without
launching the browser. Creation requires Helium, uses a browser icon (`-` in the
CLI), rejects colliding slugs/invalid URLs/multiline names, and escapes URL field
codes through the existing writer. Only user-created, nonsymlink entries can be
removed; bundled entries remain owned by manifest sync. Removal confirms the
selected identity/revision and retains browser session data.

`system-settings.py` reads selected hardware/software fields without identifiers
or serial numbers. Diagnostics run only after the explicit action, calling the
installed CLI with `doctor --normal --report` (no elevation). A private local
state file records timestamp, exit code, and plain-text output, including nonzero
findings. Timeouts keep the previous report. The native view displays and copies
reports on request; it does not trigger updates, repairs, or rollback.
