# Wallpaper Setup

Blankweave uses **awww** for beautiful dynamic wallpaper management on Wayland.

## How to Use

1. **Add wallpapers to:**
   ```bash
   ~/.local/share/blankweave/wallpapers/
   ```

2. **Change wallpaper:**
   - `Super + Shift + W` – cycle through wallpapers
   - Or manually: `~/.local/share/blankweave/shell/wallpaper.sh set /path/to/wallpaper.jpg`

3. **Set random on startup:**
   - Already configured in autostart

## Recommended Wallpapers

Download beautiful Catppuccin-themed wallpapers from:

### High Quality Collections
- **Catppuccin Wallpapers** – https://github.com/catppuccin/wallpapers
- **Unsplash** – Dark/blue themed: https://unsplash.com
- **Pexels** – Free stock photos: https://pexels.com
- **Wallpaper Engine** – Steam workshop (convert to jpg/png)

### Recommended Themes
- Dark/moody landscapes
- Cyberpunk aesthetic
- Minimalist blue/purple gradients
- Space/stars
- Terminal/code aesthetics

## Script Commands

```bash
# Set random wallpaper
~/.local/share/blankweave/shell/wallpaper.sh random

# Cycle to next wallpaper
~/.local/share/blankweave/shell/wallpaper.sh cycle

# Set specific wallpaper
~/.local/share/blankweave/shell/wallpaper.sh set /path/to/image.jpg
```

## Tips

- **Resolution:** Use high-res images (2560x1440 or higher for laptop)
- **Format:** JPG or PNG
- **Performance:** awww is lightweight and fast
- **Transitions:** Automatically uses wipe transition (customize in wallpaper.sh)

## Download Quick Start

```bash
# Create wallpapers directory
mkdir -p ~/.local/share/blankweave/wallpapers

# Download a few Catppuccin wallpapers
cd ~/.local/share/blankweave/wallpapers
# Download your favorite wallpapers here
```

Then press `Super + Shift + W` to cycle!
