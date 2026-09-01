#!/usr/bin/env bash
set -e

# If not root: show banner and elevate. Block running with sudo directly.
if [ "$EUID" -ne 0 ]; then
    echo ""
    echo "#############################################################################"
    echo "###"
    echo "###   blankweave — Arch + Hyprland bootstrap"
    echo "###"
    echo "###   This will install and configure:"
    echo "###     - Hyprland (window manager)"
    echo "###     - Quickshell, Dunst, Ghostty, Fuzzel"
    echo "###     - PipeWire audio, Bluetooth, NetworkManager"
    echo "###     - ZSH with Powerlevel10k"
    echo "###     - Host-specific GPU drivers (auto-detected)"
    echo "###"
    echo "###   Configs: ~/.config    Defaults: ~/.local/share/blankweave"
    echo "###"
    echo "#############################################################################"
    echo ""
    exec sudo env \
        BLANKWEAVE_USER_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}" \
        "$0" "$@"
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

WARNINGS=()

warn() {
    WARNINGS+=("$*")
    printf 'Warning: %s\n' "$*" >&2
}

copy_file_atomically() {
    local source_file="$1"
    local target_file="$2"
    local staged_file

    staged_file=$(mktemp "$(dirname "$target_file")/.blankweave.XXXXXX")
    install -m 0644 "$source_file" "$staged_file"
    mv -f "$staged_file" "$target_file"
}

verify_packages_installed() {
    local label="$1"
    shift
    local package
    local -a missing=()

    for package in "$@"; do
        if ! pacman -Q -- "$package" &> /dev/null; then
            missing+=("$package")
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Error: $label installation did not provide every requested package:" >&2
        printf '  - %s\n' "${missing[@]}" >&2
        return 1
    fi
}

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
[ -n "$USER_HOME" ] || { echo "Could not resolve the home directory for $SUDO_USER" >&2; exit 1; }
USER_UID="$(id -u "$SUDO_USER")"
USER_STATE_HOME_EARLY="${BLANKWEAVE_USER_STATE_HOME:-$USER_HOME/.local/state}"

# A hyprarch-era install keeps its data under the old names. Move it before
# anything is read or deployed so the theme selection, preferences, and user
# wallpapers carry over. The managed checkout lives inside that data
# directory, and bash keeps reading this script from the moved inode, so the
# only thing to fix up afterwards is the path the rest of the run uses.
LEGACY_REPO_DIR="$USER_HOME/.local/share/hyprarch/repository"
sudo -H -u "$SUDO_USER" env HOME="$USER_HOME" XDG_STATE_HOME="$USER_STATE_HOME_EARLY" \
    "$REPO_DIR/scripts/relocate-legacy.sh" "$USER_HOME"
if [ "$REPO_DIR" = "$LEGACY_REPO_DIR" ]; then
    REPO_DIR="$USER_HOME/.local/share/blankweave/repository"
fi
rm -f /etc/pam.d/hyprarch-lock
USER_RUNTIME_DIR="/run/user/$USER_UID"
USER_STATE_HOME="${BLANKWEAVE_USER_STATE_HOME:-$USER_HOME/.local/state}"
PARU_BUILD_DIR=""

# Grant temporary NOPASSWD to avoid repeated password prompts during install
SUDOERS_TMP="/etc/sudoers.d/blankweave-install"
echo "$SUDO_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_TMP"
chmod 440 "$SUDOERS_TMP"

cleanup_install() {
    rm -f "$SUDOERS_TMP"
    if [[ -n "$PARU_BUILD_DIR" && "$PARU_BUILD_DIR" == /tmp/blankweave-paru.* ]]; then
        rm -rf -- "$PARU_BUILD_DIR"
    fi
}
trap cleanup_install EXIT

DOTS_DIR="$USER_HOME/.local/share/blankweave"
CONFIG_DIR="$USER_HOME/.config"
INSTALLER_CONFIG_FILE="$CONFIG_DIR/blankweave/install.conf"

