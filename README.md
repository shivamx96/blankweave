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

```bash
git clone https://github.com/shivamx96/hyprarch.git
cd hyprarch
chmod +x install.sh
./install.sh
```

The script will:
- Detect hardware
- Install packages (Hyprland, Quickshell, Dunst, Ghostty, etc.)
- Set up defaults in `~/.local/share/hyprarch/`
- Generate user configs in `~/.config/`
- Capture a sanitized hardware inventory for the native system panel

The hardware inventory stores motherboard, display, and DIMM model/specification
fields, but excludes hardware serial numbers and machine UUIDs. Refresh it after
changing RAM or displays without reinstalling:

```bash
sudo ~/.local/share/hyprarch/shell/hardware-inventory.sh "$USER"
```

The live shell never needs elevated privileges; it only reads this cached file.

## Keybindings

### System
- `Super + L` – lock screen
- `Super + D` – toggle light/dark theme
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
- `Super + 1-9/0` – switch workspaces (1-10)
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
- **Hyprarch visual system** with a modern full-width shell and black/blue dark and
  white/blue light palettes

## Wallpapers

Wallpapers are managed with **awww** (dynamic background for Wayland).

- Add wallpapers to: `~/.local/share/hyprarch/wallpapers/`
- Change wallpaper: `Super + Shift + W` (cycles through all wallpapers)
- Set random: `~/.local/share/hyprarch/shell/wallpaper.sh random`

See [WALLPAPERS.md](WALLPAPERS.md) for recommended wallpaper sources and setup.

## Customize

Edit `~/.config/` to customize application settings. The Quickshell source is
deployed to `~/.local/share/hyprarch/quickshell/`; Dunst, Ghostty, and Fuzzel
remain symlinked from `~/.config/`.
