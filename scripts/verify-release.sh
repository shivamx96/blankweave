#!/usr/bin/env bash

set -euo pipefail

repository=${1:?repository path is required}
requested_revision=${2:-HEAD}

# shellcheck source=scripts/release-version.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/release-version.sh"

revision=$(git -C "$repository" rev-parse "$requested_revision^{commit}" 2>/dev/null) || {
    printf 'Could not resolve release revision: %s\n' "$requested_revision" >&2
    exit 1
}
version=$(blankweave_release_version_at "$repository" "$revision") || {
    printf 'Revision %s has an invalid VERSION.\n' "${revision:0:12}" >&2
    exit 1
}
tag=$(blankweave_release_tag_at "$repository" "$revision") || {
    printf 'Revision %s is not the annotated v%s release.\n' \
        "${revision:0:12}" "$version" >&2
    exit 1
}

printf '%s\n' "$tag"
