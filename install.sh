#!/usr/bin/env bash
set -e

# If not root: show banner and elevate. Block running with sudo directly.
if [ "$EUID" -ne 0 ]; then
    echo ""
    echo "#############################################################################"
    echo "###"
    echo "###   hyprarch — Arch + Hyprland bootstrap"
    echo "###"
    echo "###   This will install and configure:"
    echo "###     - Hyprland (window manager)"
    echo "###     - Quickshell, Dunst, Ghostty, Fuzzel"
    echo "###     - PipeWire audio, Bluetooth, NetworkManager"
    echo "###     - ZSH with Powerlevel10k"
    echo "###     - Host-specific GPU drivers (auto-detected)"
    echo "###"
    echo "###   Configs: ~/.config    Defaults: ~/.local/share/hyprarch"
    echo "###"
    echo "#############################################################################"
    echo ""
    exec sudo "$0" "$@"
elif [ -z "$SUDO_USER" ]; then
    echo "Do not run as root directly. Just run: ./install.sh"
    exit 1
fi

section() {
    echo ""
    echo "#############################################################################"
    echo "### $1"
    echo "#############################################################################"
    echo ""
}

copy_file_atomically() {
    local source_file="$1"
    local target_file="$2"
    local staged_file

    staged_file=$(mktemp "$(dirname "$target_file")/.hyprarch.XXXXXX")
    install -m 0644 "$source_file" "$staged_file"
    mv -f "$staged_file" "$target_file"
}

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_HOME="/home/$SUDO_USER"
USER_UID="$(id -u "$SUDO_USER")"
USER_RUNTIME_DIR="/run/user/$USER_UID"

# Grant temporary NOPASSWD to avoid repeated password prompts during install
SUDOERS_TMP="/etc/sudoers.d/hyprarch-install"
echo "$SUDO_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_TMP"
chmod 440 "$SUDOERS_TMP"
trap 'rm -f "$SUDOERS_TMP"' EXIT

DOTS_DIR="$USER_HOME/.local/share/hyprarch"
CONFIG_DIR="$USER_HOME/.config"

section "DETECTING HOST"

detect_host() {
    if lspci | grep -q "Intel.*Arc"; then
        echo "laptop"
    elif lspci | grep -q "NVIDIA"; then
        echo "pc"
    else
        echo "laptop"  # default
    fi
}

HOST=$(detect_host)
echo "Detected host: $HOST"

section "INSTALLING AUR HELPER"

if ! command -v yay &> /dev/null && ! command -v paru &> /dev/null; then
    echo "Installing paru (AUR helper)..."
    pacman -S --noconfirm --needed base-devel
    rm -rf /tmp/paru
    sudo -u "$SUDO_USER" bash -c 'cd /tmp && git clone https://aur.archlinux.org/paru.git && cd paru && makepkg -si'
fi

section "INSTALLING PACKAGES"

echo "Enabling multilib repository..."
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf
elif grep -A1 "^\[multilib\]" /etc/pacman.conf | grep -q "^#Include"; then
    sed -i '/^\[multilib\]/{n;s/^#Include/Include/}' /etc/pacman.conf
fi

echo "Running full system upgrade..."
pacman -Syu --noconfirm
pacman -Fy --noconfirm || echo "Warning: file database sync failed"

echo "Installing base packages..."
pacman -S --noconfirm --needed $(cat "$REPO_DIR/packages/base.txt") || echo "Warning: pacman failed"

AUR_HELPER=$(command -v paru || command -v yay)
if [ -n "$AUR_HELPER" ]; then
    echo "Installing AUR packages..."
    AUR_PKGS=$(cat "$REPO_DIR/packages/aur.txt" | tr '\n' ' ')
    sudo -u "$SUDO_USER" $AUR_HELPER -S --noconfirm --needed $AUR_PKGS || echo "Warning: AUR install failed"

    HOST_PKGS="$REPO_DIR/hosts/$HOST/packages.txt"
    if [ -f "$HOST_PKGS" ]; then
        echo "Installing $HOST packages..."
        sudo -u "$SUDO_USER" $AUR_HELPER -S --noconfirm --needed $(cat "$HOST_PKGS") || echo "Warning: host package install failed"
    fi
else
    echo "Error: No AUR helper available."
    exit 1
fi

echo "Package installation complete."

section "ENABLING SERVICES"

echo "Setting up Bluetooth..."
systemctl enable bluetooth.service
systemctl start bluetooth.service || echo "Warning: Could not start bluetooth service (may need manual setup)"