# shellcheck source=scripts/installer-config.sh
source "$REPO_DIR/scripts/installer-config.sh"
# shellcheck source=scripts/package-manifests.sh
source "$REPO_DIR/scripts/package-manifests.sh"

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
installer_config_load "$INSTALLER_CONFIG_FILE" "$HOST"
echo "Required profile: core"
if [ "${#INSTALLER_PROFILES[@]}" -gt 0 ]; then
    printf 'Optional profiles: %s\n' "${INSTALLER_PROFILES[*]}"
else
    echo "Optional profiles: none"
fi

section "INSTALLING AUR HELPER"

if ! command -v paru &> /dev/null; then
    echo "Installing paru (AUR helper)..."
    pacman -S --noconfirm --needed base-devel
    PARU_BUILD_DIR=$(mktemp -d /tmp/blankweave-paru.XXXXXX)
    chown "$SUDO_USER:$SUDO_USER" "$PARU_BUILD_DIR"
    sudo -H -u "$SUDO_USER" git clone https://aur.archlinux.org/paru.git "$PARU_BUILD_DIR"
    sudo -H -u "$SUDO_USER" bash -c 'cd "$1" && makepkg -si --noconfirm' _ "$PARU_BUILD_DIR"
    rm -rf -- "$PARU_BUILD_DIR"
    PARU_BUILD_DIR=""
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
if ! pacman -Fy --noconfirm; then
    warn "File database sync failed; package installation will continue."
fi

echo "Installing base packages..."
PROVIDER_PACKAGES=()
REPO_PACKAGES=()
AUR_PACKAGES=()
resolve_package_manifests "$REPO_DIR" "$HOST" providers PROVIDER_PACKAGES
if [ "${#PROVIDER_PACKAGES[@]}" -gt 0 ]; then
    echo "Installing pinned virtual dependency providers..."
    pacman -S --noconfirm --needed "${PROVIDER_PACKAGES[@]}"
    verify_packages_installed "virtual dependency provider" "${PROVIDER_PACKAGES[@]}"
fi

resolve_package_manifests "$REPO_DIR" "$HOST" repository REPO_PACKAGES
pacman -S --noconfirm --needed "${REPO_PACKAGES[@]}"
verify_packages_installed "repository package" "${REPO_PACKAGES[@]}"

resolve_package_manifests "$REPO_DIR" "$HOST" aur AUR_PACKAGES

if [ "${#AUR_PACKAGES[@]}" -gt 0 ]; then
    echo "Installing exact AUR packages..."
    AUR_TARGETS=()
    for package in "${AUR_PACKAGES[@]}"; do
        AUR_TARGETS+=("aur/$package")
    done

    sudo -H -u "$SUDO_USER" paru -S --noconfirm --needed --noprovides "${AUR_TARGETS[@]}"
    verify_packages_installed "AUR package" "${AUR_PACKAGES[@]}"
fi

echo "Package installation complete."

section "ENABLING SERVICES"

echo "Setting up Bluetooth..."
systemctl enable bluetooth.service
systemctl start bluetooth.service || warn "Could not start Bluetooth; it may need manual setup."

echo "Setting up NetworkManager..."
systemctl enable NetworkManager.service
systemctl start NetworkManager.service || warn "Could not start NetworkManager."

echo "Setting up Tailscale..."
systemctl enable tailscaled.service
systemctl start tailscaled.service || warn "Could not start Tailscale."
# Log in separately (interactive/browser auth):  tailscale up

if installer_profile_enabled development; then
    echo "Setting up Docker..."
    systemctl enable docker.service
    systemctl start docker.service || warn "Could not start Docker."
    usermod -aG docker "$SUDO_USER"
fi
usermod -aG render,video "$SUDO_USER"

echo "Creating user directories..."
sudo -u "$SUDO_USER" xdg-user-dirs-update

section "CONFIGURING DEFAULT KEYRING"

