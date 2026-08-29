#!/usr/bin/env bash
# Open pull requests authored by, or awaiting review from, the signed-in
# GitHub account. Results are cached so the bar can keep a review badge live
# without spending a search request on every poll.

set -uo pipefail

max_age=300
case "${1:-}" in
    --refresh) max_age=0 ;;
    --max-age) max_age=${2:-300} ;;
esac

cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/blankweave
cache_file=
fields=number,title,url,repository,author,isDraft,updatedAt,commentsCount

emit_unavailable() {
    jq -cn --arg error "$1" --argjson authenticated "$2" '{
        available: true, authenticated: $authenticated, stale: false,
        error: $error, login: "",
        authored: [], review: [], authoredCount: 0, reviewCount: 0, draftCount: 0
    }'
}

serve_stale() {
    if [ -s "$cache_file" ]; then
        jq -c --arg error "$1" '. + {stale: true, error: $error}' "$cache_file" 2>/dev/null && exit 0
    fi
    emit_unavailable "$1" true
    exit 0
}

if ! command -v gh >/dev/null 2>&1; then
    emit_unavailable "GitHub CLI is not installed" false
    exit 0
fi

github_host=${GH_HOST:-github.com}
if ! timeout 8 gh auth token --hostname "$github_host" >/dev/null 2>&1; then
    emit_unavailable "Not signed in to GitHub" false
    exit 0
fi

login=$(timeout 8 gh auth status \
    --active \
    --hostname "$github_host" \
    --json hosts \
    --jq '[.hosts[][] | select(.active == true)][0].login // ""' \
    2>/dev/null)
if [[ ! "$login" =~ ^[a-zA-Z0-9-]+$ ]]; then
    emit_unavailable "Could not identify the active GitHub account" false
    exit 0
fi

# Account and host are part of the cache identity, so `gh auth switch` cannot
# expose another account's cached pull requests or username.
cache_key=$(printf '%s@%s' "$login" "$github_host" | tr -c 'a-zA-Z0-9._-' '_')
cache_file=$cache_dir/git-prs-$cache_key.json

if [ -s "$cache_file" ]; then
    age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || printf 0) ))
    if [ "$age" -ge 0 ] && [ "$age" -le "$max_age" ]; then
        cat "$cache_file"
        exit 0
    fi
fi

mkdir -p "$cache_dir"

authored=$(timeout 12 gh search prs --author=@me --state=open --limit 40 --json "$fields" 2>/dev/null)
review=$(timeout 12 gh search prs --review-requested=@me --state=open --limit 40 --json "$fields" 2>/dev/null)

if [ -z "$authored" ] && [ -z "$review" ]; then
    serve_stale "Could not reach GitHub"
fi

payload=$(jq -cn \
    --argjson authored "${authored:-[]}" \
    --argjson review "${review:-[]}" \
    --arg login "$login" \
    --argjson now "$(date +%s)" '
    def ago($now):
        if . == null or . == "" then ""
        else
            ($now - (. | fromdateiso8601)) as $delta
            | if $delta < 90 then "just now"
              elif $delta < 5400 then (($delta / 60 | floor | tostring) + "m ago")
              elif $delta < 172800 then (($delta / 3600 | floor | tostring) + "h ago")
              elif $delta < 31536000 then (($delta / 86400 | floor | tostring) + "d ago")
              else (($delta / 31536000 | floor | tostring) + "y ago")
              end
        end;

    def shape($now):
        [
            .[]
            | {
                number: (.number // 0),
                title: (.title // "Untitled pull request"),
                url: (.url // ""),
                repo: (.repository.nameWithOwner // .repository.name // ""),
                author: (.author.login // ""),
                isDraft: (.isDraft // false),
                comments: (.commentsCount // 0),
                updated: ((.updatedAt // "") | ago($now)),
                updatedAt: (.updatedAt // "")
            }
        ]
        | sort_by(.updatedAt) | reverse;

    ($authored | shape($now)) as $mine
    | ($review | shape($now) | map(select(.author != $login or $login == ""))) as $reviews
    | {
        available: true,
        authenticated: true,
        stale: false,
        error: "",
        login: $login,
        authored: $mine,
        review: $reviews,
        authoredCount: ($mine | length),
        reviewCount: ($reviews | length),
        draftCount: ([$mine[] | select(.isDraft)] | length)
    }
' 2>/dev/null)

if [ -z "$payload" ]; then
    serve_stale "Could not read GitHub response"
fi

printf '%s\n' "$payload" >"$cache_file.tmp" && mv "$cache_file.tmp" "$cache_file"
printf '%s\n' "$payload"
