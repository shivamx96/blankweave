#!/usr/bin/env bash
#
# Apply the active Hyprarch theme.
#
# A theme is a directory holding theme.json with a dark and a light mode, each
# carrying the shell palette, the lock-screen treatment, a wallpaper, and the
# names of the matching application themes. Bundled themes are deployed to
# ~/.local/share/hyprarch/themes/<id>/ and a user theme in
# ~/.config/hyprarch/themes/<id>/ shadows a bundled one of the same id.
#
# This script is the only writer of ~/.config/hyprarch/theme.json, which holds
# both the persisted selection and the resolved values of the active mode, and
# of every config rendered from a *.tmpl next to it. Templates use
# {{path}} placeholders resolved against the resolved theme, with an optional
# {{path:format}} override for colours (css, rgb, fuzzel, hypr).
#
# Usage:
#   theme-apply.sh [apply]          re-render the persisted selection
#   theme-apply.sh set <theme>      switch theme, keeping the current mode
#   theme-apply.sh mode <dark|light>
#   theme-apply.sh toggle           flip between dark and light
#   theme-apply.sh list             JSON array of the available themes
#   theme-apply.sh status           JSON of the active theme

set -euo pipefail

DOTS_DIR=$HOME/.local/share/hyprarch
CONFIG_DIR=${XDG_CONFIG_HOME:-$HOME/.config}
HYPRARCH_CONFIG_DIR=$CONFIG_DIR/hyprarch
STATE_FILE=$HYPRARCH_CONFIG_DIR/theme.json
LEGACY_STATE_FILE=$DOTS_DIR/theme
DEFAULT_THEME=obsidian
DEFAULT_MODE=dark

# Every token Theme.qml and the templates may reference. A theme missing one
# is rejected rather than rendered with a hole in it.
REQUIRED_COLORS=(
    canvas barSurface barHighlight panelSurface surface surfaceRaised
    surfaceHover surfacePressed scrim text textMuted accent accentBright
    accentSurface outline outlineStrong divider success warning critical
)

# Single-pass substitution: a rendered value can never be mistaken for a
# placeholder, so no staging through intermediate markers is needed.
# shellcheck disable=SC2016
RENDER_PROGRAM='
def body: ltrimstr("#") | ascii_downcase | if length == 6 then . + "ff" else . end;
def is_color: type == "string" and test("^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$");
def render($format):
    if is_color then
        if $format == "css" then ascii_downcase
        elif $format == "rgb" then "#" + (body | .[0:6])
        elif $format == "fuzzel" then body
        elif $format == "hypr" then "rgba(" + body + ")"
        else error("unknown colour format: " + $format)
        end
    elif type == "string" then .
    elif type == "number" or type == "boolean" then tostring
    else error("placeholder does not resolve to a scalar")
    end;
def lookup($path):
    ($ctx | getpath($path | split("."))) as $value
    | if $value == null then error("unknown placeholder: " + $path) else $value end;