# Automatic login cannot provide a password to pam_gnome_keyring. Fresh
# installs therefore use a passwordless default collection, with LUKS as the
# at-rest protection. Existing encrypted collections require their current
# password for a lossless conversion, so preserve them and give the user the
# one-time Seahorse procedure instead of replacing any secrets. Do not switch
# login/session management until this succeeds: boot-time Hyprlock is the only
# thing unlocking a legacy encrypted keyring.
if sudo -H -u "$SUDO_USER" env \
    HOME="$USER_HOME" \
    XDG_DATA_HOME="$USER_HOME/.local/share" \
    "$REPO_DIR/scripts/configure-default-keyring.sh"; then
    :
else
    KEYRING_STATUS=$?
    if [ "$KEYRING_STATUS" -eq 2 ]; then
        echo "Error: Existing Login keyring must be migrated in Seahorse before switching to console automatic login." >&2
    else
        echo "Error: Could not configure the default keyring." >&2
    fi
    exit "$KEYRING_STATUS"
fi

section "CONFIGURING CONSOLE AUTO-LOGIN"

"$REPO_DIR/scripts/configure-console-autologin.sh" "$SUDO_USER"
rm -f /etc/pam.d/blankweave-lock

section "COPYING DEFAULTS"

mkdir -p "$DOTS_DIR"
mkdir -p "$CONFIG_DIR"

echo "Copying defaults to $DOTS_DIR..."

mkdir -p "$USER_HOME/.local/bin"
install -m 0755 "$REPO_DIR/bin/blankweave" "$USER_HOME/.local/bin/blankweave"
copy_file_atomically "$REPO_DIR/VERSION" "$DOTS_DIR/VERSION"

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
cp -rv "$REPO_DIR/defaults/webapps" "$DOTS_DIR/" || { echo "Failed to copy webapps"; exit 1; }
# The boot splash is rendered here by theme-apply.sh and installed by root below.
cp -rv "$REPO_DIR/defaults/plymouth" "$DOTS_DIR/" || { echo "Failed to copy plymouth"; exit 1; }

HARDWARE_OVERRIDES="$REPO_DIR/hosts/$HOST/hardware-overrides.json"
if [ -f "$HARDWARE_OVERRIDES" ]; then
    copy_file_atomically "$HARDWARE_OVERRIDES" "$DOTS_DIR/hardware-overrides.json"
fi

# Mirror wallpapers exactly so removals in the repo propagate (cp alone never deletes stale files)
rm -rf "$DOTS_DIR/wallpapers"
cp -rv "$REPO_DIR/defaults/wallpapers" "$DOTS_DIR/" || { echo "Failed to copy wallpapers"; exit 1; }

# Bundled themes are mirrored the same way; user themes live under ~/.config/blankweave/themes.
rm -rf "$DOTS_DIR/themes"
cp -rv "$REPO_DIR/defaults/themes" "$DOTS_DIR/" || { echo "Failed to copy themes"; exit 1; }

