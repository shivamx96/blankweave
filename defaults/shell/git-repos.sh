#!/usr/bin/env bash
# Local-only scan of the IntelliJ project directory. Never touches the network:
# every repository row must stay cheap enough to refresh while the panel is open.

set -uo pipefail

root=${1:-$HOME/IdeaProjects}

if [ ! -d "$root" ]; then
    jq -cn --arg root "$root" '{
        available: false,
        root: $root,
        error: "Project directory not found",
        total: 0, dirty: 0, ahead: 0, skipped: 0, repos: []
    }'
    exit 0
fi

# git@host:owner/repo.git, ssh://git@host/owner/repo, https://host/owner/repo.git
# all collapse to a browsable https URL plus an owner/name pair.
normalize_origin() {
    local url=$1 rest host path
    rest=${url%.git}
    rest=${rest%/}
    case "$rest" in
        ssh://*|git://*|http://*|https://*)
            rest=${rest#*://}
            rest=${rest#*@}
            ;;
        *@*:*)
            rest=${rest#*@}
            rest=${rest/://}
            ;;
    esac

    host=${rest%%/*}
    path=${rest#*/}
    if [ -z "$host" ] || [ "$host" = "$rest" ] || [ -z "$path" ]; then
        printf '\t\t\n'
        return
    fi
    printf '%s\t%s\thttps://%s/%s\n' "$host" "$path" "$host" "$path"
}

skipped=0
entries=()

for dir in "$root"/*/; do
    [ -e "$dir/.git" ] || continue
    dir=${dir%/}

    origin=$(git -C "$dir" config --get remote.origin.url 2>/dev/null)
    if [ -z "$origin" ]; then
        skipped=$((skipped + 1))
        continue
    fi

    IFS=$'\t' read -r host name_with_owner web_url < <(normalize_origin "$origin")
    if [ -z "$name_with_owner" ]; then
        skipped=$((skipped + 1))
        continue
    fi

    # One porcelain call yields branch, upstream divergence, and the dirty count.
    status_out=$(git -C "$dir" --no-optional-locks status --porcelain=v2 --branch 2>/dev/null)
    IFS=$'\t' read -r branch ahead behind dirty < <(
        printf '%s\n' "$status_out" | awk '
            /^# branch\.head / { head = $3 }
            /^# branch\.ab /   { ahead = $3 + 0; behind = $4 + 0 }
            !/^#/              { if (NF > 0) dirty++ }
            END {
                printf "%s\t%d\t%d\t%d\n",
                    (head == "" ? "unknown" : head), ahead, behind, dirty
            }
        '
    )

    detached=false
    if [ "$branch" = "(detached)" ]; then
        detached=true
        branch=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || printf 'detached')
    fi

    last_commit=$(git -C "$dir" log -1 --format=%cr 2>/dev/null)

    entries+=("$(jq -cn \
        --arg name "$(basename "$dir")" \
        --arg path "$dir" \
        --arg origin "$origin" \
        --arg host "$host" \
        --arg nameWithOwner "$name_with_owner" \
        --arg webUrl "$web_url" \
        --arg branch "$branch" \
        --arg lastCommit "$last_commit" \
        --argjson detached "$detached" \
        --argjson ahead "${ahead:-0}" \
        --argjson behind "${behind:-0}" \
        --argjson dirty "${dirty:-0}" \
        '{
            name: $name, path: $path, origin: $origin, host: $host,
            nameWithOwner: $nameWithOwner, webUrl: $webUrl,
            branch: $branch, detached: $detached,
            ahead: $ahead, behind: $behind, dirty: $dirty,
            lastCommit: $lastCommit
        }')")
done

printf '%s\n' "${entries[@]:-}" | jq -cs \
    --arg root "$root" \
    --argjson skipped "$skipped" '
    map(select(type == "object")) as $repos
    | ($repos | sort_by(.name | ascii_downcase)) as $repos
    | {
        available: true,
        root: $root,
        error: "",
        skipped: $skipped,
        total: ($repos | length),
        dirty: ([$repos[] | select(.dirty > 0)] | length),
        ahead: ([$repos[] | select(.ahead > 0)] | length),
        repos: $repos
    }
'
