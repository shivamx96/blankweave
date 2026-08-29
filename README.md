# hyprarch

Arch + Hyprland bootstrap with automatic hardware detection.

Supported hosts:
- **laptop** — Intel Core Ultra 9 185H with Arc iGPU
- **pc** — NVIDIA (RTX 5090 / any NVIDIA GPU) with AMD Ryzen

## Install

For a new machine starting from the Arch live USB, use the reusable
[Archinstall baseline](archinstall/README.md) first. It keeps disk selection and
LUKS/user credentials interactive, then hands the installed system to this
bootstrap.

Run the bootstrap as your normal user after the Archinstall stage:

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
  https://raw.githubusercontent.com/shivamx96/hyprarch/refs/heads/main/bootstrap.sh | sh
```

It clones the managed repository to
`~/.local/share/hyprarch/repository`, installs the `hyprarch` command in
`~/.local/bin`, and applies the system configuration. The bootstrap requires an
interactive terminal because package installation and a few first-run choices
need user input.

After the first install, use:

```bash
hyprarch version
hyprarch update
```

`hyprarch update` refuses dirty, divergent, or non-`main` managed checkouts. It
only fast-forwards from the expected GitHub repository, applies the new version,
and then records successful one-time migrations.

The script will:
- Detect hardware
- Install packages (Hyprland, Quickshell, Dunst, Ghostty, etc.)
- Set up defaults in `~/.local/share/hyprarch/`
- Generate user configs in `~/.config/`
- Capture a sanitized hardware inventory for the native system panel

For development, a local checkout can still be applied with `./install.sh`.
That path installs the same command and records the checkout as the active
Hyprarch source.

The hardware inventory stores motherboard, display, and DIMM model/specification
fields, but excludes hardware serial numbers and machine UUIDs. Refresh it after
changing RAM or displays without reinstalling:

```bash
sudo ~/.local/share/hyprarch/shell/hardware-inventory.sh "$USER"
```

The live shell never needs elevated privileges; it only reads this cached file.

## Installer profiles

The required Hyprarch environment and detected hardware support are always
installed. Optional applications are grouped into four additive profiles:

- `desktop` — browsers, notes, and personal desktop utilities;
- `development` — editors, containers, language tooling, and coding tools;
- `communication` — messaging and local sharing applications;
- `gaming` — Steam, Proton, overlays, and host-appropriate 32-bit GPU support.

Selections can be stored in `~/.config/hyprarch/install.conf`:

```ini
version=1
profiles=desktop development communication
```

The config is parsed as data and is never sourced as shell code. Profile order
does not matter, duplicate names are ignored, and unknown keys, versions, or
profiles stop the installer before package changes begin.

Until the guided `hyprarch setup` command is added, a missing config preserves
the historical installation exactly: laptop enables desktop, development, and
communication; PC additionally enables gaming. Removing a profile only stops
Hyprarch from requesting those packages in future runs—it does not uninstall
software already present.

## Keybindings

### System
- `Super + L` – lock screen
- `Super + D` – toggle dark/light mode of the active theme
- `Super + Y` – reload the desktop shell
- `Super + M` – exit Hyprland

### Applications
- `Super + Return` – terminal (ghostty)
- `Super + B` – web browser (Zen)
- `Super + Shift + B` – Bluetooth manager
- `Super + F` – file manager (Thunar)
- `Super + Space` – native application launcher
- `Super + Shift + Space` – Fuzzel fallback launcher

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

## Features

- **Multi-host** with auto-detection (Intel laptop / NVIDIA desktop)
- **Audio support** via PipeWire with Pavucontrol GUI
- **Bluetooth** with Blueman GUI manager
- **Power management** via Hypridle (auto-lock, brightness control, suspend)
- **Clean notifications** via Dunst
- **Native Quickshell bar** with multi-monitor workspaces, audio, brightness,
  network throughput, Bluetooth, hardware metrics, battery, and power controls
- **Themes** — each theme provides the shell palette, lock-screen treatment, and
  wallpapers for both dark and light modes; `hyprarch theme` switches them and
  personal themes live under `~/.config/hyprarch/themes/`

## Themes

A theme bundles the shell palette, the lock-screen treatment, a wallpaper,
the cursor and icon themes for each of its two modes, dark and light, plus
the Papirus folder colour and the boot splash. `Super + D` switches the mode;
the theme itself is chosen from the display panel in the bar or on the
command line:

```
hyprarch theme list          # available themes and their modes
hyprarch theme set <id>      # switch theme, keeping the current mode
hyprarch theme mode light    # or dark
hyprarch theme status        # the resolved theme as JSON
hyprarch theme sync          # folder colours and boot splash (needs sudo)
```

Folder colours and the boot splash live outside your home, so `set` on the
command line finishes with a sudo prompt and a switch from the bar leaves a
hint until you run `hyprarch theme sync`.

Two themes are bundled: `obsidian` (Obsidian dark / Porcelain light, blue) and
`moss` (Moss dark / Sage light, green). To make your own, copy
`defaults/themes/obsidian/` to `~/.config/hyprarch/themes/<id>/`, edit
`theme.json`, and run `hyprarch theme set <id>`; a personal theme with the same
id as a bundled one takes precedence.

## Wallpapers

Wallpapers are managed with **awww** (dynamic background for Wayland).

- Add wallpapers to: `~/.local/share/hyprarch/wallpapers/`
- Change wallpaper: `Super + Shift + W` (cycles through that folder)
- Each theme mode has its own wallpaper, restored at login and on every mode
  switch
- Set random: `~/.local/share/hyprarch/shell/wallpaper.sh random`

See [WALLPAPERS.md](WALLPAPERS.md) for recommended wallpaper sources and setup.

## Customize

Edit `~/.config/` to customize application settings. The Quickshell source is
deployed to `~/.local/share/hyprarch/quickshell/`; Dunst, Ghostty, and Fuzzel
remain symlinked from `~/.config/`.