$template
| gsub("\\{\\{(?<p>[A-Za-z0-9_.]+)(:(?<f>[a-z]+))?\\}\\}";
       (.f // $format) as $chosen | lookup(.p) | render($chosen))
'

THEME=$DEFAULT_THEME
MODE=$DEFAULT_MODE
RESOLVED=""

die() {
    printf 'theme-apply: %s\n' "$*" >&2
    exit 1
}

usage() {
    sed -n '/^# Usage:/,/^$/{s/^#\s\{0,1\}//p}' "${BASH_SOURCE[0]}"
}

valid_theme_id() {
    [[ $1 =~ ^[a-z0-9][a-z0-9-]*$ ]]
}

theme_dir() {
    local id=$1 dir

    valid_theme_id "$id" || die "invalid theme id: $id"
    for dir in "$HYPRARCH_CONFIG_DIR/themes/$id" "$DOTS_DIR/themes/$id"; do
        if [[ -r $dir/theme.json ]]; then
            printf '%s\n' "$dir"
            return 0
        fi
    done
    return 1
}

# The selection lives in the resolved state file. Before the first apply the
# pre-theme installs recorded only a mode in a plain-text file; honour it so an
# update never flips someone back to dark.
load_selection() {
    local theme mode legacy

    if [[ -r $STATE_FILE ]]; then
        theme=$(jq -r '.theme // empty' "$STATE_FILE" 2>/dev/null) || theme=""
        mode=$(jq -r '.mode // empty' "$STATE_FILE" 2>/dev/null) || mode=""
        [[ -n $theme ]] && THEME=$theme
        [[ -n $mode ]] && MODE=$mode
    elif [[ -r $LEGACY_STATE_FILE ]]; then
        IFS= read -r legacy < "$LEGACY_STATE_FILE" || true
        [[ $legacy == light ]] && MODE=light
    fi
    return 0
}

resolve_theme() {
    local id=$1 mode=$2 dir required

    dir=$(theme_dir "$id") || die "unknown theme: $id"
    required=$(printf '%s\n' "${REQUIRED_COLORS[@]}" | jq -R . | jq -s .)
    jq -e --arg id "$id" --arg mode "$mode" --arg dir "$dir" --argjson required "$required" '
        .modes[$mode] as $variant
        | if $variant == null then error("theme \($id) has no \($mode) mode") else . end
        | ($required - (($variant.colors // {}) | keys)) as $missing
        | if ($missing | length) > 0
          then error("theme \($id) \($mode) mode is missing colours: \($missing | join(", "))")
          else . end
        | ($variant.wallpaper // "") as $wallpaper
        | $variant + {
            theme: $id,
            mode: $mode,
            name: .name,
            wallpaper: (if $wallpaper == "" then null
                        elif ($wallpaper | startswith("/")) then $wallpaper
                        else "\($dir)/\($wallpaper)" end),
            modes: (.modes | map_values({label, ghostty, iconTheme}))
          }
    ' "$dir/theme.json"
}

render_template() {
    local format=$1 template=$2 output=$3 staged

    if [[ ! -r $template ]]; then
        printf 'theme-apply: template not found, skipped: %s\n' "$template" >&2
        return 0
    fi
    mkdir -p "$(dirname "$output")"
    staged=$(mktemp "$(dirname "$output")/.$(basename "$output").XXXXXX")
    if ! jq -j --rawfile template "$template" --arg format "$format" \
            --argjson ctx "$RESOLVED" -n "$RENDER_PROGRAM" > "$staged"; then
        rm -f "$staged"
        die "failed to render $template"
    fi
    chmod 0644 "$staged"
    mv -f "$staged" "$output"
}

render_all() {
    render_template css "$DOTS_DIR/dunst/dunstrc.tmpl" "$DOTS_DIR/dunst/dunstrc"
    render_template fuzzel "$DOTS_DIR/fuzzel/fuzzel.ini.tmpl" "$DOTS_DIR/fuzzel/fuzzel.ini"
    render_template css "$DOTS_DIR/ghostty/config.tmpl" "$DOTS_DIR/ghostty/config"
    render_template hypr "$DOTS_DIR/hypr/hyprlock-theme.conf.tmpl" "$DOTS_DIR/hypr/hyprlock-theme.conf"
    render_template hypr "$DOTS_DIR/hypr/theme.lua.tmpl" "$HYPRARCH_CONFIG_DIR/theme.lua"
}

# Quickshell watches this file, so replace its contents with one write rather
# than renaming a staged copy out from under the watch.
write_state() {
    mkdir -p "$HYPRARCH_CONFIG_DIR"
    printf '%s\n' "$RESOLVED" > "$STATE_FILE"
}

apply_desktop_preferences() {
    local scheme gtk_theme prefer_dark dir

    if [[ $MODE == light ]]; then
        scheme=prefer-light
        gtk_theme=Adwaita
        prefer_dark=0
    else
        scheme=prefer-dark
        gtk_theme=Adwaita-dark
        prefer_dark=1
    fi

    # Portal-aware apps (libadwaita, Ghostty, browsers) follow gsettings.
    if command -v gsettings > /dev/null; then
        gsettings set org.gnome.desktop.interface color-scheme "$scheme" 2> /dev/null || true
        gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme" 2> /dev/null || true
    fi

    # GTK3 apps on Hyprland have no settings daemon and read these files.
    for dir in gtk-3.0 gtk-4.0; do
        mkdir -p "$CONFIG_DIR/$dir"
        printf '[Settings]\ngtk-application-prefer-dark-theme=%s\ngtk-theme-name=Adwaita\n' \
            "$prefer_dark" > "$CONFIG_DIR/$dir/settings.ini"
    done
}

apply_wallpaper() {
    local wallpaper

    wallpaper=$(jq -r '.wallpaper // empty' <<< "$RESOLVED")
    [[ -n $wallpaper && -f $wallpaper ]] || return 0
    # Wallpaper availability must never keep the palette from changing.
    [[ -n ${WAYLAND_DISPLAY:-} ]] && command -v awww > /dev/null || return 0
    bash "$DOTS_DIR/shell/wallpaper.sh" set "$wallpaper" > /dev/null 2>&1 || true
}

reload_services() {
    local link

    # Symlink mtimes wake inotify-based readers such as Ghostty.
    for link in "$CONFIG_DIR/ghostty/config" "$CONFIG_DIR/dunst/dunstrc" "$CONFIG_DIR/fuzzel/fuzzel.ini"; do
        if [[ -L $link ]]; then
            touch -h "$link" 2> /dev/null || true
        fi
    done
    # Reload Dunst in place so the palette changes without discarding history.
    if command -v dunstctl > /dev/null; then
        dunstctl reload "$DOTS_DIR/dunst/dunstrc" 2> /dev/null || true
    fi
    if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && command -v hyprctl > /dev/null; then
        hyprctl reload > /dev/null 2>&1 || true
    fi
}

list_themes() {
    local -A seen=()
    local source root file id entries=()

    for source in user bundled; do
        case $source in
            user) root=$HYPRARCH_CONFIG_DIR/themes ;;
            bundled) root=$DOTS_DIR/themes ;;
        esac
        for file in "$root"/*/theme.json; do
            [[ -r $file ]] || continue
            id=$(basename "$(dirname "$file")")
            valid_theme_id "$id" || continue
            [[ -n ${seen[$id]:-} ]] && continue
            seen[$id]=1
            entries+=("$(jq -c --arg id "$id" --arg source "$source" '{
                id: $id,
                name: (.name // $id),
                description: (.description // ""),
                source: $source,
                modes: (.modes // {} | to_entries | map({mode: .key, label: (.value.label // .key)}))
            }' "$file" 2> /dev/null || printf '{"id":"%s","name":"%s","source":"%s","invalid":true}' "$id" "$id" "$source")")
        done
    done

    if [[ ${#entries[@]} -eq 0 ]]; then
        printf '[]\n'
    else
        printf '%s\n' "${entries[@]}" | jq -s 'sort_by(.name)'
    fi
}

main() {
    local command=${1:-apply}
    shift || true

    load_selection
    case $command in
        apply)
            [[ $# -eq 0 ]] || die "apply does not accept arguments"
            ;;
        set)
            [[ $# -eq 1 ]] || die "set requires a theme id"
            THEME=$1
            ;;
        mode)
            [[ $# -eq 1 ]] || die "mode requires dark or light"
            MODE=$1
            ;;
        toggle)
            [[ $# -eq 0 ]] || die "toggle does not accept arguments"
            if [[ $MODE == dark ]]; then MODE=light; else MODE=dark; fi
            ;;
        list)
            [[ $# -eq 0 ]] || die "list does not accept arguments"
            list_themes
            return 0
            ;;
        status)
            [[ $# -eq 0 ]] || die "status does not accept arguments"
            if [[ -r $STATE_FILE ]]; then
                cat "$STATE_FILE"
            else
                resolve_theme "$THEME" "$MODE"
            fi
            return 0
            ;;
        help|-h|--help)
            usage
            return 0
            ;;
        *)
            die "unknown command: $command"
            ;;
    esac

    [[ $MODE == dark || $MODE == light ]] || die "mode must be dark or light: $MODE"
    RESOLVED=$(resolve_theme "$THEME" "$MODE")
    render_all
    write_state
    apply_desktop_preferences
    apply_wallpaper
    reload_services
}

main "$@"
