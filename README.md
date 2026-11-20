# Blankweave

Blankweave configures an installed Arch Linux system as a Hyprland desktop with
Quickshell, Ghostty, Dunst and capability-selected hardware support. It manages
system configuration and application defaults as well as appearance. It is not
an operating-system installer or a package rollback tool; use Archinstall first
if you need a base system, and keep backups of existing configuration.

## Screenshots

**Owner action required: add these images. No screenshots are supplied yet.**

- `docs/screenshots/desktop.png` — desktop, bar and application launcher.
- `docs/screenshots/settings.png` — native Settings and a bar control panel.
- `docs/screenshots/lock-screen.png` — manual lock screen.

These are planned image paths, not existing assets.

## What you get

- A multi-monitor bar with keyboard-accessible device and system panels.
- An application launcher, clipboard history, Settings search and system actions.
- Native Settings for appearance, devices, networking and system maintenance.
- Bundled dark/light themes and personal theme support.
- Manual and idle lock-screen protection with Hyprlock.
- Release updates, diagnostics and bounded configuration rollback.
- Hardware adaptation for Intel, AMD and NVIDIA graphics, batteries, internal
  displays, DDC/CI brightness and Bluetooth.

## Requirements

Use an installed Arch Linux system booted in UEFI mode, a normal account with
sudo access, and working Internet access for Git, package downloads and AUR
builds. Preflight requires sudo, pacman, Git and Python 3, an unlocked package database,
and disabled Secure Boot when its status is readable. Bootstrap can install
Git through sudo if missing. Full upgrades require network access.

The boot helpers support direct Linux Boot Loader Specification entries with
kernel and initramfs files on a FAT EFI System Partition, using systemd-boot
or Limine. Blankweave installs Limine and preserves systemd-boot recovery.
GRUB, UKI-only layouts, legacy BIOS and signed Secure Boot are unsupported.
There is no distribution-derivative compatibility promise. GPU detection covers
Intel, AMD and NVIDIA; hardware-dependent controls need device/driver support.

LUKS root encryption is recommended. If encryption cannot be confirmed, setup
defaults to password sign-in and skips passwordless keyring provisioning.
Automatic sign-in can be selected explicitly: anyone who can unlock the disk
gets the desktop and its saved secrets. No display manager or boot-time lock
screen is installed. Hyprlock protects manual locking, idle, suspend and resume.

## Install

For a new system, review the [Archinstall baseline](archinstall/README.md).
Run this as your normal user in an interactive terminal:

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
  https://raw.githubusercontent.com/shivamx96/blankweave/refs/heads/main/bootstrap.sh | sh
