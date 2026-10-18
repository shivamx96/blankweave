# Completing Settings

Planning baseline: `main` at `ed93429` (0.10.0), checked 2026-10-18.
Scope: all 17 remaining `kind: "action"` rows in
`defaults/quickshell/Settings/Catalog.js`. This is an execution proposal;
provider choices below require API and installed-version validation in their
implementation slice.

## Completion contract

Every row gets a native Settings view, a real backend, capability detection,
useful missing-dependency/unsupported states, and tested mutations. A launcher
alone does not complete a row. External authentication and specialist tools
may supplement the native flow. Unsupported hardware must explain why a
specific operation is unavailable rather than show a generic preview.

Retain stable catalog IDs. Wire each view through SettingsRow, SettingsContent,
and the SettingsWindow service lifecycle; remove preview copy as slices land.
Ship dependencies, installer deployment, migrations where needed, documentation,
and CI coverage in the same slice as the feature.

## 0. Shared execution foundation

- Reuse `settings_support.py` for validation, revisions, locks, and atomic writes,
  and `SettingsTask.qml` for short status/apply operations.
- Add a persistent job contract for scans, installs, updates, backups, restores,
  and firmware: job ID, phase, progress where available, sanitized error/log,
  completion, and recovery state. Closing Settings must not terminate a job.
  Support cancellation only at provider-defined safe boundaries.
- Use existing service authorization APIs where possible. Any new privileged
  helper must be root-owned with narrowly validated operations; never elevate
  a user-writable Python helper or accept arbitrary shell commands.
- Keep credentials out of argv, logs, and plain preference files. Establish
  secure prompt/credential-store flows before adding unattended encrypted jobs.
- Coordinate package mutations with each other and the existing updater;
  respect provider locks and expose conflicts instead of bypassing them.
- Add reusable capability and job UI states, plus fixtures for denied/cancelled
  authorization, absent tools, stale state, offline services, and interruption.

## 1. Network and everyday system controls — 3 rows

- `vpn`: manage imported NetworkManager VPN profiles, activation, disconnection,
  deletion, and authentication; expose required VPN plugins. Reuse/refactor
  `tailscale-status.sh` and `tailscale-auth.sh` for status, login, peers, and
  connect/disconnect without duplicating the bar's state machine.
- `datetime`: timezone search, automatic synchronization, manual time when
  allowed, and per-user region/format preferences. Proposed providers:
  timedated/localed plus user locale configuration. State when a new session
  is needed and preserve installer-managed preferences.
- `printers`: discover/add printers, defaults, queue inspection/cancellation,
  and test page through CUPS. Include scanner discovery and an explicit scan
  handoff through a supported scanning application; evaluate SANE integration.

Acceptance: state survives reopening, external changes refresh correctly,
authentication cancellation is recoverable, and missing services offer a
specific setup path.

## 2. Storage inspection and devices — 3 rows

- `disk-usage`: filesystem totals plus an explicit, cancellable directory scan;
  show permission gaps and mount boundaries. Cleanup previews exact owned cache
  targets and estimated space, then reports actual results. No broad recursive
  deletion of arbitrary user paths.
- `drives`: enumerate, mount/unmount, unlock, and safely eject using UDisks2.
  Handle busy devices, disappearing media, and encrypted-device secrets.
- `disk-health`: expose available SMART/NVMe health, temperature, and self-test
  results via a validated provider (UDisks2 or smartmontools). Distinguish
  unsupported telemetry from a healthy device; support safe test initiation.

Acceptance: fixtures cover removable/encrypted media, denied access, USB bridges
without telemetry, and hot unplug; real-device smoke tests exercise mount/eject.

## 3. Applications and maintenance — 4 rows

- `installed`: inventory, search available software, install, and remove.
  Propose pacman repositories first, optional Flatpak support, and explicit
  presentation of AUR-managed software. Decide the AUR transaction path before
  marking this row complete; builds must remain unprivileged. Preview dependency
  changes and protect the desktop's required packages from accidental removal.
- `permissions`: expose supported portal grants and Flatpak overrides with
  revoke/reset controls and accurate scope. Clearly label native applications
  whose camera, microphone, or filesystem access cannot be centrally revoked;
  do not imply that this is a universal sandbox.
- `updates`: reuse `blankweave update --check`, `--dry-run`, apply, and recovery
  records, adding structured output rather than parsing presentation text.
  Show release notes and separately identified OS/application updates. Preserve
  release-tag validation and rollback boundaries; integrate full package
  transactions without creating a second competing updater.
- `firmware`: proposed fwupd integration for devices, available releases,
  requirements, progress, history, and pending reboot. Treat firmware flashing
  as non-cancellable once the provider crosses its safe boundary.

Acceptance: fake providers cover locks, offline checks, partial failures,
reboot requirements, and shell closure. VM tests validate package transactions
and existing update/recovery tests continue to pass.

