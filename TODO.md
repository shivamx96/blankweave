# TODOs

- [x] Tailscale setup for current user while installing
- [ ] Set up Wispr Flow — no official Linux client as of Jul 2026 (vote/waitlist only).
      Unofficial port: AUR `wispr-flow-appimage`. Needs `input` group + uinput udev rule.
      Note: Fn-hold as push-to-talk is impossible — this Ideapad's keyboard firmware
      never emits `KEY_FN` to the OS. Pick a real key (Right Alt / Super+Space).

## Bugs

- [ ] `nvtop` is referenced by the Quickshell GPU module (`on-click`) but only
      listed in `hosts/pc/packages.txt` — clicking the module does nothing on laptop.
      Either move to `base.txt` or make the click host-aware (`intel_gpu_top` on laptop).
- [ ] Audit for other `defaults/` configs referencing host-only packages — this is the
      same root cause that made `hyprsunset` fail silently on laptop.

## Installer UX

- [ ] Add `hyprarch setup`, a guided terminal flow for first-install preferences.
      Keep `bootstrap.sh` focused on acquiring the managed checkout and handing
      off to the CLI.
- [x] Define required core/hardware manifests plus optional `desktop`,
      `development`, `communication`, and `gaming` profiles.
- [x] Add a versioned, non-executable installer config parser with strict key and
      profile validation and compatibility defaults for existing machines.
- [ ] Offer optional Git identity (`user.name` and `user.email`), GitHub SSH-key
      generation, and a clear skip path. Never collect credentials or upload keys.
- [ ] Save non-secret choices in an inspectable user config so `hyprarch update`
      can converge without asking the setup questions again.
- [ ] Add a final review before package or system changes, plus a non-interactive
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
- [ ] No media keys — `XF86AudioPlay/Next/Prev` via playerctl.
- [ ] `Super+M` = `exit` with no confirmation, one key from `Super+N`. Remove it or route
      it through `power-menu.sh`.
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

- [ ] `playerctl` is installed here but in no package list — a fresh install won't have it.
- [x] `gnome-keyring` — Secret Service daemon behind `libsecret`; unlocked by the
      `hyprarch-lock` PAM service hyprlock authenticates against.
- [ ] `man-db` — no man pages currently.
- [ ] `ripgrep`, `fd` — fills the gap next to existing fzf/zoxide/lazygit.
- [ ] `pacman-contrib` — `checkupdates`, `paccache` for cache cleanup.
- [ ] `hyprpicker` — colour picker.
- [ ] `qt6ct` — Qt apps are unstyled while GTK gets themed on toggle, despite
      `QT_QPA_PLATFORM` being set. Would need wiring into `theme-toggle.sh`.
- [x] `power-profiles-daemon` for laptop battery.
- [ ] `hyprpolkitagent` — native replacement for the `polkit-gnome` we autostart.

## Brightness

- [x] Replaced gamma-faked external brightness with real DDC/CI control. The brightness
      helper maps each DRM connector to its dynamically assigned I²C bus, while internal
      panels continue to use the kernel backlight API.

## Misc

- [ ] `windowrules.lua` still has its "convert these to floating windows" TODO unresolved.
- [ ] No firewall (`ufw`).
- [ ] No snapshots/backups (`snapper` + `snap-pac`, or `timeshift`).
