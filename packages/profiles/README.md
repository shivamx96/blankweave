# Package profiles

The files in this directory describe optional capabilities layered on top of
the required environment in `packages/base.txt` and `packages/aur.txt`.

Each profile may provide:

- `<profile>.txt` for official repository packages;
- `<profile>.aur.txt` for exact AUR package names;
- `<profile>.providers.txt` for deliberate repository-backed virtual dependency
  providers.

Host-specific additions use the same filenames under
`hosts/<host>/profiles/`. Missing files mean that a profile needs no packages of
that kind for the host.

Profiles currently available:

- `desktop` — browsers, notes, and personal desktop utilities;
- `development` — editors, containers, language tooling, and coding tools;
- `communication` — messaging and local sharing applications;
- `gaming` — Steam, Proton, overlays, and the detected GPU's 32-bit driver.

Profiles are additive. Removing one from the installer config stops requesting
its packages on future runs; it does not uninstall packages already present.
