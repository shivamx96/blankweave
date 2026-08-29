# Hyprarch migrations

This directory contains small, user-scoped state transitions that run once after
a successful Hyprarch apply.

Migration files must:

- use the name `YYYYMMDD-description.sh`;
- be executable Bash scripts;
- be safe to run on either supported host;
- be idempotent, even though successful runs are recorded;
- avoid package installation and privileged system changes, which belong in the
  declarative installer.

Applied filenames are recorded in
`${XDG_STATE_HOME:-$HOME/.local/state}/hyprarch/migrations-applied`.
