#!/usr/bin/env bash

# Blankweave release metadata helpers. VERSION declares the intended stable
# SemVer; an annotated v<VERSION> tag pointing at the same commit makes that
# commit a release. Callers source this file rather than evaluating Git output.

blankweave_release_version_valid() {
    [[ $1 =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

blankweave_release_revision_valid() {
    [[ $1 =~ ^[0-9a-f]{40,64}$ ]]
}

blankweave_release_blob_value() {
    local repository=$1 revision=$2 path=$3 value

    blankweave_release_revision_valid "$revision" || return 1
    value=$(git -C "$repository" show "$revision:$path" 2>/dev/null) || return 1
    value=${value%$'\r'}
    [[ -n $value && $value != *$'\n'* ]] || return 1
    printf '%s\n' "$value"
}

blankweave_release_version_at() {
    local repository=$1 revision=$2 version

    version=$(blankweave_release_blob_value "$repository" "$revision" VERSION) || return 1
    blankweave_release_version_valid "$version" || return 1
    printf '%s\n' "$version"
}

blankweave_release_floor_at() {
    local repository=$1 revision=$2 version

    version=$(blankweave_release_blob_value \
        "$repository" "$revision" MIN_ROLLBACK_VERSION) || return 1
    blankweave_release_version_valid "$version" || return 1
    printf '%s\n' "$version"
}

blankweave_release_tag_at() {
    local repository=$1 revision=$2 version tag tagged_revision

    version=$(blankweave_release_version_at "$repository" "$revision") || return 1
    tag=v$version
    # ^{tag} rejects a lightweight tag. Releases are annotated objects so the
    # boundary has its own message, timestamp, and future signing path.
    git -C "$repository" rev-parse -q --verify "refs/tags/$tag^{tag}" \
        > /dev/null 2>&1 || return 1
    tagged_revision=$(git -C "$repository" rev-parse "refs/tags/$tag^{commit}" 2>/dev/null) \
        || return 1
    [[ $tagged_revision == "$revision" ]] || return 1
    printf '%s\n' "$tag"
}

blankweave_release_version_greater_or_equal() {
    local candidate=$1 floor=$2 candidate_part floor_part index
    local -a candidate_parts floor_parts

    blankweave_release_version_valid "$candidate" || return 1
    blankweave_release_version_valid "$floor" || return 1
    IFS=. read -r -a candidate_parts <<< "$candidate"
    IFS=. read -r -a floor_parts <<< "$floor"
    for index in 0 1 2; do
        candidate_part=${candidate_parts[$index]}
        floor_part=${floor_parts[$index]}
        if (( ${#candidate_part} > ${#floor_part} )) \
            || { (( ${#candidate_part} == ${#floor_part} )) && [[ $candidate_part > $floor_part ]]; }; then
            return 0
        elif [[ $candidate_part != "$floor_part" ]]; then
            return 1
        fi
    done
    return 0
}

blankweave_release_version_greater() {
    [[ $1 != "$2" ]] && blankweave_release_version_greater_or_equal "$1" "$2"
}

# Return a tag, never an arbitrary revision supplied by the caller. Ignore
# development, lightweight, mismatched, and off-main tags.
blankweave_release_select() {
    local repository=$1 main=${2:-origin/main} requested=${3:-}
    local tag revision version best='' best_version=''
    if [[ -n $requested ]]; then
        [[ $requested == v* ]] && blankweave_release_version_valid "${requested#v}" || return 1
    fi
    while IFS= read -r tag; do
        [[ -z $requested || $tag == "$requested" ]] || continue
        blankweave_release_version_valid "${tag#v}" || continue
        git -C "$repository" rev-parse -q --verify "refs/tags/$tag^{tag}" >/dev/null 2>&1 || continue
        revision=$(git -C "$repository" rev-parse "refs/tags/$tag^{commit}" 2>/dev/null) || continue
        git -C "$repository" merge-base --is-ancestor "$revision" "$main" || continue
        [[ $(blankweave_release_tag_at "$repository" "$revision") == "$tag" ]] || continue
        version=${tag#v}
        if [[ -z $best ]] || blankweave_release_version_greater "$version" "$best_version"; then
            best=$tag
            best_version=$version
        fi
    done < <(git -C "$repository" tag --list 'v*')
    [[ -n $best ]] || return 1
    printf '%s\n' "$best"
}