chmod +x "$DOTS_DIR/shell"/*.sh

echo "Capturing sanitized hardware inventory..."
if ! "$DOTS_DIR/shell/hardware-inventory.sh" "$SUDO_USER"; then
    warn "Could not capture hardware inventory; the system overview will use generic fallbacks."
fi

section "GENERATING USER CONFIGS"
mkdir -p "$CONFIG_DIR/hypr"
mkdir -p "$CONFIG_DIR/dunst"
mkdir -p "$CONFIG_DIR/ghostty"

HYPRLAND_LUA_STAGED=$(mktemp "$CONFIG_DIR/hypr/.hyprland.lua.XXXXXX")
cat > "$HYPRLAND_LUA_STAGED" << 'EOF'
local home = os.getenv("HOME")

require(home .. "/.local/share/blankweave/hypr/hyprland")
require(home .. "/.config/hypr/env")
require(home .. "/.config/hypr/monitors")

-- Monitor arrangement chosen in the bar's display panel. The file is written
-- only by monitor-layout.sh and is absent until a position has been picked;
-- a broken or missing file must never keep the compositor from starting.
pcall(dofile, home .. "/.config/blankweave/monitors.lua")
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

section "APPLYING THEME"

# Renders every themed config from its template and records the selection in
# ~/.config/blankweave/theme.json. Runs as the user once ownership is fixed so
# the rendered files and the state are user-owned from the start.
if ! sudo -H -u "$SUDO_USER" env \
    HOME="$USER_HOME" \
    XDG_CONFIG_HOME="$CONFIG_DIR" \
    "$DOTS_DIR/shell/theme-apply.sh"; then
    echo "Error: Could not apply the theme."
    exit 1
fi

section "SYNCING WEB APPS"

# Bundled web apps are desktop entries that open a site in Helium's app mode.
# Helium ships with the optional desktop profile, so the script skips itself
# when the browser is absent; a failed icon download is not worth aborting an
# apply over.
if ! sudo -H -u "$SUDO_USER" env \
    HOME="$USER_HOME" \
    XDG_CONFIG_HOME="$CONFIG_DIR" \
    "$DOTS_DIR/shell/webapp.sh" sync; then
    warn "Could not sync the web apps; run: blankweave webapp sync"
fi

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
            warn "Headers for running kernel $RUNNING_KERNEL were not found; DKMS modules should build on next boot."
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
    "$REPO_DIR/scripts/configure-plymouth-transition.sh"

    # Place Plymouth after the init implementation and before encrypt/sd-encrypt.
    # The helper understands both busybox/udev and systemd initramfs layouts.
    if [ -f /etc/mkinitcpio.conf ]; then
        HOOKS_BEFORE=$(grep -E '^[[:space:]]*HOOKS[[:space:]]*=' /etc/mkinitcpio.conf)
        "$REPO_DIR/scripts/configure-plymouth-hooks.sh"
        HOOKS_AFTER=$(grep -E '^[[:space:]]*HOOKS[[:space:]]*=' /etc/mkinitcpio.conf)
        if [ "$HOOKS_BEFORE" != "$HOOKS_AFTER" ]; then
            echo "Rebuilding initramfs with plymouth..."
            mkinitcpio -P
        fi
    fi

    # Reconcile every Linux entry even when it already has a partial quiet
    # setup. The theme sync below then replaces the seeded console colour with
    # the active theme's dark canvas.
    BOOT_ENTRIES="/boot/loader/entries"
    if [ -d "$BOOT_ENTRIES" ]; then
        "$REPO_DIR/scripts/configure-kernel-command-line.sh" "$BOOT_ENTRIES"
    fi
fi

# The splash artwork, its background, the console colours behind it, and the
# Papirus folder colour all follow the theme applied above; this installs the
# staged copies and only rebuilds the initramfs when the splash changed.
"$REPO_DIR/scripts/theme-system.sh" "$USER_HOME" "$CONFIG_DIR"

section "GENERATING SSH KEY"

SSH_KEY="$USER_HOME/.ssh/id_ed25519"
if [ ! -f "$SSH_KEY" ]; then
    read -r -p "Enter your email for GitHub SSH key: " GIT_EMAIL
    echo "Generating SSH key for GitHub..."
    sudo -u "$SUDO_USER" mkdir -p "$USER_HOME/.ssh"
    sudo -u "$SUDO_USER" ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY" -N ""
fi

section "APPLYING MIGRATIONS"

sudo -H -u "$SUDO_USER" env \
    HOME="$USER_HOME" \
    XDG_STATE_HOME="$USER_STATE_HOME" \
    "$REPO_DIR/scripts/run-migrations.sh" "$REPO_DIR"

section "DONE"

echo "Installation complete!"
echo "  Host: $HOST"
echo "  Defaults: ~/.local/share/blankweave"
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

if [ "${#WARNINGS[@]}" -gt 0 ]; then
    echo ""
    echo "Completed with ${#WARNINGS[@]} warning(s):"
    printf '  - %s\n' "${WARNINGS[@]}"
fi