## 4. Sharing, accessibility, and sign-in — 3 rows

- `sharing`: implement authenticated network-folder sharing plus a nearby
  transfer flow. Proposed providers are Samba and a compatible nearby-transfer
  application. Validate provider choice first; include folder permissions,
  discovery/firewall scope, stop/remove, and recipient consent.
- `assistive`: independently configure screen reader, magnifier, and on-screen
  keyboard, including launch/stop, session persistence, and conflict-checked
  shortcuts. Evaluate Orca, Hyprland magnification, and a compatible Wayland
  keyboard in the actual session. Test Settings keyboard navigation and reader
  announcements, including an accessible way to undo each setting.
- `accounts`: list/create accounts, change account type/password, and manage
  supported sign-in preferences. Inspect the tty1 autologin/UWSM path first:
  account switching and persisted sign-in choices must coexist with installer
  convergence. Prevent removal/demotion of the last usable administrator and
  handle the current account explicitly.

Acceptance: session-level tests verify startup, permissions, shortcut behavior,
and sign-in after reinstall/update convergence. Accessibility requires a real
Hyprland session; fixtures alone cannot establish usability.

## 5. Backups and recovery — 3 rows

- `backup`: proposed restic backend with source/exclusion selection, local and
  supported remote destinations, encryption, retention, manual execution, and
  systemd user timers. Define credential availability while locked/logged out,
  missed schedules, removable destinations, and failure notifications.
- `restore`: use the same repositories and credential flow; browse snapshots,
  select files, preview destination/conflicts, and restore to a separate folder
  by default. Explicitly handle overwrite, metadata, symlinks, and free space.
- `snapshots`: build on the updater's existing root Snapper configuration.
  Inventory/create/delete snapshots, configure retention/scheduling, and expose
  supported setup and recovery flows. Validate Btrfs layout, exclusions,
  encryption, and Limine integration before enabling setup. Keep file backups,
  Blankweave configuration rollback, and full-system recovery clearly distinct.
  Perform system rollback from a validated recovery environment.

Acceptance: encrypted backup/restore round trip with content verification;
missing/wrong credentials, offline destination, retention failure, interrupted
restore, and timer persistence. Prove snapshot recovery by rebooting a disposable
VM into the recovered system before declaring recovery supported.

## 6. Hibernation — 1 row

- `hibernate`: inspect swap, resume configuration, encryption, initramfs, boot
  entries, and system sleep support. Show a concrete readiness report.
- Implement reversible setup for explicitly tested layouts, integrating the
  existing Limine/initramfs deployment paths. Show required reboot and readiness
  after reboot. Never claim that swap capacity alone proves hibernation works.
- Offer hibernate only when supported, with a clear unsupported-layout reason.
  Integrate the resulting capability into power actions and idle policy.

Acceptance: setup/revert tests in disposable systems plus actual
hibernate/resume testing on representative supported hardware. Do not treat
mocked capability detection as proof of successful resume.

## Delivery and verification

Land the foundation first, then the numbered groups in order. Split each group
into reviewable feature PRs; backup and restore share one provider contract and
should be developed together. Every feature PR includes its catalog wiring and
tests, so no separate final wiring effort accumulates.

For each slice, run focused Python/helper tests, fixture-driven Quickshell/QML
tests, and relevant installer/update regressions. Follow with the repository's
`validate.yml` checks and the slice's VM/session/hardware acceptance checks.
Tests must not mutate the developer machine's packages, accounts, disks, or
network configuration.

Final gate: all 17 IDs have real providers and rendered controls, no remaining
placeholder action rows or stale preview copy, all required optional-dependency
paths work on existing installs, and documented supported configurations pass
end-to-end checks. Record unverified hardware explicitly rather than claiming
universal support.


## Implementation checkpoint

Implemented on `feat/settings-remaining`: all 17 catalog IDs now route to
native operation forms and domain-specific Python providers. The shared service
owns page activation, revision checks, private durable job reports, and safe
cancellation; the root-owned helper handles allowlisted privileged mutations.
Provider packages ship with the desktop profile, and LocalSend remains in the
communication profile. README documents the supported operations and limits.

Validation includes isolated provider/privilege tests, native QML form tests,
Quickshell service lifecycle tests, installer sign-in persistence, boot-file
rollback on failed hibernation preparation, and a real encrypted restic
backup/restore/integrity round trip. Automated tests never modify host accounts,
packages, devices, or boot configuration.

Acceptance still requires real-session/hardware checks for VPN authentication,
printing/scanning, assistive-tool usability, firmware, encrypted removable media,
and hibernate/resume, plus a disposable VM snapshot-recovery drill. Those checks
cannot be inferred from fixture tests. Supported hibernation preparation covers
existing encrypted swap partitions only; full-system snapshot rollback remains
an external rescue operation. AUR builds and interactive system upgrades retain
their existing specialist tools. These boundaries are visible in Settings.
