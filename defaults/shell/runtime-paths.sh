#!/usr/bin/env bash
# One implementation of XDG fallback and permissions for bash and Python users.
blankweave_runtime_path() {
    python3 "$(dirname -- "${BASH_SOURCE[0]}")/runtime_paths.py" "$1"
}
