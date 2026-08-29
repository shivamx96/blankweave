#!/usr/bin/env bash

set -euo pipefail

cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/hyprarch

# These account-agnostic files predate per-host, per-login caching. They contain
# only derived GitHub data and are safely recreated under the new cache key.
rm -f -- "$cache_dir/git-prs.json" "$cache_dir/git-login"