echo "Setting up NetworkManager..."
systemctl enable NetworkManager.service
systemctl start NetworkManager.service || echo "Warning: Could not start NetworkManager service"

echo "Setting up Tailscale..."
systemctl enable tailscaled.service
systemctl start tailscaled.service || echo "Warning: Could not start tailscaled service"
# Log in separately (interactive/browser auth):  tailscale up

echo "Setting up Docker..."
systemctl enable docker.service
systemctl start docker.service || echo "Warning: Could not start docker service"
usermod -aG docker "$SUDO_USER"
usermod -aG render,video "$SUDO_USER"

echo "Creating user directories..."
sudo -u "$SUDO_USER" xdg-user-dirs-update

section "CONFIGURING SDDM AUTO-LOGIN"
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/autologin.conf << SDDM
[Autologin]
User=$SUDO_USER
Session=hyprland-uwsm
SDDM
systemctl enable sddm.service

# Remove TTY autologin if present (replaced by SDDM)
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf

section "COPYING DEFAULTS"

mkdir -p "$DOTS_DIR"
mkdir -p "$CONFIG_DIR"

echo "Copying defaults to $DOTS_DIR..."

mkdir -p "$DOTS_DIR/hypr"
for hypr_config in "$REPO_DIR/defaults/hypr/"*; do
    echo "Deploying $hypr_config"
    copy_file_atomically "$hypr_config" "$DOTS_DIR/hypr/$(basename "$hypr_config")"
done
# Quickshell is a code tree, so mirror it exactly and do not retain removed modules.
rm -rf "$DOTS_DIR/quickshell"
cp -rv "$REPO_DIR/defaults/quickshell" "$DOTS_DIR/" || { echo "Failed to copy quickshell"; exit 1; }
cp -rv "$REPO_DIR/defaults/dunst" "$DOTS_DIR/" || { echo "Failed to copy dunst"; exit 1; }
cp -rv "$REPO_DIR/defaults/ghostty" "$DOTS_DIR/" || { echo "Failed to copy ghostty"; exit 1; }
cp -rv "$REPO_DIR/defaults/fuzzel" "$DOTS_DIR/" || { echo "Failed to copy fuzzel"; exit 1; }
cp -rv "$REPO_DIR/defaults/xdg-desktop-portal" "$DOTS_DIR/" || { echo "Failed to copy xdg-desktop-portal"; exit 1; }
cp -rv "$REPO_DIR/defaults/fontconfig" "$DOTS_DIR/" || { echo "Failed to copy fontconfig"; exit 1; }
cp -rv "$REPO_DIR/defaults/shell" "$DOTS_DIR/" || { echo "Failed to copy shell"; exit 1; }

# Mirror wallpapers exactly so removals in the repo propagate (cp alone never deletes stale files)
rm -rf "$DOTS_DIR/wallpapers"
cp -rv "$REPO_DIR/defaults/wallpapers" "$DOTS_DIR/" || { echo "Failed to copy wallpapers"; exit 1; }

