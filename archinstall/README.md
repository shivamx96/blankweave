# Archinstall baseline

This directory contains the reusable, non-secret first-stage configuration for
installing Arch Linux before running the Blankweave bootstrap.

The committed configuration intentionally excludes:

- disk device paths and partition object IDs;
- disk encryption passwords;
- user and root password hashes;
- the hostname, which should distinguish the laptop and desktop.

Those values are machine-specific, sensitive, or destructive when reused on the
wrong device. Archinstall should collect them interactively on every install.

## Start from the live USB

Boot the Arch ISO in UEFI mode, connect to the network, and download the baseline:

```bash
curl -fL \
  https://raw.githubusercontent.com/shivamx96/blankweave/main/archinstall/user_configuration.json \
  -o /tmp/blankweave-archinstall.json

archinstall --config /tmp/blankweave-archinstall.json
```

Always use the interactive menu. Do not add `--silent`: the deliberately omitted
disk, encryption, authentication, and hostname choices must be reviewed by a
human on the target machine.

The file preselects the stable system choices: a minimal profile, Linux kernel,
systemd-boot, NetworkManager, PipeWire, Bluetooth, zram, locale, timezone, and the
small package set required to clone and run this repository after first boot.

## Required interactive choices

Before selecting **Install**, review the full summary and explicitly configure:

1. **Hostname** — use a unique name such as `blankweave-laptop` or `blankweave-pc`.
2. **Disk configuration** — select the intended target disk. Prefer the
   best-effort Btrfs layout for a dedicated Arch disk. Never select the Windows
   disk on the desktop.
3. **Disk encryption** — choose LUKS, enter a strong passphrase, and select the
   Linux root partition. Leave the EFI system partition unencrypted.
4. **Authentication** — create the normal user with sudo access. A separate root
   password is optional and may remain disabled.

The final Archinstall summary must visibly show disk encryption and the selected
root partition. Stop if it does not. Disk operations are destructive and a saved
layout from one device must never be reused blindly on the other.

Do not place `user_credentials.json`, encryption passwords, password hashes, or
local disk-layout exports in Git. Matching patterns are ignored by the repository.
If Archinstall credentials must be saved temporarily, use its encrypted
credentials-file option and keep the decryption key separately.

## Finish the Blankweave installation

After Archinstall finishes, reboot into the new system and run:

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
  https://raw.githubusercontent.com/shivamx96/blankweave/refs/heads/main/bootstrap.sh | sh
```

The bootstrap creates a managed checkout under
`~/.local/share/blankweave/repository`, then opens `blankweave setup` for a final
review of profiles, theme, and optional Git/SSH choices. The second stage
detects the Intel laptop or NVIDIA desktop and installs the matching drivers,
AUR packages, services, and user configuration. Future updates are applied with
`blankweave update`.

Before applying one, `blankweave update --dry-run` validates the fetched
revision and prints its host/profile package plan. Successful applies retain a
last-known-good Blankweave revision for `blankweave rollback`. That command
restores managed configuration but does not downgrade Arch packages; when a
root Snapper configuration exists, the updater records a pre-update snapshot
number for manual full-system recovery. Completed one-time migrations remain
forward-only across a Blankweave rollback.

At the graphical boot splash, Plymouth displays the LUKS prompt and masked
keystrokes. If a theme or graphics regression ever hides the prompt, press
**Esc** to switch to the text console and enter the passphrase there. To bypass
Plymouth for one boot, edit the systemd-boot entry with **e** and append
`plymouth.enable=0 disablehooks=plymouth` to its options.

## Encryption policy

Use a LUKS2 passphrase at boot on both machines. Hyprlock remains necessary for
protecting an active session, but it cannot protect an unencrypted SSD when the
machine is powered off or booted from external media.

The initial design deliberately uses a passphrase rather than unattended TPM
unlocking. TPM-only unlocking offers less protection if the entire computer is
stolen. A future UKI + Secure Boot + TPM2-with-PIN setup can improve boot
integrity and convenience, but should be introduced and recovery-tested as a
separate change.

Blankweave assumes this encrypted-root baseline and uses the LUKS prompt as its
boot-time authentication boundary. TTY1 logs in the installed user
automatically and starts Hyprland through UWSM, without SDDM or a second
graphical-startup Hyprlock prompt. Hyprlock remains enabled for manual locking,
idle timeout, suspend, and resume. The tty1 login banner and console cursor are
suppressed during the Plymouth-to-Hyprland handoff; tty2 remains an ordinary
recovery login. Plymouth retains its final boot framebuffer until Hyprland
replaces it, and tty1's hidden text buffer is cleared under the running
compositor so the shutdown splash receives the same clean handoff.
