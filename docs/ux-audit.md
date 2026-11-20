# Blankweave UX audit

Baseline: `main` at `ce7eabe` (0.12.0), audited 2026-11-12 on the live machine
(single 2880×1800 laptop panel, Aurora light, bar at top, profiles desktop +
development + communication + voice-dictation).

Bar: macOS-level refinement (things work, are discoverable, give feedback, never
strand you) and Linux openness (inspectable, overridable, no lock-in).

## How this was produced

Seven independent read-only audits (onboarding and CLI, bar, Settings, window
management, launcher/notifications/lock/session, whole-OS completeness, visual
system), then two adversarial passes: a product skeptic arguing each finding
down, and a falsifier that tried to disprove every claim that had only been
inferred from code. The falsifier refuted none of 25 claims, corrected the
mechanism of five, and settled several by experiment (isolated Quickshell,
offscreen QML test, scratch fontconfig, upstream source at the installed
version). The skeptic's cuts are recorded in "Decided against".

Evidence tags: **[V]** verified by reading or running, **[X]** verified by
experiment, **[I]** inferred and still needs a hands-on check.
Effort: **S** under half a day, **M** one to two days, **L** more.

Nothing on the machine or in the repo was changed apart from this file.

## The short version

The engineering underneath is unusually careful: single-writer config files,
readback before claiming state, identity-captured mutations, a read-only
doctor, EDID-keyed monitors. The gaps are almost all at the edges where that
care stops:

1. **A few keys and events destroy work with no warning** — the power key, 
   `Super+M`, an empty battery, a Delete in the file manager.
2. **Ordinary-day basics were never installed or wired** — Trash, thumbnails,
   a video player, the intended fonts, screenshots that save, notification
   clicks that open things.
3. **The same job is implemented two or three times with different rules** —
   volume by key, by scroll and by slider; on/off in four idioms; red meaning
   both "fault" and "you chose this".
4. **Light mode and Aurora are second-class** — every measured contrast
   failure is a light-mode or Aurora failure.
5. **The path a stranger walks is untested** — bootstrap re-run, non-LUKS
   disks, other boot loaders, first terminal launch.

Track A is ordered for a daily driver. Track B is the gate before pointing
anyone else at the bootstrap line.

---

## Track A — daily driver, in fix order

### Round 0 — before anything else

**A0. CLAUDE.md contradicts the code** · P1 · S · [V] · **DONE** (branch `ux/audit-fixes`)
It is the instruction set for whoever fixes the rest.
- Lines 618 and 1053 say `Super+D` flips the theme mode; `hypr/keybindings.lua:30`
  binds `SUPER + T`, and `Super+D` is dictation.
- It says fonts, geometry and animations are "deliberately not part of a
  theme"; `Theme.qml:163-164` reads `design.*` and Aurora overrides shape,
  spacing and motion.
- It lists two bundled themes; there are three.
- `WorkspacesWidget.qml:13` and CLAUDE.md say a bar omits workspaces "shown on
  another monitor"; the code (`:23-31`) omits any workspace that *lives* on
  another monitor, and ids above 10.

### Round 1 — stop losing work

