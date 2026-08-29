#!/usr/bin/env bash
#
# Stand-in for desktop commands a script may call as a side effect (gsettings,
# dunstctl, hyprctl, awww). Symlink it under the command's name; every
# invocation is appended to $FAKE_LOG as "<command> <arguments>".

set -euo pipefail

printf '%s %s\n' "$(basename "$0")" "$*" >> "${FAKE_LOG:?FAKE_LOG must be set}"
