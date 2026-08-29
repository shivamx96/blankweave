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
`~/.local/share/blankweave/repository`. The second stage detects the Intel laptop
or NVIDIA desktop and installs the matching drivers, AUR packages, services,
and user configuration. Future updates are applied with `blankweave update`.

## Encryption policy

Use a LUKS2 passphrase at boot on both machines. Hyprlock remains necessary for
protecting an active session, but it cannot protect an unencrypted SSD when the
machine is powered off or booted from external media.

The initial design deliberately uses a passphrase rather than unattended TPM
unlocking. TPM-only unlocking offers less protection if the entire computer is
stolen. A future UKI + Secure Boot + TPM2-with-PIN setup can improve boot
integrity and convenience, but should be introduced and recovery-tested as a
separate change.

Once every supported machine has an encrypted root, the automatic Hyprlock call
at graphical-session startup can be removed to avoid two consecutive boot
prompts. Hyprlock should remain enabled for manual locking, idle timeout,
suspend, and resume. Do not remove the startup lock while an unencrypted machine
still relies on it after SDDM autologin.
