# blankweave

Arch + Hyprland bootstrap with automatic hardware detection.

Blankweave boots through Limine on UEFI systems. It imports the proven Linux
kernel, initramfs, and command line from Archinstall's Boot Loader Specification
entries, so LUKS unlocking remains an initramfs/Plymouth concern rather than a
boot-manager concern. Existing systemd-boot files and its `Linux Boot Manager`
firmware entry are deliberately retained as a recovery path.

Hardware support is capability-based rather than tied to machine labels. The
installer detects Intel and AMD CPUs, Intel, AMD, and NVIDIA GPUs, batteries,
internal panels and backlights, DDC/CI displays, Bluetooth controllers, and
gaming-driver support. It installs the matching CPU microcode and GPU stack,
plus the baseline device firmware used by modern Linux hardware.

## Install

For a new machine starting from the Arch live USB, use the reusable
[Archinstall baseline](archinstall/README.md) first. It keeps disk selection and
LUKS/user credentials interactive, then hands the installed system to this
bootstrap.

Run the bootstrap as your normal user after the Archinstall stage:

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
  https://raw.githubusercontent.com/shivamx96/blankweave/refs/heads/main/bootstrap.sh | sh
```

It clones the managed repository to
`~/.local/share/blankweave/repository`, installs the `blankweave` command in
`~/.local/bin`, and opens the guided setup before applying system configuration.
The bootstrap requires an interactive terminal so profiles, theme, and optional
Git/SSH choices can be reviewed before package or system changes begin.

After the first install, use:

```bash
blankweave version
blankweave setup
blankweave update
blankweave doctor
```

`blankweave update` refuses dirty, divergent, or non-`main` managed checkouts. It
only fast-forwards from the expected GitHub repository, applies the new version,
and then records successful one-time migrations.

## Releases

Blankweave releases are stable SemVer versions with two matching markers:
`VERSION` in the commit and an annotated `v<VERSION>` Git tag pointing to that
exact commit. An untagged checkout is shown as `unreleased` and remains usable
for local development, but `blankweave update` will never install it. The first
supported rollback boundary is the tagged `v0.1.0` known-working baseline.

See [RELEASES.md](RELEASES.md) for the release and tagging procedure.

Updates can be inspected before they are applied:

```bash
blankweave update --check
blankweave update --dry-run
```

An apply records the previous and target revisions, saves preflight and
postflight doctor reports plus the installer log under
`~/.local/state/blankweave/recovery/`, and runs a final health check. If a root
Snapper configuration already exists, Blankweave also creates paired pre/post
snapshots. `blankweave rollback` restores the previous repository revision and
reconverges its managed configuration; it deliberately does not downgrade Arch
packages or reverse completed one-time migrations. A recorded Snapper snapshot
remains available for manual full-system recovery.

Recovery records both release versions and Git revisions, verifies that they
still match their annotated tags, and will not cross `MIN_ROLLBACK_VERSION`.
Recovery protection begins with updates initiated by `v0.2.0` or newer. An
upgrade initiated by an older client—including a direct `v0.1.0` to `v0.2.0`
upgrade—cannot have a rollback point reconstructed safely; the next tagged
update creates the first one before making changes.

`blankweave doctor` performs read-only checks of the managed checkout, runtime
commands, generated Hyprland configuration, tty1/UWSM session, keyring, and
Plymouth boot handoff. In a terminal it offers a full scan by default, using
sudo only for protected boot files; choose `--normal` to never elevate or
`--full` to request the complete scan without the choice. Non-interactive use
defaults to the normal scan. It also verifies the Limine executable and Linux
entries, UEFI boot order, and systemd-boot recovery path. Add `--report` to
either mode for package and system versions with usernames, hostnames, network
addresses, disk identifiers, and hardware serial numbers deliberately omitted.

Limine is installed as `Blankweave Boot Manager` and placed first in UEFI
`BootOrder` only after its executable and configuration have been staged. Limine
shows its menu on every boot: for three seconds on Linux-only systems and five
seconds when another installed operating system is detected. This keeps the
current kernel, LTS kernel, recovery path, and alternate operating systems
discoverable. Active operating-system EFI entries are added without mounting or
copying their EFI System Partitions or maintaining a distribution allowlist.
Selecting one uses that operating system's existing UEFI entry. The menu also
contains `Blankweave recovery (systemd-boot)`.

When firmware provides a generic `EFI USB Device` record, Limine also offers a
`Boot from USB` handoff. That record is commonly persistent even when no drive
is inserted, so its presence is not treated as proof of attached media. The
visible menu and the machine's firmware boot menu both remain available.

If Limine cannot boot Blankweave, open the machine's firmware boot menu and
select `Linux Boot Manager`. That is the untouched systemd-boot installation
created by the Archinstall baseline. Secure Boot must remain disabled until
Blankweave gains a signed-boot flow; the installer refuses to activate unsigned
Limine when Secure Boot is enabled.

The script will:
- Detect hardware
- Install packages (Hyprland, Quickshell, Dunst, Ghostty, etc.)
- Configure tty1 automatic login and launch Hyprland through UWSM
- Install Limine while preserving systemd-boot as boot recovery
- Set up defaults in `~/.local/share/blankweave/`
- Generate user configs in `~/.config/`
- Capture a sanitized hardware inventory for the native system panel

For development, a local checkout can still be applied with `./install.sh`.
That path installs the same command and records the checkout as the active
Blankweave source.

The hardware inventory stores motherboard, display, and DIMM model/specification
fields, but excludes hardware serial numbers and machine UUIDs. Refresh it after
changing RAM or displays without reinstalling:

```bash
sudo ~/.local/share/blankweave/shell/hardware-inventory.sh "$USER"
```

The live shell never needs elevated privileges; it only reads this cached file.

## Installer profiles

The required Blankweave environment and detected hardware support are always
installed. Optional applications and features are grouped into five additive
profiles:

- `desktop` — browsers, notes, and personal desktop utilities;
- `development` — editors, containers, language tooling, and coding tools;
- `communication` — messaging and local sharing applications;
- `gaming` — Steam, Proton, overlays, and host-appropriate 32-bit GPU support;
- `voice-dictation` — fully local VoxType dictation, its verified `small.en`
  model, compositor bindings, compact themed OSD, and bar controls.

Selections can be stored in `~/.config/blankweave/install.conf`:

```ini
version=1
profiles=desktop development communication
```

The config is parsed as data and is never sourced as shell code. Profile order
does not matter, duplicate names are ignored, and unknown keys, versions, or
profiles stop the installer before package changes begin.

`blankweave setup` guides these profile choices, the initial theme and mode, an
optional global Git identity, and optional local Ed25519 key generation. It
shows a final review before writing anything, never asks for credentials, and
never uploads the public key. Removing a profile only stops Blankweave from
requesting those packages in future runs—it does not uninstall software already
present.

Non-secret first-run choices are saved separately in
`~/.config/blankweave/setup.conf`; both files are strict data formats and are
never sourced as shell. For repeatable provisioning, review those files and run:

```bash
blankweave setup --non-interactive
```

This mode requires both configs, validates them, prints the same review, and
then applies without prompting. A missing profile config enables desktop,
development, and communication; gaming is also enabled on a gaming-capable
machine without a battery. Ordinary updates consume the saved package/Git/SSH
choices but preserve any theme selected after setup.

## Voice dictation

Add `voice-dictation` to the space-separated `profiles=` line in
`~/.config/blankweave/install.conf`, then run `blankweave update` (or select it
during `blankweave setup`). The profile performs this exact local setup:

1. Installs `voxtype-bin`, `wtype`, and the AT-SPI Python bindings used for
   best-effort editable-focus detection.
2. Downloads `ggml-small.en.bin` into
   `~/.local/share/voxtype/models/` and rejects it unless it matches the pinned
   SHA-256 digest.
3. Installs VoxType's Quickshell frontend, renders the active Blankweave colours
   into `~/.local/share/blankweave/voxtype/config.toml`, and links that file at
   `~/.config/voxtype/config.toml` unless a user-owned config already exists.
4. Enables `voxtype.service`, reloads Hyprland, and exposes the themed status
   and recovery panel in the bar.
5. Binds `Super+D` for toggle dictation and F12 press/release for push-to-talk.

Audio and transcripts stay on the machine. A definite missing/non-editable
target routes the result to the clipboard and shows a brief bottom preview.
Apps that do not publish accessibility state continue through normal typing so
Blankweave never overwrites the clipboard based on a guess; their preview says
to copy only if insertion did not happen. Either way, only the latest transcript
is retained at `~/.local/state/blankweave/voxtype-last-transcript.json`; it can
be copied from the voice panel in the bar.

Verify the installation with:

```bash
systemctl --user is-active voxtype.service
voxtype status --format json --extended
test -L ~/.config/voxtype/config.toml
test -f ~/.local/share/voxtype/models/ggml-small.en.bin
```

## Keybindings

### System
- `Super + L` – lock screen
- `Super + T` – toggle dark/light mode of the active theme
- `Super + D` – toggle local voice dictation when `voice-dictation` is enabled
- `F12` (hold/release) – push-to-talk local voice dictation
- `Super + Shift + W` – cycle the theme wallpaper and any user extras
- `Super + Y` – reload the desktop shell
- `Super + M` – exit Hyprland

### Applications
- `Super + Return` – terminal (ghostty)
- `Super + B` – web browser (Zen)
- `Super + Shift + B` – Bluetooth manager
- `Super + F` – file manager (Thunar)
- `Super + Space` – native application launcher

### Window Management
- `Super + Arrow Keys` – focus windows
- `Super + Q` – close window
- `Super + V` – toggle floating
- `Super + J` – toggle split direction
- `Super + P` – pseudo-tile

### Workspaces
- `Super + 1-9/0` – bring workspace 1-10 to the focused monitor; press again to send it to the next monitor
- `Super + Shift + 1-9/0` – move window to workspace

### Screenshots
- `Print` – full screen screenshot to clipboard
- `Super + S` – full screen screenshot to clipboard
- `Super + Shift + S` – select region screenshot to clipboard

### Clipboard
- `Super + Shift + V` – clipboard history (pick from past copies)

### Multimedia
- `Fn + Volume Up/Down` – adjust volume (with OSD)
- `Fn + Mute` – toggle mute
- `Fn + Brightness Up/Down` – adjust brightness (with OSD)
- Media play/pause, previous, and next keys – control the active MPRIS player

## Features

- **Capability-based hardware** with Intel, AMD, and NVIDIA graphics support
- **Audio support** via PipeWire with Pavucontrol GUI
- **Bluetooth** with Blueman GUI manager
- **Power management** via Hypridle (auto-lock, brightness control, suspend)
- **Clean notifications** via Dunst
- **Native Quickshell bar** with multi-monitor workspaces, audio, brightness,
  network throughput, Bluetooth, hardware metrics, battery, and power controls
- **Themes** — each theme provides the shell palette, lock-screen treatment, and
  wallpapers for both dark and light modes; `blankweave theme` switches them and
  personal themes live under `~/.config/blankweave/themes/`
- **Web apps** — sites as standalone windows through Helium's app mode, with
  launcher entries managed by `blankweave webapp`

## Renamed from hyprarch

If you installed this as hyprarch, run `hyprarch update` once. It fetches this
revision, moves `~/.local/share/hyprarch`, `~/.config/hyprarch`, and the
state and cache directories to their blankweave names (keeping your theme,
preferences, and wallpapers), and installs the `blankweave` command; the old
one is removed.

## Themes

A theme bundles the shell palette, the lock-screen treatment, a wallpaper,
the cursor and icon themes for each of its two modes, dark and light, plus
the Papirus folder colour and the boot splash. `Super + T` switches the mode;
the theme itself is chosen from the display panel in the bar or on the
command line:

```
blankweave theme list          # available themes and their modes
blankweave theme set <id>      # switch theme, keeping the current mode
blankweave theme mode light    # or dark
blankweave theme status        # the resolved theme as JSON
blankweave theme sync          # folder colours and boot splash (needs sudo)
```

Folder colours and the boot splash live outside your home, so `set` on the
command line finishes with a sudo prompt and a switch from the bar leaves a
hint until you run `blankweave theme sync`.

Two themes are bundled: `obsidian` (Obsidian dark / Porcelain light, blue) and
`moss` (Moss dark / Sage light, green). To make your own, copy
`defaults/themes/obsidian/` to `~/.config/blankweave/themes/<id>/`, edit
`theme.json`, and run `blankweave theme set <id>`; a personal theme with the same
id as a bundled one takes precedence.

## Web apps

A web app is a site opened as its own window, Omarchy-style, through
[Helium](https://github.com/imputnet/helium)'s app mode: no tabs or address
bar, its own entry in the launcher, and its own window class for Hyprland.
Helium comes with the `desktop` profile, and app windows share the browser's
logins. WhatsApp, Google Messages, YouTube, ChatGPT, GitHub, and Figma are
bundled; add your own with an icon URL or file (PNG or SVG):

```
blankweave webapp list
blankweave webapp install "Google Calendar" https://calendar.google.com/ \
    https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/google-calendar.png
blankweave webapp remove "Google Calendar"
blankweave webapp sync          # re-converge the bundled entries
```

To bind one, call `~/.local/share/blankweave/shell/webapp.sh launch <url>`
from `keybindings.lua`.

## Wallpapers

Each theme mode has its own wallpaper, restored at login and on every theme
or mode switch. `Super + Shift + W` cycles that wallpaper together with extras
in `~/.config/blankweave/wallpapers/`; updates do not touch that folder. With
no extras, the key restores the theme wallpaper.

## Customize

Edit `~/.config/` to customize application settings. The Quickshell source is
deployed to `~/.local/share/blankweave/quickshell/`; Dunst and Ghostty remain
symlinked from `~/.config/`.