**A1. The power key shuts the machine down instantly** · P0 · S · [V] · **DONE** (branch `ux/audit-fixes`)
`HandlePowerKey` is logind's default `poweroff`; nothing in `install.sh` or
`scripts/` writes logind policy. One brush of the key ends the session.
Fix: `install.sh` writes `/etc/systemd/logind.conf.d/50-blankweave.conf` with
`HandlePowerKey=ignore`, `HandlePowerKeyLongPress=poweroff`; bind `XF86PowerOff`
to open the power panel (needs A2's IPC method). Add a doctor check.

**A2. `Super+M` kills the session with no confirmation** · P0 · S–M · [V] · **DONE** (branch `ux/audit-fixes`)
`keybindings.lua:56` runs `uwsm stop`, one key from `Super+,` (Settings).
Under tty1 autologin it is not even a logout: the session restarts empty.
Fix: add a `power` method to the `IpcHandler` in `shell.qml:87-105` that opens
the focused bar's power panel; rebind the `logout` id to it on `Super+Escape`
and free `Super+M`. Label the panel action "Restart session" when autologin is
on. Keep the catalog id; `tests/shortcuts_settings_test.py` checks it.

**A3. A dying battery gives no warning** · P0 · M · [V] · **DONE** (branch `ux/audit-fixes`)
The only cue is a bar tint at 15% (`BatteryWidget.qml:83`), and the bar hides
in fullscreen. UPower acts at 2% with no hibernation prepared.
Fix: a watcher in the shell-owned `PowerService` posting at 20/10/5%, once per
discharge, on a native toast modelled on `VoxtypeTranscriptToast` so it shows
over fullscreen and through Do Not Disturb. The 5% toast offers Suspend.

**A4. Delete in the file manager is permanent; no thumbnails, no devices** · P0 · S · [X] · **DONE** (branch `ux/audit-fixes`)
`gvfs` is in no manifest. Thunar 4.20 without the `trash://` scheme routes
Delete to permanent delete (`thunar-action-manager.c:1614`);
`~/.local/share/Trash` has never existed on this machine. `tumbler` and
`ffmpegthumbnailer` are absent too, so image folders show generic icons and a
USB stick never appears.
Fix: `gvfs`, `gvfs-mtp`, `tumbler`, `ffmpegthumbnailer`, `webp-pixbuf-loader`
in `packages/base.txt`; move `udisks2` from the desktop profile to base;
`gvfs-smb` in `profiles/desktop.txt`. Seed Thunar's "Open Terminal Here" to
`ghostty --working-directory=%f` (it currently calls an exo helper that does
not exist).

**A5. Rollback upgrades every package; update applies without asking** · P1 · M · [V] · **DONE** (branch `ux/audit-fixes`)
Both go through `apply_repository` → `install.sh:170`
`pacman -Syu --noconfirm`. So the recovery command changes the whole OS and
needs the network, while its help says packages are untouched. Update moves
from the commit log straight to applying (`bin/blankweave:438-466`), can be
interrupted by an idle suspend or a click on Restart, and never says a reboot
is needed after a kernel change. The snapshot safety net is inert here: root
is ext4 with no Snapper.
Fix: skip the upgrade on rollback; before an update print what will change
(flagging kernel, mesa, Hyprland) and ask on a TTY, with `--yes` for scripts;
wrap the apply in `systemd-inhibit --what=shutdown:sleep:idle`; write a
"restart required" marker when `/usr/lib/modules/$(uname -r)` is gone and show
it in the power panel. `-Syu` itself is correct on Arch; keep it for update.

**A6. Re-applying the configuration reverts your theme** · P1 · S–M · [V] · **DONE** (branch `ux/audit-fixes`)
`blankweave update` returns "already up to date" when no release is pending
(`bin/blankweave:419-423`), yet doctor and the README tell people to run it to
repair or to pick up an `install.conf` edit. The only real re-apply is
`setup --non-interactive`, which exports the first-day theme
(`setup.sh:309-317` → `theme-apply.sh:413-418`). On this machine that would
flip Aurora back to Moss.
Fix: `blankweave update --reapply` (and name it in the up-to-date message);
setup passes a theme only when `theme.json` is absent or the user changed it in
that run.

**A7. A crashed lock screen strands the session** · P1 · S · [V] · **DONE** (branch `ux/audit-fixes`)
`misc:allow_session_lock_restore` is unset and nothing restarts Hyprlock; a
crash on dock hotplug or resume leaves Hyprland's "lock screen died" page and
a trip to tty2.
Fix: set the option; route `Super+L`, the power panel and Hypridle through
`loginctl lock-session`; enable `key_press_enables_dpms` and
`mouse_move_enables_dpms`.

**A8. A failed session start is a black screen with no words** · P1 · S · [V]/[I] · **DONE** (branch `ux/audit-fixes`)
`defaults/shell/profile:13-15` truncates the log, then `exec`s uwsm. tty1 has
no issue text and a hidden cursor. If Hyprland cannot start, getty logs in
again and retries indefinitely (`start-hyprland` restarts in safe mode, so
systemd's start limit likely never trips). The log holds only uwsm's preamble;
the real errors are in the user journal.
Fix: drop `exec`; keep the previous log as `.1`; on a failed or sub-10-second
session print a short card (show cursor, `journalctl --user -b`,
`blankweave doctor`, `blankweave rollback`, Ctrl+Alt+F2) and stop retrying.
Longer term, start the session from a shell-neutral place so it does not
depend on the login shell being zsh (see A38).

**A9. Account passwords are set from one masked field** · P1 · S · [V] · **DONE** (branch `ux/audit-fixes`)
`settings_session.py:28,31`: "Change password" and "Create local account" take
a single hidden field. A typo sets an unknown password that only surfaces at
the next `sudo` or lock.
Fix: a `confirm=True` field flag in `settings_operations.field()`, rendered as
a second field with a mismatch error. Reuse for the backup repository password.

### Round 2 — broken every day

**A10. The rice's fonts never reach GTK, browsers or Electron** · P1 · S · [X] · **DONE** (branch `ux/audit-fixes`)
The managed fontconfig file is linked as `conf.d/local.conf`
(`install.sh:397`); fontconfig only loads names starting with a digit, so
`fc-match sans-serif` is Noto Sans and `monospace` is Noto Sans Mono while the
shell uses Atkinson Hyperlegible Next and JetBrains Mono. Renaming alone fixes
monospace only: Atkinson needs `<alias binding="strong">`.
Fix: link as `50-blankweave.conf` with a migration removing the old link, use
strong binding, set GTK `font-name`/`monospace-font-name` through
`gtk_settings.py`, add `noto-fonts-cjk` to base (CJK is tofu today), and assert
`fc-match` in a test.

**A11. Bar colours no longer mean what CLAUDE.md says they mean** · P1 · S · [V] · **DONE** (branch `ux/audit-fixes`)
Critical red marks chosen states: `AudioWidget.qml:19` `attention: muted`,
also network-off and Tailscale-disconnected. Accent marks steady states:
`BatteryWidget.qml:84` `active: charging`, `BluetoothWidget.qml:123`
`active: connectedDevices.length > 0`. A muted speaker looks like a 5% battery.
Fix: `attention` only for faults; show mute/off/disconnected by glyph;
`active` only while the panel is open.

**A12. Bar widgets miss the screen edge; scroll is unsafe on a touchpad** · P1 · S · [V] · **DONE** (branch `ux/audit-fixes`)
- Widgets are 30 px in a 40 px bar and the `MouseArea` fills the frame
  (`WidgetFrame.qml:99-101`), so the top 5 px of the screen is dead: a throw to
  the edge misses everything.
- `WidgetFrame.qml:112` emits per wheel event with no accumulation, and
  `AudioWidget.qml:30` / `BrightnessWidget.qml:226` treat a zero delta as
  "down", so a sideways swipe lowers the volume.
- Scroll and the slider go to 150%; the keys cap at 100% in different steps.
Fix: extend the hit area to the full bar height and into the corners;
accumulate `angleDelta` to 120 and ignore zero; pick one cap and one step.

**A13. Clicking a notification throws it away** · P1 · S · [V] · **DONE** (branch `ux/audit-fixes`)
`dunstrc.tmpl:60-62`: left click is `close_current`; actions sit behind
`context`, which needs a dmenu that is not installed. `monitor = 0` with no
`follow` pins popups to the first monitor. Do Not Disturb is pause level 100
with no override, so it also holds "Scheduled backup failed".
Fix (config only): `mouse_left_click = do_action, close_current`,
`mouse_right_click = close_current`, `follow = keyboard`,
`[urgency_critical] override_pause_level = 100`, `idle_threshold = 120`.

**A14. Volume and brightness feedback is a notification** · P1 · M · [V] · **DONE** (branch `ux/audit-fixes`)
`volume-popup.sh:19` and `brightness.sh:161` send `notify-send` with a `█░`
bar. It lands in history (a "Brightness" entry is there now), shows as app
"notify-send", vanishes under Do Not Disturb, and does not appear when you
scroll the bar widget. Brightness keys pass no connector, so a docked laptop
adjusts the internal panel. This is one defect with A12 and A15: keys bypass
the shell's services, so volume has three implementations.
Fix: a per-screen `OsdToast` on the `VoxtypeTranscriptToast` pattern that
reacts to `AudioService` and `DisplayBrightness` state, so keys, scroll and
sliders all produce it; route brightness keys through an IPC method that
targets the focused monitor; delete the popup scripts. Interim: add
`history_ignore` and a transient hint.

**A15. Media keys are dead on the lock screen; mic mute is unbound** · P1 · S · [V] · **DONE** (branch `ux/audit-fixes`)
All 61 binds report `locked: false`; `XF86AudioMicMute` is bound nowhere and is
missing from `KEYS` in `shortcuts-settings.py`.
Fix: `locked = true` on the nine volume/media/brightness binds; add `mic-mute`
(`wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle`) and `XF86AudioStop`.

**A16. Windows cannot be fullscreened, moved or resized** · P1 · S–M · [V] · **DONE** (branch `ux/audit-fixes`)
No fullscreen or maximize bind; no directional move, swap or keyboard resize;
zero mouse binds and `resize_on_border = false`, so a window floated with
`Super+V` cannot be moved or resized at all. `windowrules.lua` still opens
with its TODO: the portal file chooser, pavucontrol, Blueman and
Picture-in-Picture tile, and so does Settings (a plain `FloatingWindow`,
class `org.quickshell`, title "Blankweave Settings", no rule) — `Super+,`
re-tiles the workspace on every open.
Fix:
- Files → `Super+E`; `Super+F` fullscreen; `Super+Shift+F` maximize.
- `Super+Shift+arrows` move (crosses monitors, retiring `Super+Shift+K`);
  `Super+Alt+arrows` resize, repeating.
- `Super+LMB` drag, `Super+RMB` and `Super+Shift+LMB` resize;
  `resize_on_border = true`.
- Float-and-centre rules for the utilities above; PiP floats pinned.
All are free keys. Add each to `shortcut-catalog.json`. Confirm every Lua
option shape on a headless output, as CLAUDE.md prescribes: several are
inferred from the stub file.

**A17. Screenshots leave no file and can blank the clipboard** · P1 · M · [X] · **DONE** (branch `ux/audit-fixes`)
`grim - | wl-copy` three times (`keybindings.lua:36-38`): nothing saved, no
feedback, two monitors stitched into one image. Cancelling `slurp` makes grim
write nothing and `wl-copy` replace the clipboard with empty content.
Fix: `defaults/shell/screenshot.sh screen|region|window`. Focused output only;
window rectangles from `hyprctl clients -j` fed to slurp so one key picks a
region or a window; write to `Pictures/Screenshots/` first, then copy; notify
with the image and Open / Annotate actions; never pipe straight into
`wl-copy`. `satty` and `hyprpicker` go in `base.txt` because core binds use
them. Recording (`wf-recorder`) can follow.

**A18. Settings: Escape closes the window while you are typing** · P1 · S · [X] · **DONE** (branch `ux/audit-fixes`)
The window-level `Shortcut { sequence: "Escape" }` (`SettingsContent.qml:120-126`)
wins over field handlers. In an offscreen test with the project's own
`ControlTextField`, Escape in the Wi-Fi password field closed the window and
its `Keys.onEscapePressed` never fired.
Fix: fields accept the event in `Keys.onShortcutOverride`, or the shortcut
checks that no text input has focus.

**A19. Settings search misses everyday words** · P1 · S · [X] · **DONE** (branch `ux/audit-fixes`)
`searchSettings` returns nothing for wifi, trackpad, dnd, browser, font,
cursor, suspend, autostart, night shift. `scale` ranks "VPN & Tailscale"
first. It is a raw `indexOf` (`Catalog.js:165`) with aliases on 12 rows.
Fix: normalise hyphens and spaces, match on word prefixes, give every row an
alias line including the labels of its inner controls, and add these queries to
`tst_settings.qml`.

**A20. Every Settings page opens with a status sentence** · P1 · S · [V] · **DONE** (branch `ux/audit-fixes`)
`SettingsContent.qml:395-412`: "Sound controls are available…", "Theme, color
mode, bar widgets … are available." The desktop entry's comment still says
"explore upcoming system settings". `SettingsRow.qml` carries dead Preview
controls.
Fix: delete the banners (keep the Displays 20-second note as helper text),
fix the comment, remove the dead components.

**A21. The launcher runs terminal apps with no window** · P1 · S · [X] · **DONE** (branch `ux/audit-fixes`)
`ApplicationLauncher.qml:194` calls `item.execute()`; Quickshell 0.3.2 runs a
`Terminal=true` entry with no tty. btop, nvtop and jshell do nothing visible.
Fix: when `entry.runInTerminal`, run `ghostty -e` with the entry's command.

**A22. Panel header buttons are unexplained glyphs** · P1 · S–M · [V] · **DONE** (branch `ux/audit-fixes`)
`ControlPanelHeader.qml:67-108` takes `{id, icon}` only: no label, no
tooltip. The Tailscale panel's top-right button is a close-X glyph that
disconnects the VPN (`TailscaleWidget.qml:293`). Wi-Fi and Bluetooth draw
their power toggle as the feature's own glyph, so it appears twice and the
right-hand one turns the radio off.
Fix: add `label` to the action model and render a tooltip; draw power as a
switch; replace the Tailscale glyph. While there, make tooltip hints for
right-click and scroll one generated line (`Bluetooth` mentions right-click
only when already off; dictation and weather not at all).

**A23. Home and End are broken in every terminal program** · P1 · S · [V] · **DONE** (branch `ux/audit-fixes`)
`ghostty/config.tmpl:15-16` remaps Home/End to Ctrl+A/Ctrl+E for all programs:
in vim, Home increments the number under the cursor. zsh has no binding for
Delete or Ctrl+arrows, which is why the remap exists.
Fix: bind the keys in `.zshrc` from terminfo and delete the two Ghostty lines.

**A24. Shell surfaces animate on the compositor's sample values** · P2 · S · [V]/[I] · **DONE** (branch `ux/audit-fixes`)
`animations.lua` is the stock example: windows and fades 600–1000 ms, a curve
named `myBezier` that overshoots to 1.05. Layers are not overridden and there
are no layer rules, so the launcher and bar popups inherit a 700–800 ms fade
on top of the shell's own 150 ms. Hyprland's update-news and donation popups
are not disabled (`ecosystem:no_update_news`, `no_donation_nag` unset).
Fix: one non-overshooting curve at roughly 200–300 ms; `no_anim` layer rules
for `blankweave-*`; set both ecosystem options. Judge the layer fade by eye
first: both curves are front-loaded.

**A25. The light-mode and Aurora pass** · P1 · S–M · [V], measured · **DONE** (branch `ux/audit-fixes`)
- Empty workspace numerals are `textMuted` at 0.55 opacity
  (`WorkspacesWidget.qml:99`): 1.96:1 on the live bar. Out-of-month dates use
  0.5 (`ClockWidget.qml:229`). Drop the opacity; `textMuted` alone is ~4.8:1.
- Aurora sets `divider` equal to `outline` (`aurora/theme.json:31,33,82,84`),
  and `divider` is used as a foreground for the slider track, bar dividers,
  week numbers and tab badges: about 1.2:1. The slider has no visible range.
- Aurora boots with Obsidian's blue splash (`aurora/theme.json:5-8`).
- The window shadow is Hyprland's unset default (`#1a1a1aee`), a black keyline
  around every window in light mode. Render a per-mode shadow in
  `theme.lua.tmpl`.
- Porcelain and Sage `warning`/`success` sit at 3.9–4.3:1 on 12 px text.
- Aurora's popups (radius 8) are tighter than its windows (10): `shape` tokens
  reach QML only. Render them into the Hyprland, Dunst and Hyprlock templates.
Then make it permanent: `tests/theme-apply.sh` already renders every theme in
both modes; add about ten contrast assertions so this class cannot return.

**A26. No handler for video or audio** · P2 · S · [V] · **DONE** (branch `ux/audit-fixes`)
`xdg-mime query default video/mp4` and `audio/mpeg` are empty; images and PDFs
open in Firefox. No player or viewer is in any manifest.
Fix: `mpv` in base; an image viewer and PDF reader are optional but cheap
(`loupe` and `papers` follow the portal colour scheme).

**A27. Closing the lid while docked leaves a live invisible monitor** · P1 if you dock · M · [I] · **DONE** (branch `ux/audit-fixes`)
`HandleLidSwitchDocked=ignore` and nothing binds the lid switch. The internal
panel stays in the layout; the pointer and workspaces can land on it, which is
also where an ejected workspace goes.
Fix: `monitor-layout.sh lid closed|open` (it is the sole monitor writer),
disabling the internal panel only while an external is connected, bound to the
lid switch and re-enabled on monitor removal.

**A28. Pollers freeze silently and run a login shell every tick** · P2 · S–M · [V] · **DONE** (branch `ux/audit-fixes`)
`ScriptPoller.qml:20-30` runs `bash -lc`, skips ticks while a run is alive and
has no timeout: a hung `docker info` or `nvidia-smi` leaves the last number on
screen as if live. `-l` sources `~/.bash_profile` on every poll, so any output
there corrupts widget JSON. Pollers are per-bar, so two monitors double them.
Fix: `bash -c` behind `timeout`, a `stale` state that mutes the value, and
move the meters, network and notification pollers to shell-owned services the
way `AgentUsage` already is.

**A29. The clock contradicts itself** · P2 · S · [V] · **DONE** (branch `ux/audit-fixes`)
The bar label is zero-padded 12-hour (`ClockWidget.qml:95-98`); its tooltip and
panel are 24-hour. Weather mixes both in one panel and hard-codes °C.
Fix: one time-format preference, defaulting from the locale, used by both.

**A30. Package caches grow without bound** · P2 · S · [V] · **DONE** (branch `ux/audit-fixes`)
11 GB in the pacman cache, 39 GB in `~/.cache/paru`; `paccache.timer` is off
and `pacman-contrib` is in an optional profile.
Fix: `pacman-contrib` to base, enable the timer, add both caches to
Settings › Storage cleanup.

### Round 3 — one system instead of several

**A31. One search-and-deep-link mechanism** · P1 · M · [V] · **DONE** (branch `ux/audit-fixes`)
`blankweave settings` rejects arguments; `openSettings()` takes no page; no bar
panel links to its Settings page; the gear means pavucontrol in Sound and
Settings in Overview. `openSetting(id)` already exists in `SettingsContent`.
Fix: a `settings(page, row)` IPC argument, used by `blankweave settings <id>`,
a footer action in each panel, and the launcher — which then lists Settings
rows and system actions (Lock, Suspend, Restart, Shut down with a second Enter,
Toggle dark mode, Do Not Disturb). `Super+/` opens the Shortcuts page.

**A32. The bar cannot be used from the keyboard** · P1 · M–L · [V] · **DONE** (branch `ux/audit-fixes`)
No panel opens from a key, and inside a panel only Escape works: the Control*
primitives are bare `MouseArea`s with no focus, no ring and no pressed state.
On a keyboard-first desktop, Wi-Fi, audio device and power need the mouse.
Fix in three parts: an IPC `panel <id>` plus binds; focus, arrow/Enter
handling and one `FocusRing` on the six shared primitives (this also gives
Settings a real ring, where focus is now a same-width border recolour);
accessible names last.

**A33. Four idioms for on/off, four for confirmation** · P2 · M · [V] · **DONE** (branch `ux/audit-fixes`)
State-labelled buttons ("Wi-Fi: On"), Off/On dropdowns, verb buttons, and a
real `SettingsSwitch` that is essentially unused. Destructive actions confirm
four different ways.
Fix: a switch row with a pending state that only settles on readback (this
keeps the no-optimistic-updates rule), and one confirm button reused everywhere
on the power panel's arm-then-confirm model.

**A34. Errors show raw exception text, far from the control** · P2 · M · [V] · **PARTLY DONE** (older pages remain)
`SettingsTask.qml:42-46` renders "Error: …"; `settings_support.py` prints
`str(error)`; `f'Enter a valid {key}.'` yields "Enter a valid uri." Status
sits at the bottom of each stack, colours differ (warning on some pages,
critical on others), and a successful poll never clears an old error.
Fix: one status line directly under the touched control, a plain sentence
with the raw text behind "Show details", field labels instead of keys, and
clear on success.
Status: the shared pieces exist (`SettingsResult` with a plain line and
"Show details", structured `message`/`detail`/`field` errors in the common
helper and dispatcher, per-control outcomes in `SettingsTask`), and five
pages use them end to end: Startup, Web apps, Notifications, Wallpaper and
System diagnostics. Still on the old page-wide error string, sanitised only
by the `LegacyErrors.js` bridge: Appearance, Interface size, Displays, saved
setups, colour profiles, Night light, Wireless, Network connections, Wi-Fi,
Bluetooth, Sound, System sounds, Dictation, Power profiles, Automatic power,
Battery, Idle, Keyboard, Shortcuts, Pointer, Accessibility, Default apps, and
the generic operations forms. Remaining work per adapter: store the outcome
against the control and target, render it under that control, clear it on
the specific readback, then delete `LegacyErrors.js`. Best done a few
adapters at a time (network and Bluetooth; displays; power; input).

**A35. Finish the Settings rows a laptop user actually touches** · P2 · M each · [V] · **DONE** (branch `ux/audit-fixes`)
Seventeen rows are a generic form over CLI tools. Keep them, but three miss
the owner's own contract in `SETTINGS_PLAN.md`:
- Date & time: every timezone in one unfiltered dropdown; time typed as
  `YYYY-MM-DD HH:MM:SS`. Add a filter to `SettingsComboBox` and a date control.
- Drives: pairs with A4 — per-drive Mount / Eject.
- Updates: one "Check for updates", the release notes from `RELEASES.md`
  rather than `git log --oneline`, and the restart-required state from A5.
Also: the Snapshots row should say plainly that this root is not Btrfs; rows
for absent hardware (battery, Wi-Fi) should hide via a `requires:` key against
`hardware-capabilities.json`; "Text size" appears twice; Notifications belongs
outside Apps.

**A36. Settings never says where anything is stored** · P2 · M · [V] · **DONE** (branch `ux/audit-fixes`)
The one item that advances openness. No page names its file; refusal messages
say "your custom Hypridle configuration" without a path; eight `.lock` files
and a runtime directory sit in `~/.config/blankweave`.
Fix: a `file:` key per Catalog row rendered as a muted "Stored in … · Copy
path" line; name the overriding file in refusals; move locks to
`$XDG_RUNTIME_DIR`.

**A37. Clipboard history keeps everything, forever** · P2 · M · [V] · **DONE** (branch `ux/audit-fixes`)
Both watchers store unfiltered (`autostart.lua:8-9`), including password-manager
copies; there is no way to delete an entry or clear the history. (The cache
directory is 0700 on an encrypted disk, so this is hygiene, not exposure.)
Fix: a small store wrapper that skips `x-kde-passwordManagerHint`, a Delete key
on a row and a confirmed Clear; keep the list on screen while refreshing
instead of flashing "empty".

**A38. Every update re-asserts first-run choices** · P2 · M · [V] · **DONE** (branch `ux/audit-fixes`)
`install.sh` re-runs `chsh` to zsh (427), re-enables bluetooth, NetworkManager,
tailscaled and docker (193-213), re-adds the docker group, and `chown -R`s
`~/.config`, `~/.cache` and `~/.local` (441-445) — a walk over 39 GB here, and
it would flatten rootless-container ownership. `chsh` is load-bearing only
because the session start lives in `.zprofile`.
Fix: seed tailscaled, docker and the docker group once behind a marker; narrow
the `chown` to paths the installer wrote; move the session start out of the
zsh profile.

**A39. Smaller items, any order** · P2–P3 · S each · **DONE** (branch `ux/audit-fixes`)
Status: all items done on `ux/audit-fixes`. Two limits: Hyprlock 0.9 has no
date variable, so its date label still polls once a minute; and high
contrast still stops at the shell's own surfaces. `fuzzel` and an old
`~/.local/share/zinit` directory are leftovers the owner can remove.
- Hovering selects launcher rows (`ApplicationLauncher.qml:598`), so a resting
  pointer can decide what Enter launches; select on pointer movement. [I]
- Launcher favourites are a literal array of one person's apps (`:60-63`);
  record launch counts in a shell-owned service instead.
- First terminal launch clones zinit, powerlevel10k and four plugins unpinned
  and starts the p10k wizard; ship a default `p10k.zsh` and install the plugins
  from packages. [V]
- `EDITOR=nano` but nano is in no manifest; `VISUAL` and `BROWSER` unset.
- Hyprlock forks `date` every second per monitor and hard-codes 24-hour; it
  shows Caps Lock only as a border colour and uses the older Atkinson family.
- Idle: one policy for AC and battery, so a plugged-in laptop suspends at 30
  minutes; a manually locked screen never blanks.
- Keyboard settings lack repeat rate, Caps Lock remap and a compose key;
  pointer settings lack two-finger click (`clickfinger_behavior`). Two-finger
  *tap* already right-clicks; a two-finger *press* is a left click. [V]
- Nine QML animations bypass `motionDuration`; fixed label widths ignore the
  130% text size; high contrast stops at the Quickshell boundary.
- Panels have no maximum height (Network is about 760 px).
- The Display panel hides when brightness is unreadable, taking the theme,
  scale and position controls with it (`BrightnessWidget.qml:115`).
- The six adjacent system-control icons mix filled glyphs and thin-stroke
  marks; finish the glyph-to-mark migration for those six.
- Theme validation checks key presence only (`"text": "red"` passes) and a bad
  lock token aborts after some outputs are already replaced.
- `DisplayBrightness.qml:26-28` renames any "LG HDR 4K" to "LG UltraFine
  27UL850" — a host label in universal code.
- This machine: 23 duplicate banner lines in `~/.zshrc`; `fuzzel` still
  installed; `wireless-regdb` missing (kernel logs a regulatory.db failure).

---

## Track B — before a stranger runs the bootstrap

None of these touch the owner's machine; all of them decide a first impression.

**B1. Re-running the install line after a cancelled setup does nothing** · P0 · S · [V] · **DONE** (branch `ux/audit-fixes`)
`bootstrap.sh:46-58` sends an existing checkout to `update`, which prints
"already up to date" and exits 0. The setup review defaults to "no", and
`blankweave` is not on PATH yet. Fix: run `setup` when no installed revision is
recorded, and print the resume command on cancel.

**B2. Autologin and a passwordless keyring with no check that the disk is encrypted** · P0 · S · [V] · **DONE** (branch `ux/audit-fixes`)
`installer-preflight.sh` checks Arch, UEFI, tools, the pacman lock and Secure
Boot only. Fix: detect a crypt ancestor of `/`; without one, warn in the
review and default to the existing password-required mode. Say the trade-off
out loud in the review either way.

**B3. The boot-loader requirement is discovered at stage 18 of 21** · P0 · S–M · [V] · **DONE** (branch `ux/audit-fixes`)
By then autologin is on, SDDM is gone and the shell is changed. Fix: a
read-only `--check` in `configure-limine.sh`, called from preflight.

**B4. Any untagged commit on `main` breaks install and update for everyone** · P1 · M · [V] · **DONE** (branch `ux/audit-fixes`)
Both require `origin/main` itself to be the annotated tag. Main was untagged
for about 70 hours before 0.10.0. Fix: target the highest annotated tag that
is an ancestor of `origin/main`; accept `update --to vX.Y.Z`.

**B5. Doctor fails the password sign-in mode that Settings offers** · P1 · S · [V] · **DONE** (branch `ux/audit-fixes`)
`settings-system.py:189-195` writes `signin.conf`; `doctor.sh:237-241` then
reports FAIL, and every later update ends "degraded" with a rollback hint.
Most doctor failures also name a subsystem but no remedy, and discard the
validator's output.

**B6. A hard interruption leaves `NOPASSWD: ALL` behind** · P1 · S · [V] · **DONE** (branch `ux/audit-fixes`)
`install.sh:97-110` removes it only in an EXIT trap. Fix: remove a stale file
in preflight, fail on it in the root doctor helper, narrow the rule.

**B7. Core keys depend on optional profiles** · P1 · S · [V] · **DONE** (branch `ux/audit-fixes`)
`Super+B` hard-codes `zen-browser` (desktop profile); the default browser is
never seeded, so a fresh install opens links in Firefox and `Super+B` in Zen;
the bar's `xdg-open` actions need a browser that base does not provide. Fix:
resolve the default handler for `Super+B` and `Super+F`; seed defaults once;
notify when a bound tool is missing.

**B8. There is no "you're in" moment** · P1 · M · [V] · **DONE** (branch `ux/audit-fixes`)
The install ends on "A hyprctl reload cannot switch an existing legacy .conf
session to Lua"; first login is a wallpaper and a bar with no hint that
`Super+Space` exists. Fix: one closing block (reboot, your disk passphrase is
the login, five keys) and a one-time welcome card gated by a `ShellPreferences`
flag.

**B9. The README is an engineering reference** · P1 · M · [V] · **DONE** (screenshots still to be added by the owner)
No screenshot anywhere in the repo, no requirements list, no quick start,
updating, troubleshooting or uninstall. The Archinstall baseline hard-codes
`Asia/Kolkata` and talks about "the laptop and desktop".

**B10. Smaller** · P2 · **DONE** (branch `ux/audit-fixes`)
No uninstall or footprint list; `blankweave help <cmd>` errors and
`theme --help` leaks `theme-apply.sh`; bare `blankweave theme` re-applies
instead of showing status; no zsh completion; no SSH agent; printers need a
typed `ipp://` URI; no firewall (a doctor warning on non-loopback listeners is
a safer first step than a ruleset that fights Docker and the hotspot).

---

## Decided against, after argument

| Proposal | Why not |
|---|---|
| Replace Dunst with Quickshell's notification server | Every cited defect is configuration (A13). The rewrite would discard the DND ledger, tests and the documented `dunstrc.d` override. Revisit only if inline action buttons become a real need. |
| Hide the CPU / memory / GPU meters by default | Identity: a documented bar group on a developer's machine, already hideable in Settings. Only the spacing against the power button is a defect. |
| Hide or collapse the completed Settings rows | They are finished work under an explicit contract; A35 finishes three properly instead. |
| Update badge, unread dot, urgent-workspace marker, now-playing in the bar | An attention budget: the tray and inhibitor were declined for this reason. New signals should be event-only and transient (A3, A14), or pulled on demand (A35). |
| Calculator, emoji picker, window switcher in the launcher | Scope growth without a daily need here. System actions and Settings rows (A31) earn their place. A compose key covers accents. |
| Change the workspace summon / eject model, or `focus_on_activate` | Both are documented, deliberate trade-offs. The real hazard is A27. Worth one check: Hyprland may now have a per-window activation rule, contrary to CLAUDE.md. |
| Popup drop shadows; a theme generator from one accent; `force_split` | Taste, or large for what it buys. |
| Icons in the Settings sidebar | The last release deliberately quieted the navigation. |
| Focus an already-running app from the launcher | Dock thinking; activation already raises single-instance apps. |

## Needs your hands

Read-only auditing could not settle these:

- Two-finger *press* on the touchpad, and the bottom-centre click (middle-click
  paste) in a text field.
- Close the lid while docked: is the internal panel still in `hyprctl monitors`?
- Whether the 700–800 ms layer fade is visible on the launcher and popups.
- Whether Thunar asks before its permanent delete.
- Pointer resting over the launcher list, type, press Enter (A39).
- Opening a second bar panel while one is open: does the first close?
- IntelliJ at this scale with `force_zero_scaling`.
- Do **not** test the power key without saving first.

## Verify after applying

Everything marked DONE was built and tested against stubs, fakes and sandbox
roots. Apply with a saved workspace and a second console (Ctrl+Alt+F2)
available, then log out and back in so long-running helpers pick up the new
lock location.

Applied to the owner's machine on 2026-11-13 with `./install.sh` from the
working tree (twice; the second run carried four fixes the first exposed:
the GTK interface font never reached the desktop settings database because
sudo strips the session bus, `blankweave settings --list` missed rows with
storage keys, the seeded-default markers were left root-owned, and doctor
printed one line twice). Confirmed read-only afterwards: installer exit 0,
doctor with no failures, no compositor config errors, Quickshell reloaded
without QML errors, the new IPC methods and bindings registered, font
aliases, zsh startup, default applications, file ownership, and the theme
and sign-in policy unchanged. The second run upgraded the kernel, so the
session has not yet been restarted; everything below that needs a new
session, a key press, or an eye is still unchecked. A development apply
points the installation at the working tree, so `blankweave update` refuses
until the tree is committed and released or the managed checkout's installer
is run again.

**First, because a failure here costs the most**
- Boot: no text on tty1, the desktop starts, `Super+Escape` → "Restart
  session" brings the desktop back. (A8, A38)
- `ls -ld` on `~/.config/blankweave`, `~/.local/share/blankweave` and a few
  files inside: nothing owned by root. (A38)
- `Super+L` locks; the power panel's Lock locks; idle lock and
  lock-before-sleep still work. (A7)
- Short press of the power key opens the menu; a long press powers off. (A1)
- Docked: close and open the lid; unplug the dock with the lid closed. (A27)

**Daily use**
- Bar: click at the very screen edge on the first, a middle and the last
  widget, bar on top and on bottom; touchpad and wheel scroll; a sideways
  swipe does nothing; auto-hide still reveals. (A12)
- The six system icons at bar size in every theme and mode; labels at 130%
  text size. (A11, A39)
- Volume, mute, mic mute and brightness keys with the shell running, with it
  stopped, and on the lock screen; brightness on the focused monitor while
  docked; the indicator over a fullscreen window. (A14, A15)
- Panels from the keyboard: `Super+Ctrl+A/N/B/I/D`, then Tab, arrows, Enter,
  Escape; the focus ring in each theme. (A32)
- Windows: `Super+F`, `Super+Shift+F`, `Super+Shift+arrows`,
  `Super+Alt+arrows`, `Super`+drag; Settings, pavucontrol and the file
  chooser float; Picture-in-Picture sits pinned in a corner. (A16)
- Screenshots: `Print`, `Super+Shift+S` (drag and click a window),
  `Super+Alt+S`; file saved, image on the clipboard, cancel leaves both
  alone; Open and Annotate from the notification. (A17)
- Notifications: left click acts, right click dismisses, popup on the
  monitor in use, a critical one during Do Not Disturb. (A13)
- Launcher: btop opens in a terminal; a resting pointer does not change the
  selection; Settings rows and system actions appear with a query; Restart
  needs a second Enter. (A21, A31, A39)
- Clipboard: a password copied from the password manager is absent from
  history; Delete removes a row; Clear history asks first. (A37)
- Thunar: Delete moves to Trash, thumbnails appear, a USB stick shows up,
  "Open Terminal Here" opens Ghostty. (A4)
- Fonts in Thunar, a browser page using `sans-serif`, an Electron app, and a
  CJK string. (A10)
- Terminal: first launch offline, prompt in both terminal themes, Home/End
  at the prompt and in vim. (A23, A39)

**Look and feel, by eye**
- Animation speed (200–250 ms). (A24)
- Light mode in all three themes: workspace numerals, calendar, sliders,
  dividers, window shadows; Aurora's corners and boot splash. (A25)
- Sage: the slider's filled range is close in tone to its track.
- Lock screen: clock format, "Caps Lock is on", typeface, the screen turning
  off about 45 seconds after a manual lock. (A39)
- The dark lock panel on Obsidian and Moss is more opaque than before.

**Settings**
- Escape while typing in a Wi-Fi password; search for wifi, trackpad, dnd;
  switches settling after the change is confirmed; a reset arming before it
  acts. (A18, A19, A33)
- Date & time, Drives, Updates, the "Stored in …" line, Copy path. (A35, A36)
- Key repeat, Caps Lock behaviour, compose key, two-finger click. (A39)

**Only on a fresh machine or VM**
- Bootstrap picks the newest release; a cancelled setup resumes; an
  unencrypted disk defaults to password sign-in; an unsupported boot layout
  stops before any change; the closing block and the welcome card. (B1–B4,
  B8)
- A real `blankweave update` (summary, confirmation, sleep inhibition,
  restart marker) and `rollback`. (A5, A6)
- `blankweave uninstall --apply`. (B10)

**Decisions left to the owner**
- Volume capped at 100% from the bar; mains power no longer suspends by
  default; waiting pull-request reviews no longer colour the Git icon;
  `Super+Shift+B` opens Bluetooth Settings; `oh-my-zsh-git` required for the
  git aliases; weather in Fahrenheit under an `en_US` locale until the unit
  is set; GTK font size left at 11 pt.

## Worth protecting

- Single-writer text files with an overrides directory, and
  `user_config_link` never touching a file it does not own.
- Readback before claiming state; no optimistic UI; captured identities so
  hotplug cannot retarget a click.
- A strictly read-only doctor with a sanitised report.
- The boot chain: themed LUKS prompt, retained splash, silent tty1.
- `LauncherSession` on the shell root, and `VoxtypeTranscriptToast` as the
  template for every transient surface.
- Zero hard-coded colours in QML; reduced motion honoured by every animation
  and carried to the compositor, GTK and the wallpaper.
- A Super-only keymap that collides with no application.