chmod +x "$DOTS_DIR/shell"/*.sh

section "GENERATING USER CONFIGS"
mkdir -p "$CONFIG_DIR/hypr"
mkdir -p "$CONFIG_DIR/dunst"
mkdir -p "$CONFIG_DIR/ghostty"

HYPRLAND_LUA_STAGED=$(mktemp "$CONFIG_DIR/hypr/.hyprland.lua.XXXXXX")
cat > "$HYPRLAND_LUA_STAGED" << 'EOF'
local home = os.getenv("HOME")

require(home .. "/.local/share/hyprarch/hypr/hyprland")
require(home .. "/.config/hypr/env")
require(home .. "/.config/hypr/monitors")
EOF
chmod 0644 "$HYPRLAND_LUA_STAGED"
mv -f "$HYPRLAND_LUA_STAGED" "$CONFIG_DIR/hypr/hyprland.lua"

HOST_DIR="$REPO_DIR/hosts/$HOST/hypr"
if [ -d "$HOST_DIR" ]; then
    copy_file_atomically "$HOST_DIR/env.lua" "$CONFIG_DIR/hypr/env.lua"
    copy_file_atomically "$HOST_DIR/monitors.lua" "$CONFIG_DIR/hypr/monitors.lua"
    copy_file_atomically "$HOST_DIR/hypridle.conf" "$CONFIG_DIR/hypr/hypridle.conf"
else
    echo "Error: No host config found at $HOST_DIR"
    exit 1
fi

copy_file_atomically "$REPO_DIR/defaults/hypr/hyprlock.conf" "$CONFIG_DIR/hypr/hyprlock.conf"

echo "Validating Hyprland Lua config..."
if [ ! -d "$USER_RUNTIME_DIR" ]; then
    echo "Error: User runtime directory does not exist: $USER_RUNTIME_DIR"
    echo "Log in as $SUDO_USER to create a systemd user session, then run the installer again."
    exit 1
fi

if ! sudo -u "$SUDO_USER" env \
    HOME="$USER_HOME" \
    XDG_CONFIG_HOME="$CONFIG_DIR" \
    XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
    hyprland --verify-config --config "$CONFIG_DIR/hypr/hyprland.lua"; then
    echo "Error: Generated Hyprland Lua config failed validation."
    exit 1
fi

section "SYMLINKING CONFIGS"

# Dunst
rm -f "$CONFIG_DIR/dunst/dunstrc"
ln -s "$DOTS_DIR/dunst/dunstrc" "$CONFIG_DIR/dunst/dunstrc"

# XDG Desktop Portal
mkdir -p "$CONFIG_DIR/xdg-desktop-portal"
rm -f "$CONFIG_DIR/xdg-desktop-portal/hyprland-portals.conf"
ln -s "$DOTS_DIR/xdg-desktop-portal/hyprland-portals.conf" "$CONFIG_DIR/xdg-desktop-portal/hyprland-portals.conf"

# Fuzzel
mkdir -p "$CONFIG_DIR/fuzzel"
rm -f "$CONFIG_DIR/fuzzel/fuzzel.ini"
ln -s "$DOTS_DIR/fuzzel/fuzzel.ini" "$CONFIG_DIR/fuzzel/fuzzel.ini"

# Ghostty
mkdir -p "$CONFIG_DIR/ghostty"
rm -f "$CONFIG_DIR/ghostty/config"
ln -s "$DOTS_DIR/ghostty/config" "$CONFIG_DIR/ghostty/config"

# Fontconfig
mkdir -p "$CONFIG_DIR/fontconfig/conf.d"
rm -f "$CONFIG_DIR/fontconfig/conf.d/local.conf"
ln -s "$DOTS_DIR/fontconfig/local.conf" "$CONFIG_DIR/fontconfig/conf.d/local.conf"

section "SETTING UP ZSH"
chsh -s /usr/bin/zsh "$SUDO_USER"

ZSHRC="$USER_HOME/.zshrc"
MARKER="### ANY CUSTOM CONFIGS GO BELOW THIS LINE"
if [ ! -f "$ZSHRC" ]; then
    cp "$DOTS_DIR/shell/.zshrc" "$ZSHRC"
else
    # Preserve everything below the marker, replace everything above with latest default
    CUSTOM_CONFIGS=""
    if grep -qF "$MARKER" "$ZSHRC"; then
        CUSTOM_CONFIGS=$(sed "1,/$MARKER/d" "$ZSHRC")
    fi
    cp "$DOTS_DIR/shell/.zshrc" "$ZSHRC"
    if [ -n "$CUSTOM_CONFIGS" ]; then
        echo "$CUSTOM_CONFIGS" >> "$ZSHRC"
    fi
fi
chown "$SUDO_USER:$SUDO_USER" "$ZSHRC"

PROFILE_SOURCE="source $DOTS_DIR/shell/profile"
SHELL_RC="$USER_HOME/.zprofile"
touch "$SHELL_RC"
if ! grep -qF "$PROFILE_SOURCE" "$SHELL_RC"; then
    echo "$PROFILE_SOURCE" >> "$SHELL_RC"
fi

section "FIXING OWNERSHIP"
chown -R "$SUDO_USER:$SUDO_USER" "$DOTS_DIR"
chown -R "$SUDO_USER:$SUDO_USER" "$CONFIG_DIR"
chown "$SUDO_USER:$SUDO_USER" "$SHELL_RC"
[ -d "$USER_HOME/.cache" ] && chown -R "$SUDO_USER:$SUDO_USER" "$USER_HOME/.cache"
[ -d "$USER_HOME/.local" ] && chown -R "$SUDO_USER:$SUDO_USER" "$USER_HOME/.local"

section "CONFIGURING NVIDIA (PC ONLY)"

if [ "$HOST" = "pc" ]; then
    echo "Configuring NVIDIA DRM..."
    mkdir -p /etc/modprobe.d
    echo "options nvidia_drm modeset=1" > /etc/modprobe.d/nvidia.conf

    for kern in $(pacman -Qqe | grep "^linux" | grep -v headers); do
        if pacman -Si "${kern}-headers" &> /dev/null; then
            pacman -S --noconfirm --needed "${kern}-headers"
        fi
    done

    RUNNING_KERNEL=$(uname -r)
    if command -v dkms &> /dev/null; then
        if [ -d "/usr/lib/modules/$RUNNING_KERNEL/build" ]; then
            dkms autoinstall
        else
            echo "Warning: Headers for running kernel $RUNNING_KERNEL not found (kernel was likely upgraded)."
            echo "DKMS modules will build automatically on next boot."
        fi
    fi

    NVIDIA_MODULES="nvidia nvidia_modeset nvidia_uvm nvidia_drm"
    if [ -f /etc/mkinitcpio.conf ]; then
        CURRENT_MODULES=$(grep "^MODULES=" /etc/mkinitcpio.conf | sed 's/MODULES=(\(.*\))/\1/')
        NEEDS_UPDATE=false
        for mod in $NVIDIA_MODULES; do
            if ! echo "$CURRENT_MODULES" | grep -qw "$mod"; then
                NEEDS_UPDATE=true
                break
            fi
        done
        if [ "$NEEDS_UPDATE" = true ]; then
            sed -i "s/^MODULES=(\(.*\))/MODULES=(\1 $NVIDIA_MODULES)/" /etc/mkinitcpio.conf
            sed -i 's/MODULES=(  */MODULES=(/' /etc/mkinitcpio.conf
            echo "Rebuilding initramfs..."
            mkinitcpio -P
        fi
    fi
fi

section "CONFIGURING PLYMOUTH"

echo "Setting up Plymouth boot splash..."
if command -v plymouth-set-default-theme &> /dev/null; then
    # Install custom HyprArch theme
    cp -rv "$REPO_DIR/defaults/plymouth/hyprarch" /usr/share/plymouth/themes/
    plymouth-set-default-theme -R hyprarch

    # Add plymouth hook to mkinitcpio if not present
    if [ -f /etc/mkinitcpio.conf ]; then
        if ! grep "^HOOKS=" /etc/mkinitcpio.conf | grep -q "plymouth"; then
            sed -i 's/^HOOKS=(\(.*\)udev\(.*\))/HOOKS=(\1udev plymouth\2)/' /etc/mkinitcpio.conf
            echo "Rebuilding initramfs with plymouth..."
            mkinitcpio -P
        fi
    fi

    # Add splash, quiet, and loglevel to systemd-boot kernel cmdline
    BOOT_ENTRIES="/boot/loader/entries"
    if [ -d "$BOOT_ENTRIES" ]; then
        for entry in "$BOOT_ENTRIES"/*.conf; do
            if ! grep -q "splash" "$entry"; then
                sed -i '/^options/ s/$/ quiet loglevel=3 splash vt.default_red=30 vt.default_grn=30 vt.default_blu=46/' "$entry"
                echo "Updated boot entry: $entry"
            fi
        done
    fi

fi

section "GENERATING SSH KEY"

SSH_KEY="$USER_HOME/.ssh/id_ed25519"
if [ ! -f "$SSH_KEY" ]; then
    read -p "Enter your email for GitHub SSH key: " GIT_EMAIL
    echo "Generating SSH key for GitHub..."
    sudo -u "$SUDO_USER" mkdir -p "$USER_HOME/.ssh"
    sudo -u "$SUDO_USER" ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY" -N ""
fi

section "DONE"

echo "Installation complete!"
echo "  Host: $HOST"
echo "  Defaults: ~/.local/share/hyprarch"
echo "  User configs: ~/.config"
echo "  Auto-login and Hyprland auto-start configured"
if [ "$HOST" = "pc" ]; then
    echo "  NVIDIA DRM modeset and early KMS configured"
fi
echo ""
if [ -f "$SSH_KEY.pub" ]; then
    echo "── GitHub SSH Key ──"
    echo "Add this to https://github.com/settings/ssh/new"
    echo ""
    cat "$SSH_KEY.pub"
    echo ""
fi
echo "── Tailscale ──"
if ! tailscale status &>/dev/null; then
    echo "Not logged in yet. Run:  tailscale up"
    echo ""
fi
echo "Reboot to launch into Hyprland."
echo "If Hyprland was running during this install, a full session restart is required."
echo "A hyprctl reload cannot switch an existing legacy .conf session to Lua."