```

Bootstrap selects the newest valid annotated release reachable from main and
creates `~/.local/share/blankweave/repository`. Guided setup asks for optional
application profiles, theme/mode, optional global Git identity, local Ed25519
key generation and sign-in policy. It never uploads keys or asks for credentials.
Review the package list before applying. Installation includes a full Arch
upgrade, package/AUR builds, hardware configuration, boot manager, services,
login policy, managed data and config entry points. Duration depends on downloads,
AUR builds and selected profiles; no fixed completion time is guaranteed. Stages
show elapsed time. Optional package failures are listed with retry commands.

A cancelled setup prints its resume command. Run
`~/.local/share/blankweave/repository/bin/blankweave setup` again; after a failed
apply with saved choices, add `--non-interactive`. That retries convergence
rather than resuming at the failed stage. Non-interactive setup requires both
`~/.config/blankweave/install.conf` and `~/.config/blankweave/setup.conf`.

Restart when the installer says to. Automatic sign-in uses the disk passphrase
as the login; password sign-in additionally asks for the account password.
The first desktop login offers a dismissible welcome card. Five starting keys
are Super+Return (terminal), Super+Space (launcher), Super+comma (Settings),
Super+slash (all shortcuts), and Super+Escape (power panel). `blankweave welcome` shows the
card again. Run `blankweave doctor` after installation.

## Daily use

Default keys come from `defaults/shell/shortcut-catalog.json`. Settings can
change them; these are the bundled defaults:

| Key | Action |
| --- | --- |
| `Super+Return` | Open terminal <!-- shortcut:terminal --> |
| `Super+space` | Open launcher <!-- shortcut:launcher --> |
| `Super+comma` | Open Settings <!-- shortcut:settings --> |
| `Super+slash` | Keyboard shortcuts <!-- shortcut:settings-shortcuts --> |
| `Super+B` | Open web browser <!-- shortcut:browser --> |
| `Super+E` | Open file manager <!-- shortcut:files --> |
| `Super+L` | Lock screen <!-- shortcut:lock --> |
| `Super+T` | Toggle theme <!-- shortcut:theme --> |
| `Super+Shift+V` | Open clipboard <!-- shortcut:clipboard --> |
| `Super+Q` | Close window <!-- shortcut:close-window --> |
| `Super+F` | Toggle fullscreen <!-- shortcut:fullscreen-window --> |
| `Super+Shift+F` | Toggle maximize <!-- shortcut:maximize-window --> |
| `Super+S` | Copy screenshot <!-- shortcut:screenshot --> |
| `Super+Escape` | Open power menu <!-- shortcut:logout --> |
| `Super+Ctrl+A` | Open audio panel <!-- shortcut:panel-audio --> |
| `Super+Ctrl+N` | Open network panel <!-- shortcut:panel-network --> |
| `Super+Ctrl+B` | Open bluetooth panel <!-- shortcut:panel-bluetooth --> |
| `Super+Ctrl+I` | Open notifications panel <!-- shortcut:panel-notifications --> |
| `Super+Ctrl+D` | Open display panel <!-- shortcut:panel-display --> |

The bar exposes workspaces, device controls, notifications, hardware meters and
power, with optional profile/application indicators. Click an entry to open its
panel; the Super+Ctrl keys above open common panels on the focused display.
Tab/Shift+Tab move through controls, arrows adjust or navigate, Enter/Space
activate, and Escape closes. Power actions that discard work require confirmation.

The launcher searches installed desktop entries, Settings rows and a fixed set
of system actions; it also offers clipboard history with Ctrl+Tab to switch
views. It is not a general shell-command runner. Browser and file keys use the
effective default applications; a base install without a browser is supported.

Open Settings from the launcher or with `blankweave settings`. Use
`blankweave settings --list` for page/row ids, then `blankweave settings <id>`
to open a particular control. `blankweave help <command>` describes each command.
Zsh completion installs to `~/.local/share/zsh/site-functions`, on the managed
zshrc's fpath before compinit. Bash completion is installed under
`~/.local/share/bash-completion/completions/blankweave` for bash-completion users. A fresh installation seeds GCR's SSH agent socket
once; it works with the existing GNOME Keyring Secret Service. The profile only
sets SSH_AUTH_SOCK when unset and the GCR socket exists. Add keys yourself; no forwarding or SSH config
changes are made. Existing installations preserve their prior agent choice.
Printer Settings offers discovered IPP/IPPS devices from a bounded read-only
CUPS query alongside manual URI entry; no discovery daemon is installed.

## Updating

`blankweave update` fetches releases and applies the newest valid annotated
SemVer tag reachable from main whose VERSION agrees. Unreleased main commits
are ignored. The managed checkout must be clean, on main, and use the trusted
origin. `blankweave update --check` fetches and reports without applying;
`blankweave update --dry-run` also validates and prints the target package plan.
`blankweave update --to vX.Y.Z` selects a specific newer release.
`blankweave update --reapply` repairs the current revision with a full system
upgrade; it cannot combine with --to. Removing a profile never removes packages.

The confirmation shows the release transition and upgrades known to local
pacman databases, calling out kernel, GPU drivers, Hyprland and Quickshell.
The final package transaction may differ after database refresh. `--yes` skips
the terminal question; update scripts without a terminal already proceed.
Apply inhibits shutdown, sleep and idle when supported. A removed running
kernel's modules trigger a restart-required message, a power-panel hint and a
confirmed Restart action in Settings; restart when ready.

## When something goes wrong

Run `blankweave doctor` for read-only checks and the remedy printed beside each
warning/failure. `blankweave doctor --normal` never elevates; `--full` requests
sudo for protected boot checks only. `--report` omits identifying information
and is suitable for sharing. Doctor also warns about non-loopback listening
ports when it can confirm no input firewall, without changing firewall state;
if rules cannot be read it reports that the state is unknown.

A failed session start leaves a recovery card and working shell on tty1:
inspect `~/.local/state/blankweave/uwsm-session.log` (previous log: the same name
with .1), run doctor, and use `start_desktop` to retry after fixing the cause.
Ctrl+Alt+F2 opens the ordinary tty2 recovery login. User service diagnostics are
in `journalctl --user -b -p warning`. Setup logs live under
`~/.local/state/blankweave/setup/`; update/reapply logs and diagnostic reports
live under `~/.local/state/blankweave/recovery/` (repairs use its reapply directory).

`blankweave rollback` restores the recorded previous release and reconverges
managed configuration within MIN_ROLLBACK_VERSION. It never downgrades packages
or reverses migrations; normally only missing packages are installed offline
from local databases/cache. For an older installer that cannot avoid a full
upgrade, confirm on a terminal or use `blankweave rollback --allow-upgrade`.
Snapper snapshots are recorded only when a root configuration already exists;
full-system restoration is manual. Updates started before v0.2.0 cannot record
a protected rollback point. If Limine fails, choose Linux Boot Manager in the
firmware menu for the preserved systemd-boot path.

## Customising

Choose appearance in Settings or use `blankweave theme list`,
`blankweave theme set <id>`, `blankweave theme mode light` and
`blankweave theme sync`. Bare `blankweave theme` shows theme, mode and pending
system sync. System appearance needs authorization. Personal themes under
`~/.config/blankweave/themes/` shadow bundled ids. Use `blankweave theme lint`
to validate themes before applying them.

Put personal snippets in `~/.config/blankweave/overrides/`: hyprland.lua,
ghostty.conf, dunst.conf and zsh.zsh load after managed defaults. Missing starter
files are seeded once. Managed data under `~/.local/share/blankweave/` is replaced
on update. Fully custom entry points are preserved but must load snippets
themselves. The Files list below records Settings storage and editing rules.

### Files

Settings names its storage below each control. `~/.config` below means
`${XDG_CONFIG_HOME:-~/.config}`; Copy path resolves the current location.
Keep a backup before hand editing; generated Lua files should be regenerated
through Settings. External edits are read back, validated, or rejected as stale.

<!-- settings-files:start -->
- `~/.config/blankweave/accessibility.json` — accessibility preferences; writer: accessibility-settings.py; hand editing supported with the existing schema (close Settings first).
- `~/.config/blankweave/accessibility.lua` — accessibility generated compositor rules; writer: accessibility-settings.py; generated, do not hand edit.
- `~/.config/blankweave/backup.json` — backup preferences; writer: settings_backup.py; hand editing supported with the existing schema (close Settings first).
- `~/.config/blankweave/idle.json` — idle preferences; writer: idle-policy.py; hand editing supported with the existing schema (close Settings first).
- `~/.config/blankweave/interface.json` — interface preferences; writer: interface-settings.py; hand editing supported with the existing schema (close Settings first).
- `~/.config/blankweave/interface.lua` — interface generated compositor rules; writer: interface-settings.py; generated, do not hand edit.
- `~/.config/blankweave/keyboard.json` — keyboard preferences; writer: keyboard-settings.py; hand editing supported with the existing schema (close Settings first).
- `~/.config/blankweave/keyboard.lua` — keyboard generated compositor rules; writer: keyboard-settings.py; generated, do not hand edit.
- `~/.config/blankweave/monitor-setups.json` — monitor setups preferences; writer: monitor-layout.sh (monitor-setups.py); hand editing supported with the existing schema (close Settings first).
- `~/.config/blankweave/monitors.json` — monitors preferences; writer: monitor-layout.sh; hand editing supported with the existing schema (close Settings first).
- `~/.config/blankweave/monitors.lua` — monitors generated compositor rules; writer: monitor-layout.sh; generated, do not hand edit.
- `~/.config/blankweave/night-light.json` — night light preferences; writer: night-light.py; hand editing supported with the existing schema (close Settings first).
- `~/.config/blankweave/notifications.json` — notifications preferences; writer: notification-settings.py; hand editing supported with the existing schema (close Settings first).
- `~/.config/blankweave/pointer.json` — pointer preferences; writer: pointer-settings.py; hand editing supported with the existing schema (close Settings first).
- `~/.config/blankweave/pointer.lua` — pointer generated compositor rules; writer: pointer-settings.py; generated, do not hand edit.
- `~/.config/blankweave/power-profiles.json` — power profiles preferences; writer: power_policy.py; hand editing supported with the existing schema (close Settings first).
- `~/.config/blankweave/shell.json` — shell preferences; writer: ShellPreferences; hand editing supported with the existing schema (close Settings first).
- `~/.config/blankweave/shortcuts.json` — shortcuts preferences; writer: shortcuts-settings.py; hand editing supported with the existing schema (close Settings first).
- `~/.config/blankweave/shortcuts.lua` — shortcuts generated compositor rules; writer: shortcuts-settings.py; generated, do not hand edit.
- `~/.config/blankweave/theme.json` — resolved theme selection and palette; writer: theme-apply.sh; use Settings or theme-apply.sh, edit personal themes instead.
- `~/.config/blankweave/theme.lua` — theme generated compositor rules; writer: theme-apply.sh; generated, do not hand edit.
- `~/.config/blankweave/wallpapers.json` — wallpapers preferences; writer: wallpaper-settings.py; hand editing supported with the existing schema (close Settings first).
- `~/.config/mimeapps.list` — mimeapps preferences; writer: default-apps.py; hand editing supported with the existing schema (close Settings first).
- `~/.config/blankweave/magnifier.lua` — magnifier shortcuts; writer: settings_session.py; managed file, use Settings or personal Hyprland overrides.
- `~/.config/blankweave/idle-hibernate` — idle sleep selects suspend or hibernate; writer: settings_recovery.py; hand editing supported (`yes` or `no`).
<!-- settings-files:end -->

Other contents of the Blankweave configuration directory:

- `~/.config/blankweave/install.conf` — package profile choices; writer: installer choices parser; hand editing supported (strict key=value).
- `~/.config/blankweave/setup.conf` — non-secret first-run choices; writer: guided setup; hand editing supported (strict key=value).
- `~/.config/blankweave/weather.json` — weather location; writer: weather-status.sh; hand editing supported with its schema.
- `~/.config/blankweave/interface.lua` — generated sizing defaults; writer: interface-settings.py; do not hand edit.
- `~/.config/blankweave/accessibility.lua` — generated animations; writer: accessibility-settings.py; do not hand edit.
- `~/.config/blankweave/system-bell.json` — desktop bell preference; writer: system_bell.py; hand editing supported with its schema.
- `~/.config/blankweave/system-bell.lua` — generated bell rules; writer: system_bell.py; do not hand edit.
- `~/.config/blankweave/overrides/` — personal Hyprland, Ghostty, Dunst and Zsh snippets; seeded by install.sh, then user-owned; hand editing supported.
- `~/.config/blankweave/wallpapers/` — personal wallpaper images; writer: user; add or remove images by hand.
- `~/.config/blankweave/themes/` — personal themes shadowing bundled IDs; writer: user; hand editing supported.
- `~/.config/blankweave/color-profiles/` — imported display ICC profiles; writer: display_color.py; manage through Settings.

Locks and transient Settings scratch files live in `$XDG_RUNTIME_DIR/blankweave/`
(private mode 0700), or `${XDG_STATE_HOME:-~/.local/state}/blankweave/locks/`
without a session runtime directory. Saved ledgers, job records, revisions,
and recovery snapshots remain in their persistent state locations.

## Uninstalling

Run `blankweave uninstall` to preview the footprint. `blankweave uninstall --apply`
requires terminal confirmation, or `--yes` without a terminal. Packages are
listed by manifest and never removed. The root-owned before/after ledger in
`/var/lib/blankweave/uninstall/` records installer changes: unchanged deployed
files can be removed, and recorded originals restored. Modified files, unknown
ownership, recovery state/cache and the managed checkout are retained and reported.
An older installation without a ledger is preview-only until changes can be
recorded; reapplying cannot reconstruct its original state.

Personal preferences, overrides, themes and wallpapers under
`~/.config/blankweave/` stay unless `--purge-config` is given. Review that option
carefully. Running shared services, installed packages, keyrings, login shell, groups,
GPU capabilities and boot loader configuration require manual review; only
recorded added styling tokens are removed from boot entries. The
uninstaller does not remove Limine or change firmware boot order. Set up a
display manager or another session before rebooting: automatic sign-in is going
away. Review retained items and test removal in a VM before relying on it.

## Engineering reference

See [RELEASES.md](RELEASES.md) for annotated-tag release policy and
[CLAUDE.md](CLAUDE.md) for the architecture and deployment contract.
Optional profiles are desktop, development, communication, gaming and
voice-dictation. Core and detected hardware packages are mandatory. Profiles
are additive and install.conf is parsed as data. Defaults are desktop,
development and communication, plus gaming on gaming-capable battery-free
hardware. Local source applies use the internal `install.sh` engine.

### Profiles, voice and application indicators

Profiles are selected in guided setup or the space-separated profiles= line in
`~/.config/blankweave/install.conf`; use `blankweave update --reapply` after
changing them. desktop adds browsers and personal utilities; development adds
editors, containers and coding tools; communication adds messaging/local sharing;
gaming adds Steam/Proton and compatible 32-bit graphics; voice-dictation adds
local VoxType, wtype, accessibility bindings and a verified small.en model.
The model lives under `~/.local/share/voxtype/models/`. Voice audio and
transcripts stay local. Non-editable targets use clipboard fallback; the latest
transcript is retained in `~/.local/state/blankweave/voxtype-last-transcript.json`.
The voice panel exposes status and recovery; F12 is reserved for push-to-talk
while the profile is enabled; it replaces the focused application F12 binding
(including browser DevTools). Optional package failures do not bypass checksums
or signatures and do not stop other optional applications from being attempted.

The coding agent indicator appears for locally installed, signed-in Codex or
Claude Code. Provider allowance checks use their local interfaces, cache for five
minutes and mark old readings stale; refresh has a 15-second minimum interval.
A fresh remaining allowance at 20% or below is highlighted. Cache contains quota
fields and hashed account identity, never prompts, credentials or project paths.
API-key subscriptions and incompatible CLI interfaces are reported unavailable.
The bar has no system tray and no manual idle-inhibitor control.

### Boot and deployment reference

Limine becomes Blankweave Boot Manager only after staging succeeds. Its menu is
shown for three seconds on Linux-only systems and five when another operating
system is detected. Other systems use their existing firmware entries; their
partitions are not mounted or copied. Firmware USB handoff is offered when a
matching firmware record exists, which does not prove a USB drive is inserted.
The systemd-boot recovery entry and Linux Boot Manager remain available.
Plymouth owns the disk passphrase prompt; press Esc for text if graphics hide it.

The hardware inventory contains model/specification fields but excludes serial
numbers and machine UUIDs. Quickshell reads the cached inventory without root.
Configuration changes are capability-based, without machine-name branches.
User config entry points link to deployed defaults; edited files and foreign
symlinks are preserved. Application-rewritten settings such as Thunar actions
are seeded as regular files. Quickshell and shell helpers deploy by atomic tree
exchange so a running watcher does not see a missing tree.

## Settings application

Open **Blankweave Settings** from the application launcher, press `Super + ,`,
click the settings icon in the system overview panel, or run:

```bash
blankweave settings
```

The searchable settings window covers Appearance, Displays, Sound, Network &
Bluetooth, Power, Input & Accessibility, Apps, Storage & Backup, and System.
Press `Ctrl+F` to search individual settings. Results show their category and
section; select a result to jump to its controls with a temporary highlight.
Use Up/Down and Enter to navigate results, or Escape to clear the search.
Common terms such as “time zone”, “screen reader”, and “uninstall” are supported.

Appearance's theme, dark/light mode, bar position, and bar visibility controls
are connected to the existing desktop configuration and apply immediately.
Changes made from the bar remain reflected in Settings. When folder colors or
boot appearance are pending, choose **Apply system appearance…** to authenticate
through the desktop and follow progress in the window. Cancelling leaves the
changes pending; failures can be retried. Settings checks the installed state
before confirming completion. This action becomes available after the installer
deploys its system helper; `blankweave theme sync` remains available in a terminal.

Displays lists connected monitors and lets you choose a supported scale or
Automatic for each one. It shows the active scale and display resolution,
keeps changes made from the bar in sync, and saves choices through the existing
monitor configuration. A saved choice that differs from the active scale is
reported separately, including after a failed apply.
XWayland windows are left unscaled so they stay sharp and games see the
display's native resolution. Steam is the one X11 application whose interface
does not follow the display scale: set it once under Steam's Settings >
Accessibility > UI scale. Games keep rendering while another workspace is on
screen, so loading or running a game and switching away no longer stalls it.
With multiple displays connected, select an external display and choose its
saved position: left, right, above, below, or Automatic around the existing
desktop layout. Position changes preserve its scaling preference and follow
the display across reconnects. The position menu shows the saved choice;
current desktop coordinates are shown separately.
Brightness adjusts the selected display from 5–100% using the built-in backlight
or DDC/CI on supported external monitors. The slider follows hardware readings,
including changes from the bar, and rechecks the level after applying a change.
Unavailable controls explain how to retry; external monitors may need DDC/CI
enabled in their own menu. Brightness changes use the existing hardware controls
and do not add a saved login-time override.

Sound provides live output selection, volume (0–150%), and mute. It shares
PipeWire state with the bar and follows changes from media keys or other mixers.
The selector shows the output actually in use; a preferred device that has not
become active is reported separately. Device removal cancels an in-progress
volume drag so it cannot change a different output.

Microphone controls select the default input, adjust gain (0–150%), and mute or
unmute it. The live signal meter runs only while the microphone controls are
shown in Settings, and stops when muted, minimized, closed, or on another page.
It measures the signal before software gain; it does not save audio. Input
selection and gain follow the same hotplug safeguards as output controls.
Local voice dictation shows VoxType's current status, model, microphone, and
backend. Record from Settings to copy the result to the clipboard, stop and
transcribe, cancel, or recover the latest transcript. Start/restart is available
only while stopped or confirmed idle. The bar shares these command guards, and
Settings waits for observed status before accepting a change. The existing
shortcuts still dictate into the focused application. Enable the optional
Voice dictation profile through Blankweave setup if it is not installed.
Model, device, and shortcut configuration continues through the existing
VoxType and Hyprland configuration; this panel does not rewrite those files.

Per-app mixing is available through Pavucontrol from the bar. System sounds
controls event sounds, input feedback, and installed sound themes for supporting
apps, with a quiet preview button. Preferences use the desktop settings store;
**Apply to apps** synchronizes the GTK fallback files when needed. Reopen apps
that do not pick up changes. Visual theme switches preserve sound preferences
and unrelated GTK settings. Notification and dictation sounds remain separate.

The separate **System bell** control manages Hyprland's Wayland bell. It keeps
the compositor's default behavior until you save a choice, then persists it
across sessions. It does not play a test sound or change GTK event sounds.
Personal compositor overrides are preserved and must be resolved before Settings
can change the bell; unavailable compositor capabilities are explained in place.

**Network & Bluetooth → Wi-Fi** shows live nearby networks, radio state, and
connection progress. Connect to open or personal-password networks, reuse saved
connections, or disconnect. Saved profiles include networks that are out of
range; forgetting one requires confirmation and is disabled while it is active.
New enterprise/certificate and hidden-network setup remains in a NetworkManager
connection editor. The bar and Settings share Wi-Fi state and scan ownership;
scanning stops when the last requesting view closes.

**Bluetooth devices** discovers nearby accessories, pairs and connects them,
shows connection and battery state, and disconnects or forgets saved devices.
Pairing supports confirmation codes, PIN entry, and codes to type on a keyboard;
closing the initiating view cancels an unfinished pairing request. The bar and
Settings share discovery and actions, and report command failures. Bluetooth
audio connections select the matching sound output.

**Ethernet & DNS** shows cable and connection state, available wired profiles,
and link speed. Connect an existing profile, create an automatic DHCP connection
when no profile exists, or disconnect. Select an active Ethernet or Wi-Fi
connection to inspect IPv4/IPv6 addresses, gateways, and DNS servers. DNS supports
automatic network settings, provider presets, and custom addresses. Changes are
saved to that profile and applied live without reconnecting; a failed live update
is reported explicitly. The bar shares the same DNS backend.

**Airplane mode** blocks wireless radios while keeping Ethernet available. Turning
it off restores the previous radio blocks and Bluetooth power state. Hardware
blocks and radios re-enabled elsewhere are shown explicitly.

**Wi-Fi hotspot** creates a temporary WPA2 network on an AP-capable adapter.
Choose the adapter, name, and password; replacing an active Wi-Fi connection
requires confirmation. Internet sharing needs Ethernet or another upstream
adapter, plus the required `dnsmasq` and `nftables` packages. Hotspots do not
autoconnect, disappear after disconnect/reboot, and keep their password out of
process arguments and disk. Stop the hotspot from Settings and reconnect a saved
Wi-Fi network when finished. VPN controls import OpenVPN/WireGuard profiles and
manage saved connections. Tailscale sign-in opens its browser authorization
flow. File sharing configures authenticated, read-only Samba usershares; nearby
transfers open LocalSend with recipient consent.

The remaining system controls have native operation forms with observed status,
explicit confirmation, stale-selection checks, and local job reports. Long
operations continue when Settings closes. Missing packages and unsupported
hardware are reported without fabricated state. The `desktop` profile installs
optional providers for storage, printing, scanning, firmware, backups, VPNs,
Flatpak, and assistive tools; the `communication` profile supplies LocalSend.
Services such as Samba and CUPS are enabled by explicit setup actions.

While Settings is open, a task bar tracks running operations across categories
and keeps their outcomes available until dismissed or the shell restarts. It also
finds jobs that were already running when the shell started. Reports show status
and elapsed time when timestamps are available, with expandable details and an
explicit **Copy report** action. Dismissing a report hides it for this shell
session without deleting the saved report. Progress percentages are not estimated.

Operation forms retain non-secret drafts while you navigate Settings or close
and reopen its window in the same shell session. Failed or cancelled operations
keep those inputs for review and retry; successful jobs clear their forms.
Passwords are cleared after submission and when leaving a page. Drafts are never
saved to disk and do not survive a shell restart. If the available settings or
target changes, review the current action before submitting again.

Backup retention uses a themed number field with step buttons and Up/Down keys,
inline range validation, and a 1–365 limit. Simple on/off operation preferences
use switches; changes remain in the draft until applied. Invalid numbers stay
visible for correction and cannot be submitted. Descriptive mode choices remain
menus, including Suspend versus Hibernate.

Each operation section exposes its primary task directly, with secondary tasks
under **More actions**. An ellipsis indicates that input or review comes next.
Supported read-only tasks can run immediately, including drive health when only
one drive is available; multiple targets still open a chooser. Destructive and
system-changing actions retain their review step.

Unavailable controls distinguish missing software, disconnected devices,
incomplete setup, unsupported configurations, and services that cannot be read.
Each explanation includes a next step. Restore and unsupported system snapshots
link to file-backup setup; empty Flatpak permission controls link to installed
applications. These links only navigate Settings and never install software or
change system configuration automatically.

Storage supports directory scans, thumbnail-cache cleanup, removable-drive
mount/unlock/eject, and SMART health/self-tests. Backups use encrypted restic
repositories on local storage or SSH/SFTP, with passwords in Secret Service,
exclusions, retention, and persistent daily/weekly user timers. Timers require
an active user manager and an unlocked keyring. Restore always creates a new
folder and verifies restored data; an interrupted restore retains its partial
folder. Snapper supports existing root configurations and setup on Btrfs roots
without an existing `/.snapshots` layout. Full-system recovery still requires a
separately validated rescue environment; Settings does not roll back a mounted
root filesystem or create a Limine snapshot-boot integration.

Apps provides package inventory/search, reviewed repository installation/removal,
optional user Flatpak operations, and supported Flatpak permission controls.
Foreign/AUR packages are identified, but building AUR packages remains the AUR
helper's responsibility. Native applications have no universal camera,
microphone, or file permission switch. Blankweave and full system upgrades use
the existing interactive updater/pacman transaction for review and authorization;
opening that terminal is not reported as a successful update. Firmware uses
fwupd and reports unsupported devices and reboot requirements.

Users and sign-in manages local accounts and persists the tty1 password-required
or automatic-login preference across installer runs. Date/time changes are
system-wide. Printer setup supports IPP Everywhere devices; scanner discovery
and PNG capture use SANE. Assistive tools use managed user services for Orca and
wvkbd, plus persistent compositor magnification. Their shortcuts are editable in
Keyboard shortcuts (defaults: `Super+Ctrl+R`, `Super+Ctrl+K`, and `Super+Ctrl+M`
for the screen reader, keyboard, and magnification reset).

Hibernation shows kernel, swap, and logind readiness. Resume preparation supports
an **existing encrypted swap partition** large enough for memory, persistently
unlocked with a passphrase through `crypttab.initramfs`, systemd/sd-encrypt
initramfs hooks, and regular non-UKI BLS entries imported by Limine. It saves the
original command lines, rebuilds initramfs images, and refreshes Limine. Other
layouts require manual preparation; Settings never repartitions disks or creates
swap files. Revert refuses to overwrite later boot-file edits. Reboot and test
resume on the actual hardware before relying on it. The power menu offers
hibernation when supported, and managed idle sleep can use it with a suspend
fallback. Existing lock-before-sleep behavior remains in place.

Use `Ctrl+F` to search, Tab to move between controls, and arrow keys plus Enter
to navigate the category list. Escape clears a search or closes the window;
`Ctrl+W` closes it directly.

## Theme reference

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
command line finishes with a sudo prompt. After a switch from the bar, open
Settings → Appearance and choose **Apply system appearance…**, or run
`blankweave theme sync` in a terminal.

Three themes are bundled: `obsidian` (Obsidian dark / Porcelain light, blue),
`moss` (Moss dark / Sage light, green), and `aurora` (violet, sky, and rose
gradients in dark and light modes). To make your own, copy
`defaults/themes/obsidian/` to `~/.config/blankweave/themes/<id>/`, edit
`theme.json`, and run `blankweave theme set <id>`; a personal theme with the same
id as a bundled one takes precedence.

Themes can override shared spacing, shapes, typography, transition timing, and
gradient materials through a partial `design` object. Unspecified values inherit
the existing defaults; navigation and behavior stay shared. See
[the design token reference](docs/theme-design.md) for the schema, precedence,
validation, and toolkit boundaries. Aurora is opt-in with `blankweave theme set
aurora`; updates preserve the active theme.

The Hyprtoolkit screen-sharing picker follows the selected palette, text size,
and high-contrast preference through `~/.config/hypr/hyprtoolkit.conf`. Blankweave
updates this regular file only while its generated content checksum matches.
Editing it takes ownership; existing personal files and symlinks are preserved,
and Settings reports that the picker uses personal configuration. Reopen the
picker after changing appearance if it does not refresh immediately.

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

## Configuration reference

Put personal settings in `~/.config/blankweave/overrides/`. Setup creates
commented starter files only when they are missing; updates and theme switches
never replace them. You can also symlink these files to your own dotfiles repo.

| File | Precedence | Apply edits |
| --- | --- | --- |
| `hyprland.lua` | After theme, hardware, monitor arrangement, and optional voice bindings | `hyprctl reload` |
| `ghostty.conf` | After the themed terminal defaults | Ghostty's Reload Configuration action |
| `dunst.conf` | A native `dunstrc.d/99-blankweave-user.conf` snippet, after the base config | `dunstctl reload` |
| `zsh.zsh` | After shell defaults, before the legacy custom section in `.zshrc` | Open a new terminal |

For example, in `overrides/hyprland.lua`:

```lua
hl.config({ general = { gaps_in = 4, gaps_out = 8 } })
```

Or in `overrides/ghostty.conf`:

```ini
font-size = 13
```

Hyprland override errors are reported by the compositor and by
`blankweave doctor`; they are not silently ignored. Dunst snippets use its normal
filename ordering, so another snippet sorted after `99-blankweave-user.conf`
can override the same settings. Ghostty uses its native
[additional config files](https://ghostty.org/docs/config); Dunst uses its native
[config snippets](https://dunst-project.org/documentation/dunst/).

For full control, replace an application's managed symlink with your own file
or symlink. The installer preserves existing user configs for Hyprland,
Hypridle, Hyprlock, Ghostty, Dunst, Fontconfig, portals, and VoxType. During
upgrade, only byte-identical legacy generated Hyprland configs are adopted as
managed symlinks. Edited files stay active. A fully custom `.zshrc` is also
preserved; the old marked custom section continues to survive managed updates.

Full replacements own their configuration loading. If you already customized
`~/.config/hypr/hyprland.lua`, append this line to opt into the new override file:

```lua
require(os.getenv("HOME") .. "/.local/share/blankweave/hypr/user-overrides")
```

For a custom Ghostty config, add
`config-file = ?~/.config/blankweave/overrides/ghostty.conf`; for a custom
`.zshrc`, source `~/.config/blankweave/overrides/zsh.zsh` yourself.

Files under `~/.local/share/blankweave/` remain managed and are replaced on
update, including the Quickshell source. Keep personal themes and wallpapers
in their documented `~/.config/blankweave/` directories. Theme state, display
panel state, and GTK theme settings remain generated files, not override files.

### Idle timeouts

Settings → Power provides separate dim, lock, screen-off, and suspend delays for
plugged-in and battery use. Preferences live in
`~/.config/blankweave/idle.json` and survive updates. Until the first edit, the
installed Hypridle policy remains unchanged. “Never” disables only that action;
manual locking and lock-before-sleep remain available. Short screen-off or sleep
delays move enabled lock and dim timers earlier. Set all four actions to Never
to keep the session awake without a custom Hypridle override.
Lid behavior remains controlled by the system.

The session starts `idle-policy.sh`, which supervises its own Hypridle child.
Saved edits and power-source changes restart the idle timers; they continue to
work while Settings is closed. Settings distinguishes saved preferences awaiting
application from an active policy. After upgrading an existing session, sign out
and back in to start the new supervisor.

A custom `~/.config/hypr/hypridle.conf` file or foreign symlink takes precedence.
Settings explains this and disables its idle controls without modifying that
file. To opt back into managed behavior, back up your custom configuration and
restore the symlink to `~/.local/share/blankweave/hypr/hypridle.conf`, then sign
out and back in.

### Mouse and touchpad

Settings → Input & Accessibility provides pointer speed, acceleration, natural
scrolling, left-handed buttons, tap-to-click, and disable-while-typing controls.
Choose Pointer defaults, Touchpad defaults, or a connected device. Defaults show
live compositor values; per-device rows show saved Blankweave overrides, because
Hyprland does not expose every effective per-device option. Personal Hyprland
overrides still load last and may supersede saved device choices.

Preferences are stored in `~/.config/blankweave/pointer.json`; the helper renders
`pointer.lua` alongside it and reloads the compositor configuration. Reset removes
only the selected Blankweave override. Saved device settings follow the device
name across reconnects; ambiguous names are read-only. Changes capture both the
name and current device identity, so unplugging or replacing a device does not
silently apply an edit to another pointer. Configuration failures restore previous
files and attempt to restore the running configuration.

Keep handwritten settings in `overrides/hyprland.lua` rather than editing the
generated files. A custom compositor configuration must load Blankweave's
`hypr/input.lua` before its personal overrides to use these controls.

### More native Settings controls

- **Notifications:** Settings → Apps controls manual Do Not Disturb, daily quiet
  hours, and popup muting for apps seen in notification history. Quiet hours use
  local time, can cross midnight, and continue while Settings is closed. Manual
  pause/resume changes, including external Dunst controls, override the current
  quiet-hours window. Scheduling resumes at the next window; ending a window
  only releases a pause created by that schedule. Muted popups remain in history.
  The bar toggles the actual Dunst pause state.
- **Startup applications:** Enable or disable existing XDG autostart entries for
  the next sign-in. System entries use reversible user overrides; personal
  desktop restrictions and commands are preserved. Core desktop services are
  managed separately.
- **Wallpaper:** Settings → Appearance selects PNG, JPEG, or WebP images and
  fill, fit, stretch, or center modes per display. Custom choices survive theme
  changes and reconnects. Use theme wallpaper removes that display's override.
  The lock screen retains the shared theme/cycle wallpaper.
- **Bar widgets:** Show, hide, and reorder widgets within the left, center, and
  right sections. The right side retains separate application, device-control,
  and system-meter groups; reordering stays within those groups. Preferences
  apply across displays. System and power menus stay
  available; Restore default widgets resets visibility and order.
- **Web apps:** Settings → Apps creates named HTTP(S) apps through Helium and
  removes user-created entries after confirmation. Browser logins/data are kept.
  Bundled apps remain managed by installation updates.
- **System:** View hardware/software details and run read-only health checks.
  Diagnostics uses `blankweave doctor --normal --report`, without elevation, and
  retains the last report locally for viewing or copying. Protected checks can
  be skipped; this does not perform repairs or updates.

These preferences survive updates. Notifications use `notifications.json` and
one Dunst drop-in; wallpapers use `wallpapers.json`; bar widgets use `shell.json`
under `~/.config/blankweave`. Startup overrides live in `~/.config/autostart` and
web-app entries in `~/.local/share/applications`. Diagnostics reports are stored
privately under `~/.local/state/blankweave`.

Install and update select the highest stable SemVer annotated `vX.Y.Z` tag
reachable from `origin/main` whose commit's `VERSION` matches. Unreleased main
commits, lightweight tags, mismatched tags, and off-main tags are ignored.
The managed `main` branch stops exactly at that release. `update --check`
notes when main has unreleased commits. `update --to vX.Y.Z` selects a specific
newer release under the same ancestry and rollback-floor rules; it supports
`--check`, `--dry-run`, and `--yes`, but cannot combine with `--reapply`.
Downgrades use `blankweave rollback`.
