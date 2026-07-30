# TODOs

- [x] Tailscale setup for current user while installing
- [ ] Set up Wispr Flow — no official Linux client as of Jul 2026 (vote/waitlist only).
      Unofficial port: AUR `wispr-flow-appimage`. Needs `input` group + uinput udev rule.
      Note: Fn-hold as push-to-talk is impossible — this Ideapad's keyboard firmware
      never emits `KEY_FN` to the OS. Pick a real key (Right Alt / Super+Space).

## Bugs

- [ ] `nvtop` is referenced by `defaults/waybar/config` (GPU module `on-click`) but only
      listed in `hosts/pc/packages.txt` — clicking the module does nothing on laptop.
      Either move to `base.txt` or make the click host-aware (`intel_gpu_top` on laptop).
- [ ] `install.sh` has no trailing newline on its last line.
- [ ] Audit for other `defaults/` configs referencing host-only packages — this is the
      same root cause that made `hyprsunset` fail silently on laptop.

## Hyprland: Lua config migration

Hyprland 0.55+ deprecated hyprlang (`.conf`) in favour of Lua. We're on 0.56.1 and the
log confirms we're on the fallback path: `[cfg] Lua config not found, using legacy config`.

- [ ] Decide whether to migrate `defaults/hypr/*.conf` → `hyprland.lua`.
      Legacy `.conf` still parses and `hyprctl configerrors` is clean, so this is not
      urgent — but new features (user-defined layouts) are Lua-only.
      Reference: `/usr/share/hypr/hyprland.lua`, stubs at `/usr/share/hypr/stubs/hl.meta.lua`
- [ ] If migrating, the `.conf`-per-concern split maps to Lua `require()` modules, so the
      defaults/hosts layout survives intact.
- [ ] `windowrulev2` is now hard-deprecated. We already use the new `match:` form —
      keep it that way. Note effects need explicit values now (`float true`, not `float`).

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

## Waybar

- [ ] No `tray` module — Slack, LocalSend and Blueman all expect one. Slack's
      close-to-tray is effectively broken without it.
- [ ] No `idle_inhibitor` module. hypridle dims at 150s and locks at 300s, which fires
      mid-video. Built into Waybar, no script needed.
- [ ] Autostart `blueman-applet` once the tray exists.

## Screenshots & capture

- [ ] Screenshots are clipboard-only (`grim - | wl-copy`) — no file kept, no feedback.
      Save to `~/Pictures/Screenshots` with a timestamp, copy *and* notify.
- [ ] Add `satty` (or `swappy`) for annotation.
- [ ] Add screen recording (`wl-screenrec` or `wf-recorder`).

## Packages

- [ ] `playerctl` is installed here but in no package list — a fresh install won't have it.
- [ ] `gnome-keyring` — no secret store daemon; Slack and Bruno will nag. (`libsecret`
      is present but has nothing behind it.)
- [ ] `man-db` — no man pages currently.
- [ ] `ripgrep`, `fd` — fills the gap next to existing fzf/zoxide/lazygit.
- [ ] `pacman-contrib` — `checkupdates`, `paccache` for cache cleanup.
- [ ] `hyprpicker` — colour picker.
- [ ] `qt6ct` — Qt apps are unstyled while GTK gets themed on toggle, despite
      `QT_QPA_PLATFORM` being set. Would need wiring into `theme-toggle.sh`.
- [ ] `power-profiles-daemon` for laptop battery.
- [ ] `hyprpolkitagent` — native replacement for the `polkit-gnome` we autostart.

## Brightness

- [ ] hyprsunset removed (2026-07-31) — it was gamma-faking brightness and was never
      installed on laptop anyway. External monitors now have **no** brightness backend;
      `brightness.sh` reports `none` and the Waybar module hides itself.
- [ ] Add a `ddcutil` backend for external monitors (real DDC/CI backlight control, not
      gamma). Needs the `i2c-dev` module and `i2c` group. This was the original intent —
      `brightness-module.sh`'s header comment already claims ddcutil support.

## Misc

- [ ] `windowrules.conf` still has its "convert these to floating windows" TODO unresolved.
- [ ] No firewall (`ufw`).
- [ ] No snapshots/backups (`snapper` + `snap-pac`, or `timeshift`).
