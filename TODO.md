# TODOs

- [x] Tailscale setup for current user while installing
- [ ] Set up Wispr Flow — no official Linux client as of Jul 2026 (vote/waitlist only).
      Unofficial port: AUR `wispr-flow-appimage`. Needs `input` group + uinput udev rule.
      Note: Fn-hold as push-to-talk is impossible — this Ideapad's keyboard firmware
      never emits `KEY_FN` to the OS. Pick a real key (Right Alt / Super+Space).

## Bugs

- [x] Resolve GPU monitoring tools from detected GPU capabilities; Intel systems
      receive both `intel_gpu_top` and `nvtop`, while AMD/NVIDIA receive `nvtop`.
- [x] Audit core widget commands against required/capability manifests.

## Installer UX

- [x] Establish SemVer releases with matching annotated Git tags and an explicit
      `0.1.0` minimum rollback boundary.
- [x] Add `blankweave doctor` with read-only health checks and a sanitized,
      shareable support report.
- [x] Add update check/dry-run modes, last-known-good revision state, installer
      logs, postflight health validation, optional Snapper integration, and
      configuration rollback without claiming to downgrade Arch packages.
- [x] Establish SemVer releases, revision/version-paired recovery metadata, and
      an explicit `0.1.0` minimum rollback boundary.
- [x] Add `blankweave setup`, a guided terminal flow for first-install preferences.
      Keep `bootstrap.sh` focused on acquiring the managed checkout and handing
      off to the CLI.
- [x] Define required core/hardware manifests plus optional `desktop`,
      `development`, `communication`, and `gaming` profiles.
- [x] Add a versioned, non-executable installer config parser with strict key and
      profile validation and compatibility defaults for existing machines.
- [x] Offer optional Git identity (`user.name` and `user.email`), GitHub SSH-key
      generation, and a clear skip path. Never collect credentials or upload keys.
- [x] Save non-secret choices in an inspectable user config so `blankweave update`
      can converge without asking the setup questions again.
- [x] Add a final review before package or system changes, plus a non-interactive
      mode that consumes an existing config for repeatable installs.

## Hyprland: Lua config migration

Hyprland 0.55+ deprecated Hyprlang (`.conf`) in favour of Lua.

- [x] Migrated the Hyprland compositor config to `hyprland.lua` and Lua modules.
      Hyprlock and Hypridle stay in Hyprlang, as required by those tools.
- [x] Preserved the per-concern defaults and per-host overrides with Lua `require()`.
- [x] Replaced the legacy window-rule form with `hl.window_rule()` definitions.

## Keybinds

- [ ] No fullscreen bind at all. `Super+F` is taken by Thunar — consider moving Thunar to
      `Super+E` and freeing `Super+F`.
- [ ] No mouse move/resize: `bindm = $mainMod, mouse:272, movewindow` and
      `mouse:273, resizewindow`. Biggest single ergonomic win on a dwindle layout.
- [ ] No keyboard window resizing (`resizeactive`).
- [x] Media play/pause/next/previous keys are wired through `playerctl`.
- [ ] `Super+M` = `exit` with no confirmation, one key from `Super+N`. Remove it or route
      it through the bar's power control, which already confirms logout.
- [ ] Special workspace / scratchpad (`Super+grave`) for a floating terminal.
- [ ] Notification history: `dunstctl history-pop` and `dunstctl close-all`.

## Quickshell bar

- [x] ~~Add a `tray` module~~ — **declined 2026-07-31, deliberate.** A tray is an
      attention surface; this rice is meant to be minimal and distraction-free.
      Consequence, accepted: apps that expect a tray have nowhere to go. Slack's
      "close to tray" (`runFromTray: true` in its own config) can't work — closing
      the window quits it. Use `Super+Shift+B` for Blueman instead of an applet.
      Don't re-suggest this.
- [x] ~~Add an idle-inhibitor module~~ — **declined 2026-08-28.** Keep the shell
      free of an explicit inhibitor control.
- [x] Replaced Waybar with a native Quickshell bar, removing the minimum-height warning.

## Screenshots & capture

- [ ] Screenshots are clipboard-only (`grim - | wl-copy`) — no file kept, no feedback.
      Save to `~/Pictures/Screenshots` with a timestamp, copy *and* notify.
- [ ] Add `satty` (or `swappy`) for annotation.
- [ ] Add screen recording (`wl-screenrec` or `wf-recorder`).

## Packages

- [x] `playerctl` is a required package and media keys control the active player.
- [x] `gnome-keyring` — Secret Service daemon behind `libsecret`; fresh installs
      provision a passwordless default collection protected at rest by LUKS.
- [ ] `man-db` — no man pages currently.
- [ ] `ripgrep`, `fd` — fills the gap next to existing fzf/zoxide/lazygit.
- [ ] `pacman-contrib` — `checkupdates`, `paccache` for cache cleanup.
- [ ] `hyprpicker` — colour picker.
- [ ] `qt6ct` — Qt apps are unstyled while GTK gets themed on toggle, despite
      `QT_QPA_PLATFORM` being set. Would need wiring into `theme-apply.sh`.
- [x] `power-profiles-daemon` for laptop battery.
- [ ] `hyprpolkitagent` — native replacement for the `polkit-gnome` we autostart.

## Brightness

- [x] Replaced gamma-faked external brightness with real DDC/CI control. The brightness
      helper maps each DRM connector to its dynamically assigned I²C bus, while internal
      panels continue to use the kernel backlight API.

## Misc

- [ ] `windowrules.lua` still has its "convert these to floating windows" TODO unresolved.
- [ ] No firewall (`ufw`).
- [ ] Provision and recovery-test Snapper on fresh Btrfs installations.
      `blankweave update` already uses an existing root Snapper configuration,
      but Blankweave does not create one or automate full-system rollback yet.
